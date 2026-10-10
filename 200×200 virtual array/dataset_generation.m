clear; clc;
rng(2026, 'twister');

scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);
waveformPath = fullfile(scriptDir, 'waveform', 'sample.xlsx');
datasetDir = fullfile(scriptDir, 'dataset');

if ~isfile(waveformPath)
    error('Waveform file not found: %s', waveformPath);
end

%% Configure generator
params.fs = 1000;
params.array_size = 200;
params.time_total = 1;
params.selected_row = 100;
params.selected_col = 100;
params.category = 0;
params.speed = 4;
params.delta = 4.5;

selectedRow = zeros(1, 1200);
for block = 1:12
    uniqueNumbers = randperm(141, 100) + 29;
    shuffledNumbers = uniqueNumbers(randperm(100));
    startIndex = (block - 1) * 100 + 1;
    endIndex = block * 100;
    selectedRow(startIndex:endIndex) = shuffledNumbers;
end

%% Generate dataset
for category = 1:10
    params.category = category;

    outputDir = fullfile(datasetDir, sprintf('%02d', category));
    if ~isfolder(outputDir)
        mkdir(outputDir);
    end

    for sampleId = 1:100
        params.selected_row = selectedRow(sampleId * category);
        params.selected_col = selectedRow(sampleId * category + 200);
        outputPath = fullfile(outputDir, sprintf('%d_%03d.mat', category, sampleId));

        if ismember(category, 1:8)
            myFun_sweep(waveformPath, outputPath, params);
        elseif ismember(category, 9:10)
            myFun_press(waveformPath, outputPath, params);
        else
            error('No such category: %d.', category);
        end
    end
end


