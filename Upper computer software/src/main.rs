#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod app;
mod dsp;
mod io;
mod pipeline;

use crate::app::AdcFilterApp;
use crate::io::{start_worker_thread, SerialWorkerConfig};
use crate::pipeline::{WorkerCommand, WorkerEvent};
use eframe::egui;
use std::env;
use std::process;

pub const NUM_CHANNELS: usize = 16;
pub const SAMPLE_RATE_HZ: f32 = 500.0;
pub const CHUNK_SIZE: usize = 64;
pub const BUFFER_SECONDS: usize = 5;
pub const CARRIER_FREQ_HZ: f32 = 50.0;
pub const BASEBAND_BW_HZ: f32 = 5.0;
pub const NOTCH_Q: f32 = 30.0;
pub const FILTER_ORDER: usize = 4;

fn main() -> eframe::Result<()> {
    let (event_tx, event_rx) = crossbeam_channel::unbounded::<WorkerEvent>();
    let (command_tx, command_rx) = crossbeam_channel::unbounded::<WorkerCommand>();
    let mut worker_config = SerialWorkerConfig::default();
    match parse_launch_mode() {
        LaunchMode::Serial(port) => {
            worker_config.port_name = Some(port);
            worker_config.simulate_only = false;
        }
        LaunchMode::Simulated => {
            worker_config.simulate_only = true;
        }
        LaunchMode::None => {
            // No initial connection
        }
    }
    let worker_handle =
        start_worker_thread(worker_config, event_tx, command_rx).unwrap_or_else(|err| {
            eprintln!("无法初始化数据源: {err}");
            process::exit(1);
        });

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([1400.0, 900.0])
            .with_min_inner_size([900.0, 600.0]),
        follow_system_theme: true,
        centered: true,
        ..Default::default()
    };

    let result = eframe::run_native(
        "ADC Filter UI",
        options,
        Box::new(move |cc| Box::new(AdcFilterApp::new(cc, event_rx, command_tx))),
    );

    if let Err(err) = worker_handle.join() {
        eprintln!("Worker thread join error: {err:?}");
    }

    result
}

enum LaunchMode {
    Serial(String),
    Simulated,
    None,
}

fn parse_launch_mode() -> LaunchMode {
    let mut args = env::args().skip(1);
    let mut simulate = false;
    let mut port: Option<String> = None;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--help" | "-h" => {
                print_usage_and_exit(0);
            }
            "--port" | "-p" => {
                if let Some(value) = args.next() {
                    port = Some(value);
                } else {
                    eprintln!("Expected value after {arg}");
                    print_usage_and_exit(1);
                }
            }
            "--simulate" | "-s" => {
                simulate = true;
            }
            _ if arg.starts_with("--port=") => {
                port = Some(arg["--port=".len()..].to_string());
            }
            _ if arg.starts_with('-') => continue,
            _ => {
                port = Some(arg);
            }
        }
    }

    match (simulate, port) {
        (true, Some(_)) => {
            eprintln!("不能同时指定串口和 --simulate。");
            print_usage_and_exit(1);
        }
        (true, None) => LaunchMode::Simulated,
        (false, Some(port)) => LaunchMode::Serial(port),
        (false, None) => LaunchMode::None,
    }
}

fn print_usage_and_exit(code: i32) -> ! {
    eprintln!("Usage: adc-filter-ui [OPTIONS]\n");
    eprintln!("Options:");
    eprintln!("  --port <PATH>    Connect to specific serial port on launch");
    eprintln!("  --simulate       Start in simulation mode");
    eprintln!("\nExamples:");
    eprintln!("  adc-filter-ui");
    eprintln!("  adc-filter-ui --port /dev/tty.usbserial-110");
    eprintln!("  adc-filter-ui COM3");
    eprintln!("  adc-filter-ui --simulate");
    process::exit(code);
}
