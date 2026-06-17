use std::collections::VecDeque;
use std::fs::File;
use std::io::Write;
use std::path::Path;

use crossbeam_channel::{Receiver, Sender};
use eframe::egui::{self, FontData, FontDefinitions, FontFamily, RichText, ScrollArea};
use egui_plot::{Line, Plot, PlotPoints, PlotUi};
use rfd::FileDialog;
use rustfft::num_complex::Complex32;
use rustfft::FftPlanner;

use crate::pipeline::{ProcessedChunk, WorkerCommand, WorkerEvent};
use crate::{BUFFER_SECONDS, NUM_CHANNELS, SAMPLE_RATE_HZ};

const MAX_BUFFER_LEN: usize = (BUFFER_SECONDS as f32 * SAMPLE_RATE_HZ) as usize;
const MAX_FFT_SAMPLES: usize = 1024;
const MAX_TIME_PLOT_POINTS: usize = 2500;
const CHINESE_FONT_BYTES: &[u8] = include_bytes!("../assets/fonts/NotoSansSC-Regular.otf");
const NUM_MOTORS: usize = 8;
const MOTOR_ENABLE_THRESHOLD: u8 = 128;
const SIMULATED_PORT: &str = "SIMULATED";

pub struct AdcFilterApp {
    receiver: Receiver<WorkerEvent>,
    command_tx: Sender<WorkerCommand>,
    channels: Vec<ChannelUiState>,
    paused: bool,
    expanded_channel: Option<usize>,
    fft_enabled: bool,
    packets_received: usize,
    last_chunk_len: usize,
    reset_zoom_requested: bool,
    active_tab: MainTab,
    motor: MotorCtrlState,
    latest_samples: LatestSamples,
    export_status: Option<ExportStatus>,
    
    // Connection management
    port_list: Vec<String>,
    selected_port: Option<String>,
    is_connected: bool,
}

impl AdcFilterApp {
    pub fn new(
        cc: &eframe::CreationContext<'_>,
        receiver: Receiver<WorkerEvent>,
        command_tx: Sender<WorkerCommand>,
    ) -> Self {
        configure_fonts(&cc.egui_ctx);
        let channels = (0..NUM_CHANNELS).map(|_| ChannelUiState::new()).collect();
        Self {
            receiver,
            command_tx,
            channels,
            paused: false,
            expanded_channel: None,
            fft_enabled: false,
            packets_received: 0,
            last_chunk_len: 0,
            reset_zoom_requested: false,
            active_tab: MainTab::Charts,
            motor: MotorCtrlState::new(),
            latest_samples: LatestSamples::new(),
            export_status: None,
            port_list: Vec::new(),
            selected_port: None,
            is_connected: false,
        }
    }

    fn sync_packets(&mut self) {
        while let Ok(event) = self.receiver.try_recv() {
            match event {
                WorkerEvent::Telemetry(packet) => {
                    if self.paused {
                        continue;
                    }
                    self.packets_received += 1;
                    self.last_chunk_len = packet[0].raw.len();
                    for (idx, chunk) in packet.iter().enumerate() {
                        self.latest_samples.update(idx, chunk);
                        if let Some(channel) = self.channels.get_mut(idx) {
                            channel.push_chunk(chunk);
                        }
                    }
                }
                WorkerEvent::CommandResponse(resp) => {
                    self.motor.handle_response(resp);
                }
                WorkerEvent::Error(err) => {
                    self.motor.handle_error(err);
                }
                WorkerEvent::ConnectionState(connected) => {
                    self.is_connected = connected;
                }
            }
        }
    }

    fn draw_single_plot(
        &mut self,
        ui: &mut egui::Ui,
        idx: usize,
        expanded: bool,
        plot_data: &PlotData,
        half_span: f64,
        reset_zoom: bool,
    ) {
        let title = format!("CH-{:02}", idx + 1);
        let frame = egui::Frame::group(ui.style()).inner_margin(egui::Margin::symmetric(8.0, 6.0));
        let mut expand_requested = false;
        let ctrl_zoom_active = ui.input(|i| i.modifiers.ctrl);

        {
            let state = &mut self.channels[idx];
            frame.show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.label(RichText::new(title.clone()).strong());
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        egui::ComboBox::from_id_source(format!("view_mode_{idx}"))
                            .selected_text(state.selected_mode.label())
                            .show_ui(ui, |ui| {
                                for mode in ViewMode::ALL {
                                    ui.selectable_value(
                                        &mut state.selected_mode,
                                        mode,
                                        mode.label(),
                                    );
                                }
                            });
                    });
                });

                let (label, y_log) = if self.fft_enabled {
                    ("FFT", true)
                } else {
                    (state.selected_mode.label(), false)
                };

                let plot_height = if expanded {
                    ui.available_height()
                } else {
                    160.0
                };
                let zoom_axes = if ctrl_zoom_active {
                    [true, false]
                } else {
                    [false, true]
                };
                let mut plot = Plot::new(format!("plot_{idx}"))
                    .height(plot_height)
                    // 所有图表依旧绑定到一个同步组中，保证平移/缩放的视图范围一致
                    .link_axis("main_sync_group", true, false)
                    // 十字准星也同步显示
                    .link_cursor("main_sync_group", true, true)
                    .legend(Default::default())
                    // 鼠标左键拖拽允许同时在 X/Y 方向平移
                    .allow_drag([true, true])
                    // Ctrl + 滚轮缩放 X 轴，默认缩放 Y 轴
                    .allow_zoom(zoom_axes)
                    // 滚轮滑动依旧只影响 X 轴的平移
                    .allow_scroll([true, false]);
                if reset_zoom {
                    plot = plot.reset();
                }

                if y_log {
                    plot = plot.y_axis_formatter(|_, value, _| format!("{value:.1e}"));
                }

                let lower = plot_data.center() - half_span;
                let upper = plot_data.center() + half_span;
                plot = plot.include_y(lower).include_y(upper);

                let response = plot
                    .show(ui, |plot_ui: &mut PlotUi| {
                        plot_ui.line(Line::new(plot_data.to_plot_points()).name(label).width(1.5));
                    })
                    .response;

                if !expanded && response.double_clicked() {
                    expand_requested = true;
                }
            });
        }

        if expand_requested {
            self.expanded_channel = Some(idx);
        }
    }

    fn draw_channels(&mut self, ui: &mut egui::Ui) {
        let reset_zoom = std::mem::take(&mut self.reset_zoom_requested);
        let plot_data: Vec<PlotData> = self
            .channels
            .iter()
            .map(|channel| channel.plot_data(self.fft_enabled))
            .collect();

        let global_span = plot_data
            .iter()
            .fold(0.0_f64, |max_span, data| max_span.max(data.span()));
        let half_span = if global_span > 0.0 {
            global_span / 2.0
        } else {
            0.5
        };

        if let Some(expanded) = self.expanded_channel {
            if let Some(data) = plot_data.get(expanded) {
                self.draw_single_plot(ui, expanded, true, data, half_span, reset_zoom);
            }
            ui.add_space(4.0);
            ui.label("按 ESC 返回网格视图，双击图表也可以恢复。");
            return;
        }

        let columns = 4;
        let spacing = 8.0;
        let total_spacing = spacing * (columns as f32 - 1.0);
        let available_width = ui.available_width();
        let cell_width = ((available_width - total_spacing) / columns as f32).max(150.0);

        ScrollArea::vertical().show(ui, |ui| {
            egui::Grid::new("channel_grid")
                .spacing([spacing, spacing])
                .striped(false)
                .show(ui, |grid_ui| {
                    for idx in 0..self.channels.len() {
                        // 使用标准的垂直布局容器
                        grid_ui.vertical(|cell_ui| {
                            // 强制设定该单元格的宽度，确保网格整齐
                            cell_ui.set_width(cell_width);
                            // 绘制图表，高度会自动正确计算
                            if let Some(data) = plot_data.get(idx) {
                                self.draw_single_plot(
                                    cell_ui, idx, false, data, half_span, reset_zoom,
                                );
                            }
                        });
                        if (idx + 1) % columns == 0 {
                            grid_ui.end_row();
                        }
                    }
                });
        });
    }

    fn set_all_view_modes(&mut self, mode: ViewMode) {
        for channel in &mut self.channels {
            channel.selected_mode = mode;
        }
    }

    fn draw_top_panel(&mut self, ui: &mut egui::Ui) {
        self.draw_connection_panel(ui);
        ui.separator();
        ui.horizontal(|ui| {
            ui.selectable_value(
                &mut self.active_tab,
                MainTab::Charts,
                MainTab::Charts.label(),
            );
            ui.selectable_value(&mut self.active_tab, MainTab::Motor, MainTab::Motor.label());
        });
        ui.add_space(4.0);
        ui.separator();
        match self.active_tab {
            MainTab::Charts => self.draw_chart_controls(ui),
            MainTab::Motor => self.draw_motor_toolbar(ui),
        }
    }

    fn draw_chart_controls(&mut self, ui: &mut egui::Ui) {
        ui.horizontal(|ui| {
            let button_label = if self.paused { "继续" } else { "暂停" };
            if ui.button(button_label).clicked() {
                self.paused = !self.paused;
            }

            ui.checkbox(&mut self.fft_enabled, "FFT 模式");
            if ui.button("全部原始").clicked() {
                self.set_all_view_modes(ViewMode::Raw);
            }
            if ui.button("全部滤波").clicked() {
                self.set_all_view_modes(ViewMode::Filter1);
            }
            if ui.button("全部解调").clicked() {
                self.set_all_view_modes(ViewMode::Filter2);
            }
            ui.label(format!(
                "数据块: {} ({} 样本)",
                self.packets_received, self.last_chunk_len
            ));
            if ui.button("重置缓冲区").clicked() {
                for channel in &mut self.channels {
                    channel.clear();
                }
                self.packets_received = 0;
                self.last_chunk_len = 0;
            }
            if ui.button("恢复默认缩放").clicked() {
                self.reset_zoom_requested = true;
            }
            if ui.button("保存数据").clicked() {
                self.save_current_view_data();
            }
        });
        if let Some(status) = &self.export_status {
            let color = if status.is_error {
                egui::Color32::RED
            } else {
                egui::Color32::from_rgb(0, 128, 0)
            };
            ui.colored_label(color, &status.message);
        }
    }

    fn current_view_mode(&self) -> ViewMode {
        self.channels
            .first()
            .map(|channel| channel.selected_mode)
            .unwrap_or(ViewMode::Raw)
    }

    fn save_current_view_data(&mut self) {
        let mode = self.current_view_mode();
        let default_name = format!("waveform_{}.csv", mode.file_suffix());
        let dialog = FileDialog::new()
            .set_title("保存波形数据")
            .add_filter("CSV 文件", &["csv"])
            .add_filter("文本文件", &["txt"])
            .set_file_name(default_name);

        if let Some(path) = dialog.save_file() {
            match self.export_history(path.as_path(), mode) {
                Ok(rows) => {
                    let message = format!(
                        "已保存 {rows} 行 {} 数据到 {}",
                        mode.label(),
                        path.display()
                    );
                    self.export_status = Some(ExportStatus::success(message));
                }
                Err(err) => {
                    self.export_status =
                        Some(ExportStatus::error(format!("保存失败: {err}")));
                }
            }
        }
    }

    fn export_history(&self, path: &Path, mode: ViewMode) -> Result<usize, String> {
        let rows = self.collect_export_rows(mode);
        if rows.is_empty() {
            return Err("当前没有可保存的数据".into());
        }
        let header = self.build_export_header();
        let ext = path
            .extension()
            .and_then(|ext| ext.to_str())
            .map(|ext| ext.to_ascii_lowercase());

        match ext.as_deref() {
            Some("txt") => self.write_txt(path, &header, &rows)?,
            _ => self.write_csv(path, &header, &rows)?,
        }
        Ok(rows.len())
    }

    fn build_export_header(&self) -> Vec<String> {
        let mut header = Vec::with_capacity(self.channels.len() + 1);
        header.push("sample".to_string());
        for idx in 0..self.channels.len() {
            header.push(format!("CH{:02}", idx + 1));
        }
        header
    }

    fn collect_export_rows(&self, mode: ViewMode) -> Vec<Vec<f32>> {
        let buffers: Vec<&VecDeque<f32>> = self
            .channels
            .iter()
            .map(|channel| channel.buffer_by_mode(mode))
            .collect();
        if buffers.is_empty() {
            return Vec::new();
        }
        let len = buffers.iter().map(|buf| buf.len()).min().unwrap_or(0);
        if len == 0 {
            return Vec::new();
        }

        let offsets: Vec<usize> = buffers.iter().map(|buf| buf.len() - len).collect();
        let mut rows = Vec::with_capacity(len);
        for sample_idx in 0..len {
            let mut row = Vec::with_capacity(buffers.len());
            for (buf, offset) in buffers.iter().zip(offsets.iter()) {
                row.push(buf[offset + sample_idx]);
            }
            rows.push(row);
        }
        rows
    }

    fn write_csv(
        &self,
        path: &Path,
        header: &[String],
        rows: &[Vec<f32>],
    ) -> Result<(), String> {
        let mut writer =
            csv::Writer::from_path(path).map_err(|err| format!("无法写入 CSV: {err}"))?;
        writer
            .write_record(header)
            .map_err(|err| format!("写入 CSV 表头失败: {err}"))?;
        for (idx, row) in rows.iter().enumerate() {
            let mut record = Vec::with_capacity(row.len() + 1);
            record.push(idx.to_string());
            for value in row {
                record.push(format!("{value:.6}"));
            }
            writer
                .write_record(&record)
                .map_err(|err| format!("写入 CSV 数据失败: {err}"))?;
        }
        writer
            .flush()
            .map_err(|err| format!("写入 CSV 失败: {err}"))?;
        Ok(())
    }

    fn write_txt(
        &self,
        path: &Path,
        header: &[String],
        rows: &[Vec<f32>],
    ) -> Result<(), String> {
        let mut file = File::create(path).map_err(|err| format!("无法创建文件: {err}"))?;
        writeln!(file, "{}", header.join("\t"))
            .map_err(|err| format!("写入文本表头失败: {err}"))?;
        for (idx, row) in rows.iter().enumerate() {
            let mut line = idx.to_string();
            for value in row {
                line.push('\t');
                line.push_str(&format!("{value:.6}"));
            }
            writeln!(file, "{line}").map_err(|err| format!("写入文本数据失败: {err}"))?;
        }
        Ok(())
    }

    fn draw_motor_toolbar(&mut self, ui: &mut egui::Ui) {
        ui.horizontal(|ui| {
            if let Some(err) = &self.motor.last_error {
                ui.colored_label(egui::Color32::RED, format!("串口错误: {err}"));
            } else if let Some(resp) = &self.motor.last_response {
                ui.label(format!("串口响应: {resp}"));
            } else {
                ui.label("串口响应: --");
            }
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button("全部停止").clicked() {
                    self.stop_all_motors();
                }
            });
        });
    }

    fn draw_motor_panel(&mut self, ui: &mut egui::Ui) {
        ui.vertical(|ui| {
            ui.horizontal(|ui| {
                ui.label("控制模式：");
                ui.selectable_value(
                    &mut self.motor.mode,
                    ControlMode::Manual,
                    ControlMode::Manual.label(),
                );
                ui.selectable_value(
                    &mut self.motor.mode,
                    ControlMode::Auto,
                    ControlMode::Auto.label(),
                );
            });
            ui.add_space(6.0);
            match self.motor.mode {
                ControlMode::Manual => self.draw_manual_controls(ui),
                ControlMode::Auto => self.draw_auto_controls(ui),
            }
        });
    }

    fn draw_manual_controls(&mut self, ui: &mut egui::Ui) {
        ui.label("拖动滑块设置 8 路电机的强度（0-127 视为禁用），点击「应用设置」下发命令。");
        ui.add_space(6.0);
        let slider_width = ui.spacing().slider_width * 2.0;
        egui::Grid::new("manual_motor_grid")
            .striped(true)
            .spacing([12.0, 8.0])
            .show(ui, |grid_ui| {
                grid_ui.label("电机");
                grid_ui.label("强度");
                grid_ui.label("状态");
                grid_ui.end_row();
                for idx in 0..NUM_MOTORS {
                    grid_ui.label(format!("#{idx}"));
                    let mut value = self.motor.manual_intensities[idx] as i32;
                    let slider = egui::Slider::new(&mut value, 0..=255)
                        .smart_aim(true);
                    let height = grid_ui.spacing().interact_size.y;
                    if grid_ui.add_sized([slider_width, height], slider).changed() {
                        self.motor.manual_intensities[idx] = value as u8;
                    }
                    self.draw_motor_indicator(grid_ui, idx);
                    grid_ui.end_row();
                }
            });
        ui.add_space(10.0);
        if ui.button("应用设置").clicked() {
            self.apply_manual_intensities();
        }
    }

    fn draw_auto_controls(&mut self, ui: &mut egui::Ui) {
        ui.label("为每路电机绑定一个 ADC 通道，高于阈值则输出设置的强度，低于阈值则关闭。");
        ui.add_space(6.0);
        let slider_width = ui.spacing().slider_width * 2.0;
        ui.horizontal(|ui| {
            ui.label("采样来源：");
            for source in SampleSource::ALL {
                ui.selectable_value(&mut self.motor.sample_source, source, source.label());
            }
        });
        ui.add_space(6.0);
        ui.add_sized(
            [slider_width, 0.0],
            egui::Slider::new(&mut self.motor.hysteresis, 1.0..=1024.0)
                .smart_aim(true)
                .text("滞回区间"),
        );
        let mut intensity = self.motor.active_intensity as i32;
        if ui
            .add_sized(
                [slider_width, 0.0],
                egui::Slider::new(
                    &mut intensity,
                    MOTOR_ENABLE_THRESHOLD as i32..=u8::MAX as i32,
                )
                .text("触发强度")
                .smart_aim(true),
            )
            .changed()
        {
            self.motor.active_intensity = intensity as u8;
        }
        ui.separator();
        egui::Grid::new("auto_motor_grid")
            .striped(true)
            .spacing([12.0, 8.0])
            .show(ui, |grid_ui| {
                grid_ui.label("电机");
                grid_ui.label("阈值");
                grid_ui.label("ADC 通道");
                grid_ui.label(format!("当前{}", self.motor.sample_source.value_label()));
                grid_ui.label("状态");
                grid_ui.end_row();
                for idx in 0..NUM_MOTORS {
                    grid_ui.label(format!("#{idx}"));
                    let height = grid_ui.spacing().interact_size.y;
                    grid_ui.add_sized(
                        [slider_width, height],
                        egui::Slider::new(&mut self.motor.thresholds[idx], 0.0..=4096.0)
                            .smart_aim(true),
                    );
                    let current = self.motor.trigger_mappings[idx];
                    let selected_text = match current {
                        Some(ch) => format!("CH-{:02}", ch + 1),
                        None => "未连接".to_string(),
                    };
                    egui::ComboBox::from_id_source(format!("motor_mapping_{idx}"))
                        .selected_text(selected_text)
                        .show_ui(grid_ui, |combo| {
                            if combo
                                .selectable_value(
                                    &mut self.motor.trigger_mappings[idx],
                                    None,
                                    "未连接",
                                )
                                .clicked()
                            {
                                self.motor.reset_trigger(idx);
                            }
                            for ch in 0..NUM_CHANNELS {
                                let label = format!("CH-{:02}", ch + 1);
                                combo.selectable_value(
                                    &mut self.motor.trigger_mappings[idx],
                                    Some(ch),
                                    label,
                                );
                            }
                        });
                    if let Some(ch) = self.motor.trigger_mappings[idx] {
                        let value = self.latest_samples.value(ch, self.motor.sample_source);
                        grid_ui.label(format!("{value:.0}"));
                    } else {
                        grid_ui.label("--");
                    }
                    self.draw_motor_indicator(grid_ui, idx);
                    grid_ui.end_row();
                }
            });
    }

    fn draw_motor_indicator(&self, ui: &mut egui::Ui, idx: usize) {
        let active = self.motor.motor_status[idx];
        ui.horizontal(|ui| {
            let desired = egui::vec2(28.0, 18.0);
            let (rect, _) = ui.allocate_exact_size(desired, egui::Sense::hover());
            let painter = ui.painter_at(rect);
            let radius = rect.height().min(rect.width()) * 0.4;
            let color = if active {
                egui::Color32::from_rgb(40, 200, 120)
            } else {
                egui::Color32::from_gray(80)
            };
            painter.circle_filled(rect.center(), radius, color);
            painter.circle_stroke(
                rect.center(),
                radius,
                egui::Stroke::new(1.0, egui::Color32::from_gray(30)),
            );
        });
    }

    fn apply_manual_intensities(&mut self) {
        let mut any_sent = false;
        for idx in 0..NUM_MOTORS {
            let target = self.motor.manual_intensities[idx];
            if self.motor.last_sent[idx] != target {
                self.dispatch_motor_command(idx, target);
                any_sent = true;
            } else {
                self.motor.motor_status[idx] = target >= MOTOR_ENABLE_THRESHOLD;
            }
        }
        if !any_sent {
            self.motor.last_response = Some("未检测到强度变化".into());
            self.motor.last_error = None;
        }
    }

    fn stop_all_motors(&mut self) {
        let mut changed = false;
        for idx in 0..NUM_MOTORS {
            self.motor.reset_trigger(idx);
            if self.motor.last_sent[idx] != 0 {
                self.dispatch_motor_command(idx, 0);
                changed = true;
            } else {
                self.motor.motor_status[idx] = false;
            }
        }
        if !changed {
            self.motor.last_response = Some("所有电机已禁用".into());
            self.motor.last_error = None;
        }
    }

    fn update_auto_control(&mut self) {
        if self.motor.mode != ControlMode::Auto {
            return;
        }
        for idx in 0..NUM_MOTORS {
            if let Some(channel) = self.motor.trigger_mappings[idx] {
                let value = self.latest_samples.value(channel, self.motor.sample_source);
                let target = self.motor.compute_auto_target(idx, value);
                self.ensure_motor_target(idx, target);
            } else {
                self.motor.reset_trigger(idx);
                self.ensure_motor_target(idx, 0);
            }
        }
    }

    fn ensure_motor_target(&mut self, idx: usize, target: u8) {
        if self.motor.last_sent[idx] != target {
            self.dispatch_motor_command(idx, target);
        } else {
            self.motor.motor_status[idx] = target >= MOTOR_ENABLE_THRESHOLD;
        }
    }

    fn dispatch_motor_command(&mut self, idx: usize, intensity: u8) {
        let command = WorkerCommand::SetMotor {
            id: idx as u8,
            intensity,
        };
        if let Err(err) = self.command_tx.send(command) {
            self.motor.handle_error(format!("无法发送电机命令: {err}"));
        } else {
            self.motor.record_send(idx, intensity);
        }
    }

    fn refresh_ports(&mut self) {
        self.port_list.clear();
        if let Ok(ports) = serialport::available_ports() {
            self.port_list = ports.into_iter().map(|p| p.port_name).collect();
        }
    }

    fn draw_connection_panel(&mut self, ui: &mut egui::Ui) {
        ui.horizontal(|ui| {
            ui.label("端口:");
            if ui.button("↻").on_hover_text("刷新串口列表").clicked() {
                self.refresh_ports();
            }

            egui::ComboBox::from_id_source("port_select")
                .selected_text(self.selected_port.as_deref().unwrap_or("已选择..."))
                .width(200.0)
                .show_ui(ui, |ui| {
                    ui.selectable_value(
                        &mut self.selected_port,
                        Some(SIMULATED_PORT.to_string()),
                        "模拟数据源 (Simulated)",
                    );
                    for port in &self.port_list {
                        ui.selectable_value(
                            &mut self.selected_port,
                            Some(port.clone()),
                            port,
                        );
                    }
                });

            ui.add_space(10.0);
            if self.is_connected {
                if ui.button("断开连接").clicked() {
                    let _ = self.command_tx.send(WorkerCommand::Disconnect);
                }
                ui.colored_label(egui::Color32::GREEN, "● 已连接");
            } else {
                let enabled = self.selected_port.is_some();
                if ui
                    .add_enabled(enabled, egui::Button::new("连接设备"))
                    .clicked()
                {
                    if let Some(port) = &self.selected_port {
                        let _ = self.command_tx.send(WorkerCommand::Connect {
                            port: port.clone(),
                        });
                    }
                }
                ui.colored_label(egui::Color32::RED, "○ 未连接");
            }
        });
    }
}

impl eframe::App for AdcFilterApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.sync_packets();
        self.update_auto_control();

        egui::TopBottomPanel::top("controls").show(ctx, |ui| {
            self.draw_top_panel(ui);
        });

        egui::CentralPanel::default().show(ctx, |ui| match self.active_tab {
            MainTab::Charts => self.draw_channels(ui),
            MainTab::Motor => self.draw_motor_panel(ui),
        });

        if self.active_tab == MainTab::Charts
            && self.expanded_channel.is_some()
            && ctx.input(|i| i.key_pressed(egui::Key::Escape))
        {
            self.expanded_channel = None;
        }

        ctx.request_repaint();
    }
}

struct ChannelUiState {
    raw_buffer: VecDeque<f32>,
    filt1_buffer: VecDeque<f32>,
    filt2_buffer: VecDeque<f32>,
    selected_mode: ViewMode,
}

impl ChannelUiState {
    fn new() -> Self {
        Self {
            raw_buffer: VecDeque::with_capacity(MAX_BUFFER_LEN),
            filt1_buffer: VecDeque::with_capacity(MAX_BUFFER_LEN),
            filt2_buffer: VecDeque::with_capacity(MAX_BUFFER_LEN),
            selected_mode: ViewMode::Raw,
        }
    }

    fn push_chunk(&mut self, chunk: &ProcessedChunk) {
        push_to_buffer(&mut self.raw_buffer, &chunk.raw);
        push_to_buffer(&mut self.filt1_buffer, &chunk.filtered_1);
        push_to_buffer(&mut self.filt2_buffer, &chunk.filtered_2);
    }

    fn clear(&mut self) {
        self.raw_buffer.clear();
        self.filt1_buffer.clear();
        self.filt2_buffer.clear();
    }

    fn buffer(&self) -> &VecDeque<f32> {
        self.buffer_by_mode(self.selected_mode)
    }

    fn buffer_by_mode(&self, mode: ViewMode) -> &VecDeque<f32> {
        match mode {
            ViewMode::Raw => &self.raw_buffer,
            ViewMode::Filter1 => &self.filt1_buffer,
            ViewMode::Filter2 => &self.filt2_buffer,
        }
    }

    fn plot_data(&self, fft_enabled: bool) -> PlotData {
        if fft_enabled {
            compute_fft_plot_data(self.buffer())
        } else {
            deque_to_plot_data(self.buffer())
        }
    }
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
enum ViewMode {
    Raw,
    Filter1,
    Filter2,
}

impl ViewMode {
    const ALL: [ViewMode; 3] = [ViewMode::Raw, ViewMode::Filter1, ViewMode::Filter2];

    fn label(self) -> &'static str {
        match self {
            ViewMode::Raw => "Raw",
            ViewMode::Filter1 => "Filtered",
            ViewMode::Filter2 => "Envelope",
        }
    }

    fn file_suffix(self) -> &'static str {
        match self {
            ViewMode::Raw => "raw",
            ViewMode::Filter1 => "filtered",
            ViewMode::Filter2 => "envelope",
        }
    }
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
enum MainTab {
    Charts,
    Motor,
}

impl MainTab {
    fn label(self) -> &'static str {
        match self {
            MainTab::Charts => "波形图表",
            MainTab::Motor => "电机控制",
        }
    }
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
enum ControlMode {
    Manual,
    Auto,
}

impl ControlMode {
    fn label(self) -> &'static str {
        match self {
            ControlMode::Manual => "手动",
            ControlMode::Auto => "自动触发",
        }
    }
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
enum SampleSource {
    Raw,
    Filtered,
    Envelope,
}

impl SampleSource {
    const ALL: [SampleSource; 3] = [
        SampleSource::Raw,
        SampleSource::Filtered,
        SampleSource::Envelope,
    ];

    fn label(self) -> &'static str {
        match self {
            SampleSource::Raw => "原始",
            SampleSource::Filtered => "滤波",
            SampleSource::Envelope => "包络",
        }
    }

    fn value_label(self) -> &'static str {
        match self {
            SampleSource::Raw => "原始值",
            SampleSource::Filtered => "滤波值",
            SampleSource::Envelope => "包络值",
        }
    }
}

struct MotorCtrlState {
    mode: ControlMode,
    manual_intensities: [u8; NUM_MOTORS],
    last_sent: [u8; NUM_MOTORS],
    trigger_mappings: [Option<usize>; NUM_MOTORS],
    trigger_status: [bool; NUM_MOTORS],
    thresholds: [f32; NUM_MOTORS],
    hysteresis: f32,
    active_intensity: u8,
    motor_status: [bool; NUM_MOTORS],
    sample_source: SampleSource,
    last_response: Option<String>,
    last_error: Option<String>,
}

impl MotorCtrlState {
    fn new() -> Self {
        Self {
            mode: ControlMode::Manual,
            manual_intensities: [0; NUM_MOTORS],
            last_sent: [0; NUM_MOTORS],
            trigger_mappings: [None; NUM_MOTORS],
            trigger_status: [false; NUM_MOTORS],
            thresholds: [1024.0; NUM_MOTORS],
            hysteresis: 20.0,
            active_intensity: 180,
            motor_status: [false; NUM_MOTORS],
            sample_source: SampleSource::Envelope,
            last_response: None,
            last_error: None,
        }
    }

    fn record_send(&mut self, idx: usize, intensity: u8) {
        self.last_sent[idx] = intensity;
        self.motor_status[idx] = intensity >= MOTOR_ENABLE_THRESHOLD;
        if self.mode == ControlMode::Manual {
            self.manual_intensities[idx] = intensity;
        }
    }

    fn reset_trigger(&mut self, idx: usize) {
        self.trigger_status[idx] = false;
    }

    fn compute_auto_target(&mut self, idx: usize, sample: f32) -> u8 {
        let threshold = self.thresholds[idx];
        let lower = (threshold - self.hysteresis.max(0.1)).max(0.0);
        let mut triggered = self.trigger_status[idx];
        if triggered {
            if sample <= lower {
                triggered = false;
            }
        } else if sample >= threshold {
            triggered = true;
        }
        self.trigger_status[idx] = triggered;
        if triggered {
            self.active_intensity
        } else {
            0
        }
    }

    fn handle_response(&mut self, response: String) {
        let trimmed = response.trim().to_string();
        if trimmed.is_empty() {
            return;
        }
        let upper = trimmed.to_ascii_uppercase();
        let ok = upper == "OK" || upper.starts_with("OK ");
        if ok {
            self.last_response = Some(trimmed);
            self.last_error = None;
        } else {
            self.last_error = Some(trimmed);
            self.last_response = None;
        }
    }

    fn handle_error(&mut self, message: String) {
        self.last_error = Some(message);
        self.last_response = None;
    }
}

struct LatestSamples {
    raw: [f32; NUM_CHANNELS],
    filtered: [f32; NUM_CHANNELS],
    envelope: [f32; NUM_CHANNELS],
}

impl LatestSamples {
    fn new() -> Self {
        Self {
            raw: [0.0; NUM_CHANNELS],
            filtered: [0.0; NUM_CHANNELS],
            envelope: [0.0; NUM_CHANNELS],
        }
    }

    fn update(&mut self, idx: usize, chunk: &ProcessedChunk) {
        if let Some(last) = chunk.raw.last().copied() {
            self.raw[idx] = last;
        }
        if let Some(last) = chunk.filtered_1.last().copied() {
            self.filtered[idx] = last;
        }
        if let Some(last) = chunk.filtered_2.last().copied() {
            self.envelope[idx] = last;
        }
    }

    fn value(&self, idx: usize, source: SampleSource) -> f32 {
        match source {
            SampleSource::Raw => self.raw[idx],
            SampleSource::Filtered => self.filtered[idx],
            SampleSource::Envelope => self.envelope[idx],
        }
    }
}

struct ExportStatus {
    message: String,
    is_error: bool,
}

impl ExportStatus {
    fn success<T: Into<String>>(msg: T) -> Self {
        Self {
            message: msg.into(),
            is_error: false,
        }
    }

    fn error<T: Into<String>>(msg: T) -> Self {
        Self {
            message: msg.into(),
            is_error: true,
        }
    }
}

struct PlotData {
    points: Vec<[f64; 2]>,
    min: f64,
    max: f64,
}

impl PlotData {
    fn empty() -> Self {
        Self {
            points: Vec::new(),
            min: 0.0,
            max: 0.0,
        }
    }

    fn from_points(points: Vec<[f64; 2]>, min: f64, max: f64) -> Self {
        Self { points, min, max }
    }

    fn span(&self) -> f64 {
        (self.max - self.min).max(0.0)
    }

    fn center(&self) -> f64 {
        (self.max + self.min) * 0.5
    }

    fn to_plot_points(&self) -> PlotPoints {
        if self.points.is_empty() {
            PlotPoints::default()
        } else {
            PlotPoints::from(self.points.clone())
        }
    }
}

fn push_to_buffer(buffer: &mut VecDeque<f32>, samples: &[f32]) {
    buffer.extend(samples.iter().copied());
    if buffer.len() > MAX_BUFFER_LEN {
        let overflow = buffer.len() - MAX_BUFFER_LEN;
        buffer.drain(..overflow);
    }
}

fn deque_to_plot_data(buffer: &VecDeque<f32>) -> PlotData {
    let len = buffer.len();
    if len == 0 {
        return PlotData::empty();
    }

    // 1. 计算全局最大最小值用于自动缩放（这部分保持不变）
    let mut min_val = f32::MAX;
    let mut max_val = f32::MIN;
    for &value in buffer {
        if value < min_val {
            min_val = value;
        }
        if value > max_val {
            max_val = value;
        }
    }

    // 2. 改进的降采样逻辑 (Min-Max Peak Detect)
    // 目标点数。如果点数太多，egui渲染会变慢；太少则精度不够。
    // 增加这个值可以提高水平分辨率。
    let target_points = MAX_TIME_PLOT_POINTS.max(200);

    // 如果数据量小于目标点数，直接全画，不进行降采样
    if len <= target_points {
        let points: Vec<[f64; 2]> = buffer
            .iter()
            .enumerate()
            .map(|(i, &v)| [i as f64 / SAMPLE_RATE_HZ as f64, v as f64])
            .collect();
        return PlotData::from_points(points, min_val as f64, max_val as f64);
    }

    // 计算每个“桶”的大小
    let chunk_size = len / target_points;
    let mut points = Vec::with_capacity(target_points * 2); // 每个桶存 min 和 max 两个点

    // 由于 VecDeque 不支持像 slice 那样的 chunks()，我们需要手动迭代
    let mut chunk_min = f32::MAX;
    let mut chunk_max = f32::MIN;
    let mut chunk_count = 0;
    let mut chunk_start_idx = 0;

    for (i, &value) in buffer.iter().enumerate() {
        if value < chunk_min {
            chunk_min = value;
        }
        if value > chunk_max {
            chunk_max = value;
        }
        chunk_count += 1;

        // 当填满一个 chunk 时，或者到达最后一个元素时
        if chunk_count >= chunk_size || i == len - 1 {
            // 计算这个 chunk 在时间轴上的中心位置（或者起始位置）
            // 为了视觉连贯，我们通常让 min 和 max 共享同一个 x 坐标，
            // 或者稍微错开一点点。这里使用简单的同一 x 坐标，egui 会连成垂直线。
            let time_x = (chunk_start_idx + chunk_count / 2) as f64 / SAMPLE_RATE_HZ as f64;

            // 存入两个点：Min 和 Max。
            // 顺序很重要：为了画出连贯的波形，通常交替顺序，但简单的 Min->Max 也可以。
            points.push([time_x, chunk_min as f64]);
            points.push([time_x, chunk_max as f64]);

            // 重置状态
            chunk_min = f32::MAX;
            chunk_max = f32::MIN;
            chunk_count = 0;
            chunk_start_idx = i + 1;
        }
    }

    PlotData::from_points(points, min_val as f64, max_val as f64)
}

fn compute_fft_plot_data(buffer: &VecDeque<f32>) -> PlotData {
    let len = buffer.len().min(MAX_FFT_SAMPLES);
    if len < 8 {
        return PlotData::empty();
    }

    let start = buffer.len().saturating_sub(len);
    let mut signal: Vec<Complex32> = buffer
        .iter()
        .skip(start)
        .take(len)
        .map(|&v| Complex32::new(v, 0.0))
        .collect();

    if !signal.is_empty() {
        let dc = signal.iter().map(|c| c.re).sum::<f32>() / signal.len() as f32;
        for sample in &mut signal {
            sample.re -= dc;
        }
    }

    let mut planner = FftPlanner::new();
    let fft = planner.plan_fft_forward(len);
    fft.process(&mut signal);

    let half = len / 2;
    if half == 0 {
        return PlotData::empty();
    }

    let mut points = Vec::with_capacity(half);
    let mut min_val = f64::INFINITY;
    let mut max_val = f64::NEG_INFINITY;
    for (i, complex) in signal.iter().take(half).enumerate() {
        let freq = i as f32 * SAMPLE_RATE_HZ / len as f32;
        let magnitude = (complex.norm() / len as f32).max(1e-6) as f64;
        if magnitude < min_val {
            min_val = magnitude;
        }
        if magnitude > max_val {
            max_val = magnitude;
        }
        points.push([freq as f64, magnitude]);
    }

    if points.is_empty() {
        return PlotData::empty();
    }

    PlotData::from_points(points, min_val, max_val)
}

fn configure_fonts(ctx: &egui::Context) {
    let mut fonts = FontDefinitions::default();
    fonts.font_data.insert(
        "noto_sans_sc".into(),
        FontData::from_static(CHINESE_FONT_BYTES),
    );
    for family in [FontFamily::Proportional, FontFamily::Monospace] {
        fonts
            .families
            .entry(family)
            .or_default()
            .insert(0, "noto_sans_sc".into());
    }
    ctx.set_fonts(fonts);
}
