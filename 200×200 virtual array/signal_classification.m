clear; clc;

scriptDir = fileparts(mfilename('fullpath'));
datasetDir = fullfile(scriptDir, 'dataset');
if ~isfolder(datasetDir)
    error('Extract dataset.zip to: %s', datasetDir);
end

%% Load dataset
sigds = signalDatastore(datasetDir, IncludeSubfolders=true, ReadFcn=@load);
labels = folders2labels(sigds);
sigdataRaw = readall(sigds);
sigdata = cellfun(@(x) x.all_data, sigdataRaw, 'UniformOutput', false);

%% Split data
rng(2026, 'twister');
idx = splitlabels(labels, [0.8 0.1], 'randomized');
trainidx = idx{1};
validx = idx{2};
testidx = idx{3};
splitInfo = struct('seed', 2026, 'trainidx', trainidx, ...
    'validx', validx, 'testidx', testidx);

traindata = prepareSequenceData(sigdata(trainidx));
trainlabels = labels(trainidx);
valdata = prepareSequenceData(sigdata(validx));
vallabels = labels(validx);
testdata = prepareSequenceData(sigdata(testidx));
testlabels = labels(testidx);

%% Define network
inputHeight = 200;
inputWidth = 200;
numChannels = 1;
numClasses = 10;

lgraph = layerGraph();
inputLayers = [
    sequenceInputLayer([inputHeight inputWidth numChannels], "Name", "input")
    sequenceFoldingLayer("Name", "fold")
];
lgraph = addLayers(lgraph, inputLayers);

cnnLayers = [
    convolution2dLayer([3 3], 4, "Name", "conv1", "Padding", "same")
    batchNormalizationLayer("Name", "bn1")
    reluLayer("Name", "relu1")
    maxPooling2dLayer([5 5], "Name", "pool1", "Stride", [5 5])

    convolution2dLayer([3 3], 8, "Name", "conv2", "Padding", "same")
    batchNormalizationLayer("Name", "bn2")
    reluLayer("Name", "relu2")
    maxPooling2dLayer([5 5], "Name", "pool2", "Stride", [5 5])

    convolution2dLayer([3 3], 12, "Name", "conv3", "Padding", "same")
    batchNormalizationLayer("Name", "bn3")
    reluLayer("Name", "relu3")
    maxPooling2dLayer([4 4], "Name", "pool3", "Stride", [4 4])
];
lgraph = addLayers(lgraph, cnnLayers);

outputLayers = [
    sequenceUnfoldingLayer("Name", "unfold")
    flattenLayer("Name", "flatten")
    lstmLayer(16, "Name", "lstm", "OutputMode", "last")
    dropoutLayer(0.5, "Name", "dropout")
    fullyConnectedLayer(numClasses, "Name", "fc1")
    softmaxLayer("Name", "softmax")
    classificationLayer("Name", "output")
];
lgraph = addLayers(lgraph, outputLayers);

lgraph = connectLayers(lgraph, "fold/out", "conv1");
lgraph = connectLayers(lgraph, "fold/miniBatchSize", "unfold/miniBatchSize");
lgraph = connectLayers(lgraph, "pool3", "unfold/in");
%plot(lgraph);

miniBatchSize = 16;
validationFrequency = floor(size(traindata, 1) / miniBatchSize);

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

trainingInfo = struct('Epoch', [], 'Iteration', [], ...
    'TrainingAccuracy', [], 'TrainingLoss', []);
opts.OutputFcn = @(info) saveTrainingProgress(info);

%% Train and evaluate
NET = trainNetwork(traindata, trainlabels, lgraph, opts);
save(fullfile(scriptDir, 'NET.mat'), 'NET', 'splitInfo');

predlabels = classify(NET, testdata, 'MiniBatchSize', miniBatchSize);
acc = mean(predlabels == testlabels);
confusionchart(testlabels, predlabels, RowSummary="row-normalized");

%% Local functions
function sequences = prepareSequenceData(cellData)
    numSamples = length(cellData);
    sequences = cell(numSamples, 1);

    for i = 1:numSamples
        video = cellData{i};
        sequences{i} = reshape(video, size(video, 1), size(video, 2), ...
            1, size(video, 3));
    end
end

function stop = saveTrainingProgress(info)
    persistent savedData;
    if info.State == "start"
        savedData = struct('Epoch', [], 'Iteration', [], ...
            'TrainingAccuracy', [], 'TrainingLoss', []);
    elseif info.State == "iteration"
        if ~isempty(info.TrainingLoss) && ~isempty(info.TrainingAccuracy)
            savedData.Epoch(end+1) = info.Epoch;
            savedData.Iteration(end+1) = info.Iteration;
            savedData.TrainingAccuracy(end+1) = info.TrainingAccuracy;
            savedData.TrainingLoss(end+1) = info.TrainingLoss;
        end
    elseif info.State == "done"
        assignin('base', 'trainingInfo', savedData);
        disp('Training data saved to trainingInfo');
    end
    stop = false;
end

