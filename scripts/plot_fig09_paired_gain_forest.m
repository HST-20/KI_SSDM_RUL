function plot_fig09_paired_gain_forest(outDir)
% PLOT_FIG09_PAIRED_GAIN_FOREST
% Generates Figure 9: Paired prognostic gain forest plot across fleets.

if nargin < 1 || isempty(outDir)
    packageRoot = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(packageRoot, 'output_figures_600dpi');
end
if ~exist(outDir, 'dir'), mkdir(outDir); end

packageRoot = fileparts(fileparts(mfilename('fullpath')));
figFile = fullfile(packageRoot, 'data', 'benchmark_30fleets', 'Fig2_paired_gain_forest.fig');

if ~exist(figFile, 'file')
    error('Figure file not found: %s', figFile);
end

fprintf('[Fig 09] Generating Figure 9 (Paired Prognostic Gain Forest Plot) at 600 DPI...\n');

fig = openfig(figFile, 'invisible');
set(fig, 'Color', 'w');

ensure_fontsize_increment(fig, 3);
relabel_method_names(fig);
drawnow;

pngOut = fullfile(outDir, 'Fig2_paired_gain_forest.png');
pdfOut = fullfile(outDir, 'Fig2_paired_gain_forest.pdf');

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
