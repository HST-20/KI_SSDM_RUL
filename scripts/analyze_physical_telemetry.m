function T = analyze_physical_telemetry(opts)
% ANALYZE_PHYSICAL_TELEMETRY
% Computes every bench quantity reported in the manuscript directly from the
% raw OPC UA telemetry in data/physical_telemetry. Nothing is typed in.
%
% Outputs (output_tables/):
%   Table09_Bench_Operating_Point_Metrics.csv  steady-speed torque, temperature,
%       torque-equivalent axial load and relative fatigue-life index per regime
%   Table09b_Bench_Initial_vs_Final.csv        same-day cold vs warm runs (Dec 2025)
% Figure (output_figures_600dpi/):
%   Fig11_Bench_Operating_Points.png/.pdf
%
% Physics used (stated assumptions, change via opts):
%   External axial load per sample (manuscript Eq. 38, no cutting force):
%       Fa = mu_g * M * g * sign(v) + M * a,   a from the measured speed signal
%   Preloaded double nut (ISO 3408-5): Fa1 = Fpr*(1 + Fa/(2.83*Fpr))^1.5,
%       Fa2 = Fa1 - Fa (roles swap with load direction; a nut unloads past 2.83*Fpr)
%   Equivalent load per nut, revolution-weighted: Fm = (sum|F|^3 |n| dt / sum |n| dt)^(1/3)
%   Life in revolutions per nut L = (Ca/Fm)^3 * 1e6, system L = (L1^-10/9 + L2^-10/9)^-9/10
%   Life in hours = L / (60 * mean|n|)
%   Ca cancels in the RELATIVE life index L_h / L_h,ref (reference = unladen
%   10,000 mm/min); absolute hours need the catalogue Ca in opts.Ca_N.
%   Sensitivity: the same calculation with Fa taken from motor torque,
%   Fa = 2*pi*eta*|tau|/lead, an upper bound (torque includes preload drag).

if nargin < 1, opts = struct(); end
def = struct('eta', 0.90, 'lead_m', 0.010, 'Ca_N', NaN, 'speedTol', 0.03, ...
             'Fpr_N', 1200, 'mu_g', 0.003, 'refRegime', 'Unladen 10000');
fn = fieldnames(def);
for k = 1:numel(fn), if ~isfield(opts, fn{k}), opts.(fn{k}) = def.(fn{k}); end, end

P = pkg_paths();
regimes = { ...
  'Unladen 5000',  'without load/fd_data_without_load_110825_5000.csv',  5000, 25; ...
  'Unladen 10000', 'without load/fd_data_without_load_110825_10000.csv', 10000, 25; ...
  'Unladen 15000', 'without load/fd_data_without_load_110825_15000.csv', 15000, 25; ...
  'Unladen 20000', 'without load/fd_data_without_load_110825_20000.csv', 20000, 25; ...
  'Laden 5000',    'with load/fd_data_with_load_110825_5000.csv',         5000, 175; ...
  'Laden 10000',   'with load/fd_data_with_load_110825_10000.csv',        10000, 175; ...
  'Laden 15000',   'with load/fd_data_with_load_110825_15000.csv',        15000, 175; ...
  'Laden 20000',   'with load/fd_data_with_load_110825_20000.csv',        20000, 175};

n = size(regimes, 1);
rows = cell(n, 1);
for i = 1:n
    M = steady_metrics(fullfile(P.telemetry, regimes{i, 2}), regimes{i, 3}, opts, regimes{i, 4});
    M.Regime = string(regimes{i, 1});
    M.Feedrate_mm_min = regimes{i, 3};
    M.CarriageMass_kg = regimes{i, 4};
    rows{i} = M;
end
T = struct2table([rows{:}]);
T = movevars(T, {'Regime', 'Feedrate_mm_min', 'CarriageMass_kg'}, 'Before', 1);

iRef = find(T.Regime == opts.refRegime, 1);
T.RelativeLifeIndex = T.LifeUnitCa_h ./ T.LifeUnitCa_h(iRef);
T.RelativeLifeIndex_TorqueBound = T.LifeUnitCaTorque_h ./ T.LifeUnitCaTorque_h(iRef);
if isfinite(opts.Ca_N)
    T.RatedLife_h = T.LifeUnitCa_h * opts.Ca_N^3;
end
T = removevars(T, {'LifeUnitCa_h', 'LifeUnitCaTorque_h'});
writetable(T, fullfile(P.tables, 'Table09_Bench_Operating_Point_Metrics.csv'));

% Same-day initial (cold) vs final (warm) runs, December 2025
pairs = { ...
  5000,  'initial-final/opcua_5kfd_initial_data_17122025.csv',  'initial-final/opcua_5kfd_final_data_17122025.csv'; ...
  10000, 'initial-final/opcua_10kfd_initial_data_18122025.csv', 'initial-final/opcua_10kfd_final_data_18122025.csv'; ...
  15000, 'initial-final/opcua_15kfd_initial_data_19122025.csv', 'initial-final/opcua_15kfd_final_data_19122025.csv'};
pr = cell(size(pairs, 1), 1);
for i = 1:size(pairs, 1)
    A = steady_metrics(fullfile(P.telemetry, pairs{i, 2}), pairs{i, 1}, opts, 25);
    B = steady_metrics(fullfile(P.telemetry, pairs{i, 3}), pairs{i, 1}, opts, 25);
    pr{i} = struct('Feedrate_mm_min', pairs{i, 1}, ...
        'Initial_start', A.StartTime, 'Final_start', B.StartTime, ...
        'Initial_TorqueRMS_Nm', A.TorqueRMS_Nm, 'Final_TorqueRMS_Nm', B.TorqueRMS_Nm, ...
        'TorqueChange_pct', 100 * (B.TorqueRMS_Nm / A.TorqueRMS_Nm - 1), ...
        'Initial_MeanTemp_C', A.MeanTemp_C, 'Final_MeanTemp_C', B.MeanTemp_C);
end
TF = struct2table([pr{:}]);
writetable(TF, fullfile(P.tables, 'Table09b_Bench_Initial_vs_Final.csv'));

plot_bench(T, TF, P);
fprintf('[Bench] %d regimes and %d initial/final pairs analysed from raw telemetry.\n', n, height(TF));
end

function M = steady_metrics(file, feed_mm_min, opts, mass_kg)
D = readtable(file, 'TextType', 'string');
t = parse_times(D.times);
spd = double(D.speed); trq = double(D.torque); tmp = double(D.temperature);
nNom = feed_mm_min / (opts.lead_m * 1000);              % rpm (lead in mm)
ok = abs(abs(spd) - nNom) <= opts.speedTol * nNom & isfinite(trq);
M.Samples = numel(spd);
M.SteadySamples = nnz(ok);
M.Duration_min = (t(end) - t(1)) / 60;
M.StartTime = string(D.times(1));
M.MeanSpeed_rpm = mean(abs(spd(ok)));
M.TorqueRMS_Nm = sqrt(mean(trq(ok).^2));
M.TorqueMeanAbs_Nm = mean(abs(trq(ok)));
valid = tmp > 1;                                         % drop 0.0 placeholders
M.MeanTemp_C = mean(tmp(valid));
M.StartTemp_C = tmp(find(valid, 1, 'first'));
M.EndTemp_C = tmp(find(valid, 1, 'last'));

% Revolution-weighted ISO 3408-5 life over the whole record (Ca factored out)
dt = [diff(t); 0]; dt(dt < 0 | dt > 5) = 0;
v = spd * opts.lead_m / 60;                              % m/s
dtv = diff(t); dv = diff(v);
a = [0; dv ./ max(dtv, 1e-3)];                          % m/s^2 (backward difference)
a(abs(a) > 50) = 0;                                      % drop timestamp glitches
Fext = opts.mu_g * mass_kg * 9.81 * sign(v) + mass_kg * a;
Ftrq = 2 * pi * opts.eta * abs(trq) / opts.lead_m .* sign(v);
w = abs(spd) .* dt;                                      % revolution weights
[M.LifeUnitCa_h, M.Fm1_N, M.Fm2_N] = double_nut_life(Fext, w, opts.Fpr_N, mean(abs(spd(w > 0))));
M.LifeUnitCaTorque_h = double_nut_life(Ftrq, w, opts.Fpr_N, mean(abs(spd(w > 0))));
M.PeakExternalLoad_N = max(abs(Fext));
end

function [Lh, Fm1, Fm2] = double_nut_life(Fa, w, Fpr, nMean)
% Per-nut loads for a preloaded double nut; life with Ca = 1 N (scale by Ca^3).
lift = 2.83 * Fpr;
x = min(abs(Fa), lift);
F1 = Fpr * (1 + x / lift).^1.5;                          % loaded nut
F2 = max(F1 - abs(Fa), 0);                               % opposing nut
pos = Fa >= 0;
nutA = F1 .* pos + F2 .* ~pos;
nutB = F2 .* pos + F1 .* ~pos;
Fm1 = (sum(nutA.^3 .* w) / sum(w))^(1/3);
Fm2 = (sum(nutB.^3 .* w) / sum(w))^(1/3);
L1 = (1 / Fm1)^3 * 1e6; L2 = (1 / Fm2)^3 * 1e6;
Lrev = (L1^(-10/9) + L2^(-10/9))^(-9/10);
Lh = Lrev / (60 * nMean);
end

function s = parse_times(x)
x = string(x);
if contains(x(1), "-")
    d = datetime(x, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
    s = seconds(d - d(1));
else
    s = seconds(duration(x, 'InputFormat', 'hh:mm:ss.SSSSSS'));
    s = s + 86400 * cumsum([0; diff(s) < -12 * 3600]);
    s = s - s(1);
end
end

function plot_bench(T, TF, P)
fig = figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 26 9], 'Visible', 'off');
tl = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
un = T.CarriageMass_kg == 25; ld = ~un;
feeds = unique(T.Feedrate_mm_min);

ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
plot(ax, T.Feedrate_mm_min(un), T.TorqueRMS_Nm(un), '-o', 'LineWidth', 1.6, 'DisplayName', 'Unladen (25 kg)');
plot(ax, T.Feedrate_mm_min(ld), T.TorqueRMS_Nm(ld), '--s', 'LineWidth', 1.6, 'DisplayName', 'Laden (175 kg)');
xlabel(ax, 'Feed rate (mm/min)'); ylabel(ax, 'Steady-speed torque RMS (N·m)');
title(ax, '(a) Drive torque'); legend(ax, 'Location', 'best'); xticks(ax, feeds);
ax.XAxis.Exponent = 0;

ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
plot(ax, T.Feedrate_mm_min(un), T.RelativeLifeIndex(un), '-o', 'LineWidth', 1.6, 'DisplayName', 'Unladen (25 kg)');
plot(ax, T.Feedrate_mm_min(ld), T.RelativeLifeIndex(ld), '--s', 'LineWidth', 1.6, 'DisplayName', 'Laden (175 kg)');
yline(ax, 1, ':', 'Reference (unladen 10,000)', 'HandleVisibility', 'off');
xlabel(ax, 'Feed rate (mm/min)'); ylabel(ax, 'Relative rated life L/L_{ref}');
title(ax, '(b) ISO 3408-5 relative life'); legend(ax, 'Location', 'best'); xticks(ax, feeds);
ax.XAxis.Exponent = 0;

ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
TF = sortrows(TF, 'Feedrate_mm_min');
b = bar(ax, [TF.Initial_TorqueRMS_Nm TF.Final_TorqueRMS_Nm]);
xticks(ax, 1:height(TF)); xticklabels(ax, string(TF.Feedrate_mm_min));
b(1).DisplayName = 'Initial run (cold)'; b(2).DisplayName = 'Final run (warm, same day)';
ylabel(ax, 'Steady-speed torque RMS (N·m)'); xlabel(ax, 'Feed rate (mm/min)');
title(ax, '(c) Same-day initial vs final'); legend(ax, 'Location', 'best');

exportgraphics(fig, fullfile(P.figures, 'Fig11_Bench_Operating_Points.png'), 'Resolution', 600);
exportgraphics(fig, fullfile(P.figures, 'Fig11_Bench_Operating_Points.pdf'), 'ContentType', 'vector');
close(fig);
end
