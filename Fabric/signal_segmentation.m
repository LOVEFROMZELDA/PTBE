clear; clc;

%% plot all data

% folder_path = ".\data_origin\*";
% file_names = dir(fullfile(folder_path, "*.xlsx"));
% 
% for i = 3
%     figure;
%     hold on
%     for j = 1:10
%         ind = (i-1) * 10 + j;
%         file_path = fullfile(file_names(ind).folder, file_names(ind).name);
%         m = readmatrix(file_path);
%         plot(m(:,1), m(:,2), LineWidth=1);
%         plot(m(:,1), m(:,3), LineWidth=1);
%     end
%     hold off
%     txt = extractBefore(file_names(ind).name, ".");
%     title(txt);
% end

%% segment every sequence into 10 pieces

folder_path = ".\data_origin\*";
file_names = dir(fullfile(folder_path, "*.xlsx"));

params.snr_db = 13;
params.density = 0.03;
params.amplitude_factor = 1.5;

for i = 1:14
    for j = 1:10
        ind = (i-1) * 10 + j;
        file_path = fullfile(file_names(ind).folder, file_names(ind).name);
        m = readmatrix(file_path);
        m_noisy = zeros(size(m, 1), 2);
        
        % segment
        len0 = floor(length(m) / 10);
        seq10 = (1:len0) + 9 * len0;
        seq9 = (1:len0) + 8 * len0;
        [~, index10] = min(m(seq10, 3));
        [~, index9] = min(m(seq9, 3));
        len = index10 - index9 + len0;
        delay = max([floor(len0/2 - index10), 0]);

        % add noise
        m_noisy(:, 1) = addNoiseToSignal(m(:, 2), 'both', params);
        m_noisy(:, 2) = addNoiseToSignal(m(:, 3), 'both', params);
        if any(isnan(m_noisy), 'all')
            error('i=%d, j=%d', i, j);
        end
        
        mtmp = zeros(len, 2);
        txt_folder = extractBefore(file_names(ind).name, ".");
        txt_file = extractBetween(file_names(ind).name, ".", ".");
        if str2double(txt_folder) < 10
            name_dir = ".\data\0"+txt_folder;
        else
            name_dir = ".\data\"+txt_folder;
        end
        if ~exist(name_dir, "dir")
            mkdir(name_dir);
        end
        for k = 1:10
            seq_tmp =  length(m) - len - 1 - delay + (1:len) - (k-1) * len;
            mtmp = m_noisy(seq_tmp, :);
            path_new = name_dir + "\" ...
            + txt_folder + "_" + txt_file{1} + "_" + num2str(11-k) + ".csv";
            writematrix(mtmp(1:3100, :), path_new);
        end
    end
end



