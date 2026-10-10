clear; clc;

scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, 'data');
modelPath = fullfile(scriptDir, 'Net.mat');
resultsDir = fullfile(scriptDir, 'results');
if ~isfolder(dataDir)
    error('Run signal_segmentation.m first to create: %s', dataDir);
end
if ~isfile(modelPath)
    error('Model file not found: %s', modelPath);
end
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

%% Load data
t = 0:0.1:5.3;
len = length(t);
numChannels = 16;

sigds = signalDatastore(dataDir, IncludeSubfolders=true, ReadFcn=@readmatrix);
labels = folders2labels(dataDir);
sigdata = readall(sigds);

rng(2026, 'twister');
idx = splitlabels(labels, [0.8 0.1], "randomized");
trainidx = idx{1}; validx = idx{2}; testidx = idx{3};

traindata = prepareDataForImageInput(sigdata(trainidx), len, numChannels);
trainlabels = labels(trainidx);
valdata   = prepareDataForImageInput(sigdata(validx), len, numChannels);
vallabels = labels(validx);
testdata  = prepareDataForImageInput(sigdata(testidx), len, numChannels);
testlabels = labels(testidx);

%% Define network
inputSize = len;
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

%% Configure training
MiniBatchSize = 32;
Val_Freq = floor(size(traindata, 4) / MiniBatchSize);
opts = trainingOptions("adam", ...
    ExecutionEnvironment="auto", ...
    MaxEpochs=30, ...
    ValidationPatience=7, ...
    ValidationFrequency=Val_Freq, ...
    MiniBatchSize=MiniBatchSize, ...
    InitialLearnRate=0.001, ...
    GradientThreshold=1, ...
    ValidationData={valdata, vallabels}, ...
    Plots="training-progress");

%% Define array topologies
% Unit positions are [row, column].
unitPos = [1 1; 1 2; 1 3; 1 4; 2 1; 2 2; 2 3; 2 4];
configs = {
    struct('name', 'Full 2×4', 'units', 1:8);
    struct('name', '2×3',      'units', [1 2 3 5 6 7]);
    struct('name', '2×2',      'units', [1 2 5 6]);
    struct('name', '1×4',      'units', 1:4);
    struct('name', '1×2',      'units', 1:2);
    struct('name', 'Single node', 'units', 1);
};

% Build a 16-channel mask for each topology.
masks = cell(length(configs), 1);
for cfg = 1:length(configs)
    mask = false(1, numChannels);
    for u = configs{cfg}.units
        row = unitPos(u,1); col = unitPos(u,2);
        chs = ((row-1)*4 + (col-1))*2 + (1:2);  % Two channels per unit.
        mask(chs) = true;
    end
    masks{cfg} = mask;
end

%% Evaluate fixed topologies
% Retrain each topology when true; otherwise mask the pretrained model.
doRetrain = true;

results = table('Size', [length(configs), 5], ...
    'VariableNames', {'Config', 'Accuracy', 'Confidence', 'Entropy', 'ConfMat'}, ...
    'VariableTypes', {'string', 'double', 'double', 'double', 'cell'});

% Load the pretrained full-array model for masked inference.
if ~doRetrain
    load(modelPath, 'NET');
end

for cfg = 1:length(configs)
    mask = masks{cfg};
    fprintf('Processing %s ...\n', configs{cfg}.name);
    

    trainMasked = applyMaskToData(traindata, mask);
    valMasked   = applyMaskToData(valdata, mask);
    testMasked  = applyMaskToData(testdata, mask);
    
    if doRetrain
        optsNoVal = trainingOptions("adam", ...
            ExecutionEnvironment="auto", ...
            MaxEpochs=30, ...
            ValidationPatience=7, ...
            MiniBatchSize=32, ...
            InitialLearnRate=0.001, ...
            GradientThreshold=1, ...
            Plots="none");
        net = trainNetwork(trainMasked, trainlabels, layers, optsNoVal);
    else
        net = NET;
    end
    

    [pred, scores] = classify(net, testMasked, 'MiniBatchSize', 32);
    acc = mean(pred == testlabels);
    conf = max(scores, [], 2);
    avgConf = mean(conf);
    entropy = -sum(scores .* log2(scores + eps), 2);
    avgEnt = mean(entropy);
    confMat = confusionmat(testlabels, pred);
    
    results.Config(cfg) = configs{cfg}.name;
    results.Accuracy(cfg) = acc;
    results.Confidence(cfg) = avgConf;
    results.Entropy(cfg) = avgEnt;
    results.ConfMat{cfg} = confMat;
    
    fprintf('  Accuracy: %.2f%%, Confidence: %.3f, Entropy: %.3f\n', acc*100, avgConf, avgEnt);
end

disp(results);
writetable(results, fullfile(resultsDir, 'sparsity_results.xlsx'));

%% Evaluate random channel dropout
% Load the full-array model for random dropout.
if doRetrain
    load(modelPath, 'NET');
end
net = NET;

dropoutRatios = [0.2, 0.4, 0.6, 0.8];
numTrials = 30;
randResults = table('Size', [length(dropoutRatios), 4], ...
    'VariableNames', {'DropRatio', 'MeanAcc', 'StdAcc', 'MeanConf'}, ...
    'VariableTypes', {'double', 'double', 'double', 'double'});

for r = 1:length(dropoutRatios)
    ratio = dropoutRatios(r);
    accs = zeros(numTrials, 1);
    confs = zeros(numTrials, 1);
    for trial = 1:numTrials
        numKeep = max(1, round(numChannels * (1 - ratio)));
        keepIdx = randperm(numChannels, numKeep);
        mask = false(1, numChannels);
        mask(keepIdx) = true;
        testMasked = applyMaskToData(testdata, mask);
        [pred, scores] = classify(net, testMasked, 'MiniBatchSize', 32);
        accs(trial) = mean(pred == testlabels);
        confs(trial) = mean(max(scores, [], 2));
    end
    randResults.DropRatio(r) = ratio;
    randResults.MeanAcc(r) = mean(accs);
    randResults.StdAcc(r) = std(accs);
    randResults.MeanConf(r) = mean(confs);
    fprintf('Drop %.0f%%: Acc=%.2f±%.2f%%, Conf=%.3f\n', ratio*100, mean(accs)*100, std(accs)*100, mean(confs));
end
disp(randResults);
writetable(randResults, fullfile(resultsDir, 'random_dropout_results.xlsx'));

%% Plot results
figure;
accVals = results.Accuracy * 100;
bar(1:length(accVals), accVals, 'FaceColor', [0.2 0.6 0.8]);
set(gca, 'XTickLabel', results.Config, 'XTickLabelRotation', 30);
ylabel('Accuracy (%)');
grid on;
ylim([0 100]);

figure;
errorbar(dropoutRatios, randResults.MeanAcc*100, randResults.StdAcc*100, 'o-', ...
    'LineWidth', 1.5, 'MarkerSize', 8);
xlabel('Channel Dropout Ratio');
ylabel('Accuracy (%)');
grid on;
ylim([0 100]);

figure;
plot(dropoutRatios, randResults.MeanConf, 's-', 'LineWidth', 1.5);
xlabel('Channel Dropout Ratio');
ylabel('Average Confidence');
grid on;

%% Local functions
function X = prepareDataForImageInput(cellData, inputSize, numChannels)
% Convert cells to [1, time, channels, samples].
    numSamples = length(cellData);
    X = zeros(1, inputSize, numChannels, numSamples);
    for i = 1:numSamples
        X(1, :, :, i) = cellData{i};
    end
end

function X_masked = applyMaskToData(X, mask)
% Zero masked channels.
    % X: [1, time, channels, samples]
% mask: [1, channels] logical vector.
    maskExp = reshape(mask, [1, 1, numel(mask), 1]);
    X_masked = X .* maskExp;
end
