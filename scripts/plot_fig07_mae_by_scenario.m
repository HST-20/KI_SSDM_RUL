function plot_fig07_mae_by_scenario(outDir)
% PLOT_FIG07_MAE_BY_SCENARIO
% Generates Figure 7: Fleet MAE distributions across scenarios S1-S6.

if nargin < 1 || isempty(outDir)
    packageRoot = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(packageRoot, 'output_figures_600dpi');
end
if ~exist(outDir, 'dir'), mkdir(outDir); end

packageRoot = fileparts(fileparts(mfilename('fullpath')));
figFile = fullfile(packageRoot, 'data', 'benchmark_30fleets', 'Fig1_MAE_by_scenario.fig');

if ~exist(figFile, 'file')
    error('Figure file not found: %s', figFile);
end

fprintf('[Fig 07] Generating Figure 7 (Fleet MAE Distributions by Scenario) at 600 DPI...\n');

fig = openfig(figFile, 'invisible');
set(fig, 'Color', 'w');

ensure_fontsize_increment(fig, 3);
relabel_method_names(fig);
drawnow;

pngOut = fullfile(outDir, 'Fig1_MAE_by_scenario.png');
pdfOut = fullfile(outDir, 'Fig1_MAE_by_scenario.pdf');

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
