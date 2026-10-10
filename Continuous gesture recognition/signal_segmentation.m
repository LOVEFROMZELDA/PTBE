clear; clc;
rng(2026, 'twister');

scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);
sourceDir = fullfile(scriptDir, 'data_origin');
dataDir = fullfile(scriptDir, 'data');

if ~isfolder(sourceDir)
    error('Extract data_origin.zip to: %s', sourceDir);
end

time = 0:0.1:5.3;
sequenceLength = length(time);
numChannels = 16;

%% Convert each recording to a 16-channel sample
fileNames = dir(fullfile(sourceDir, '*', '*.xlsx'));
expectedFileCount = 10 * 100;
if numel(fileNames) ~= expectedFileCount
    error('Expected %d XLSX files under %s, found %d.', ...
        expectedFileCount, sourceDir, numel(fileNames));
end

params.snr_db = 10;
params.density = 0.03;
params.amplitude_factor = 1.5;

for ind = 1:numel(fileNames)
    filePath = fullfile(fileNames(ind).folder, fileNames(ind).name);
    m = readmatrix(filePath);
    if size(m, 1) < sequenceLength || size(m, 2) < numChannels + 1
        error('Unexpected sample size in %s.', filePath);
    end

    m = m(1:sequenceLength, :);
    noisyData = zeros(sequenceLength, numChannels);
    for channel = 1:numChannels
        noisyData(:, channel) = addNoiseToSignal(m(:, channel + 1), 'both', params);
    end
    if any(isnan(noisyData), 'all')
        error('Noise generation produced NaN values for %s.', filePath);
    end

    [~, className] = fileparts(fileNames(ind).folder);
    classId = str2double(className);
    if isnan(classId)
        error('Invalid class folder: %s', fileNames(ind).folder);
    end

    outputDir = fullfile(dataDir, sprintf('%02d', classId));
    if ~isfolder(outputDir)
        mkdir(outputDir);
    end

    [~, fileStem] = fileparts(fileNames(ind).name);
    trialId = extractAfter(string(fileStem), '_');
    outputName = sprintf('%s_%s.csv', className, char(trialId));
    writematrix(noisyData, fullfile(outputDir, outputName));
end
