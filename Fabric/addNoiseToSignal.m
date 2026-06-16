function noisy_signal = addNoiseToSignal(signal, noise_type, params)

    signal_mean = mean(signal);
    signal_std = std(signal);
%     signal_mean = 0;
%     signal_std = 1;
    signal_normalized = (signal - signal_mean) / signal_std;
    noisy_normalized = signal_normalized;
    
    switch noise_type
        case 'gaussian'
            if isfield(params, 'snr_db')
                snr_db = params.snr_db;
            else
                snr_db = 40;
            end
            
            signal_power = mean(signal_normalized.^2);
            noise_power = signal_power / (10^(snr_db/10));
            gaussian_noise = sqrt(noise_power) * randn(size(signal_normalized));
            noisy_normalized = signal_normalized + gaussian_noise;
            
        case 'saltpepper'
            if isfield(params, 'density')
                density = params.density;
            else
                density = 0.01;
            end
            
            if isfield(params, 'amplitude_factor')
                amp_factor = params.amplitude_factor;
            else
                amp_factor = 0.2;
            end
            
            n = length(signal_normalized);
            num_affected = round(density * n);
            affected_idx = randperm(n, min(num_affected, n));
            
            impulse_noise = zeros(size(signal_normalized));
            signal_range = max(signal_normalized) - min(signal_normalized);
            impulse_amplitude = amp_factor * signal_range;
            
            is_salt = rand(size(affected_idx)) > 0.5;
            impulse_noise(affected_idx(is_salt)) = impulse_amplitude;
            impulse_noise(affected_idx(~is_salt)) = -impulse_amplitude;
            
            noisy_normalized = signal_normalized + impulse_noise;
            
        case 'both'
            if isfield(params, 'snr_db')
                snr_db = params.snr_db;
            else
                snr_db = 40;
            end
            
            if isfield(params, 'density')
                density = params.density;
            else
                density = 0.01;
            end
            
            if isfield(params, 'amplitude_factor')
                amp_factor = params.amplitude_factor;
            else
                amp_factor = 0.2;
            end
            
            signal_power = mean(signal_normalized.^2);
            noise_power = signal_power / (10^(snr_db/10));
            gaussian_noise = sqrt(noise_power) * randn(size(signal_normalized));
            temp_signal = signal_normalized + gaussian_noise;
            
            n = length(temp_signal);
            num_affected = round(density * n);
            affected_idx = randperm(n, min(num_affected, n));
            
            impulse_noise = zeros(size(temp_signal));
            signal_range = max(temp_signal) - min(temp_signal);
            impulse_amplitude = amp_factor * signal_range;
            
            is_salt = rand(size(affected_idx)) > 0.5;
            impulse_noise(affected_idx(is_salt)) = impulse_amplitude;
            impulse_noise(affected_idx(~is_salt)) = -impulse_amplitude;
            
            noisy_normalized = temp_signal + impulse_noise;
    end

    noisy_signal = noisy_normalized * signal_std + signal_mean;
    
end


