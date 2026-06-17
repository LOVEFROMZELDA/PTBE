use std::array::from_fn;

use crate::{CHUNK_SIZE, NUM_CHANNELS};

#[derive(Debug, Clone)]
pub struct ProcessedChunk {
    pub raw: Vec<f32>,
    pub filtered_1: Vec<f32>,
    pub filtered_2: Vec<f32>,
}

impl ProcessedChunk {
    pub fn new(raw: Vec<f32>, filtered_1: Vec<f32>, filtered_2: Vec<f32>) -> Self {
        Self {
            raw,
            filtered_1,
            filtered_2,
        }
    }
}

impl Default for ProcessedChunk {
    fn default() -> Self {
        Self {
            raw: Vec::with_capacity(CHUNK_SIZE),
            filtered_1: Vec::with_capacity(CHUNK_SIZE),
            filtered_2: Vec::with_capacity(CHUNK_SIZE),
        }
    }
}

pub type DataPacket = [ProcessedChunk; NUM_CHANNELS];

pub type RawPacket = [Vec<f32>; NUM_CHANNELS];

pub fn empty_raw_packet() -> RawPacket {
    from_fn(|_| Vec::with_capacity(CHUNK_SIZE))
}

pub fn empty_packet() -> DataPacket {
    from_fn(|_| ProcessedChunk::default())
}

#[derive(Debug, Clone)]
pub enum WorkerCommand {
    SetMotor { id: u8, intensity: u8 },
    Disconnect,
    Connect { port: String },
}

impl WorkerCommand {
    /// Serialize the command into the ASCII line required by the serial protocol.
    /// Returns None if the command is an internal worker control command.
    pub fn to_serial_line(&self) -> Option<String> {
        match self {
            WorkerCommand::SetMotor { id, intensity } => {
                Some(format!("SET_MOTOR {} {}\r\n", id, intensity))
            }
            WorkerCommand::Disconnect | WorkerCommand::Connect { .. } => None,
        }
    }
}

#[derive(Debug, Clone)]
pub enum WorkerEvent {
    Telemetry(DataPacket),
    CommandResponse(String),
    Error(String),
    ConnectionState(bool),
}
