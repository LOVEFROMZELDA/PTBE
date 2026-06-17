use std::f32::consts::PI;

#[derive(Debug, Clone, Copy)]
pub struct SosCoefficients {
    pub b: [f32; 3],
    pub a: [f32; 3],
}

#[derive(Debug, Clone)]
pub struct SosState {
    z1: f32,
    z2: f32,
    coeffs: SosCoefficients,
}

impl SosState {
    pub fn from_coeffs(coeffs: SosCoefficients) -> Self {
        Self {
            z1: 0.0,
            z2: 0.0,
            coeffs,
        }
    }

    pub fn process(&mut self, x: f32) -> f32 {
        let y = self.coeffs.b[0] * x + self.z1;
        self.z1 = self.coeffs.b[1] * x - self.coeffs.a[1] * y + self.z2;
        self.z2 = self.coeffs.b[2] * x - self.coeffs.a[2] * y;
        y
    }
}

#[derive(Debug, Clone)]
pub struct SosCascade {
    stages: Vec<SosState>,
}

impl SosCascade {
    pub fn from_sections(sections: Vec<SosCoefficients>) -> Self {
        let stages = sections
            .into_iter()
            .map(SosState::from_coeffs)
            .collect::<Vec<_>>();
        Self { stages }
    }

    pub fn process(&mut self, mut sample: f32) -> f32 {
        for stage in &mut self.stages {
            sample = stage.process(sample);
        }
        sample
    }
}

pub fn design_notch(sample_rate: f32, freq: f32, q: f32) -> SosCoefficients {
    let omega = 2.0 * PI * freq / sample_rate.max(1.0);
    let alpha = omega.sin() / (2.0 * q.max(0.01));
    let cos_w0 = omega.cos();

    let b0 = 1.0;
    let b1 = -2.0 * cos_w0;
    let b2 = 1.0;

    let a0 = 1.0 + alpha;
    let a1 = -2.0 * cos_w0;
    let a2 = 1.0 - alpha;

    normalize(b0, b1, b2, a0, a1, a2)
}

fn normalize(b0: f32, b1: f32, b2: f32, a0: f32, a1: f32, a2: f32) -> SosCoefficients {
    let inv_a0 = if a0.abs() < f32::EPSILON {
        1.0
    } else {
        1.0 / a0
    };

    SosCoefficients {
        b: [b0 * inv_a0, b1 * inv_a0, b2 * inv_a0],
        a: [1.0, a1 * inv_a0, a2 * inv_a0],
    }
}

pub fn butterworth_lowpass(
    order: usize,
    cutoff_hz: f32,
    sample_rate_hz: f32,
) -> Vec<SosCoefficients> {
    assert!(
        order >= 2 && order % 2 == 0,
        "Butterworth order must be even and >= 2"
    );
    assert!(
        cutoff_hz > 0.0 && cutoff_hz < sample_rate_hz * 0.5,
        "cutoff must be within (0, Nyquist)"
    );
    let omega_c = prewarp(cutoff_hz, sample_rate_hz);
    butterworth_q_factors(order)
        .into_iter()
        .map(|q| bilinear_lowpass(omega_c, q, sample_rate_hz))
        .collect()
}

pub fn butterworth_highpass(
    order: usize,
    cutoff_hz: f32,
    sample_rate_hz: f32,
) -> Vec<SosCoefficients> {
    assert!(
        order >= 2 && order % 2 == 0,
        "Butterworth order must be even and >= 2"
    );
    assert!(
        cutoff_hz > 0.0 && cutoff_hz < sample_rate_hz * 0.5,
        "cutoff must be within (0, Nyquist)"
    );
    let omega_c = prewarp(cutoff_hz, sample_rate_hz);
    butterworth_q_factors(order)
        .into_iter()
        .map(|q| bilinear_highpass(omega_c, q, sample_rate_hz))
        .collect()
}

pub fn butterworth_bandpass(
    order: usize,
    low_cut_hz: f32,
    high_cut_hz: f32,
    sample_rate_hz: f32,
) -> Vec<SosCoefficients> {
    assert!(
        order >= 4 && order % 4 == 0,
        "bandpass order must be a multiple of 4"
    );
    assert!(
        low_cut_hz > 0.0 && high_cut_hz > low_cut_hz && high_cut_hz < sample_rate_hz * 0.5,
        "invalid band edges"
    );
    let half_order = order / 2;
    let mut sections = Vec::new();
    sections.extend(butterworth_highpass(half_order, low_cut_hz, sample_rate_hz));
    sections.extend(butterworth_lowpass(half_order, high_cut_hz, sample_rate_hz));
    sections
}

fn butterworth_q_factors(order: usize) -> Vec<f32> {
    let sections = order / 2;
    (0..sections)
        .map(|k| {
            let theta = PI * (2.0 * (k as f32) + 1.0) / (2.0 * order as f32);
            1.0 / (2.0 * theta.cos())
        })
        .collect()
}

fn prewarp(cutoff_hz: f32, sample_rate_hz: f32) -> f32 {
    let omega = PI * cutoff_hz / sample_rate_hz;
    (omega.tan()) * 2.0 * sample_rate_hz
}

fn bilinear_lowpass(omega_c: f32, q: f32, sample_rate_hz: f32) -> SosCoefficients {
    let k = 2.0 * sample_rate_hz;
    let omega_sq = omega_c * omega_c;
    let a1 = omega_c / q;
    let a2 = omega_sq;

    let a0_d = k * k + a1 * k + a2;
    let a1_d = -2.0 * k * k + 2.0 * a2;
    let a2_d = k * k - a1 * k + a2;

    let b0_d = omega_sq;
    let b1_d = 2.0 * omega_sq;
    let b2_d = omega_sq;

    SosCoefficients {
        b: [b0_d / a0_d, b1_d / a0_d, b2_d / a0_d],
        a: [1.0, a1_d / a0_d, a2_d / a0_d],
    }
}

fn bilinear_highpass(omega_c: f32, q: f32, sample_rate_hz: f32) -> SosCoefficients {
    let k = 2.0 * sample_rate_hz;
    let omega_sq = omega_c * omega_c;
    let a1 = omega_c / q;
    let a2 = omega_sq;

    let a0_d = k * k + a1 * k + a2;
    let a1_d = -2.0 * k * k + 2.0 * a2;
    let a2_d = k * k - a1 * k + a2;

    let b0_d = k * k;
    let b1_d = -2.0 * k * k;
    let b2_d = k * k;

    SosCoefficients {
        b: [b0_d / a0_d, b1_d / a0_d, b2_d / a0_d],
        a: [1.0, a1_d / a0_d, a2_d / a0_d],
    }
}
