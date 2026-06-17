use std::array::from_fn;
use std::io::{Read, Write};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use crossbeam_channel::{Receiver, Sender};
use rand::rngs::StdRng;
use rand::{Rng, SeedableRng};

use crate::dsp::ChannelProcessor;
use crate::pipeline::{empty_packet, empty_raw_packet, RawPacket, WorkerCommand, WorkerEvent};
use crate::{
    BASEBAND_BW_HZ, CARRIER_FREQ_HZ, CHUNK_SIZE, FILTER_ORDER, NOTCH_Q, NUM_CHANNELS,
    SAMPLE_RATE_HZ,
};

use super::parser::parse_csv_frame;

#[derive(Clone, Debug)]
pub struct SerialWorkerConfig {
    pub port_name: Option<String>,
    pub chunk_size: usize,
    pub sample_rate_hz: f32,
    pub simulate_only: bool,
}

impl Default for SerialWorkerConfig {
    fn default() -> Self {
        Self {
            port_name: None,
            chunk_size: CHUNK_SIZE,
            sample_rate_hz: SAMPLE_RATE_HZ,
            simulate_only: false,
        }
    }
}

pub fn start_worker_thread(
    config: SerialWorkerConfig,
    sender: Sender<WorkerEvent>,
    command_rx: Receiver<WorkerCommand>,
) -> Result<JoinHandle<()>> {
    let source = match DataSource::new(&config) {
        Ok(s) => Some(s),
        Err(e) => {
            eprintln!("无法初始化数据源: {e} (将以断开状态启动)");
            None
        }
    };
    let handle = thread::Builder::new()
        .name("serial-worker".into())
        .spawn(move || worker_loop(config, source, sender, command_rx))
        .expect("failed to spawn worker thread");
    Ok(handle)
}

fn worker_loop(
    config: SerialWorkerConfig,
    mut source: Option<DataSource>,
    sender: Sender<WorkerEvent>,
    command_rx: Receiver<WorkerCommand>,
) {
    let mut processors: Vec<ChannelProcessor> = (0..NUM_CHANNELS)
        .map(|_| {
            ChannelProcessor::new(
                config.sample_rate_hz,
                CARRIER_FREQ_HZ,
                BASEBAND_BW_HZ,
                NOTCH_Q,
                FILTER_ORDER,
            )
        })
        .collect();

    // Report initial state
    if source.is_some() {
        let _ = sender.send(WorkerEvent::ConnectionState(true));
    }

    // Loop forever
    loop {
        // 1. Handle Commands
        // If we are disconnected, we BLOCK waiting for a command (specifically Connect).
        // If we are connected, we POLL for commands (non-blocking).
        if source.is_none() {
            match command_rx.recv() {
                Ok(cmd) => handle_command_logic(cmd, &mut source, &sender, &config),
                Err(_) => break, // Channel closed, exit worker
            }
        } else {
            while let Ok(cmd) = command_rx.try_recv() {
                handle_command_logic(cmd, &mut source, &sender, &config);
            }
        }

        // 2. Read Data (if connected)
        if let Some(src) = &mut source {
            match src.read_event(config.chunk_size) {
                Ok(event) => match event {
                    SourceEvent::Samples(block) => {
                        let mut packet = empty_packet();
                        for ch in 0..NUM_CHANNELS {
                            packet[ch] = processors[ch].process_block(&block[ch]);
                        }
                        if sender.send(WorkerEvent::Telemetry(packet)).is_err() {
                            break;
                        }
                    }
                    SourceEvent::CommandResponse(resp) => {
                        if sender.send(WorkerEvent::CommandResponse(resp)).is_err() {
                            break;
                        }
                    }
                },
                Err(err) => {
                    let msg = format!("数据源错误 (自动断开): {err:?}");
                    let _ = sender.send(WorkerEvent::Error(msg));
                    // Auto disconnect
                    source = None;
                    let _ = sender.send(WorkerEvent::ConnectionState(false));
                    thread::sleep(Duration::from_millis(250)); // Prevent rapid error loops if logic changes
                }
            }
        }
    }
}

fn handle_command_logic(
    cmd: WorkerCommand,
    source: &mut Option<DataSource>,
    sender: &Sender<WorkerEvent>,
    config: &SerialWorkerConfig, // Used for sample rate config if needed, or defaults
) {
    match cmd {
        WorkerCommand::Disconnect => {
            *source = None;
            let _ = sender.send(WorkerEvent::ConnectionState(false));
        }
        WorkerCommand::Connect { port } => {
            if port == "SIMULATED" {
                *source = Some(DataSource::Simulated(SimulatedSource::new(
                    config.sample_rate_hz,
                )));
                let _ = sender.send(WorkerEvent::ConnectionState(true));
            } else {
                match SerialDataSource::new(&port, 115_200) {
                    Ok(ds) => {
                        *source = Some(DataSource::Serial(ds));
                        let _ = sender.send(WorkerEvent::ConnectionState(true));
                    }
                    Err(err) => {
                        let _ = sender.send(WorkerEvent::Error(format!("连接失败: {err}")));
                    }
                }
            }
        }
        WorkerCommand::SetMotor { .. } => {
            if let Some(src) = source {
                match src.send_command(&cmd) {
                    Ok(Some(msg)) => {
                        let _ = sender.send(WorkerEvent::CommandResponse(msg));
                    }
                    Ok(None) => {}
                    Err(err) => {
                        let _ = sender.send(WorkerEvent::Error(format!("命令发送失败: {err:?}")));
                    }
                }
            }
        }
    }
}

enum DataSource {
    Serial(SerialDataSource),
    Simulated(SimulatedSource),
}

impl DataSource {
    fn new(config: &SerialWorkerConfig) -> Result<Self> {
        if config.simulate_only {
            return Ok(Self::Simulated(SimulatedSource::new(config.sample_rate_hz)));
        }

        let port_name = match config.port_name.as_deref() {
            Some(name) => name,
            None => bail!("未提供串口名称"),
        };
        let source = SerialDataSource::new(port_name, 115_200)?;
        eprintln!("已连接串口 {port_name}");
        Ok(Self::Serial(source))
    }

    fn read_event(&mut self, chunk_size: usize) -> Result<SourceEvent> {
        match self {
            DataSource::Serial(source) => source.read_event(chunk_size),
            DataSource::Simulated(source) => {
                Ok(SourceEvent::Samples(source.read_block(chunk_size)))
            }
        }
    }

    fn send_command(&mut self, command: &WorkerCommand) -> Result<Option<String>> {
        match self {
            DataSource::Serial(source) => {
                source.write_command(command)?;
                Ok(None)
            }
            DataSource::Simulated(source) => Ok(source.handle_command(command)),
        }
    }
}

enum SourceEvent {
    Samples(RawPacket),
    CommandResponse(String),
}

struct SerialDataSource {
    port: Box<dyn serialport::SerialPort>,
    buffer: Vec<u8>,
    packet: RawPacket,
    frames_collected: usize,
}

impl SerialDataSource {
    fn new(port_name: &str, baud_rate: u32) -> Result<Self> {
        let port = serialport::new(port_name, baud_rate)
            .timeout(Duration::from_millis(10))
            .open()
            .with_context(|| format!("Failed to open serial port {port_name}"))?;

        Ok(Self {
            port,
            buffer: Vec::new(),
            packet: empty_raw_packet(),
            frames_collected: 0,
        })
    }

    fn read_event(&mut self, chunk_size: usize) -> Result<SourceEvent> {
        let mut read_buf = [0u8; 512];

        loop {
            match self.port.read(&mut read_buf) {
                Ok(0) => continue,
                Ok(bytes_read) => {
                    self.buffer.extend_from_slice(&read_buf[..bytes_read]);
                    while let Some(pos) = self.buffer.iter().position(|&b| b == b'\n') {
                        let line: Vec<u8> = self.buffer.drain(..=pos).collect();
                        if let Some(event) = self.handle_line(&line, chunk_size)? {
                            return Ok(event);
                        }
                    }
                }
                Err(ref err) if err.kind() == std::io::ErrorKind::TimedOut => continue,
                Err(err) => return Err(err.into()),
            }
        }
    }

    fn handle_line(&mut self, line: &[u8], chunk_size: usize) -> Result<Option<SourceEvent>> {
        let line_str = String::from_utf8_lossy(line);
        let trimmed = line_str.trim_matches(|c| c == '\r' || c == '\n').trim();
        if trimmed.is_empty() {
            return Ok(None);
        }

        let first_char = trimmed.chars().next().unwrap_or_default();
        if first_char.is_ascii_digit() || first_char == '-' {
            if let Some(frame) = parse_csv_frame(trimmed) {
                for ch in 0..NUM_CHANNELS {
                    self.packet[ch].push(frame[ch]);
                }
                self.frames_collected += 1;
                if self.frames_collected >= chunk_size {
                    let packet = std::mem::replace(&mut self.packet, empty_raw_packet());
                    self.frames_collected = 0;
                    return Ok(Some(SourceEvent::Samples(packet)));
                }
            }
            return Ok(None);
        }

        if first_char.is_ascii_alphabetic() {
            return Ok(Some(SourceEvent::CommandResponse(trimmed.to_string())));
        }

        Ok(None)
    }

    fn write_command(&mut self, command: &WorkerCommand) -> Result<()> {
        if let Some(payload) = command.to_serial_line() {
            self.port.write_all(payload.as_bytes())?;
            self.port.flush()?;
        }
        Ok(())
    }
}

struct SimulatedSource {
    sample_rate_hz: f32,
    carrier_phases: [f32; NUM_CHANNELS],
    envelope_phases: [f32; NUM_CHANNELS],
    carrier_freqs: [f32; NUM_CHANNELS],
    envelope_freqs: [f32; NUM_CHANNELS],
    amplitude_scales: [f32; NUM_CHANNELS],
    rng: StdRng,
    next_emit: Instant,
}

impl SimulatedSource {
    fn new(sample_rate_hz: f32) -> Self {
        let rng = StdRng::from_entropy();
        let carrier_freqs = from_fn(|i| 10.0 + (i as f32 * 2.5));
        let envelope_freqs = from_fn(|i| 0.4 + 0.05 * i as f32);
        let amplitude_scales =
            from_fn(|i| 0.4 + 0.05 * (i as f32) + (i % 3) as f32 * 0.1).map(|v| v.min(1.3));

        Self {
            sample_rate_hz,
            carrier_phases: [0.0; NUM_CHANNELS],
            envelope_phases: [0.0; NUM_CHANNELS],
            carrier_freqs,
            envelope_freqs,
            amplitude_scales,
            rng,
            next_emit: Instant::now(),
        }
    }

    fn read_block(&mut self, chunk_size: usize) -> RawPacket {
        let mut packet = empty_raw_packet();
        for _ in 0..chunk_size {
            for ch in 0..NUM_CHANNELS {
                let carrier = (self.carrier_phases[ch]).sin();
                let envelope = 0.5 + 0.5 * (self.envelope_phases[ch]).sin();
                let noise: f32 = self.rng.gen_range(-0.05..0.05);
                let sample = (carrier * envelope + noise) * self.amplitude_scales[ch];
                packet[ch].push(sample);
                self.advance_phase(ch);
            }
        }
        self.sync_with_time(chunk_size);
        packet
    }

    fn advance_phase(&mut self, idx: usize) {
        let carrier_step =
            2.0 * std::f32::consts::PI * self.carrier_freqs[idx] / self.sample_rate_hz;
        let env_step = 2.0 * std::f32::consts::PI * self.envelope_freqs[idx] / self.sample_rate_hz;
        self.carrier_phases[idx] =
            (self.carrier_phases[idx] + carrier_step).rem_euclid(2.0 * std::f32::consts::PI);
        self.envelope_phases[idx] =
            (self.envelope_phases[idx] + env_step).rem_euclid(2.0 * std::f32::consts::PI);
    }

    fn sync_with_time(&mut self, chunk_size: usize) {
        let chunk_duration = Duration::from_secs_f32(chunk_size as f32 / self.sample_rate_hz);
        self.next_emit += chunk_duration;
        let now = Instant::now();
        if self.next_emit > now {
            thread::sleep(self.next_emit - now);
        } else {
            self.next_emit = now;
        }
    }

    fn handle_command(&mut self, command: &WorkerCommand) -> Option<String> {
        // Simulated source does not forward commands to any hardware; report status back to UI.
        match command {
            WorkerCommand::SetMotor { id, intensity } => {
                Some(format!("OK (simulate) motor {id} -> {intensity}"))
            }
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn simulated_source_produces_samples() {
        let mut source = SimulatedSource::new(SAMPLE_RATE_HZ);
        let block = source.read_block(CHUNK_SIZE);
        assert_eq!(block.len(), NUM_CHANNELS);
        assert!(block.iter().all(|channel| channel.len() == CHUNK_SIZE));
    }

    #[test]
    fn channel_processor_filters_block() {
        let mut source = SimulatedSource::new(SAMPLE_RATE_HZ);
        let block = source.read_block(CHUNK_SIZE);
        let mut processor = ChannelProcessor::new(
            SAMPLE_RATE_HZ,
            CARRIER_FREQ_HZ,
            BASEBAND_BW_HZ,
            NOTCH_Q,
            FILTER_ORDER,
        );
        let result = processor.process_block(&block[0]);
        assert_eq!(result.raw.len(), CHUNK_SIZE);
        assert_eq!(result.filtered_1.len(), CHUNK_SIZE);
        assert_eq!(result.filtered_2.len(), CHUNK_SIZE);
    }
}
