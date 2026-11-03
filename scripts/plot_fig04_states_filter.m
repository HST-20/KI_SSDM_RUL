function plot_fig04_states_filter(outDir)
% PLOT_FIG04_STATES_FILTER
% Generates Figure 4: Continuous latent state-space filter tracking and
% residual decoupling across operational degradation.

if nargin < 1 || isempty(outDir)
    packageRoot = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(packageRoot, 'output_figures_600dpi');
end
if ~exist(outDir, 'dir'), mkdir(outDir); end

packageRoot = fileparts(fileparts(mfilename('fullpath')));
figFile = fullfile(packageRoot, 'data', 'benchmark_30fleets', 'E01_States_filter.fig');

if ~exist(figFile, 'file')
    error('Figure file not found: %s', figFile);
end

fprintf('[Fig 04] Generating Figure 4 (Latent State-Space Filter Tracking) at 600 DPI...\n');

fig = openfig(figFile, 'invisible');
set(fig, 'Color', 'w');

ensure_fontsize_increment(fig, 3);
% Shorter panel titles: the v17 originals overlap at export size
relabel_method_names(fig, { ...
    'Smoothed paths, filtered mean, independent anchors', 'Damage D(t)'; ...
    'Standardized residual B; sensor-scale amplitude in loading', 'Standardised nuisance B(t)'; ...
    'Emission mean and measurement-noise bands', 'Channel 1, 90% noise band'; ...
    'Unit-effect grid, MH N/A NaN, distinct 10', 'Frailty support points'});
drawnow;

pngOut = fullfile(outDir, 'E01_States_filter.png');
pdfOut = fullfile(outDir, 'E01_States_filter.pdf');

exportgraphics(fig, pngOut, 'Resolution', 600);
try
    exportgraphics(fig, pdfOut, 'ContentType', 'vector');
catch
    exportgraphics(fig, pdfOut, 'Resolution', 600);
end
close(fig);

fprintf('         Saved: %s (600 DPI)\n', pngOut);
fprintf('         Saved: %s\n', pdfOut);
end
