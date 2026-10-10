clear; clc; close all;

% This demo evaluates one deterministic test split, not a multi-run mean.
scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, 'data');
modelPath = fullfile(scriptDir, 'Net.mat');
inputSize = 54;
numChannels = 16;
miniBatchSize = 32;

if ~isfolder(dataDir)
    error('Run signal_segmentation.m first to create: %s', dataDir);
end
if ~isfile(modelPath)
    error('Model file not found: %s', modelPath);
end

modelData = load(modelPath);
if ~isfield(modelData, 'NET')
    error('Model file is missing the NET variable: %s', modelPath);
end

sigds = signalDatastore(dataDir, IncludeSubfolders=true, ReadFcn=@readmatrix);
labels = folders2labels(sigds);
if numel(sigds.Files) ~= numel(labels)
    error('The number of data files and labels does not match.');
end

[testidx, splitSource] = selectTestIndices(modelData, labels);
testFiles = sigds.Files(testidx);
testLabels = labels(testidx);
testSignals = readNumericFiles(testFiles, inputSize, numChannels);
testData = prepareDataForImageInput(testSignals, inputSize, numChannels);

predictedLabels = classify(modelData.NET, testData, ...
    MiniBatchSize=miniBatchSize);
overallAccuracy = mean(predictedLabels == testLabels);
classSummary = summarizeByClass(testLabels, predictedLabels);

fprintf('\nTask: Continuous gesture recognition\n');
fprintf('Evaluation split: %s\n', splitSource);
fprintf('Test samples: %d\n', numel(testLabels));
fprintf('Overall accuracy: %.2f%%\n\n', 100 * overallAccuracy);
disp(classSummary);

figure(Name='Continuous gesture recognition - test confusion matrix');
chart = confusionchart(testLabels, predictedLabels, ...
    Normalization='row-normalized', RowSummary='row-normalized');
chart.Title = 'Continuous gesture recognition - test set';

%% Local functions
function [testidx, splitSource] = selectTestIndices(modelData, labels)
    if isfield(modelData, 'splitInfo') && ...
            isfield(modelData.splitInfo, 'testidx')
        testidx = modelData.splitInfo.testidx;
        validateTestIndices(testidx, numel(labels));
        splitSource = 'indices stored with the model';
        return;
    end

    warning('CNN_sample:MissingSplitInfo', ...
        ['The model does not contain splitInfo. Using the public seed-2026 ' ...
         'split. Retrain with signal_classification.m to bind the model to ' ...
         'this exact test split.']);
    rng(2026, 'twister');
    idx = splitlabels(labels, [0.8 0.1], 'randomized');
    testidx = idx{3};
    splitSource = 'seed-2026 split (not stored with this model)';
end

function validateTestIndices(testidx, numSamples)
    if islogical(testidx)
        if numel(testidx) ~= numSamples || ~any(testidx)
            error('Stored logical test indices are invalid for this dataset.');
        end
    elseif ~isnumeric(testidx) || isempty(testidx) || ...
            any(testidx < 1 | testidx > numSamples | testidx ~= fix(testidx))
        error('Stored numeric test indices are invalid for this dataset.');
    end
end

function signals = readNumericFiles(files, inputSize, numChannels)
    signals = cell(numel(files), 1);
    for i = 1:numel(files)
        signals{i} = readmatrix(files{i});
        if size(signals{i}, 1) ~= inputSize || ...
                size(signals{i}, 2) ~= numChannels
            error('Unexpected data size in: %s', files{i});
        end
    end
end

function X = prepareDataForImageInput(cellData, inputSize, numChannels)
    numSamples = numel(cellData);
    X = zeros(1, inputSize, numChannels, numSamples);
    for i = 1:numSamples
        X(1, :, :, i) = cellData{i};
    end
end

function summaryTable = summarizeByClass(trueLabels, predictedLabels)
    classNames = categories(trueLabels);
    sampleCount = zeros(numel(classNames), 1);
    correctCount = zeros(numel(classNames), 1);

    for i = 1:numel(classNames)
        mask = trueLabels == classNames{i};
        sampleCount(i) = sum(mask);
        correctCount(i) = sum(predictedLabels(mask) == trueLabels(mask));
    end

    accuracyPercent = 100 * correctCount ./ sampleCount;
    summaryTable = table(string(classNames(:)), sampleCount, correctCount, ...
        accuracyPercent, VariableNames={...
        'Class', 'Samples', 'Correct', 'AccuracyPercent'});
end
