use std::io::Cursor;

use crate::NUM_CHANNELS;

pub fn parse_csv_frame(line: &str) -> Option<[f32; NUM_CHANNELS]> {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return None;
    }

    let mut reader = csv::ReaderBuilder::new()
        .has_headers(false)
        .flexible(true)
        .trim(csv::Trim::All)
        .from_reader(Cursor::new(trimmed));

    let mut record = csv::StringRecord::new();
    let has_record = reader.read_record(&mut record).ok()?;
    if !has_record {
        return None;
    }

    if record.len() < NUM_CHANNELS {
        return None;
    }

    let mut values = [0.0f32; NUM_CHANNELS];
    for idx in 0..NUM_CHANNELS {
        let field = record.get(idx)?;
        values[idx] = field.parse().ok()?;
    }
    Some(values)
}
