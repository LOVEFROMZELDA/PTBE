%% ========================================================================
%  超参数消融实验完整脚本
%  适用架构：CNN (Conv2D + MaxPooling + FC)
%  作者：根据审稿意见编写
%  说明：每次只运行一个实验部分（用 %% 分隔），跑完记录结果
% ========================================================================

clear; clc; close all; rng(2026);  % 固定随机种子，保证可重复

%% ========================================================================
%  第一部分：数据加载与预处理（固定不变，所有实验共用）
% ========================================================================

fprintf('========== 开始加载数据 ==========\n');

% 1. 读取数据
sigds = signalDatastore("data\", IncludeSubfolders=true, ReadFcn=@readmatrix);
labels = folders2labels("data\");
sigdata = readall(sigds);

% 2. 去基线
sigdata = cellfun(@(x) x - mean(x), sigdata, 'UniformOutput', false);

% 3. 全局归一化
allData = cat(1, sigdata{:});
globalMean = mean(allData);
globalStd  = std(allData);
globalStd(globalStd == 0) = 1;
sigdata = cellfun(@(x) (x - globalMean) ./ globalStd, sigdata, 'UniformOutput', false);

% 4. 划分训练/验证/测试集（固定划分，保证不同实验公平可比）
idx = splitlabels(labels, [0.8 0.1]);
trainidx = idx{1};
validx   = idx{2};
testidx  = idx{3};

% 基础参数（窗口长度默认3100）
inputSize = 3100;
numChannels = 2;
numClasses = 14;

% 准备训练集和验证集（仅用于窗口长度不变的实验）
traindata = prepareDataForImageInput(sigdata(trainidx), inputSize, numChannels);
trainlabels = labels(trainidx);
valdata   = prepareDataForImageInput(sigdata(validx), inputSize, numChannels);
vallabels = labels(validx);

fprintf('数据加载完成！训练集: %d, 验证集: %d\n', size(traindata,4), size(valdata,4));

% 通用训练参数
MiniBatchSize = 32;
Val_Freq = floor(size(traindata, 4) / MiniBatchSize);
MaxEpochs = 30;  % 正式实验用30，快速测试可改10

%% ========================================================================
%  辅助函数：构建网络 + 训练 + 评估（放在文件底部，这里先定义调用）
% ========================================================================

% (函数定义见文件末尾，MATLAB要求主脚本中函数写在最后)

%% ========================================================================
%  实验 1：卷积核宽度（Kernel Width）消融
%  候选值：1, 3(默认), 5, 7
% ========================================================================

fprintf('\n========== 实验 1：卷积核宽度消融 ==========\n');

% 候选值列表（第一个为你的默认值）
candidates_kernel = [3, 1, 5, 7];
results_kernel = table();

for i = 1:length(candidates_kernel)
    k = candidates_kernel(i);
    fprintf('\n>>> 正在测试卷积核宽度 = %d (%d/%d) ...\n', k, i, length(candidates_kernel));
    
    % 构建网络层
    layers = buildCNNLayers(inputSize, numChannels, numClasses, ...
                            k, [4, 8], 2, 64, 0.5);
    
    % 训练选项
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
    
    % 训练并计时
    tic;
    net = trainNetwork(traindata, trainlabels, layers, opts);
    elapsedTime = toc;
    
    % 验证集评估
    valPred = classify(net, valdata, 'MiniBatchSize', MiniBatchSize);
    valAcc  = mean(valPred == vallabels);
    
    % 计算参数量
    numParams = countParams(net);
    
    % 记录结果
    results_kernel = [results_kernel; table(k, valAcc, numParams, elapsedTime, ...
        'VariableNames', {'KernelWidth', 'ValAcc', 'Params', 'TrainTime'})];
    
    fprintf('  验证准确率: %.2f%%  |  参数量: %d  |  耗时: %.1f秒\n', valAcc*100, numParams, elapsedTime);
end

disp('----- 实验1结果 -----');
disp(results_kernel);
save('Ablation_Results_Kernel.mat', 'results_kernel');

%% ========================================================================
%  实验 2：卷积核通道数（Num Filters）消融
%  候选值：[2,4], [4,8](默认), [8,16]
% ========================================================================

fprintf('\n========== 实验 2：卷积核通道数消融 ==========\n');

candidates_filters = {[4,8], [2,4], [8,16]};  % 元胞数组，因为每行两个数
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
save('Ablation_Results_Filters.mat', 'results_filters');

%% ========================================================================
%  实验 3：池化步长（Pooling Stride）消融
%  候选值：1, 2(默认), 3
% ========================================================================

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
save('Ablation_Results_Stride.mat', 'results_stride');

%% ========================================================================
%  实验 4：全连接层单元数（FC Units）消融
%  候选值：32, 64(默认), 128
% ========================================================================

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
save('Ablation_Results_FC.mat', 'results_fc');

%% ========================================================================
%  实验 5：Dropout比率消融
%  候选值：0.3, 0.5(默认), 0.7
% ========================================================================

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
save('Ablation_Results_Dropout.mat', 'results_drop');

%% ========================================================================
%  实验 6：输入窗口长度（Window Length）消融  ⚠️ 需重新切数据
%  候选值：1550, 3100(默认), 6200
% ========================================================================

fprintf('\n========== 实验 6：窗口长度消融（需重切数据，较耗时） ==========\n');

candidates_win = [3100, 1550, 6200];
results_win = table();

for i = 1:length(candidates_win)
    win = candidates_win(i);
    fprintf('\n>>> 正在测试窗口长度 = %d (%d/%d) ...\n', win, i, length(candidates_win));
    
    % ---- 关键：重新切片数据 ----
    traindata_win = prepareDataForImageInput_win(sigdata(trainidx), win, numChannels);
    valdata_win   = prepareDataForImageInput_win(sigdata(validx), win, numChannels);
    
    % 更新 ValidationFrequency（因为训练集大小变了）
    local_Val_Freq = floor(size(traindata_win, 4) / MiniBatchSize);
    
    % 构建网络（注意 inputSize 换成 win）
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
save('Ablation_Results_Window.mat', 'results_win');

fprintf('\n========== 所有消融实验执行完毕！ ==========\n');


%% ========================================================================
%  ===================== 下方为所有自定义函数 =============================
%  MATLAB要求：主脚本中的函数定义必须放在文件末尾
% ========================================================================

%% 函数 1：标准网络构建（卷积核宽度、通道数、FC、Dropout可调）
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

%% 函数 2：专门用于池化步长消融（结构相同，单独写是为了避免参数歧义）
function layers = buildCNNLayers_stride(inputSize, numChannels, numClasses, ...
                                        kernelWidth, numFilters, stride, fcUnits, dropoutRate)
    % 与 buildCNNLayers 完全一样，但为了实验3单独调用，保持清晰
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

%% 函数 3：统计模型总参数量
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

%% 函数 4：准备固定窗口数据（你的原函数，保留）
function X = prepareDataForImageInput(cellData, inputSize, numChannels)
    numSamples = length(cellData);
    X = zeros(1, inputSize, numChannels, numSamples);
    for i = 1:numSamples
        sample = cellData{i};
        % 如果长度不足则补零（以防万一）
        if size(sample, 1) < inputSize
            sample = [sample; zeros(inputSize - size(sample,1), numChannels)];
        else
            sample = sample(1:inputSize, :);
        end
        X(1, :, :, i) = sample;
    end
end

%% 函数 5：准备可变窗口数据（用于实验6）
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