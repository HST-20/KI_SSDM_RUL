function plot_fig11_speed_load_deployment(outDir)
% PLOT_FIG11_SPEED_LOAD_DEPLOYMENT
% Generates Figure 11: Real-time physical test-bench RUL prognostic evaluation
% comparing PI-DSSDM and baseline methods across feed speeds for unladen
% (25 kg) and 150 kg carriage payload (175 kg total) regimes.
%
% Strictly reconciled with Figure 11 & Table 9 of PI_DSSDM_Final_Draft.pdf.
%
% Output:
%   - fig_realtime_speed_load.png (600 DPI)
%   - fig_realtime_speed_load.pdf (Vector / 600 DPI)

if nargin < 1 || isempty(outDir)
    packageRoot = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(packageRoot, 'output_figures_600dpi');
end
if ~exist(outDir, 'dir'), mkdir(outDir); end

fprintf('[Fig 11] Generating Figure 11 (Physical Test-Bench Speed & Load Matrix) at 600 DPI...\n');

speeds_mmpm = [5000, 10000, 15000, 20000];
rpm_labels  = {'5k (500 RPM)', '10k (1,000 RPM)', '15k (1,500 RPM)', '20k (2,000 RPM)'};

% Unladen Carriage Configuration (m_c = 25 kg)
% Order: [PI-DSSDM, Physics SSM, Inverse PINN, Deep LSTM, Bayesian PF]
rul_unladen = [
    8271, 8250, 8225, 8215, 8240; % 5k mm/min
    8238, 8224, 8198, 8185, 8215; % 10k mm/min
    8172, 8160, 8134, 8160, 8190; % 15k mm/min
    8132, 8121, 8095, 8110, 8145  % 20k mm/min
];

% Conformal / Predictive Bounds Unladen
lo_unladen = [
    8165, 8250, 8225, 8145, 8175;
    8132, 8224, 8198, 8115, 8150;
    8066, 8160, 8134, 8090, 8125;
    8026, 8121, 8095, 8040, 8080
];
hi_unladen = [
    8377, 8250, 8225, 8285, 8305;
    8344, 8224, 8198, 8255, 8280;
    8278, 8160, 8134, 8230, 8255;
    8238, 8121, 8095, 8180, 8210
];

% 150 kg Dynamic Payload Configuration (M_tot = 175 kg)
rul_loaded = [
    8143, 8086, 8098, 8135, 8165; % 5k mm/min
    8165, 8209, 8120, 8125, 8170; % 10k mm/min
    8150, 8045, 8105, 8095, 8135; % 15k mm/min
    8056, 8056, 8012, 8045, 8090  % 20k mm/min
];

lo_loaded = [
    8037, 8086, 8098, 8065, 8100;
    8059, 8209, 8120, 8055, 8105;
    8044, 8045, 8105, 8025, 8070;
    7950, 8056, 8012, 7975, 8025
];
hi_loaded = [
    8249, 8086, 8098, 8205, 8230;
    8271, 8209, 8120, 8195, 8235;
    8256, 8045, 8105, 8165, 8200;
    8162, 8056, 8012, 8115, 8155
];

% Palette matching manuscript
c_pi   = [0.04, 0.33, 0.85]; % Blue (PI-DSSDM Proposed)
c_phys = [0.52, 0.15, 0.78]; % Purple (Physics SSM)
c_pinn = [0.85, 0.35, 0.05]; % Orange (Inverse PINN)
c_lstm = [0.88, 0.65, 0.10]; % Amber Gold (Deep LSTM)
c_pf   = [0.12, 0.70, 0.86]; % Teal (Bayesian PF)

fig = figure('Position', [80, 80, 1500, 680], 'Color', 'w', 'Visible', 'off');
tlayout = tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

lw = 2.0; ms = 7.5;
fontName = 'Helvetica';

% --- PANEL (A): UNLADEN CARRIAGE (m_c = 25 kg) ---
nexttile(tlayout, 1);
hold on; box on; grid on;
set(gca, 'FontName', fontName, 'FontSize', 12, 'LineWidth', 1.2, 'GridAlpha', 0.25, 'GridLineStyle', ':');

errorbar(speeds_mmpm, rul_unladen(:, 1), rul_unladen(:, 1) - lo_unladen(:, 1), hi_unladen(:, 1) - rul_unladen(:, 1), ...
    '-s', 'Color', c_pi, 'LineWidth', lw + 0.6, 'MarkerSize', ms + 1, 'MarkerFaceColor', c_pi, 'CapSize', 6);
errorbar(speeds_mmpm, rul_unladen(:, 2), zeros(4,1), zeros(4,1), ...
    '--o', 'Color', c_phys, 'LineWidth', lw, 'MarkerSize', ms, 'MarkerFaceColor', 'w', 'CapSize', 5);
errorbar(speeds_mmpm, rul_unladen(:, 3), zeros(4,1), zeros(4,1), ...
    '-.^', 'Color', c_pinn, 'LineWidth', lw, 'MarkerSize', ms, 'MarkerFaceColor', 'w', 'CapSize', 5);
errorbar(speeds_mmpm, rul_unladen(:, 4), rul_unladen(:, 4) - lo_unladen(:, 4), hi_unladen(:, 4) - rul_unladen(:, 4), ...
    '--v', 'Color', c_lstm, 'LineWidth', lw, 'MarkerSize', ms, 'MarkerFaceColor', 'w', 'CapSize', 5);
errorbar(speeds_mmpm, rul_unladen(:, 5), rul_unladen(:, 5) - lo_unladen(:, 5), hi_unladen(:, 5) - rul_unladen(:, 5), ...
    ':d', 'Color', c_pf, 'LineWidth', lw, 'MarkerSize', ms, 'MarkerFaceColor', 'w', 'CapSize', 5);

yline(8260, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Nominal Operating Horizon (8,260 h)');

xlabel('Feed Speed mm/min (Servomotor Rotational Speed)', 'FontSize', 13, 'FontWeight', 'bold');
ylabel('Remaining Useful Life (operating hours)', 'FontSize', 13, 'FontWeight', 'bold');
title('(a) Unladen Carriage Configuration (m_c = 25 kg)', 'FontSize', 14, 'FontWeight', 'bold');
set(gca, 'XTick', speeds_mmpm, 'XTickLabel', rpm_labels);
xlim([4000, 21000]); ylim([7800, 8500]);

legend({'PI-DSSDM (Proposed, 90% Conformal)', 'Physics SSM (Nominal First-Principles)', ...
        'Inverse PINN', 'Deep LSTM', 'Bayesian PF (90% CI)', 'Nominal Operating Horizon (8,260 h)'}, ...
        'FontSize', 10.5, 'FontWeight', 'bold', 'Location', 'southwest');

% --- PANEL (B): 150 KG DYNAMIC PAYLOAD (M_tot = 175 kg) ---
nexttile(tlayout, 2);
hold on; box on; grid on;
set(gca, 'FontName', fontName, 'FontSize', 12, 'LineWidth', 1.2, 'GridAlpha', 0.25, 'GridLineStyle', ':');

errorbar(speeds_mmpm, rul_loaded(:, 1), rul_loaded(:, 1) - lo_loaded(:, 1), hi_loaded(:, 1) - rul_loaded(:, 1), ...
    '-s', 'Color', c_pi, 'LineWidth', lw + 0.6, 'MarkerSize', ms + 1, 'MarkerFaceColor', c_pi, 'CapSize', 6);
errorbar(speeds_mmpm, rul_loaded(:, 2), zeros(4,1), zeros(4,1), ...
    '--o', 'Color', c_phys, 'LineWidth', lw, 'MarkerSize', ms, 'MarkerFaceColor', 'w', 'CapSize', 5);
errorbar(speeds_mmpm, rul_loaded(:, 3), zeros(4,1), zeros(4,1), ...
    '-.^', 'Color', c_pinn, 'LineWidth', lw, 'MarkerSize', ms, 'MarkerFaceColor', 'w', 'CapSize', 5);
errorbar(speeds_mmpm, rul_loaded(:, 4), rul_loaded(:, 4) - lo_loaded(:, 4), hi_loaded(:, 4) - rul_loaded(:, 4), ...
    '--v', 'Color', c_lstm, 'LineWidth', lw, 'MarkerSize', ms, 'MarkerFaceColor', 'w', 'CapSize', 5);
errorbar(speeds_mmpm, rul_loaded(:, 5), rul_loaded(:, 5) - lo_loaded(:, 5), hi_loaded(:, 5) - rul_loaded(:, 5), ...
    ':d', 'Color', c_pf, 'LineWidth', lw, 'MarkerSize', ms, 'MarkerFaceColor', 'w', 'CapSize', 5);

yline(8260, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Nominal Operating Horizon (8,260 h)');

xlabel('Feed Speed mm/min (Servomotor Rotational Speed)', 'FontSize', 13, 'FontWeight', 'bold');
ylabel('Remaining Useful Life (operating hours)', 'FontSize', 13, 'FontWeight', 'bold');
title('(b) 150 kg Dynamic Carriage Payload (M_{tot} = 175 kg)', 'FontSize', 14, 'FontWeight', 'bold');
set(gca, 'XTick', speeds_mmpm, 'XTickLabel', rpm_labels);
xlim([4000, 21000]); ylim([7800, 8500]);

ensure_fontsize_increment(fig, 2);
drawnow;

pngOut = fullfile(outDir, 'fig_realtime_speed_load.png');
pdfOut = fullfile(outDir, 'fig_realtime_speed_load.pdf');

exportgraphics(fig, pngOut, 'Resolution', 600);
try
    exportgraphics(fig, pdfOut, 'ContentType', 'vector');
catch
    exportgraphics(fig, pdfOut, 'Resolution', 600);
end
close(fig);

% Synchronize to workspace directories
syncDirs = {'C:\Users\harit\Desktop\DSSM_RUL', 'C:\Users\harit\Desktop\FD_ALT_DATA\Vibration Data'};
for sIdx = 1:numel(syncDirs)
    tgt = syncDirs{sIdx};
    if exist(tgt, 'dir') && ~strcmpi(tgt, outDir)
        copyfile(pngOut, fullfile(tgt, 'fig_realtime_speed_load.png'));
        copyfile(pdfOut, fullfile(tgt, 'fig_realtime_speed_load.pdf'));
    end
end

fprintf('         Saved: %s (600 DPI)\n', pngOut);
fprintf('         Saved: %s\n', pdfOut);
end
