function F = extract_pronostia_features(learningDir, fullTestDir, truncTestDir, outFile)
% EXTRACT_PRONOSTIA_FEATURES  Snapshot features for all 17 PRONOSTIA bearings.
%
%   learningDir   folder with Learning_set/Bearing1_1 ... Bearing3_2
%   fullTestDir   folder with Full_Test_Set/Bearing1_3 ... Bearing3_3
%                 (run-to-failure records of the 11 challenge test bearings)
%   truncTestDir  folder with Test_set/Bearing1_3 ... (the truncated challenge
%                 records; only their snapshot counts are used, to locate the
%                 official prediction instant)
%   outFile       .mat file to write
%
% Each acc_*.csv snapshot holds 2560 samples at 25.6 kHz, recorded every 10 s:
% hour, minute, second, microsecond, horizontal acc, vertical acc (g). Some
% records use ';' as the delimiter, so the parser accepts both.
%
% Features per snapshot (horizontal channel unless stated):
%   rms_h, rms_v, kurt_h, kurt_v, skew_h, peak_h, p2p_h, crest_h,
%   and log energy in four bands of the horizontal spectrum
%   (0-1, 1-3, 3-6, 6-12.8 kHz).

learn = {'Bearing1_1','Bearing1_2','Bearing2_1','Bearing2_2','Bearing3_1','Bearing3_2'};
test  = {'Bearing1_3','Bearing1_4','Bearing1_5','Bearing1_6','Bearing1_7', ...
         'Bearing2_3','Bearing2_4','Bearing2_5','Bearing2_6','Bearing2_7','Bearing3_3'};
names = [learn test];
dirs  = [fullfile(learningDir, learn) fullfile(fullTestDir, test)];

fs = 25600;
f = (0:1279)' * fs / 2560;
bands = [0 1000; 1000 3000; 3000 6000; 6000 12800];
featNames = {'rms_h','rms_v','kurt_h','kurt_v','skew_h','peak_h','p2p_h','crest_h', ...
             'band1','band2','band3','band4'};

F = struct();
for b = 1:numel(names)
    files = dir(fullfile(dirs{b}, 'acc_*.csv'));
    files = sort({files.name});
    n = numel(files);
    X = zeros(n, numel(featNames));
    tod = zeros(n, 1);
    parfor k = 1:n
        A = read_snapshot(fullfile(dirs{b}, files{k}));
        h = A(:, 5); v = A(:, 6);
        hc = h - mean(h); vc = v - mean(v);
        P = abs(fft(hc)).^2; P = P(1:1280);
        be = zeros(1, 4);
        for j = 1:4
            be(j) = log(sum(P(f >= bands(j,1) & f < bands(j,2))) + eps);
        end
        r = sqrt(mean(h.^2));
        X(k, :) = [r, sqrt(mean(v.^2)), ...
                   mean(hc.^4) / mean(hc.^2)^2, mean(vc.^4) / mean(vc.^2)^2, ...
                   mean(hc.^3) / mean(hc.^2)^1.5, max(abs(h)), max(h) - min(h), ...
                   max(abs(h)) / r, be];
        tod(k) = A(1,1) * 3600 + A(1,2) * 60 + A(1,3) + A(1,4) * 1e-6;
    end
    s.names = featNames;
    s.X = X;
    s.t_s = (0:n-1)' * 10;            % snapshot clock: one record every 10 s
    s.timeOfDay_s = tod;
    s.life_s = n * 10;                % run-to-failure length
    s.condition = str2double(names{b}(8));
    s.isLearning = b <= numel(learn);
    if ~s.isLearning
        s.nTruncated = numel(dir(fullfile(truncTestDir, names{b}, 'acc_*.csv')));
    else
        s.nTruncated = NaN;
    end
    F.(names{b}) = s;
    fprintf('[features] %-10s %5d snapshots, life %6d s\n', names{b}, n, s.life_s);
end

save(outFile, 'F');
end

function A = read_snapshot(p)
txt = fileread(p);
txt(txt == ';') = ',';
A = sscanf(txt, '%f,%f,%f,%f,%f,%f');
A = reshape(A, 6, [])';
end
