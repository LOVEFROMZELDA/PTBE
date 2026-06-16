clear; clc;

t = 0:0.1:5.3;
len = length(t);
numChannels = 16;

%% plot all data

% folder_path = ".\motion_data\*";
% file_names = dir(fullfile(folder_path, "*.xlsx"));
% 
% for i = 1:10
%     figure;
%     hold on
%     for j = 1:10
%         ind = (i-1) * 100 + j;
%         file_path = fullfile(file_names(ind).folder, file_names(ind).name);
%         m = readmatrix(file_path);
%         plot(t, m(1:len,2:end), LineWidth=1);  
%     end
%     hold off
%     txt = extractAfter(file_names(ind).folder, "motion_data\");
%     title(txt);
% end

%% segment every sequence into 10 pieces

folder_path = ".\data_origin\*";
file_names = dir(fullfile(folder_path, "*.xlsx"));

params.snr_db = 10;
params.density = 0.03;
params.amplitude_factor = 1.5;

for i = 1:10
    for j = 1:100
        ind = (i-1) * 100 + j;
        file_path = fullfile(file_names(ind).folder, file_names(ind).name);
        m = readmatrix(file_path);
        m = m(1:len, :);
        m_noisy = zeros(len, numChannels);
        
        % add noise
        for k = 1:numChannels
            if m(1, k+1) ~= 0
                m_noisy(:, k) = addNoiseToSignal(m(:, k+1), 'both', params);
            end
        end
        if any(isnan(m_noisy), 'all')
            error('i=%d, j=%d', i, j);
        end

        txt_folder = extractAfter(file_names(ind).folder, "motion_data\");
        txt_file = extractBetween(file_names(ind).name, "_", ".");
        if str2double(txt_folder) < 10
            name_dir = ".\data\0"+txt_folder;
        else
            name_dir = ".\data\"+txt_folder;
        end
        if ~exist(name_dir, "dir")
            mkdir(name_dir);
        end
        path_new = name_dir + "\" ...
        + txt_folder + "_" + txt_file{1} + ".csv";
        writematrix(m_noisy, path_new);
    end
end
