clear; clc;

scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, 'data');
if ~isfolder(dataDir)
    error('Run signal_segmentation.m first to create: %s', dataDir);
end

time = 0:0.1:5.3;
inputSize = length(time);
numChannels = 16;

%% Load data
sigds = signalDatastore(dataDir, IncludeSubfolders=true, ReadFcn=@readmatrix);
labels = folders2labels(sigds);
sigdata = readall(sigds);

%% Split data
rng(2026, 'twister');
idx = splitlabels(labels, [0.8 0.1], 'randomized');
trainidx = idx{1};
validx = idx{2};
testidx = idx{3};
splitInfo = struct('seed', 2026, 'trainidx', trainidx, ...
    'validx', validx, 'testidx', testidx);

traindata = prepareDataForImageInput(sigdata(trainidx), inputSize, numChannels);
trainlabels = labels(trainidx);
valdata = prepareDataForImageInput(sigdata(validx), inputSize, numChannels);
vallabels = labels(validx);
testdata = prepareDataForImageInput(sigdata(testidx), inputSize, numChannels);
testlabels = labels(testidx);

%% Define network
numClasses = 10;
layers = [
    imageInputLayer([1 inputSize numChannels], "Name", "imageinput")

    convolution2dLayer([1 3], 4, "Name", "conv1", "Padding", "same")
    batchNormalizationLayer("Name", "bn1")
    reluLayer("Name", "relu1")
    maxPooling2dLayer([1 2], "Name", "pool1", "Padding", "same", "Stride", [1 2])

    convolution2dLayer([1 3], 8, "Name", "conv2", "Padding", "same")
    batchNormalizationLayer("Name", "bn2")
    reluLayer("Name", "relu2")
    maxPooling2dLayer([1 2], "Name", "pool2", "Padding", "same", "Stride", [1 2])

    flattenLayer("Name", "flatten")
    dropoutLayer(0.5, "Name", "dropout")
    fullyConnectedLayer(64, "Name", "fc1")
    fullyConnectedLayer(numClasses, "Name", "fc2")
    softmaxLayer("Name", "softmax")
    classificationLayer("Name", "classification")
];

miniBatchSize = 32;
validationFrequency = floor(size(traindata, 4) / miniBatchSize);

opts = trainingOptions("adam", ...
    ExecutionEnvironment="auto", ...
    MaxEpochs=30, ...
    ValidationPatience=7, ...
    ValidationFrequency=validationFrequency, ...
    MiniBatchSize=miniBatchSize, ...
    InitialLearnRate=0.001, ...
    GradientThreshold=1, ...
    ValidationData={valdata vallabels}, ...
    Plots="training-progress");

%% Train and evaluate
NET = trainNetwork(traindata, trainlabels, layers, opts);
save(fullfile(scriptDir, 'Net.mat'), 'NET', 'splitInfo');

predlabels = classify(NET, testdata, 'MiniBatchSize', miniBatchSize);
acc = mean(predlabels == testlabels);
confusionchart(testlabels, predlabels, RowSummary="row-normalized");

%% Local function
function X = prepareDataForImageInput(cellData, inputSize, numChannels)
    numSamples = length(cellData);
    X = zeros(1, inputSize, numChannels, numSamples);

    for i = 1:numSamples
        X(1, :, :, i) = cellData{i};
    end
end



