function plot_fig10_calibration_sharpness(outDir)
% PLOT_FIG10_CALIBRATION_SHARPNESS
% Generates Figure 10: Conformal coverage vs sharpness across regimes.

if nargin < 1 || isempty(outDir)
    packageRoot = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(packageRoot, 'output_figures_600dpi');
end
if ~exist(outDir, 'dir'), mkdir(outDir); end

packageRoot = fileparts(fileparts(mfilename('fullpath')));
figFile = fullfile(packageRoot, 'data', 'benchmark_30fleets', 'Fig3_calibration_sharpness.fig');

if ~exist(figFile, 'file')
    error('Figure file not found: %s', figFile);
end

fprintf('[Fig 10] Generating Figure 10 (Calibration Coverage vs Sharpness) at 600 DPI...\n');

fig = openfig(figFile, 'invisible');
set(fig, 'Color', 'w');

ensure_fontsize_increment(fig, 3);
relabel_method_names(fig);
drawnow;

pngOut = fullfile(outDir, 'Fig3_calibration_sharpness.png');
pdfOut = fullfile(outDir, 'Fig3_calibration_sharpness.pdf');

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
