clear; clc; close all;

%% ===== 配置参数 =====
% 数据集与网络基础参数
cfg = struct();
cfg.datasetPath = '.\dataset\';          % 数据集路径
cfg.numClasses = 10;
cfg.inputHeight = 200;
cfg.inputWidth = 200;
cfg.numChannels = 1;
cfg.numFrames = 50;
cfg.MiniBatchSize = 16;
cfg.MaxEpochs = 30;
cfg.InitialLearnRate = 0.001;
cfg.GradientThreshold = 1;
cfg.ValidationPatience = 7;
cfg.saveModels = false;
cfg.pooledSize = 10;

% B3 时间窗口长度（确保不超过50）
cfg.timeWindows = [1, 5, 10, 20];

% 实验开关（按需开启/关闭）
cfg.run_CNN_only = true;
cfg.run_classical = true;
cfg.run_time_windows = true;
cfg.run_notch = true;
cfg.run_norm = true;

% 陷波滤波器参数（根据实际采样率调整）
cfg.fs = 1000;                  % 采样频率 (Hz)
cfg.notchFreq = 50;             % 工频干扰频率

%% ===== 导入数据集 =====
fprintf('Loading dataset...\n');
sigds = signalDatastore(cfg.datasetPath, IncludeSubfolders=true, ReadFcn=@load);
labels = folders2labels(cfg.datasetPath);
sigdata_raw = readall(sigds);
sigdata = cellfun(@(x) x.all_data, sigdata_raw, 'UniformOutput', false);
% summary(labels);

%% ===== 固定划分 =====
rng(2026);  % 固定随机种子保证可重复
idx = splitlabels(labels, [0.8 0.1 0.1], 'randomized');
trainidx = idx{1}; validx = idx{2}; testidx = idx{3};

% 原始数据（无滤波）准备（固定帧数）
traindata = prepareSequenceData(sigdata(trainidx), cfg.numFrames);
trainlabels = labels(trainidx);
valdata   = prepareSequenceData(sigdata(validx), cfg.numFrames);
vallabels = labels(validx);
testdata  = prepareSequenceData(sigdata(testidx), cfg.numFrames);
testlabels = labels(testidx);

% 如果开启 B4，生成滤波后的数据（也固定帧数）
if cfg.run_notch
    fprintf('Applying notch filter (%d Hz) to all samples...\n', cfg.notchFreq);
    d = designfilt('bandstopiir', 'FilterOrder', 4, ...
                   'HalfPowerFrequency1', cfg.notchFreq-1, ...
                   'HalfPowerFrequency2', cfg.notchFreq+1, ...
                   'DesignMethod', 'butter', 'SampleRate', cfg.fs);
    sigdata_notch = cell(size(sigdata));
    for i = 1:length(sigdata)
        video = double(sigdata{i});
        [H, W, T] = size(video);
        data_2d = reshape(video, H*W, T)';          % 按像素展开
        data_filtered = filtfilt(d, data_2d);
        sigdata_notch{i} = single(reshape(data_filtered', H, W, T));
    end
    train_notch = prepareSequenceData(sigdata_notch(trainidx), cfg.numFrames);
    val_notch   = prepareSequenceData(sigdata_notch(validx), cfg.numFrames);
    test_notch  = prepareSequenceData(sigdata_notch(testidx), cfg.numFrames);
    clear sigdata_notch;
end

%% ===== 0. Baseline =====
fprintf('\n=====Baseline:=====\n');
lgraph_base = buildBaseNetwork(cfg.numClasses, cfg.inputHeight, cfg.inputWidth, cfg.numChannels);
[net_base, ~] = trainWrapperSeq(traindata, trainlabels, valdata, vallabels, lgraph_base, cfg);
[acc_base, f1_base, ece_base, time_base] = evaluateSeq(net_base, testdata, testlabels, cfg.MiniBatchSize);
fprintf('Baseline: Acc=%.2f%%, F1=%.3f, ECE=%.3f, Time=%.2f ms\n', ...
        acc_base*100, f1_base, ece_base, time_base*1000);

% 初始化结果表
results = table({'Baseline (CNN-LSTM)'}, ...
                acc_base, f1_base, ece_base, time_base*1000, ...
                'VariableNames', {'Experiment', 'Accuracy', 'F1', 'ECE', 'InferenceTime_ms'});

%% ===== 1. CNN-only  =====
if cfg.run_CNN_only
    fprintf('\n===== CNN-only =====\n');
    % 将序列数据转换为多通道图像 [H,W,1,T] -> [H,W,T]
    trainImg = cellfun(@(x) reshape(x, [size(x,1), size(x,2), size(x,4)]), traindata, 'UniformOutput', false);
    valImg   = cellfun(@(x) reshape(x, [size(x,1), size(x,2), size(x,4)]), valdata,   'UniformOutput', false);
    testImg  = cellfun(@(x) reshape(x, [size(x,1), size(x,2), size(x,4)]), testdata,  'UniformOutput', false);
    trainImg = cat(4, trainImg{:});
    valImg   = cat(4, valImg{:});
    testImg  = cat(4, testImg{:});

    lgraph_cnn = buildCNNOnly(cfg.numClasses, cfg.inputHeight, cfg.inputWidth, cfg.numFrames);
    opts_cnn = trainingOptions("adam", ...
        ExecutionEnvironment="auto", ...
        MaxEpochs=cfg.MaxEpochs, ...
        ValidationPatience=cfg.ValidationPatience, ...
        ValidationFrequency=max(1, floor(size(trainImg,4)/cfg.MiniBatchSize)), ...
        MiniBatchSize=cfg.MiniBatchSize, ...
        InitialLearnRate=cfg.InitialLearnRate, ...
        GradientThreshold=cfg.GradientThreshold, ...
        ValidationData={valImg, vallabels}, ...
        Plots="training-progress", ...
        Verbose=false);
    net_cnn = trainNetwork(trainImg, trainlabels, lgraph_cnn, opts_cnn);
    
    tic; pred_cnn = classify(net_cnn, testImg, 'MiniBatchSize', cfg.MiniBatchSize); time_cnn = toc;
    acc_cnn = mean(pred_cnn == testlabels);
    C_cnn = confusionmat(testlabels, pred_cnn);
    f1_cnn = computeF1(C_cnn);
    [~, scores_cnn] = classify(net_cnn, testImg, 'MiniBatchSize', cfg.MiniBatchSize);
    ece_cnn = computeECE(scores_cnn, testlabels, 10);
    fprintf('CNN-only: Acc=%.2f%%, F1=%.3f, ECE=%.3f, Time=%.2f ms\n', ...
            acc_cnn*100, f1_cnn, ece_cnn, time_cnn*1000);
    results = [results; table({'CNN-only'}, acc_cnn, f1_cnn, ece_cnn, time_cnn*1000, ...
                              'VariableNames', results.Properties.VariableNames)];
end

%% ===== 2. Classical Classifiers =====
if cfg.run_classical
    fprintf('\n===== Classical Classifiers =====\n');
    
    % ---- 特征提取函数（传入池化尺寸） ----
    extractHandFeatures = @(video) extractTraditionalFeatures(video, cfg.numFrames, cfg.pooledSize);
    
    % ---- 准备固定帧数数据（不归一化） ----
    trainDataFixed = prepareSequenceData(sigdata(trainidx), cfg.numFrames);
    testDataFixed  = prepareSequenceData(sigdata(testidx),  cfg.numFrames);
    
    % ---- 提取特征（cell → 矩阵） ----
    train_feat_cell = cellfun(@(x) extractHandFeatures(squeeze(x)), trainDataFixed, 'UniformOutput', false);
    test_feat_cell  = cellfun(@(x) extractHandFeatures(squeeze(x)), testDataFixed,  'UniformOutput', false);
    
    train_feat = cell2mat(cellfun(@(x) x(:)', train_feat_cell, 'UniformOutput', false));
    test_feat  = cell2mat(cellfun(@(x) x(:)', test_feat_cell,  'UniformOutput', false));
    
    % ---- 标准化 ----
    mu = mean(train_feat);
    sigma = std(train_feat);
    train_feat_norm = (train_feat - mu) ./ (sigma + eps);
    test_feat_norm  = (test_feat - mu)  ./ (sigma + eps);
    
    % ---- 标签转换 ----
    train_lab = double(trainlabels);
    test_lab  = double(testlabels);
    
    % ---- 分类器列表 ----
    classifiers = {'SVM', 'RandomForest', 'LogisticRegression', 'kNN'};
    
    for c = 1:length(classifiers)
        name = classifiers{c};
        fprintf('  Training %s...\n', name);
        
        switch name
            case 'SVM'
                model = fitcecoc(train_feat_norm, train_lab, ...
                                 'Learners', templateSVM('KernelFunction', 'rbf', 'BoxConstraint', 10, 'KernelScale', 'auto'), ...
                                 'Coding', 'onevsone');
            case 'RandomForest'
                model = TreeBagger(100, train_feat_norm, train_lab, ...
                                   'Method', 'classification', ...
                                   'MinLeafSize', 5, ...
                                   'MaxNumSplits', 20);
            case 'LogisticRegression'
                model = fitcecoc(train_feat_norm, train_lab, ...
                                 'Learners', templateLinear('Learner', 'logistic', 'Lambda', 0.5), ...
                                 'Coding', 'onevsone');
            case 'kNN'
                model = fitcknn(train_feat_norm, train_lab, ...
                                'NumNeighbors', 10, ...
                                'Standardize', false, ...
                                'Distance', 'euclidean');
        end
        
        % ---- 预测 ----
        if strcmp(name, 'RandomForest')
            pred = predict(model, test_feat_norm);
            pred = str2double(pred);
        else
            pred = predict(model, test_feat_norm);
            if iscategorical(pred)
                pred = double(pred);
            end
        end
        
        acc = mean(pred == test_lab);
        C = confusionmat(test_lab, pred);
        f1 = computeF1(C);
        ece = NaN;
        fprintf('    Acc=%.2f%%, F1=%.3f\n', acc*100, f1);
        
        results = [results; table({['Classical Classifier: ' name]}, acc, f1, ece, NaN, ...
                                  'VariableNames', results.Properties.VariableNames)];
    end
end

%% ===== 3. Without Temporal Modeling =====
if cfg.run_time_windows
    fprintf('\n===== Without Temporal Modeling =====\n');
    
    % ---- 9.1 不同时间窗口长度消融 ----
    for T = cfg.timeWindows
        fprintf('  Window T = %d\n', T);
        trainT = prepareSequenceData(sigdata(trainidx), T);
        valT   = prepareSequenceData(sigdata(validx), T);
        testT  = prepareSequenceData(sigdata(testidx), T);
        lgraph = buildBaseNetwork(cfg.numClasses, cfg.inputHeight, cfg.inputWidth, cfg.numChannels);
        [netT, ~] = trainWrapperSeq(trainT, trainlabels, valT, vallabels, lgraph, cfg);
        [acc, f1, ece, t] = evaluateSeq(netT, testT, testlabels, cfg.MiniBatchSize);
        fprintf('    Acc=%.2f%%, F1=%.3f, ECE=%.3f\n', acc*100, f1, ece);
        results = [results; table({['Window=' num2str(T)]}, acc, f1, ece, t*1000, ...
                                  'VariableNames', results.Properties.VariableNames)];
    end

    % ---- 9.2 完整 50 帧下的时序打乱实验（证明时序依赖） ----
    fprintf('  Window T=50 (Shuffled)\n');
    % 对原始数据进行时间轴随机打乱（保持空间信息不变，破坏时序结构）
    shuffleData = @(video) video(:, :, randperm(size(video,3)));
    train_shuffled = cellfun(@(x) shuffleData(x), sigdata(trainidx), 'UniformOutput', false);
    val_shuffled   = cellfun(@(x) shuffleData(x), sigdata(validx), 'UniformOutput', false);
    test_shuffled  = cellfun(@(x) shuffleData(x), sigdata(testidx), 'UniformOutput', false);
    
    % 固定帧数准备（50帧）
    trainT_shuf = prepareSequenceData(train_shuffled, cfg.numFrames);
    valT_shuf   = prepareSequenceData(val_shuffled, cfg.numFrames);
    testT_shuf  = prepareSequenceData(test_shuffled, cfg.numFrames);
    
    % 使用与基线完全相同的网络结构（输入尺寸为 cfg.numFrames）
    lgraph_shuf = buildBaseNetwork(cfg.numClasses, cfg.inputHeight, cfg.inputWidth, cfg.numChannels);
    [net_shuf, ~] = trainWrapperSeq(trainT_shuf, trainlabels, valT_shuf, vallabels, lgraph_shuf, cfg);
    [acc_shuf, f1_shuf, ece_shuf, t_shuf] = evaluateSeq(net_shuf, testT_shuf, testlabels, cfg.MiniBatchSize);
    fprintf('    Acc=%.2f%%, F1=%.3f, ECE=%.3f (Shuffled)\n', acc_shuf*100, f1_shuf, ece_shuf);
    results = [results; table({'Window=50 (Shuffled)'}, acc_shuf, f1_shuf, ece_shuf, t_shuf*1000, ...
                              'VariableNames', results.Properties.VariableNames)];
end

%% ===== 4. With Notch Filtering =====
if cfg.run_notch
    fprintf('\n===== With Notch Filtering =====\n');
    lgraph_notch = buildBaseNetwork(cfg.numClasses, cfg.inputHeight, cfg.inputWidth, cfg.numChannels);
    [net_notch, ~] = trainWrapperSeq(train_notch, trainlabels, val_notch, vallabels, lgraph_notch, cfg);
    [acc_notch, f1_notch, ece_notch, time_notch] = evaluateSeq(net_notch, test_notch, testlabels, cfg.MiniBatchSize);
    fprintf('With Notch Filtering: Acc=%.2f%%, F1=%.3f, ECE=%.3f, Time=%.2f ms\n', ...
            acc_notch*100, f1_notch, ece_notch, time_notch*1000);
    results = [results; table({'With Notch Filtering'}, acc_notch, f1_notch, ece_notch, time_notch*1000, ...
                              'VariableNames', results.Properties.VariableNames)];
end

%% ===== 5. Without Normalization =====
if cfg.run_norm
    fprintf('\n===== Without Normalization =====\n');
    train_norm = prepareSequenceData(sigdata(trainidx), cfg.numFrames);
    val_norm   = prepareSequenceData(sigdata(validx), cfg.numFrames);
    test_norm  = prepareSequenceData(sigdata(testidx), cfg.numFrames);
    lgraph_norm = buildWithoutNorm(cfg.numClasses, cfg.inputHeight, cfg.inputWidth, cfg.numChannels);
    [net_norm, ~] = trainWrapperSeq(train_norm, trainlabels, val_norm, vallabels, lgraph_norm, cfg);
    [acc_norm, f1_norm, ece_norm, time_norm] = evaluateSeq(net_norm, test_norm, testlabels, cfg.MiniBatchSize);
    fprintf('Without Normalization: Acc=%.2f%%, F1=%.3f, ECE=%.3f, Time=%.2f ms\n', ...
            acc_norm*100, f1_norm, ece_norm, time_norm*1000);
    results = [results; table({'Without Normalization'}, acc_norm, f1_norm, ece_norm, time_norm*1000, ...
                              'VariableNames', results.Properties.VariableNames)];
end

%% ===== Print and Save =====
fprintf('\n===== Summary =====\n');
disp(results);
save('ablation_results6.mat', 'results');
writetable(results, 'ablation_results6.xlsx');
fprintf('结果已保存至 ablation_results6.mat 和 .csv\n');
fprintf('所有实验完成！\n');

%% ===== Functions =====
function seq = prepareSequenceData(cellData, numFrames)
    % 准备固定长度序列（仅截取，不填充）
    % 若实际帧数 > numFrames，截取前 numFrames 帧；
    % 若实际帧数 < numFrames，发出警告并保留全部（可能导致尺寸不匹配）
    numSamples = length(cellData);
    seq = cell(numSamples, 1);
    for i = 1:numSamples
        video = cellData{i};
        T = size(video,3);
        if T > numFrames
            r = floor(rand(1, 1) * (T-numFrames-1));
            video = video(:,:,r+(1:numFrames));
        elseif T < numFrames
            warning('视频帧数 (%d) 小于 %d，将使用全部帧，可能导致网络输入尺寸不匹配。', T, numFrames);
        end
        seq{i} = reshape(video, size(video,1), size(video,2), 1, size(video,3));
    end
end

function [acc, f1, ece, infTime] = evaluateSeq(net, testdata, testlabels, miniBatchSize)
    % 评估序列数据网络
    tic;
    [pred, scores] = classify(net, testdata, 'MiniBatchSize', miniBatchSize);
    infTime = toc;
    acc = mean(pred == testlabels);
    C = confusionmat(testlabels, pred);
    f1 = computeF1(C);
    ece = computeECE(scores, testlabels, 10);
end

function f1 = computeF1(C)
    nC = size(C,1);
    f1s = zeros(nC,1);
    for i = 1:nC
        tp = C(i,i);
        fp = sum(C(:,i)) - tp;
        fn = sum(C(i,:)) - tp;
        precision = tp / (tp + fp + eps);
        recall = tp / (tp + fn + eps);
        f1s(i) = 2 * precision * recall / (precision + recall + eps);
    end
    f1 = mean(f1s);
end

function ece = computeECE(scores, labels, numBins)
    % 期望校准误差
    [~, predClass] = max(scores, [], 2);
    conf = max(scores, [], 2);
    labelsNum = double(labels);
    acc = (predClass == labelsNum);
    binEdges = linspace(0, 1, numBins+1);
    ece = 0;
    for b = 1:numBins
        inBin = (conf >= binEdges(b)) & (conf < binEdges(b+1));
        if sum(inBin) > 0
            avgConf = mean(conf(inBin));
            avgAcc = mean(acc(inBin));
            ece = ece + (sum(inBin) / length(conf)) * abs(avgConf - avgAcc);
        end
    end
end

function lgraph = buildBaseNetwork(numClasses, inputHeight, inputWidth, numChannels)
    % Create nerual network
    lgraph = layerGraph();
    
    tempLayers = [
        sequenceInputLayer([inputHeight inputWidth numChannels],"Name","input")
        sequenceFoldingLayer("Name","fold")];
    lgraph = addLayers(lgraph,tempLayers);
    
    tempLayers = [
        convolution2dLayer([3 3],4,"Name","conv1","Padding","same")
        batchNormalizationLayer("Name","bn1")
        reluLayer("Name","relu1")
        maxPooling2dLayer([5 5],"Name","pool1","Stride",[5 5])
    
        convolution2dLayer([3 3],8,"Name","conv2","Padding","same")
        batchNormalizationLayer("Name","bn2")
        reluLayer("Name","relu2")
        maxPooling2dLayer([5 5],"Name","pool2","Stride",[5 5]);
    
        convolution2dLayer([3 3],12,"Name","conv3","Padding","same")
        batchNormalizationLayer("Name","bn3")
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
end

function lgraph = buildCNNOnly(numClasses, inputHeight, inputWidth, numFrames)
    % 构建 CNN-only 网络（多通道图像输入）
    lgraph = layerGraph();
    lgraph = addLayers(lgraph, imageInputLayer([inputHeight, inputWidth, numFrames], 'Name', 'input'));
    convBlock = [
        convolution2dLayer([3 3], 4, 'Padding', 'same', 'Name', 'conv1')
        reluLayer('Name', 'relu1')
        maxPooling2dLayer([5 5], 'Stride', [5 5], 'Name', 'pool1')
        convolution2dLayer([3 3], 8, 'Padding', 'same', 'Name', 'conv2')
        reluLayer('Name', 'relu2')
        maxPooling2dLayer([5 5], 'Stride', [5 5], 'Name', 'pool2')
        convolution2dLayer([3 3], 12, 'Padding', 'same', 'Name', 'conv3')
        reluLayer('Name', 'relu3')
        maxPooling2dLayer([4 4], 'Stride', [4 4], 'Name', 'pool3')
    ];
    lgraph = addLayers(lgraph, convBlock);
    tempLayers = [
        flattenLayer("Name", "flatten")
        dropoutLayer(0.5, "Name", "dropout")
        fullyConnectedLayer(numClasses, "Name", "fc")
        softmaxLayer("Name", "softmax")
        classificationLayer("Name", "output")];
    lgraph = addLayers(lgraph, tempLayers);
    lgraph = connectLayers(lgraph, 'input', 'conv1');
    lgraph = connectLayers(lgraph, 'pool3', 'flatten');
end

function lgraph = buildWithoutNorm(numClasses, inputHeight, inputWidth, numChannels)
    % Create nerual network
    lgraph = layerGraph();
    
    tempLayers = [
        sequenceInputLayer([inputHeight inputWidth numChannels],"Name","input")
        sequenceFoldingLayer("Name","fold")];
    lgraph = addLayers(lgraph,tempLayers);
    
    tempLayers = [
        convolution2dLayer([3 3],4,"Name","conv1","Padding","same")
%         batchNormalizationLayer("Name","bn1")
        reluLayer("Name","relu1")
        maxPooling2dLayer([5 5],"Name","pool1","Stride",[5 5])
    
        convolution2dLayer([3 3],8,"Name","conv2","Padding","same")
%         batchNormalizationLayer("Name","bn2")
        reluLayer("Name","relu2")
        maxPooling2dLayer([5 5],"Name","pool2","Stride",[5 5]);
    
        convolution2dLayer([3 3],12,"Name","conv3","Padding","same")
%         batchNormalizationLayer("Name","bn3")
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
end

function [net, info] = trainWrapperSeq(traindata, trainlabels, valdata, vallabels, lgraph, cfg)
    % 封装序列数据训练
    numIter = floor(length(traindata) / cfg.MiniBatchSize);
    valFreq = max(1, numIter);
    opts = trainingOptions("adam", ...
        ExecutionEnvironment="auto", ...
        MaxEpochs=cfg.MaxEpochs, ...
        ValidationPatience=cfg.ValidationPatience, ...
        ValidationFrequency=valFreq, ...
        MiniBatchSize=cfg.MiniBatchSize, ...
        InitialLearnRate=cfg.InitialLearnRate, ...
        GradientThreshold=cfg.GradientThreshold, ...
        ValidationData={valdata, vallabels}, ...
        Plots="training-progress", ...
        Verbose=false);
    [net, info] = trainNetwork(traindata, trainlabels, lgraph, opts);
end

% -------------------------------------------------------------------------
% 子函数：提取手工特征（支持可配置池化尺寸）
function feat = extractTraditionalFeatures(video, fixedFrames, pooledSize)
    % 输入: video [H, W, T], pooledSize 为下采样后的边长（例如 5 → 5×5）
    % 输出: 1×D 维特征向量，D = 2*pooledSize^2 + (T-1) + 10
    
    [H, W, T] = size(video);
    
    % ---- 1. 固定帧数（补零或截断） ----
    if T < fixedFrames
        video = cat(3, video, zeros(H, W, fixedFrames - T));
    elseif T > fixedFrames
        video = video(:,:,1:fixedFrames);
    end

    % ---- 2. 下采样
    video_resized = imresize(video, [pooledSize, pooledSize]);
    data_2d = reshape(video_resized, pooledSize*pooledSize, fixedFrames);

    % ---- 4. 特征组 A：每个像素点的时序均值与标准差（2*pooledSize^2 维） ----
    mean_vals = mean(data_2d, 2)';
    std_vals  = std(data_2d, 0, 2)';
    
    % ---- 5. 特征组 B：帧间变化强度（T-1 维） ----
    diff_vals = mean(abs(diff(data_2d, 1, 2)), 1);
    
    % ---- 6. 特征组 C：全局频域特征（取前 10 个交流分量，固定 10 维） ----
    global_signal = sum(data_2d, 1);
    Y = fft(global_signal);
    fft_vals = abs(Y(2:11));
    
    % ---- 7. 拼接（总维度 = 2*pooledSize^2 + (T-1) + 10） ----
    feat = [mean_vals, std_vals, diff_vals, fft_vals];
    feat = feat(:)';   % 强制行向量
end