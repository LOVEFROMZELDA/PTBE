use std::f32::consts::TAU;

use super::filters::{butterworth_bandpass, butterworth_lowpass, SosCascade};
use crate::FILTER_ORDER;

pub struct AmDemodulator {
    bandpass: SosCascade,
    lpf_i: SosCascade,
    lpf_q: SosCascade,
    phase_accumulator: f32,
    phase_step: f32,
}

impl AmDemodulator {
    pub fn new(sample_rate: f32, carrier_hz: f32, baseband_bw_hz: f32) -> Self {
        let low = (carrier_hz - baseband_bw_hz).max(0.5);
        let high = (carrier_hz + baseband_bw_hz).min(sample_rate * 0.5 - 1.0);
        let bandpass =
            SosCascade::from_sections(butterworth_bandpass(FILTER_ORDER, low, high, sample_rate));
        let baseband_sections = butterworth_lowpass(FILTER_ORDER, baseband_bw_hz, sample_rate);
        let lpf_i = SosCascade::from_sections(baseband_sections.clone());
        let lpf_q = SosCascade::from_sections(baseband_sections);

        let phase_step = TAU * carrier_hz / sample_rate;
        Self {
            bandpass,
            lpf_i,
            lpf_q,
            phase_accumulator: 0.0,
            phase_step,
        }
    }

    pub fn process(&mut self, sample: f32) -> f32 {
        let bandpassed = self.bandpass.process(sample);
        let (sin_p, cos_p) = self.phase_accumulator.sin_cos();
        self.advance_phase();
        let i = self.lpf_i.process(bandpassed * cos_p);
        let q = self.lpf_q.process(bandpassed * sin_p);
        (i * i + q * q).sqrt()
    }

    fn advance_phase(&mut self) {
        self.phase_accumulator += self.phase_step;
        if self.phase_accumulator >= TAU {
            self.phase_accumulator -= TAU;
        }
    }
}
