clear; clc;

%% Import dataset
sigds = signalDatastore(".\dataset\",IncludeSubfolders=true,ReadFcn=@load);
labels = folders2labels(".\dataset\");
sigdata_raw = readall(sigds);
sigdata = cellfun(@(x) x.all_data, sigdata_raw, 'UniformOutput', false);
% summary(labels);

%% Split data
idx = splitlabels(labels,[0.8 0.1]);

trainidx = idx{1};
validx = idx{2};
testidx = idx{3};

traindata = prepareSequenceData(sigdata(trainidx));
trainlabels = labels(trainidx);

valdata = prepareSequenceData(sigdata(validx));
vallabels = labels(validx);

testdata = prepareSequenceData(sigdata(testidx));
testlabels = labels(testidx);

%% Create architecture
inputHeight = 200;
inputWidth = 200;
numChannels = 1;
numFrames = 200;
numClasses = 10;
featureSize = 25 * 25 * 16;

% Create nerual network
lgraph = layerGraph();

tempLayers = [
    sequenceInputLayer([inputHeight inputWidth numChannels],"Name","input")
    sequenceFoldingLayer("Name","fold")];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    convolution2dLayer([3 3],4,"Name","conv1","Padding","same")
    reluLayer("Name","relu1")
    maxPooling2dLayer([5 5],"Name","pool1","Stride",[5 5])
    convolution2dLayer([3 3],8,"Name","conv2","Padding","same")
    reluLayer("Name","relu2")
    maxPooling2dLayer([5 5],"Name","pool2","Stride",[5 5]);
    convolution2dLayer([3 3],12,"Name","conv3","Padding","same")
    reluLayer("Name","relu3")
    maxPooling2dLayer([4 4],"Name","pool3","Stride",[4 4])];
lgraph = addLayers(lgraph,tempLayers);

tempLayers = [
    sequenceUnfoldingLayer("Name","unfold")
    flattenLayer("Name","flatten")
    lstmLayer(16,"Name","lstm","OutputMode","last")
    dropoutLayer(0.5,"Name","dropout")
    fullyConnectedLayer(numClasses,"Name","fc1")
    softmaxLayer("Name","softmax")
    classificationLayer("Name","output")];
lgraph = addLayers(lgraph,tempLayers);

clear tempLayers;

lgraph = connectLayers(lgraph,"fold/out","conv1");
lgraph = connectLayers(lgraph,"fold/miniBatchSize","unfold/miniBatchSize");
lgraph = connectLayers(lgraph,"pool3","unfold/in");
% plot(lgraph);

MiniBatchSize = 16;
Val_Freq = floor(size(traindata, 1) / MiniBatchSize);

opts = trainingOptions("adam", ...
    ExecutionEnvironment="auto", ...
    MaxEpochs=30, ...
    ValidationPatience=7, ...
    ValidationFrequency=Val_Freq, ...
    MiniBatchSize=MiniBatchSize, ...
    InitialLearnRate=0.001, ...
    GradientThreshold=1, ...
    ValidationData={valdata vallabels}, ...
    Plots="training-progress");

trainingInfo = struct('Epoch', [], 'Iteration', [], 'TrainingAccuracy', [], 'TrainingLoss', []);
opts.OutputFcn = @(info) saveTrainingProgress(info);

%% Train the Network

NET = trainNetwork(traindata,trainlabels,lgraph,opts);

%% Evaluate the Network

predlabels = classify(NET,testdata,'MiniBatchSize',MiniBatchSize);
acc = mean(predlabels == testlabels);
confusionchart(testlabels,predlabels,RowSummary="row-normalized");

%% Function

function sequences = prepareSequenceData(cellData)    
    numSamples = length(cellData);
    sequences = cell(numSamples, 1);
    
    for i = 1:numSamples
        video = cellData{i};
        video = reshape(video, size(video,1), size(video,2), 1, size(video,3));
        sequences{i} = video;
    end
end

function stop = saveTrainingProgress(info)
    persistent savedData;
    if info.State == "start"
        savedData = struct('Epoch', [], 'Iteration', [], 'TrainingAccuracy', [], 'TrainingLoss', []);
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

