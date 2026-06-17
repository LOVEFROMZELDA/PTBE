mod parser;
mod serial_worker;

pub use serial_worker::{start_worker_thread, SerialWorkerConfig};
