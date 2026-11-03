function plot_fig08_hierarchical_inference(outDir)
% PLOT_FIG08_HIERARCHICAL_INFERENCE
% Generates Figure 8: Hierarchical unit frailty inference and identifiability.

if nargin < 1 || isempty(outDir)
    packageRoot = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(packageRoot, 'output_figures_600dpi');
end
if ~exist(outDir, 'dir'), mkdir(outDir); end

packageRoot = fileparts(fileparts(mfilename('fullpath')));
figFile = fullfile(packageRoot, 'data', 'benchmark_30fleets', 'E01_Hierarchical_inference.fig');

if ~exist(figFile, 'file')
    error('Figure file not found: %s', figFile);
end

fprintf('[Fig 08] Generating Figure 8 (Hierarchical Frailty Inference) at 600 DPI...\n');

fig = openfig(figFile, 'invisible');
set(fig, 'Color', 'w');

ensure_fontsize_increment(fig, 3);
relabel_method_names(fig);
drawnow;

pngOut = fullfile(outDir, 'E01_Hierarchical_inference.png');
pdfOut = fullfile(outDir, 'E01_Hierarchical_inference.pdf');

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
