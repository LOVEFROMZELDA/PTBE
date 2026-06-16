clear; clc;

%% Set parameters
input = '.\waveform\sample.xlsx';
output = 'data';

params.fs = 1000;
params.array_size = 200;
params.time_per_frame = 0.1;
params.selected_row = 100;
params.selected_col = 100;
params.category = 0;
params.speed = 4;
params.delta = 4.5;

selected_row = zeros(1, 1200);
for i = 1:12
    unique_numbers = randperm(141, 100) + 29;
    shuffled_numbers = unique_numbers(randperm(100));
    
    start_idx = (i-1) * 100 + 1;
    end_idx = i * 100;
    selected_row(start_idx:end_idx) = shuffled_numbers;
end

%% Generate dataset
for category = 1:10
    params.category = category;
    
    for i = 1:100
        params.selected_row = selected_row(i*category);
        params.selected_col = selected_row(i*category + 200);

        txt_folder = sprintf("%02d", category);
        txt_file = sprintf("%03d.mat", i);
        name_dir = ".\dataset\"+txt_folder;
        if ~exist(name_dir, "dir")
            mkdir(name_dir);
        end
        output = name_dir + "\" + num2str(category) + "_" + txt_file;

        if ismember(category, 1:8)
            myFun_sweep(input, output, params);
        elseif ismember(category, 9:10)
            myFun_press(input, output, params);
        else
            error('No such category %d.', category);
        end
    end
end


