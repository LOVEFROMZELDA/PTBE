clear; clc;
rng(2026, 'twister');

scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);
sourceDir = fullfile(scriptDir, 'data_origin');
dataDir = fullfile(scriptDir, 'data');

if ~isfolder(sourceDir)
    error('Extract data_origin.zip to: %s', sourceDir);
end

%% Segment each recording into ten samples
fileNames = dir(fullfile(sourceDir, '*', '*.xlsx'));
expectedFileCount = 14 * 10;
if numel(fileNames) ~= expectedFileCount
    error('Expected %d XLSX files under %s, found %d.', ...
        expectedFileCount, sourceDir, numel(fileNames));
end

params.snr_db = 20;
params.density = 0.05;
params.amplitude_factor = 1.5;
segmentCount = 10;
outputLength = 3100;

for ind = 1:numel(fileNames)
    filePath = fullfile(fileNames(ind).folder, fileNames(ind).name);
    m = readmatrix(filePath);
    if size(m, 2) < 3
        error('Expected at least three columns in %s.', filePath);
    end

    noisyData = zeros(size(m, 1), 2);

    baseLength = floor(size(m, 1) / segmentCount);
    seq10 = (1:baseLength) + 9 * baseLength;
    seq9 = (1:baseLength) + 8 * baseLength;
    [~, index10] = min(m(seq10, 3));
    [~, index9] = min(m(seq9, 3));
    segmentLength = index10 - index9 + baseLength;
    delay = max(floor(baseLength / 2 - index10), 0);

    noisyData(:, 1) = addNoiseToSignal(m(:, 2), 'both', params);
    noisyData(:, 2) = addNoiseToSignal(m(:, 3), 'both', params);
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
    trialId = extractAfter(string(fileStem), '.');

    for segmentId = 1:segmentCount
        sampleIndices = size(m, 1) - segmentLength - 1 - delay ...
            + (1:segmentLength) - (segmentId - 1) * segmentLength;
        if min(sampleIndices) < 1 || max(sampleIndices) > size(m, 1)
            error('Invalid segment indices for %s.', filePath);
        end

        segment = noisyData(sampleIndices, :);
        if size(segment, 1) < outputLength
            error('Segment in %s is shorter than %d samples.', filePath, outputLength);
        end

        outputName = sprintf('%s_%s_%d.csv', className, char(trialId), ...
            segmentCount + 1 - segmentId);
        writematrix(segment(1:outputLength, :), fullfile(outputDir, outputName));
    end
end



