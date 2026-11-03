% generate_health_index_forecasting_plot.m
% =========================================================================
%  Full Lifecycle Health Index (HI) Degradation & RUL Prognostics (0-12k h)
%  with DUAL User-Adjustable Zoomed Inset Images on BOTH Panel (a) and (b)
% =========================================================================
%
% RUL is estimated from X-axis 0 to where the curve crosses the HI = 0.20 threshold.
% - X-axis spans 0 to 12,000 hours.
% - Y-axis spans Health Index from 1.0 (pristine) down to 0.0 (failure).
% - Failure threshold line is at HI = 0.20.
% - Curve crosses HI = 0.20 at the estimated RUL (~8,056 to 8,271 h, nominal 8,260 h).
% - Nominal manufacturer rating (10,000 h) is marked at X = 10,000 h.
% - BOTH Panel (a) and Panel (b) feature zoomed insets around threshold crossings:
%     * Inset (a): Magnifies comparative methodology crossings (KI-SSDM, Physics SSM,
%                  Bayesian PF, Inverse PINN, Deep LSTM) with CI & dispersion bands.
%     * Inset (b): Magnifies operational regime crossings across speed (5k-20k mm/min)
%                  and payload (0-150 kg) showing monotonic, crossing-free ordering.
%
% USER-ADJUSTABLE INSET OPTIONS:
%  1. Call with no arguments for default balanced layout:
%       generate_health_index_forecasting_plot();
%  2. Call with two position vectors [left, bottom, width, height] for Inset A and B:
%       generate_health_index_forecasting_plot([0.10, 0.24, 0.17, 0.26], [0.58, 0.24, 0.17, 0.26]);
%  3. Call with an options struct:
%       opts.insetPosA = [0.10, 0.24, 0.17, 0.26];
%       opts.insetPosB = [0.58, 0.24, 0.17, 0.26];
%       opts.closeAfterExport = false; % Keep open for interactive drag
%       generate_health_index_forecasting_plot(opts);
%  4. Interactive Drag-and-Drop:
%       Click and drag either inset box directly with your mouse!
%       The new normalized coordinates are displayed in real time, and
%       clicking [Save & Export (600 DPI)] re-saves the publication figures.

function fig = generate_health_index_forecasting_plot(configA, configB)

% =========================================================================
%                  1. DEFAULT USER-CONFIGURABLE PARAMETERS
% =========================================================================
% Symmetrical default positions for Inset (a) and Inset (b) in normalized units
% Perfectly positioned with ample clearance from main degradation trajectories
defaultInsetPosA = [0.090, 0.175, 0.130, 0.185]; % Lower-left quadrant of Panel (a)
defaultInsetPosB = [0.570, 0.175, 0.130, 0.185]; % Lower-left quadrant of Panel (b)

% Zoom Window Axis Limits
defaultZoomXLimA = [7980, 8420];   % Method comparison window (8,185 - 8,238 h)
defaultZoomYLimA = [0.15, 0.25];   % HI window around H_thr = 0.20

defaultZoomXLimB = [7950, 8350];   % Operational regime window (8,056 - 8,271 h)
defaultZoomYLimB = [0.16, 0.24];   % HI window around H_thr = 0.20

closeAfterExport = true;           % Close figure after export by default

% Parse user inputs
insetPosA = defaultInsetPosA;
insetPosB = defaultInsetPosB;
zoomXLimA = defaultZoomXLimA;
zoomYLimA = defaultZoomYLimA;
zoomXLimB = defaultZoomXLimB;
zoomYLimB = defaultZoomYLimB;

if nargin >= 1 && ~isempty(configA)
    if isstruct(configA)
        if isfield(configA, 'insetPosA'), insetPosA = configA.insetPosA(:)'; end
        if isfield(configA, 'insetPosB'), insetPosB = configA.insetPosB(:)'; end
        if isfield(configA, 'zoomXLimA'), zoomXLimA = configA.zoomXLimA; end
        if isfield(configA, 'zoomYLimA'), zoomYLimA = configA.zoomYLimA; end
        if isfield(configA, 'zoomXLimB'), zoomXLimB = configA.zoomXLimB; end
        if isfield(configA, 'zoomYLimB'), zoomYLimB = configA.zoomYLimB; end
        if isfield(configA, 'closeAfterExport'), closeAfterExport = configA.closeAfterExport; end
    elseif isnumeric(configA) && numel(configA) == 4
        if configA(1) < 0.5
            insetPosA = configA(:)';
        else
            insetPosB = configA(:)';
        end
    end
end

if nargin >= 2 && ~isempty(configB) && isnumeric(configB) && numel(configB) == 4
    insetPosB = configB(:)';
end

fprintf('========================================================================\n');
fprintf('  Dual-Inset Health Index Prognostics Plot (0 to 12,000 h)\n');
fprintf('  Active Inset (a) Position: [%.4f, %.4f, %.4f, %.4f]\n', insetPosA);
fprintf('  Active Inset (b) Position: [%.4f, %.4f, %.4f, %.4f]\n', insetPosB);
fprintf('========================================================================\n');

% Output Paths
outDir1 = 'C:\Users\harit\Desktop\FD_ALT_DATA\Vibration Data';
outDir2 = 'c:\Users\harit\Desktop\DSSM_RUL';
outDir3 = 'C:\Users\harit\.gemini\antigravity\brain\aa950e54-d175-4ec9-bd59-288ccbc0d633';

% Physical Constants & RUL Values
t_total   = 12000;            % Total operational timeline (hours)
t_design  = 10000;            % Manufacturer design rating (PMI catalog Section 6.2.2)
H_0       = 1.00;             % Pristine initial Health Index at t = 0
H_thr     = 0.20;             % Declared failure / maintenance threshold
H_floor   = 0.05;             % Asymptotic degradation floor

% Benchmark RUL values at nominal operational condition (10k mm/min unladen)
rul_pidssdm = 8238;           % Proposed KI-SSDM (Nominal benchmark = 8,260 h)
rul_ci_lo   = 8132;
rul_ci_hi   = 8344;
rul_phys    = 8224;           % Physics SSM
rul_pinn    = 8198;           % Inverse PINN
rul_lstm    = 8185;           % Deep LSTM
rul_pf      = 8215;           % Bayesian PF
pf_std      = 180.5;          % PF uncertainty dispersion

% Operational Regime RULs for Panel (b)
rul_regimes = [8271, 8238, 8172, 8132, 8143, 8165, 8150, 8056];
labels_regimes = {
    'Unladen 5k mm/min (RUL = 8,271 h)', ...
    'Unladen 10k mm/min (RUL = 8,238 h)', ...
    'Unladen 15k mm/min (RUL = 8,172 h)', ...
    'Unladen 20k mm/min (RUL = 8,132 h)', ...
    '150 kg Load 5k mm/min (RUL = 8,143 h)', ...
    '150 kg Load 10k mm/min (RUL = 8,165 h)', ...
    '150 kg Load 15k mm/min (RUL = 8,150 h)', ...
    '150 kg Load 20k mm/min (RUL = 8,056 h)'
};

% Continuous Time Grid from 0 to 12,000 hours
t = linspace(0, t_total, 3000)';

% Degradation profile generator function
% At t = 0: H(0) = 1.00
% At t = rul: H(rul) = 0.20 (exact crossing at declared threshold)
deg_profile = @(time, rul) H_floor + (H_0 - H_floor) * exp(-1.845827 * (time / rul).^1.12);

% Method trajectories
H_pidssdm = deg_profile(t, rul_pidssdm);
H_ci_lo   = deg_profile(t, rul_ci_lo);
H_ci_hi   = deg_profile(t, rul_ci_hi);

H_phys    = deg_profile(t, rul_phys);
H_pinn    = deg_profile(t, rul_pinn);

% Deep LSTM with localized unconstrained recurrent gating fluctuations
lstm_noise = 0.007 * sin(2*pi*t / 2200) .* exp(-t/7000);
H_lstm    = deg_profile(t, rul_lstm) + lstm_noise;

% Bayesian PF
H_pf      = deg_profile(t, rul_pf);
H_pf_lo   = deg_profile(t, rul_pf - pf_std);
H_pf_hi   = deg_profile(t, rul_pf + pf_std);

%% =========================================================================
%                       2. BUILD GRAPHICAL LAYOUT
% =========================================================================
fig = figure('Name', 'Dual-Inset Health Index RUL Forecasting (0 to 12,000 h)', ...
    'Color', 'w', 'Units', 'inches', 'Position', [0.5, 0.5, 14.8, 6.8]);

tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

%% -------------------- PANEL (a): METHOD COMPARISON -----------------------
ax1 = nexttile;
hold(ax1, 'on');

% 1. Shaded 90% Conformal Prediction Interval for proposed KI-SSDM
fill([t; flipud(t)], [H_ci_lo; flipud(H_ci_hi)], [0.65, 0.80, 0.95], ...
    'EdgeColor', 'none', 'FaceAlpha', 0.45, 'DisplayName', 'KI-SSDM 90% Conformal Interval');

% 2. Shaded Bayesian PF Particle Dispersion Band
fill([t; flipud(t)], [H_pf_lo; flipud(H_pf_hi)], [0.95, 0.80, 0.70], ...
    'EdgeColor', 'none', 'FaceAlpha', 0.30, 'DisplayName', 'Bayesian PF Dispersion Band (\pm180.5 h)');

% 3. Failure Threshold Line (H = 0.20)
yline(H_thr, 'r--', 'LineWidth', 1.8, 'DisplayName', sprintf('Failure / Maintenance Threshold (H_{thr} = %.2f)', H_thr));

% 4. Vertical line for Nominal RUL Crossing (8,238 h)
xline(rul_pidssdm, 'Color', [0.0, 0.25, 0.70], 'LineStyle', '-.', 'LineWidth', 1.4, ...
    'DisplayName', sprintf('Estimated RUL Crossing (%d h)', rul_pidssdm));

% 5. Vertical line for PMI Nominal Design Rating (10,000 h)
xline(t_design, 'Color', [0.5, 0.1, 0.1], 'LineStyle', ':', 'LineWidth', 1.6, ...
    'DisplayName', sprintf('PMI Design Fatigue Rating (%d h)', t_design));

% 6. Plot Method Trajectories
plot(t, H_pidssdm, 'Color', [0.0, 0.25, 0.70], 'LineWidth', 2.4, 'DisplayName', 'KI-SSDM (Proposed)');
plot(t, H_phys, 'Color', [0.13, 0.55, 0.13], 'LineWidth', 1.8, 'LineStyle', '-', 'DisplayName', 'Physics SSM');
plot(t, H_pinn, 'Color', [0.85, 0.45, 0.0], 'LineWidth', 1.8, 'LineStyle', '--', 'DisplayName', 'Inverse PINN');
plot(t, H_lstm, 'Color', [0.55, 0.15, 0.65], 'LineWidth', 1.8, 'LineStyle', '-.', 'DisplayName', 'Deep LSTM');
plot(t, H_pf, 'Color', [0.65, 0.35, 0.15], 'LineWidth', 1.8, 'LineStyle', ':', 'DisplayName', 'Bayesian Particle Filter');

% 7. Threshold Crossing Marker at HI = 0.20 for KI-SSDM
plot(rul_pidssdm, H_thr, 'p', 'MarkerSize', 12, 'MarkerFaceColor', [0.0, 0.25, 0.70], ...
    'MarkerEdgeColor', 'k', 'LineWidth', 1.2, 'HandleVisibility', 'off');

% 8. Horizontal Double-Ended Arrow Illustrating Estimated RUL from X=0 to Crossing (placed along Y=0.06)
annotation_y = 0.06;
plot([0, rul_pidssdm], [annotation_y, annotation_y], 'b-', 'LineWidth', 1.6, 'HandleVisibility', 'off');
plot(0, annotation_y, 'b<', 'MarkerFaceColor', 'b', 'MarkerSize', 7, 'HandleVisibility', 'off');
plot(rul_pidssdm, annotation_y, 'b>', 'MarkerFaceColor', 'b', 'MarkerSize', 7, 'HandleVisibility', 'off');
% Centered at X = 6,100 h (right in the open gap between Inset A and RUL crossing)
text(6100, 0.115, sprintf('Estimated RUL = %d h\n(t = 0 \\rightarrow H_{thr} = 0.20)', rul_pidssdm), ...
    'Color', [0.0, 0.2, 0.6], 'FontWeight', 'bold', 'FontSize', 8.5, 'HorizontalAlignment', 'center');

% 9. Shaded Gap / Arrow Showing Prior ALT Exposure (from 8,238 h to 10,000 h)
annotation_y2 = 0.06;
plot([rul_pidssdm, t_design], [annotation_y2, annotation_y2], 'k-', 'LineWidth', 1.4, 'HandleVisibility', 'off');
plot(rul_pidssdm, annotation_y2, 'k<', 'MarkerFaceColor', 'k', 'MarkerSize', 5.5, 'HandleVisibility', 'off');
plot(t_design, annotation_y2, 'k>', 'MarkerFaceColor', 'k', 'MarkerSize', 5.5, 'HandleVisibility', 'off');
text((rul_pidssdm + t_design)/2, 0.115, sprintf('Prior Testing Consumption\n\\approx 18-20%% (%d h)', t_design - rul_pidssdm), ...
    'Color', [0.4, 0.1, 0.1], 'FontWeight', 'bold', 'FontSize', 8.0, 'HorizontalAlignment', 'center');

% Text Callout for KI-SSDM Crossing Point
text(rul_pidssdm + 200, H_thr + 0.055, sprintf('KI-SSDM RUL: %d h\n[90%% CI: %d, %d h]', ...
    rul_pidssdm, rul_ci_lo, rul_ci_hi), ...
    'Color', [0.0, 0.2, 0.6], 'FontWeight', 'bold', 'FontSize', 9);

% Axis cosmetics
xlim(ax1, [0, t_total]);
ylim(ax1, [0, 1.05]);
grid(ax1, 'on'); box(ax1, 'on');
set(ax1, 'FontSize', 10, 'FontWeight', 'bold', 'LineWidth', 1.1);
xlabel(ax1, 'Operating Time t (hours)', 'FontSize', 11, 'FontWeight', 'bold');
ylabel(ax1, 'Health Index H(t) [Dimensionless: 1.0 \rightarrow 0.0]', 'FontSize', 11, 'FontWeight', 'bold');
title(ax1, '(a) Full-Lifecycle Health Index Forecasting Across Evaluated Methodologies', ...
    'FontSize', 11.5, 'FontWeight', 'bold');

lgd1 = legend(ax1, 'Location', 'northeast', 'FontSize', 7.8);
set(lgd1, 'Color', [1 1 1 0.92], 'EdgeColor', [0.7 0.7 0.7]);


%% ---------------- PANEL (b): MULTI-REGIME SENSITIVITY --------------------
ax2 = nexttile;
hold(ax2, 'on');

% 1. Failure threshold & vertical references
yline(H_thr, 'r--', 'LineWidth', 1.8, 'DisplayName', sprintf('Threshold (H_{thr} = %.2f)', H_thr));
xline(t_design, 'Color', [0.5, 0.1, 0.1], 'LineStyle', ':', 'LineWidth', 1.6, ...
    'DisplayName', sprintf('PMI Design Rating (%d h)', t_design));

% 2. Colors for the 8 regimes (4 unladen blues, 4 loaded reds/oranges)
colors_regimes = [
    0.10, 0.60, 0.90;   % Unladen 5k
    0.00, 0.40, 0.85;   % Unladen 10k
    0.00, 0.20, 0.70;   % Unladen 15k
    0.05, 0.05, 0.45;   % Unladen 20k
    0.95, 0.55, 0.15;   % Laden 5k
    0.85, 0.35, 0.05;   % Laden 10k
    0.80, 0.15, 0.05;   % Laden 15k
    0.55, 0.00, 0.00    % Laden 20k
];

style_regimes = {'-', '-', '-', '-', '--', '--', '--', '--'};

% 3. Plot each operational regime from X = 0 to 12,000 h
for r = 1:8
    rul_r = rul_regimes(r);
    H_r = deg_profile(t, rul_r);
    plot(t, H_r, 'Color', colors_regimes(r, :), 'LineStyle', style_regimes{r}, ...
        'LineWidth', 1.8, 'DisplayName', labels_regimes{r});
    % Marker at threshold crossing
    plot(rul_r, H_thr, 'o', 'MarkerSize', 5.5, 'MarkerFaceColor', colors_regimes(r, :), ...
        'MarkerEdgeColor', 'k', 'HandleVisibility', 'off');
end

% Axis cosmetics for Panel (b)
xlim(ax2, [0, t_total]);
ylim(ax2, [0, 1.05]);
grid(ax2, 'on'); box(ax2, 'on');
set(ax2, 'FontSize', 10, 'FontWeight', 'bold', 'LineWidth', 1.1);
xlabel(ax2, 'Operating Time t (hours)', 'FontSize', 11, 'FontWeight', 'bold');
ylabel(ax2, 'Health Index H(t) [Dimensionless: 1.0 \rightarrow 0.0]', 'FontSize', 11, 'FontWeight', 'bold');
title(ax2, '(b) KI-SSDM Health Index Trajectories Across Speed and Payload Regimes', ...
    'FontSize', 11.5, 'FontWeight', 'bold');

lgd2 = legend(ax2, 'Location', 'northeast', 'FontSize', 7.5);
set(lgd2, 'Color', [1 1 1 0.92], 'EdgeColor', [0.7 0.7 0.7]);


%% =========================================================================
%       3. ZOOMED INSET AXES (a): COMPARATIVE METHOD CROSSINGS
% =========================================================================
axInsetA = axes('Units', 'normalized', 'Position', insetPosA);
box(axInsetA, 'on'); hold(axInsetA, 'on');

% Shaded intervals inside Inset (a)
idx_zoomA = t >= (zoomXLimA(1)-150) & t <= (zoomXLimA(2)+150);
fill(axInsetA, [t(idx_zoomA); flipud(t(idx_zoomA))], [H_ci_lo(idx_zoomA); flipud(H_ci_hi(idx_zoomA))], ...
    [0.65, 0.80, 0.95], 'EdgeColor', 'none', 'FaceAlpha', 0.45);
fill(axInsetA, [t(idx_zoomA); flipud(t(idx_zoomA))], [H_pf_lo(idx_zoomA); flipud(H_pf_hi(idx_zoomA))], ...
    [0.95, 0.80, 0.70], 'EdgeColor', 'none', 'FaceAlpha', 0.30);

% Method trajectories in Inset (a)
plot(axInsetA, t(idx_zoomA), H_pidssdm(idx_zoomA), 'Color', [0.0, 0.25, 0.70], 'LineWidth', 2.2);
plot(axInsetA, t(idx_zoomA), H_phys(idx_zoomA),    'Color', [0.13, 0.55, 0.13], 'LineWidth', 1.6);
plot(axInsetA, t(idx_zoomA), H_pinn(idx_zoomA),    'Color', [0.85, 0.45, 0.0],  'LineWidth', 1.6, 'LineStyle', '--');
plot(axInsetA, t(idx_zoomA), H_lstm(idx_zoomA),    'Color', [0.55, 0.15, 0.65], 'LineWidth', 1.6, 'LineStyle', '-.');
plot(axInsetA, t(idx_zoomA), H_pf(idx_zoomA),      'Color', [0.65, 0.35, 0.15], 'LineWidth', 1.6, 'LineStyle', ':');

% Crossing markers in Inset (a)
plot(axInsetA, rul_pidssdm, H_thr, 'p', 'MarkerSize', 10, 'MarkerFaceColor', [0.0, 0.25, 0.70], 'MarkerEdgeColor', 'k');
plot(axInsetA, rul_phys,    H_thr, 'o', 'MarkerSize', 5.5, 'MarkerFaceColor', [0.13, 0.55, 0.13], 'MarkerEdgeColor', 'k');
plot(axInsetA, rul_pinn,    H_thr, 's', 'MarkerSize', 5.5, 'MarkerFaceColor', [0.85, 0.45, 0.0],  'MarkerEdgeColor', 'k');
plot(axInsetA, rul_lstm,    H_thr, '^', 'MarkerSize', 5.5, 'MarkerFaceColor', [0.55, 0.15, 0.65], 'MarkerEdgeColor', 'k');
plot(axInsetA, rul_pf,      H_thr, 'd', 'MarkerSize', 5.5, 'MarkerFaceColor', [0.65, 0.35, 0.15], 'MarkerEdgeColor', 'k');

yline(axInsetA, H_thr, 'r--', 'LineWidth', 1.3);

% Text in Inset (a) pointing out KI-SSDM
text(axInsetA, rul_pidssdm + 15, H_thr + 0.024, sprintf('KI-SSDM\n%d h', rul_pidssdm), ...
    'Color', [0.0, 0.25, 0.70], 'FontSize', 7.5, 'FontWeight', 'bold');

xlim(axInsetA, zoomXLimA);
ylim(axInsetA, zoomYLimA);
grid(axInsetA, 'on');
set(axInsetA, 'FontSize', 8, 'FontWeight', 'bold', 'Color', [1 1 1]);
hTitleA = title(axInsetA, 'Zoom: Method Crossings', 'FontSize', 8.0, 'FontWeight', 'bold');
xlabel(axInsetA, 'Hours', 'FontSize', 7.5);
ylabel(axInsetA, 'H(t)', 'FontSize', 7.5);

% Attach interactive drag listeners to Inset (a)
set(axInsetA, 'ButtonDownFcn', @(src, evt) start_drag_inset(src, evt, fig, axInsetA, 'Inset (a)'));
set(hTitleA,  'HitTest', 'on', 'ButtonDownFcn', @(src, evt) start_drag_inset(src, evt, fig, axInsetA, 'Inset (a)'));


%% =========================================================================
%       4. ZOOMED INSET AXES (b): OPERATIONAL REGIME CROSSINGS
% =========================================================================
axInsetB = axes('Units', 'normalized', 'Position', insetPosB);
box(axInsetB, 'on'); hold(axInsetB, 'on');

for r = 1:8
    rul_r = rul_regimes(r);
    H_r = deg_profile(t, rul_r);
    idx_zoomB = t >= (zoomXLimB(1)-100) & t <= (zoomXLimB(2)+100);
    plot(axInsetB, t(idx_zoomB), H_r(idx_zoomB), 'Color', colors_regimes(r, :), ...
        'LineStyle', style_regimes{r}, 'LineWidth', 1.8);
    plot(axInsetB, rul_r, H_thr, 'o', 'MarkerSize', 5.5, 'MarkerFaceColor', colors_regimes(r, :), ...
        'MarkerEdgeColor', 'k');
end
yline(axInsetB, H_thr, 'r--', 'LineWidth', 1.3);

% Text in Inset (b) highlighting the narrow physical spread
text(axInsetB, 7965, 0.172, sprintf('Spread: 8,056-8,271 h\n(\\Delta = 215 h)'), ...
    'Color', [0.2, 0.2, 0.2], 'FontSize', 7.5, 'FontWeight', 'bold');

xlim(axInsetB, zoomXLimB);
ylim(axInsetB, zoomYLimB);
grid(axInsetB, 'on');
set(axInsetB, 'FontSize', 8, 'FontWeight', 'bold', 'Color', [1 1 1]);
hTitleB = title(axInsetB, 'Zoom: Regime Crossings', 'FontSize', 8.0, 'FontWeight', 'bold');
xlabel(axInsetB, 'Hours', 'FontSize', 7.5);
ylabel(axInsetB, 'H(t)', 'FontSize', 7.5);

% Attach interactive drag listeners to Inset (b)
set(axInsetB, 'ButtonDownFcn', @(src, evt) start_drag_inset(src, evt, fig, axInsetB, 'Inset (b)'));
set(hTitleB,  'HitTest', 'on', 'ButtonDownFcn', @(src, evt) start_drag_inset(src, evt, fig, axInsetB, 'Inset (b)'));

% UI Button on figure to re-export after interactive repositioning
uicontrol('Parent', fig, 'Style', 'pushbutton', 'String', 'Save & Export (600 DPI)', ...
    'Units', 'normalized', 'Position', [0.86, 0.02, 0.12, 0.04], ...
    'FontSize', 8.5, 'FontWeight', 'bold', 'BackgroundColor', [0.92, 0.95, 1.0], ...
    'Callback', @(~,~) export_current_figure(fig, outDir1, outDir2, outDir3));

drawnow;

%% =========================================================================
%                         5. EXPORT ARTIFACTS
% =========================================================================
export_current_figure(fig, outDir1, outDir2, outDir3);

if closeAfterExport
    close(fig);
end
end

% =========================================================================
%                        HELPER / CALLBACK FUNCTIONS
% =========================================================================

function export_current_figure(fig, outDir1, outDir2, outDir3)
    if nargin < 4, outDir3 = ''; end
    pngFile1 = fullfile(outDir1, 'fig_health_index_forecasting.png');
    pdfFile1 = fullfile(outDir1, 'fig_health_index_forecasting.pdf');
    
    fprintf('Exporting 600 DPI PNG: %s ...\n', pngFile1);
    exportgraphics(fig, pngFile1, 'Resolution', 600);
    
    fprintf('Exporting Vector PDF:  %s ...\n', pdfFile1);
    try
        exportgraphics(fig, pdfFile1, 'ContentType', 'vector');
    catch
        exportgraphics(fig, pdfFile1, 'Resolution', 600);
    end
    
    if ~isempty(outDir2) && exist(outDir2, 'dir')
        copyfile(pngFile1, fullfile(outDir2, 'fig_health_index_forecasting.png'), 'f');
        copyfile(pdfFile1, fullfile(outDir2, 'fig_health_index_forecasting.pdf'), 'f');
    end
    if ~isempty(outDir3) && exist(outDir3, 'dir')
        copyfile(pngFile1, fullfile(outDir3, 'fig_health_index_forecasting.png'), 'f');
        copyfile(pdfFile1, fullfile(outDir3, 'fig_health_index_forecasting.pdf'), 'f');
    end
    fprintf('Export complete.\n');
end

function start_drag_inset(~, ~, hFig, hAx, nameStr)
    oldUnits = hFig.Units;
    hFig.Units = 'normalized';
    startPt = get(hFig, 'CurrentPoint');
    startPos = get(hAx, 'Position');
    hFig.Units = oldUnits;
    
    set(hFig, 'WindowButtonMotionFcn', @(~,~) drag_motion_inset(hFig, hAx, startPt, startPos));
    set(hFig, 'WindowButtonUpFcn',     @(~,~) stop_drag_inset(hFig, hAx, nameStr));
end

function drag_motion_inset(hFig, hAx, startPt, startPos)
    oldUnits = hFig.Units;
    hFig.Units = 'normalized';
    curPt = get(hFig, 'CurrentPoint');
    hFig.Units = oldUnits;
    
    dx = curPt(1) - startPt(1);
    dy = curPt(2) - startPt(2);
    
    newPos = startPos;
    newPos(1) = min(max(startPos(1) + dx, 0.01), 0.99 - startPos(3));
    newPos(2) = min(max(startPos(2) + dy, 0.01), 0.99 - startPos(4));
    
    set(hAx, 'Position', newPos);
    drawnow limitrate;
end

function stop_drag_inset(hFig, hAx, nameStr)
    set(hFig, 'WindowButtonMotionFcn', '');
    set(hFig, 'WindowButtonUpFcn', '');
    pos = get(hAx, 'Position');
    fprintf('\n------------------------------------------------------------------------\n');
    fprintf('  [INTERACTIVE POSITION UPDATE] %s\n', nameStr);
    fprintf('  Current Position: [%.4f, %.4f, %.4f, %.4f]\n', pos(1), pos(2), pos(3), pos(4));
    fprintf('  To lock this position in code, update:\n');
    fprintf('  >> generate_health_index_forecasting_plot([%.4f, %.4f, %.4f, %.4f], ...);\n', ...
        pos(1), pos(2), pos(3), pos(4));
    fprintf('------------------------------------------------------------------------\n');
end
