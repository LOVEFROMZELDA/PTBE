pub mod demod;
pub mod filters;

use crate::pipeline::ProcessedChunk;
use demod::AmDemodulator;
use filters::{butterworth_lowpass, design_notch, SosCascade, SosState};

pub struct ChannelProcessor {
    notch: SosState,
    post_notch_lowpass: SosCascade,
    demodulator: AmDemodulator,
}

impl ChannelProcessor {
    pub fn new(
        sample_rate: f32,
        carrier_hz: f32,
        baseband_bw_hz: f32,
        notch_q: f32,
        filter_order: usize,
    ) -> Self {
        let notch = SosState::from_coeffs(design_notch(sample_rate, carrier_hz, notch_q));
        let lp_sections = butterworth_lowpass(filter_order, baseband_bw_hz, sample_rate);
        let post_notch_lowpass = SosCascade::from_sections(lp_sections);
        let demodulator = AmDemodulator::new(sample_rate, carrier_hz, baseband_bw_hz);
        Self {
            notch,
            post_notch_lowpass,
            demodulator,
        }
    }

    pub fn process_block(&mut self, samples: &[f32]) -> ProcessedChunk {
        if samples.is_empty() {
            return ProcessedChunk::default();
        }

        let mut raw = Vec::with_capacity(samples.len());
        let mut filtered_1 = Vec::with_capacity(samples.len());
        let mut filtered_2 = Vec::with_capacity(samples.len());

        for &sample in samples {
            raw.push(sample);
            let notch_out = self.notch.process(sample);
            let lp_out = self.post_notch_lowpass.process(notch_out);
            filtered_1.push(lp_out);
            let demod_out = self.demodulator.process(sample);
            filtered_2.push(demod_out);
        }

        ProcessedChunk::new(raw, filtered_1, filtered_2)
    }
}
