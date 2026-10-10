
%% CNN-LSTM hyperparameter ablation
% Pooling configurations must preserve valid spatial dimensions.
% Each candidate trains for 12 epochs and is evaluated on validation data.

clear; clc; close all; rng(2026, 'twister');

scriptDir = fileparts(mfilename('fullpath'));
datasetDir = fullfile(scriptDir, 'dataset');
resultsDir = fullfile(scriptDir, 'results');
if ~isfolder(datasetDir)
    error('Extract dataset.zip to: %s', datasetDir);
end
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

%% Load and split data
fprintf('========== 加载数据 ==========\n');
sigds = signalDatastore(datasetDir, IncludeSubfolders=true, ReadFcn=@load);
labels = folders2labels(datasetDir);
sigdata_raw = readall(sigds);
sigdata = cellfun(@(x) x.all_data, sigdata_raw, 'UniformOutput', false);

idx = splitlabels(labels, [0.8 0.1], 'randomized');
trainidx = idx{1}; validx = idx{2}; testidx = idx{3};

traindata = prepareSequenceData(sigdata(trainidx));
trainlabels = labels(trainidx);
valdata = prepareSequenceData(sigdata(validx));
vallabels = labels(validx);
testdata = prepareSequenceData(sigdata(testidx));
testlabels = labels(testidx);

fprintf('训练集: %d, 验证集: %d\n', length(traindata), length(valdata));

% Fixed settings.
inputHeight = 200; inputWidth = 200; numChannels = 1; numClasses = 10;
MiniBatchSize = 16;
Epochs = 12;

%% Experiment 1: Kernel size

fprintf('\n========== 实验 1：卷积核尺寸消融 ==========\n');
kernelCandidates = [3, 5, 7];
results_kernel = table();

defaultFilters = [4, 8, 12];
defaultPool = struct('w', {[5,5], [5,5], [4,4]}, 's', {[5,5], [5,5], [4,4]});
defaultLSTM = 16;
defaultDrop = 0.5;

for i = 1:length(kernelCandidates)
    k = kernelCandidates(i);
    fprintf('>>> 测试 Kernel = %d×%d (%d/%d) ...\n', k, k, i, length(kernelCandidates));
    
    lgraph = buildCNNLSTMGraph(inputHeight, inputWidth, numChannels, numClasses, ...
                               k, defaultFilters, defaultPool, defaultLSTM, defaultDrop);
    [acc, params, time] = trainAndEvaluate(lgraph, traindata, trainlabels, ...
                                           valdata, vallabels, MiniBatchSize, Epochs);
    
    results_kernel = [results_kernel; table(k, acc, params, time, ...
        'VariableNames', {'KernelSize', 'ValAcc', 'Params', 'TrainTime'})];
    fprintf('  验证准确率: %.2f%%  |  参数量: %d  |  耗时: %.1f秒\n', acc*100, params, time);
end

disp(results_kernel);
save(fullfile(resultsDir, 'Ablation_LSTM_Kernel.mat'), 'results_kernel');

%% Experiment 2: Filter counts

fprintf('\n========== 实验 2：CNN通道数消融 ==========\n');
filterCandidates = {[4,8,12], [8,16,24], [2,4,6]};
results_filters = table();

for i = 1:length(filterCandidates)
    f = filterCandidates{i};
    fprintf('>>> 测试通道数 = [%d,%d,%d] (%d/%d) ...\n', f(1), f(2), f(3), i, length(filterCandidates));
    
    lgraph = buildCNNLSTMGraph(inputHeight, inputWidth, numChannels, numClasses, ...
                               3, f, defaultPool, defaultLSTM, defaultDrop);
    [acc, params, time] = trainAndEvaluate(lgraph, traindata, trainlabels, ...
                                           valdata, vallabels, MiniBatchSize, Epochs);
    
    results_filters = [results_filters; table({sprintf('[%d,%d,%d]', f(1), f(2), f(3))}, ...
                       acc, params, time, 'VariableNames', {'Filters', 'ValAcc', 'Params', 'TrainTime'})];
    fprintf('  验证准确率: %.2f%%  |  参数量: %d  |  耗时: %.1f秒\n', acc*100, params, time);
end

disp(results_filters);
save(fullfile(resultsDir, 'Ablation_LSTM_Filters.mat'), 'results_filters');

%% Experiment 3: Pooling configuration

fprintf('\n========== 实验 3：池化配置消融 ==========\n');

poolA = struct('w', {[5,5], [5,5], [4,4]}, 's', {[5,5], [5,5], [4,4]});

poolB = struct('w', {[3,3], [3,3], [2,2]}, 's', {[3,3], [3,3], [2,2]});

fprintf('注意：池化步长受输入尺寸(200×200)约束，必须保证整除。\n');
fprintf('默认配置 [5,5]/[5,5]/[4,4] 经验证可行（200→40→8→2）。\n');
fprintf('受限于架构约束，池化配置固定为默认值，不做消融。\n');

%% Experiment 4: LSTM units

fprintf('\n========== 实验 4：LSTM单元数消融 ==========\n');
lstmCandidates = [16, 8, 32];
results_lstm = table();

for i = 1:length(lstmCandidates)
    u = lstmCandidates(i);
    fprintf('>>> 测试 LSTM单元数 = %d (%d/%d) ...\n', u, i, length(lstmCandidates));
    
    lgraph = buildCNNLSTMGraph(inputHeight, inputWidth, numChannels, numClasses, ...
                               3, defaultFilters, defaultPool, u, defaultDrop);
    [acc, params, time] = trainAndEvaluate(lgraph, traindata, trainlabels, ...
                                           valdata, vallabels, MiniBatchSize, Epochs);
    
    results_lstm = [results_lstm; table(u, acc, params, time, ...
        'VariableNames', {'LSTMUnits', 'ValAcc', 'Params', 'TrainTime'})];
    fprintf('  验证准确率: %.2f%%  |  参数量: %d  |  耗时: %.1f秒\n', acc*100, params, time);
end

disp(results_lstm);
save(fullfile(resultsDir, 'Ablation_LSTM_LSTMUnits.mat'), 'results_lstm');

%% Experiment 5: Dropout rate

fprintf('\n========== 实验 5：Dropout比率消融 ==========\n');
dropCandidates = [0.5, 0.3, 0.7];
results_drop = table();

for i = 1:length(dropCandidates)
    d = dropCandidates(i);
    fprintf('>>> 测试 Dropout = %.1f (%d/%d) ...\n', d, i, length(dropCandidates));
    
    lgraph = buildCNNLSTMGraph(inputHeight, inputWidth, numChannels, numClasses, ...
                               3, defaultFilters, defaultPool, defaultLSTM, d);
    [acc, params, time] = trainAndEvaluate(lgraph, traindata, trainlabels, ...
                                           valdata, vallabels, MiniBatchSize, Epochs);
    
    results_drop = [results_drop; table(d, acc, params, time, ...
        'VariableNames', {'Dropout', 'ValAcc', 'Params', 'TrainTime'})];
    fprintf('  验证准确率: %.2f%%  |  参数量: %d  |  耗时: %.1f秒\n', acc*100, params, time);
end

disp(results_drop);
save(fullfile(resultsDir, 'Ablation_LSTM_Dropout.mat'), 'results_drop');

%% Export summary

fprintf('\n========== 汇总结果到 Excel ==========\n');

% Result files to combine.
matFiles = {
    'KernelSize', 'Ablation_LSTM_Kernel.mat', 'results_kernel';
    'Filters',    'Ablation_LSTM_Filters.mat', 'results_filters';
    'LSTMUnits',  'Ablation_LSTM_LSTMUnits.mat', 'results_lstm';
    'Dropout',    'Ablation_LSTM_Dropout.mat', 'results_drop'
};

outputFile = fullfile(resultsDir, 'Ablation_CNN_LSTM_Summary.xlsx');

for i = 1:size(matFiles, 1)
    sheetName = matFiles{i, 1};
    matFile = matFiles{i, 2};
    varName = matFiles{i, 3};
    
    matPath = fullfile(resultsDir, matFile);
    if exist(matPath, 'file') == 2
        load(matPath);
        if exist(varName, 'var')
            data = eval(varName);
            writetable(data, outputFile, 'Sheet', sheetName);
            fprintf('Wrote %s to sheet %s.\n', matFile, sheetName);
        end
    else
        fprintf('Skipped missing file: %s.\n', matFile);
    end
end

fprintf('汇总完成！保存至: %s\n', outputFile);

%% Local functions

function sequences = prepareSequenceData(cellData)    
    numSamples = length(cellData);
    sequences = cell(numSamples, 1);
    
    for i = 1:numSamples
        video = cellData{i};
        video = reshape(video, size(video,1), size(video,2), 1, size(video,3));
        sequences{i} = video;
    end
end

%% Build a configurable CNN-LSTM

function lgraph = buildCNNLSTMGraph(inputHeight, inputWidth, numChannels, numClasses, ...
                                     kernelSize, numFilters, poolConfig, lstmUnits, dropoutRate)
% kernelSize is a scalar.
% numFilters contains one value per convolution block.
% poolConfig stores each pooling window and stride.
    
    lgraph = layerGraph();
    
% Sequence input and folding.
    tempLayers = [
        sequenceInputLayer([inputHeight inputWidth numChannels], "Name", "input")
        sequenceFoldingLayer("Name", "fold")];
    lgraph = addLayers(lgraph, tempLayers);
    
% Convolution blocks.
    convLayers = [
        convolution2dLayer([kernelSize kernelSize], numFilters(1), "Name", "conv1", "Padding", "same")
        batchNormalizationLayer("Name", "bn1")
        reluLayer("Name", "relu1")
        maxPooling2dLayer(poolConfig(1).w, "Name", "pool1", "Stride", poolConfig(1).s)
        
        convolution2dLayer([kernelSize kernelSize], numFilters(2), "Name", "conv2", "Padding", "same")
        batchNormalizationLayer("Name", "bn2")
        reluLayer("Name", "relu2")
        maxPooling2dLayer(poolConfig(2).w, "Name", "pool2", "Stride", poolConfig(2).s)
        
        convolution2dLayer([kernelSize kernelSize], numFilters(3), "Name", "conv3", "Padding", "same")
        batchNormalizationLayer("Name", "bn3")
        reluLayer("Name", "relu3")
        maxPooling2dLayer(poolConfig(3).w, "Name", "pool3", "Stride", poolConfig(3).s)];
    lgraph = addLayers(lgraph, convLayers);
    
% Sequence unfolding and LSTM.
    rnnLayers = [
        sequenceUnfoldingLayer("Name", "unfold")
        flattenLayer("Name", "flatten")
        lstmLayer(lstmUnits, "Name", "lstm", "OutputMode", "last")
        dropoutLayer(dropoutRate, "Name", "dropout")
        fullyConnectedLayer(numClasses, "Name", "fc1")
        softmaxLayer("Name", "softmax")
        classificationLayer("Name", "output")];
    lgraph = addLayers(lgraph, rnnLayers);
    
% Graph connections.
    lgraph = connectLayers(lgraph, "fold/out", "conv1");
    lgraph = connectLayers(lgraph, "fold/miniBatchSize", "unfold/miniBatchSize");
    lgraph = connectLayers(lgraph, "pool3", "unfold/in");
end

%% Train and evaluate one candidate

function [valAcc, numParams, trainTime] = trainAndEvaluate(lgraph, traindata, trainlabels, valdata, vallabels, MiniBatchSize, Epochs)
    Val_Freq = floor(length(traindata) / MiniBatchSize);
    
    opts = trainingOptions("adam", ...
        ExecutionEnvironment="auto", ...
        MaxEpochs=Epochs, ...
        ValidationPatience=4, ...
        ValidationFrequency=Val_Freq, ...
        MiniBatchSize=MiniBatchSize, ...
        InitialLearnRate=0.001, ...
        GradientThreshold=1, ...
        ValidationData={valdata, vallabels}, ...
        Plots="none", ...
        Verbose=false);
    
    tic;
    net = trainNetwork(traindata, trainlabels, lgraph, opts);
    trainTime = toc;
    
    valPred = classify(net, valdata, 'MiniBatchSize', MiniBatchSize);
    valAcc = mean(valPred == vallabels);
    
% Count trainable parameters.
    numParams = 0;
    for l = 1:length(net.Layers)
        if isprop(net.Layers(l), 'Weights')
            numParams = numParams + numel(net.Layers(l).Weights);
        end
        if isprop(net.Layers(l), 'Bias')
            numParams = numParams + numel(net.Layers(l).Bias);
        end
    end
end
