clear; clc;

t = 0:0.1:5.3;
len = length(t);

%% Plot All Data

% folder_path = ".\data\*";
% file_names = dir(fullfile(folder_path, "*.csv"));
% 
% for i = 1:3
%     figure;
%     hold on
%     for j = 1:100
%         ind = (i-1) * 100 + j;
%         file_path = fullfile(file_names(ind).folder, file_names(ind).name);
%         m = readmatrix(file_path);
%         plot(m, LineWidth=1);
%     end
%     hold off
%     txt = extractAfter(file_names(ind).folder, "data\");
%     title(txt);
% end

%% Import and Pre-process

% Import labeled signal data set into memory.
sigds = signalDatastore("data\",IncludeSubfolders=true,ReadFcn=@readmatrix);
labels = folders2labels("data\");
sigdata = readall(sigds);
% summary(labels);

%% Split data for training, validation, and testing

inputSize = len;
numChannels = 16;

idx = splitlabels(labels,[0.8 0.1]);

trainidx = idx{1};
validx = idx{2};
testidx = idx{3};

traindata = prepareDataForImageInput(sigdata(trainidx), inputSize, numChannels);
trainlabels = labels(trainidx);

valdata = prepareDataForImageInput(sigdata(validx), inputSize, numChannels);
vallabels = labels(validx);

testdata = prepareDataForImageInput(sigdata(testidx), inputSize, numChannels);
testlabels = labels(testidx);

%% Create Architecture

inputSize = len;
numChannels = 16;
numClasses = 10;
flattenedSize = inputSize / 4 * 8;

layers = [
    imageInputLayer([1 inputSize numChannels],"Name","imageinput")

    convolution2dLayer([1 3],4,"Name","conv1","Padding","same")
    batchNormalizationLayer("Name","bn1")
    reluLayer("Name","relu1")
    maxPooling2dLayer([1 2],"Name","pool1","Padding","same","Stride",[1 2])

    convolution2dLayer([1 3],8,"Name","conv2","Padding","same")
    batchNormalizationLayer("Name","bn2")
    reluLayer("Name","relu2")
    maxPooling2dLayer([1 2],"Name","pool2","Padding","same","Stride",[1 2])

    flattenLayer("Name","flatten")
    dropoutLayer(0.5,"Name","dropout")
    fullyConnectedLayer(64,"Name","fc1")
    fullyConnectedLayer(numClasses,"Name","fc2")
    softmaxLayer("Name","softmax")
    classificationLayer("Name","classification")];


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
    ValidationData={valdata vallabels}, ...
    Plots="training-progress");

%% Train the Network

NET = trainNetwork(traindata,trainlabels,layers,opts);

%% Evaluate the Network

predlabels = classify(NET,testdata,'MiniBatchSize',MiniBatchSize);
acc = mean(predlabels == testlabels);
confusionchart(testlabels,predlabels,RowSummary="row-normalized");

%% Function

function X = prepareDataForImageInput(cellData, inputSize, numChannels)
    numSamples = length(cellData);
    X = zeros(1, inputSize, numChannels, numSamples);
    
    for i = 1:numSamples
        sample = cellData{i};
        X(1, :, :, i) = sample;
    end
end



