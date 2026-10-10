clear; clc; close all;

scriptDir = fileparts(mfilename('fullpath'));
datasetDir = fullfile(scriptDir, 'dataset');
resultsDir = fullfile(scriptDir, 'results');
if ~isfolder(datasetDir)
    error('Extract dataset.zip to: %s', datasetDir);
end
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

%% Configuration

cfg = struct();
cfg.datasetPath = datasetDir;
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

% Temporal windows must not exceed 50 frames.
cfg.timeWindows = [1, 5, 10, 20];

% Experiment switches.
cfg.run_CNN_only = true;
cfg.run_classical = true;
cfg.run_time_windows = true;
cfg.run_notch = true;
cfg.run_norm = true;

% Notch-filter settings.
cfg.fs = 1000;
cfg.notchFreq = 50;

%% Load dataset
fprintf('Loading dataset...\n');
sigds = signalDatastore(cfg.datasetPath, IncludeSubfolders=true, ReadFcn=@load);
labels = folders2labels(cfg.datasetPath);
sigdata_raw = readall(sigds);
sigdata = cellfun(@(x) x.all_data, sigdata_raw, 'UniformOutput', false);
%% Split data
rng(2026, 'twister');
idx = splitlabels(labels, [0.8 0.1 0.1], 'randomized');
trainidx = idx{1}; validx = idx{2}; testidx = idx{3};

% Prepare fixed-length unfiltered sequences.
traindata = prepareSequenceData(sigdata(trainidx), cfg.numFrames);
trainlabels = labels(trainidx);
valdata   = prepareSequenceData(sigdata(validx), cfg.numFrames);
vallabels = labels(validx);
testdata  = prepareSequenceData(sigdata(testidx), cfg.numFrames);
testlabels = labels(testidx);

% Prepare filtered sequences when enabled.
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
        data_2d = reshape(video, H*W, T)';
        data_filtered = filtfilt(d, data_2d);
        sigdata_notch{i} = single(reshape(data_filtered', H, W, T));
    end
    train_notch = prepareSequenceData(sigdata_notch(trainidx), cfg.numFrames);
    val_notch   = prepareSequenceData(sigdata_notch(validx), cfg.numFrames);
    test_notch  = prepareSequenceData(sigdata_notch(testidx), cfg.numFrames);
    clear sigdata_notch;
end

%% Baseline
fprintf('\n=====Baseline:=====\n');
lgraph_base = buildBaseNetwork(cfg.numClasses, cfg.inputHeight, cfg.inputWidth, cfg.numChannels);
[net_base, ~] = trainWrapperSeq(traindata, trainlabels, valdata, vallabels, lgraph_base, cfg);
[acc_base, f1_base, ece_base, time_base] = evaluateSeq(net_base, testdata, testlabels, cfg.MiniBatchSize);
fprintf('Baseline: Acc=%.2f%%, F1=%.3f, ECE=%.3f, Time=%.2f ms\n', ...
        acc_base*100, f1_base, ece_base, time_base*1000);

% Initialize the result table.
results = table({'Baseline (CNN-LSTM)'}, ...
                acc_base, f1_base, ece_base, time_base*1000, ...
                'VariableNames', {'Experiment', 'Accuracy', 'F1', 'ECE', 'InferenceTime_ms'});

%% CNN-only model
if cfg.run_CNN_only
    fprintf('\n===== CNN-only =====\n');
% Convert [H,W,1,T] sequences to [H,W,T] images.
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

%% Classical classifiers
if cfg.run_classical
    fprintf('\n===== Classical Classifiers =====\n');
    
% Configure handcrafted feature extraction.
    extractHandFeatures = @(video) extractTraditionalFeatures(video, cfg.numFrames, cfg.pooledSize);
    
% Prepare fixed-length inputs.
    trainDataFixed = prepareSequenceData(sigdata(trainidx), cfg.numFrames);
    testDataFixed  = prepareSequenceData(sigdata(testidx),  cfg.numFrames);
    
% Convert extracted features to matrices.
    train_feat_cell = cellfun(@(x) extractHandFeatures(squeeze(x)), trainDataFixed, 'UniformOutput', false);
    test_feat_cell  = cellfun(@(x) extractHandFeatures(squeeze(x)), testDataFixed,  'UniformOutput', false);
    
    train_feat = cell2mat(cellfun(@(x) x(:)', train_feat_cell, 'UniformOutput', false));
    test_feat  = cell2mat(cellfun(@(x) x(:)', test_feat_cell,  'UniformOutput', false));
    
% Standardize using training statistics.
    mu = mean(train_feat);
    sigma = std(train_feat);
    train_feat_norm = (train_feat - mu) ./ (sigma + eps);
    test_feat_norm  = (test_feat - mu)  ./ (sigma + eps);
    
% Convert labels to numeric values.
    train_lab = double(trainlabels);
    test_lab  = double(testlabels);
    
% Classical classifiers.
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
        
% Predict labels.
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

%% Temporal ablation
if cfg.run_time_windows
    fprintf('\n===== Without Temporal Modeling =====\n');
    
% Evaluate temporal window lengths.
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

% Evaluate shuffled 50-frame sequences.
    fprintf('  Window T=50 (Shuffled)\n');
% Shuffle time while preserving spatial frames.
    shuffleData = @(video) video(:, :, randperm(size(video,3)));
    train_shuffled = cellfun(@(x) shuffleData(x), sigdata(trainidx), 'UniformOutput', false);
    val_shuffled   = cellfun(@(x) shuffleData(x), sigdata(validx), 'UniformOutput', false);
    test_shuffled  = cellfun(@(x) shuffleData(x), sigdata(testidx), 'UniformOutput', false);
    
% Prepare 50-frame sequences.
    trainT_shuf = prepareSequenceData(train_shuffled, cfg.numFrames);
    valT_shuf   = prepareSequenceData(val_shuffled, cfg.numFrames);
    testT_shuf  = prepareSequenceData(test_shuffled, cfg.numFrames);
    
% Use the baseline network structure.
    lgraph_shuf = buildBaseNetwork(cfg.numClasses, cfg.inputHeight, cfg.inputWidth, cfg.numChannels);
    [net_shuf, ~] = trainWrapperSeq(trainT_shuf, trainlabels, valT_shuf, vallabels, lgraph_shuf, cfg);
    [acc_shuf, f1_shuf, ece_shuf, t_shuf] = evaluateSeq(net_shuf, testT_shuf, testlabels, cfg.MiniBatchSize);
    fprintf('    Acc=%.2f%%, F1=%.3f, ECE=%.3f (Shuffled)\n', acc_shuf*100, f1_shuf, ece_shuf);
    results = [results; table({'Window=50 (Shuffled)'}, acc_shuf, f1_shuf, ece_shuf, t_shuf*1000, ...
                              'VariableNames', results.Properties.VariableNames)];
end

%% Notch-filter ablation
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

%% Normalization ablation
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

%% Save results
fprintf('\n===== Summary =====\n');
disp(results);
save(fullfile(resultsDir, 'ablation_results6.mat'), 'results');
writetable(results, fullfile(resultsDir, 'ablation_results6.xlsx'));
fprintf('Results saved to ablation_results6.mat and ablation_results6.xlsx.\n');
fprintf('All experiments completed.\n');

%% Local functions
function seq = prepareSequenceData(cellData, numFrames)
% Prepare fixed-length sequences.
% Crop sequences longer than numFrames.
% Warn when a sequence is shorter than numFrames.
    numSamples = length(cellData);
    seq = cell(numSamples, 1);
    for i = 1:numSamples
        video = cellData{i};
        T = size(video,3);
        if T > numFrames
            r = floor(rand(1, 1) * (T-numFrames-1));
            video = video(:,:,r+(1:numFrames));
        elseif T < numFrames
            warning('Sequence has %d frames; expected at least %d.', T, numFrames);
        end
        seq{i} = reshape(video, size(video,1), size(video,2), 1, size(video,3));
    end
end

function [acc, f1, ece, infTime] = evaluateSeq(net, testdata, testlabels, miniBatchSize)
% Evaluate a sequence model.
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
% Expected calibration error.
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
    % Build the sequence model.
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
% Build the CNN-only model.
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
    % Build the sequence model without batch normalization.
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
end

function [net, info] = trainWrapperSeq(traindata, trainlabels, valdata, vallabels, lgraph, cfg)
% Train a sequence model.
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

% Extract configurable handcrafted features.
function feat = extractTraditionalFeatures(video, fixedFrames, pooledSize)
% Input: video [H,W,T] and the pooled spatial size.
% Output length: 2*pooledSize^2 + (T-1) + 10.
    
    [H, W, T] = size(video);
    
% Pad or crop to a fixed frame count.
    if T < fixedFrames
        video = cat(3, video, zeros(H, W, fixedFrames - T));
    elseif T > fixedFrames
        video = video(:,:,1:fixedFrames);
    end

% Downsample spatial dimensions.
    video_resized = imresize(video, [pooledSize, pooledSize]);
    data_2d = reshape(video_resized, pooledSize*pooledSize, fixedFrames);

% Spatial mean and standard deviation features.
    mean_vals = mean(data_2d, 2)';
    std_vals  = std(data_2d, 0, 2)';
    
% Frame-difference features.
    diff_vals = mean(abs(diff(data_2d, 1, 2)), 1);
    
% First ten non-DC frequency features.
    global_signal = sum(data_2d, 1);
    Y = fft(global_signal);
    fft_vals = abs(Y(2:11));
    
% Concatenate all feature groups.
    feat = [mean_vals, std_vals, diff_vals, fft_vals];
    feat = feat(:)';
end
