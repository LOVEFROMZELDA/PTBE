
%% Discrete CNN hyperparameter ablation
% Architecture: Conv2D, max pooling, and fully connected layers.

% Run sections independently when needed.

clear; clc; close all; rng(2026, 'twister');

scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, 'data');
resultsDir = fullfile(scriptDir, 'results');
if ~isfolder(dataDir)
    error('Run signal_segmentation.m first to create: %s', dataDir);
end
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

%% Load and preprocess data

fprintf('========== 开始加载数据 ==========\n');

sigds = signalDatastore(dataDir, IncludeSubfolders=true, ReadFcn=@readmatrix);
labels = folders2labels(dataDir);
sigdata = readall(sigds);

sigdata = cellfun(@(x) x - mean(x), sigdata, 'UniformOutput', false);

allData = cat(1, sigdata{:});
globalMean = mean(allData);
globalStd  = std(allData);
globalStd(globalStd == 0) = 1;
sigdata = cellfun(@(x) (x - globalMean) ./ globalStd, sigdata, 'UniformOutput', false);

idx = splitlabels(labels, [0.8 0.1]);
trainidx = idx{1};
validx   = idx{2};
testidx  = idx{3};

inputSize = 3100;
numChannels = 2;
numClasses = 14;

traindata = prepareDataForImageInput(sigdata(trainidx), inputSize, numChannels);
trainlabels = labels(trainidx);
valdata   = prepareDataForImageInput(sigdata(validx), inputSize, numChannels);
vallabels = labels(validx);

fprintf('数据加载完成！训练集: %d, 验证集: %d\n', size(traindata,4), size(valdata,4));

MiniBatchSize = 32;
Val_Freq = floor(size(traindata, 4) / MiniBatchSize);
MaxEpochs = 30;

%% Experiment 1: Kernel width

fprintf('\n========== 实验 1：卷积核宽度消融 ==========\n');

candidates_kernel = [3, 1, 5, 7];
results_kernel = table();

for i = 1:length(candidates_kernel)
    k = candidates_kernel(i);
    fprintf('\n>>> 正在测试卷积核宽度 = %d (%d/%d) ...\n', k, i, length(candidates_kernel));
    

    layers = buildCNNLayers(inputSize, numChannels, numClasses, ...
                            k, [4, 8], 2, 64, 0.5);
    

    opts = trainingOptions("adam", ...
        ExecutionEnvironment="auto", ...
        MaxEpochs=MaxEpochs, ...
        ValidationPatience=7, ...
        ValidationFrequency=Val_Freq, ...
        MiniBatchSize=MiniBatchSize, ...
        InitialLearnRate=0.001, ...
        GradientThreshold=1, ...
        ValidationData={valdata, vallabels}, ...
        Plots="none", ...
        Verbose=false);
    

    tic;
    net = trainNetwork(traindata, trainlabels, layers, opts);
    elapsedTime = toc;
    

    valPred = classify(net, valdata, 'MiniBatchSize', MiniBatchSize);
    valAcc  = mean(valPred == vallabels);
    

    numParams = countParams(net);
    

    results_kernel = [results_kernel; table(k, valAcc, numParams, elapsedTime, ...
        'VariableNames', {'KernelWidth', 'ValAcc', 'Params', 'TrainTime'})];
    
    fprintf('  验证准确率: %.2f%%  |  参数量: %d  |  耗时: %.1f秒\n', valAcc*100, numParams, elapsedTime);
end

disp('----- 实验1结果 -----');
disp(results_kernel);
save(fullfile(resultsDir, 'Ablation_Results_Kernel.mat'), 'results_kernel');

%% Experiment 2: Filter counts

fprintf('\n========== 实验 2：卷积核通道数消融 ==========\n');

candidates_filters = {[4,8], [2,4], [8,16]};
results_filters = table();

for i = 1:length(candidates_filters)
    f = candidates_filters{i};
    fprintf('\n>>> 正在测试通道数 = [%d, %d] (%d/%d) ...\n', f(1), f(2), i, length(candidates_filters));
    
    layers = buildCNNLayers(inputSize, numChannels, numClasses, ...
                            3, f, 2, 64, 0.5);
    
    opts = trainingOptions("adam", ...
        ExecutionEnvironment="auto", ...
        MaxEpochs=MaxEpochs, ...
        ValidationPatience=7, ...
        ValidationFrequency=Val_Freq, ...
        MiniBatchSize=MiniBatchSize, ...
        InitialLearnRate=0.001, ...
        GradientThreshold=1, ...
        ValidationData={valdata, vallabels}, ...
        Plots="none", ...
        Verbose=false);
    
    tic;
    net = trainNetwork(traindata, trainlabels, layers, opts);
    elapsedTime = toc;
    
    valPred = classify(net, valdata, 'MiniBatchSize', MiniBatchSize);
    valAcc  = mean(valPred == vallabels);
    numParams = countParams(net);
    
    results_filters = [results_filters; table( ...
        {sprintf('[%d,%d]', f(1), f(2))}, valAcc, numParams, elapsedTime, ...
        'VariableNames', {'Filters', 'ValAcc', 'Params', 'TrainTime'})];
    
    fprintf('  验证准确率: %.2f%%  |  参数量: %d  |  耗时: %.1f秒\n', valAcc*100, numParams, elapsedTime);
end

disp('----- 实验2结果 -----');
disp(results_filters);
save(fullfile(resultsDir, 'Ablation_Results_Filters.mat'), 'results_filters');

%% Experiment 3: Pooling stride

fprintf('\n========== 实验 3：池化步长消融 ==========\n');

candidates_stride = [2, 1, 3];
results_stride = table();

for i = 1:length(candidates_stride)
    s = candidates_stride(i);
    fprintf('\n>>> 正在测试池化步长 = %d (%d/%d) ...\n', s, i, length(candidates_stride));
    
    layers = buildCNNLayers_stride(inputSize, numChannels, numClasses, ...
                                   3, [4, 8], s, 64, 0.5);
    
    opts = trainingOptions("adam", ...
        ExecutionEnvironment="auto", ...
        MaxEpochs=MaxEpochs, ...
        ValidationPatience=7, ...
        ValidationFrequency=Val_Freq, ...
        MiniBatchSize=MiniBatchSize, ...
        InitialLearnRate=0.001, ...
        GradientThreshold=1, ...
        ValidationData={valdata, vallabels}, ...
        Plots="none", ...
        Verbose=false);
    
    tic;
    net = trainNetwork(traindata, trainlabels, layers, opts);
    elapsedTime = toc;
    
    valPred = classify(net, valdata, 'MiniBatchSize', MiniBatchSize);
    valAcc  = mean(valPred == vallabels);
    numParams = countParams(net);
    
    results_stride = [results_stride; table(s, valAcc, numParams, elapsedTime, ...
        'VariableNames', {'Stride', 'ValAcc', 'Params', 'TrainTime'})];
    
    fprintf('  验证准确率: %.2f%%  |  参数量: %d  |  耗时: %.1f秒\n', valAcc*100, numParams, elapsedTime);
end

disp('----- 实验3结果 -----');
disp(results_stride);
save(fullfile(resultsDir, 'Ablation_Results_Stride.mat'), 'results_stride');

%% Experiment 4: Fully connected units

fprintf('\n========== 实验 4：全连接层单元数消融 ==========\n');

candidates_fc = [64, 32, 128];
results_fc = table();

for i = 1:length(candidates_fc)
    fc = candidates_fc(i);
    fprintf('\n>>> 正在测试FC单元数 = %d (%d/%d) ...\n', fc, i, length(candidates_fc));
    
    layers = buildCNNLayers(inputSize, numChannels, numClasses, ...
                            3, [4, 8], 2, fc, 0.5);
    
    opts = trainingOptions("adam", ...
        ExecutionEnvironment="auto", ...
        MaxEpochs=MaxEpochs, ...
        ValidationPatience=7, ...
        ValidationFrequency=Val_Freq, ...
        MiniBatchSize=MiniBatchSize, ...
        InitialLearnRate=0.001, ...
        GradientThreshold=1, ...
        ValidationData={valdata, vallabels}, ...
        Plots="none", ...
        Verbose=false);
    
    tic;
    net = trainNetwork(traindata, trainlabels, layers, opts);
    elapsedTime = toc;
    
    valPred = classify(net, valdata, 'MiniBatchSize', MiniBatchSize);
    valAcc  = mean(valPred == vallabels);
    numParams = countParams(net);
    
    results_fc = [results_fc; table(fc, valAcc, numParams, elapsedTime, ...
        'VariableNames', {'FCUnits', 'ValAcc', 'Params', 'TrainTime'})];
    
    fprintf('  验证准确率: %.2f%%  |  参数量: %d  |  耗时: %.1f秒\n', valAcc*100, numParams, elapsedTime);
end

disp('----- 实验4结果 -----');
disp(results_fc);
save(fullfile(resultsDir, 'Ablation_Results_FC.mat'), 'results_fc');

%% Experiment 5: Dropout rate

fprintf('\n========== 实验 5：Dropout比率消融 ==========\n');

candidates_drop = [0.5, 0.3, 0.7];
results_drop = table();

for i = 1:length(candidates_drop)
    d = candidates_drop(i);
    fprintf('\n>>> 正在测试Dropout = %.1f (%d/%d) ...\n', d, i, length(candidates_drop));
    
    layers = buildCNNLayers(inputSize, numChannels, numClasses, ...
                            3, [4, 8], 2, 64, d);
    
    opts = trainingOptions("adam", ...
        ExecutionEnvironment="auto", ...
        MaxEpochs=MaxEpochs, ...
        ValidationPatience=7, ...
        ValidationFrequency=Val_Freq, ...
        MiniBatchSize=MiniBatchSize, ...
        InitialLearnRate=0.001, ...
        GradientThreshold=1, ...
        ValidationData={valdata, vallabels}, ...
        Plots="none", ...
        Verbose=false);
    
    tic;
    net = trainNetwork(traindata, trainlabels, layers, opts);
    elapsedTime = toc;
    
    valPred = classify(net, valdata, 'MiniBatchSize', MiniBatchSize);
    valAcc  = mean(valPred == vallabels);
    numParams = countParams(net);
    
    results_drop = [results_drop; table(d, valAcc, numParams, elapsedTime, ...
        'VariableNames', {'Dropout', 'ValAcc', 'Params', 'TrainTime'})];
    
    fprintf('  验证准确率: %.2f%%  |  参数量: %d  |  耗时: %.1f秒\n', valAcc*100, numParams, elapsedTime);
end

disp('----- 实验5结果 -----');
disp(results_drop);
save(fullfile(resultsDir, 'Ablation_Results_Dropout.mat'), 'results_drop');

%% Experiment 6: Input window length

fprintf('\n========== 实验 6：窗口长度消融（需重切数据，较耗时） ==========\n');

candidates_win = [3100, 1550, 6200];
results_win = table();

for i = 1:length(candidates_win)
    win = candidates_win(i);
    fprintf('\n>>> 正在测试窗口长度 = %d (%d/%d) ...\n', win, i, length(candidates_win));
    

    traindata_win = prepareDataForImageInput_win(sigdata(trainidx), win, numChannels);
    valdata_win   = prepareDataForImageInput_win(sigdata(validx), win, numChannels);
    

    local_Val_Freq = floor(size(traindata_win, 4) / MiniBatchSize);
    

    layers = buildCNNLayers(win, numChannels, numClasses, ...
                            3, [4, 8], 2, 64, 0.5);
    
    opts = trainingOptions("adam", ...
        ExecutionEnvironment="auto", ...
        MaxEpochs=MaxEpochs, ...
        ValidationPatience=7, ...
        ValidationFrequency=local_Val_Freq, ...
        MiniBatchSize=MiniBatchSize, ...
        InitialLearnRate=0.001, ...
        GradientThreshold=1, ...
        ValidationData={valdata_win, vallabels}, ...
        Plots="none", ...
        Verbose=false);
    
    tic;
    net = trainNetwork(traindata_win, trainlabels, layers, opts);
    elapsedTime = toc;
    
    valPred = classify(net, valdata_win, 'MiniBatchSize', MiniBatchSize);
    valAcc  = mean(valPred == vallabels);
    numParams = countParams(net);
    
    results_win = [results_win; table(win, valAcc, numParams, elapsedTime, ...
        'VariableNames', {'WindowLen', 'ValAcc', 'Params', 'TrainTime'})];
    
    fprintf('  验证准确率: %.2f%%  |  参数量: %d  |  耗时: %.1f秒\n', valAcc*100, numParams, elapsedTime);
end

disp('----- 实验6结果 -----');
disp(results_win);
save(fullfile(resultsDir, 'Ablation_Results_Window.mat'), 'results_win');

fprintf('\n========== 所有消融实验执行完毕！ ==========\n');

%% Local functions

%% Build the configurable CNN
function layers = buildCNNLayers(inputSize, numChannels, numClasses, ...
                                 kernelWidth, numFilters, stride, fcUnits, dropoutRate)
    layers = [
        imageInputLayer([1 inputSize numChannels], "Name", "imageinput")
        
        convolution2dLayer([1, kernelWidth], numFilters(1), "Name", "conv1", "Padding", "same")
        batchNormalizationLayer("Name","bn1")
        reluLayer("Name","relu1")
        maxPooling2dLayer([1, 2], "Name", "pool1", "Padding", "same", "Stride", [1, stride])
        
        convolution2dLayer([1, kernelWidth], numFilters(2), "Name", "conv2", "Padding", "same")
        batchNormalizationLayer("Name","bn2")
        reluLayer("Name","relu2")
        maxPooling2dLayer([1, 2], "Name", "pool2", "Padding", "same", "Stride", [1, stride])
        
        flattenLayer("Name","flatten")
        dropoutLayer(dropoutRate, "Name","dropout")
        fullyConnectedLayer(fcUnits, "Name","fc1")
        fullyConnectedLayer(numClasses, "Name","fc2")
        softmaxLayer("Name","softmax")
        classificationLayer("Name","classification")
    ];
end

%% Build the pooling-stride variant
function layers = buildCNNLayers_stride(inputSize, numChannels, numClasses, ...
                                        kernelWidth, numFilters, stride, fcUnits, dropoutRate)

    layers = [
        imageInputLayer([1 inputSize numChannels], "Name", "imageinput")
        
        convolution2dLayer([1, kernelWidth], numFilters(1), "Name", "conv1", "Padding", "same")
        batchNormalizationLayer("Name","bn1")
        reluLayer("Name","relu1")
        maxPooling2dLayer([1, 2], "Name", "pool1", "Padding", "same", "Stride", [1, stride])
        
        convolution2dLayer([1, kernelWidth], numFilters(2), "Name", "conv2", "Padding", "same")
        batchNormalizationLayer("Name","bn2")
        reluLayer("Name","relu2")
        maxPooling2dLayer([1, 2], "Name", "pool2", "Padding", "same", "Stride", [1, stride])
        
        flattenLayer("Name","flatten")
        dropoutLayer(dropoutRate, "Name","dropout")
        fullyConnectedLayer(fcUnits, "Name","fc1")
        fullyConnectedLayer(numClasses, "Name","fc2")
        softmaxLayer("Name","softmax")
        classificationLayer("Name","classification")
    ];
end

%% Count trainable parameters
function totalParams = countParams(net)
    totalParams = 0;
    for l = 1:length(net.Layers)
        if isprop(net.Layers(l), 'Weights')
            totalParams = totalParams + numel(net.Layers(l).Weights);
        end
        if isprop(net.Layers(l), 'Bias')
            totalParams = totalParams + numel(net.Layers(l).Bias);
        end
    end
end

%% Prepare fixed-length inputs
function X = prepareDataForImageInput(cellData, inputSize, numChannels)
    numSamples = length(cellData);
    X = zeros(1, inputSize, numChannels, numSamples);
    for i = 1:numSamples
        sample = cellData{i};

        if size(sample, 1) < inputSize
            sample = [sample; zeros(inputSize - size(sample,1), numChannels)];
        else
            sample = sample(1:inputSize, :);
        end
        X(1, :, :, i) = sample;
    end
end

%% Prepare variable-length inputs
function X = prepareDataForImageInput_win(cellData, inputSize, numChannels)
    numSamples = length(cellData);
    X = zeros(1, inputSize, numChannels, numSamples);
    for i = 1:numSamples
        sample = cellData{i};
        if size(sample, 1) < inputSize
            sample = [sample; zeros(inputSize - size(sample,1), numChannels)];
        else
            sample = sample(1:inputSize, :);
        end
        X(1, :, :, i) = sample;
    end
end
