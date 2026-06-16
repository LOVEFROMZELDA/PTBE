function myFun_press(input, output, params)

%% Load input file
m = readmatrix(input);
waveform_even= m(:, 2);
waveform_odd = m(:, 3);

waveform_even = waveform_even - min(waveform_even);
waveform_even = waveform_even / max(waveform_even);
waveform_odd = waveform_odd - max(waveform_odd);
waveform_odd = waveform_odd / abs(min(waveform_odd));

len = length(waveform_even);

%% Load parameters and creare array
if isfield(params, 'fs')
    fs = params.fs;
else
    fs = 1000;
end
duration = len / fs;

if isfield(params, 'array_size')
    array_size = params.array_size;
else
    array_size = 200;
end

if isfield(params, 'time_per_frame')
    time_per_frame = params.time_per_frame;
else
    time_per_frame = 0.1;
end

if isfield(params, 'selected_row')
    selected_row = params.selected_row;
else
    selected_row = array_size / 2;
end

if isfield(params, 'selected_col')
    selected_col = params.selected_col;
else
    selected_col = array_size / 2;
end

if isfield(params, 'speed')
    speed = params.speed;
else
    speed = 1;
end

if isfield(params, 'delta')
    delta = params.delta;
else
    delta = 1;
end

[x_grid, y_grid] = meshgrid(1:array_size, 1:array_size);
intensity1 = zeros(array_size);
intensity2 = zeros(array_size);
total_frames = array_size / speed;
all_data = zeros(array_size, array_size, total_frames);

if isfield(params, 'category')
    category = params.category;
else
    category = 0;
end

switch category
    case 9  % press single core
        double = 0;
    
    case 10  % press double core
        double = 1;
        
    otherwise
        error('Error category');
end

%% Generate data
distance1 = sqrt((x_grid - selected_col).^2 + (y_grid - selected_row).^2);
distance1 = distance1 * time_per_frame;
distance2 = sqrt((x_grid - selected_col - delta).^2 + (y_grid - selected_row).^2);
distance2 = distance2 * time_per_frame;
for i = 1:array_size
    for j = 1:array_size
        if distance1(i,j) > duration
            intensity1(i,j) = 0;
        else
            n1 = floor(distance1(i,j) / duration * len);
            if mod(j, 2)
                intensity1(i,j) = waveform_even(max(n1, 1));
            else
                intensity1(i,j) = waveform_odd(max(n1, 1));
            end
        end

        if distance2(i,j) > duration
            intensity2(i,j) = 0;
        else
            n2 = floor(distance2(i,j) / duration * len);
            if mod(j, 2)
                intensity2(i,j) = waveform_even(max(n2, 1));
            else
                intensity2(i,j) = waveform_odd(max(n2, 1));
            end
        end
    end
end

for frame = 1:total_frames
    ratio = 1 - abs(1 - 2 * frame / total_frames);
    intensity1_tmp = intensity1 * ratio;
    intensity2_tmp = intensity2 * ratio;

    if double
        intensity = (intensity1_tmp + intensity2_tmp) / 2;
    else
        intensity = intensity1_tmp;
    end

    all_data(:, :, frame) = intensity;
end

%% Save all data
all_data = single(all_data);
save(output, 'all_data');

end