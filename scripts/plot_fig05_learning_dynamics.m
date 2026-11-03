function plot_fig05_learning_dynamics(outDir)
% PLOT_FIG05_LEARNING_DYNAMICS
% Generates Figure 5: Multi-fleet neural discrepancy learning dynamics.

if nargin < 1 || isempty(outDir)
    packageRoot = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(packageRoot, 'output_figures_600dpi');
end
if ~exist(outDir, 'dir'), mkdir(outDir); end

packageRoot = fileparts(fileparts(mfilename('fullpath')));
figFile = fullfile(packageRoot, 'data', 'benchmark_30fleets', 'E01_Learning.fig');

if ~exist(figFile, 'file')
    error('Figure file not found: %s', figFile);
end

fprintf('[Fig 05] Generating Figure 5 (Discrepancy Learning Dynamics) at 600 DPI...\n');

fig = openfig(figFile, 'invisible');
set(fig, 'Color', 'w');

ensure_fontsize_increment(fig, 3);
relabel_method_names(fig, { ...
    'Integrated B and unit frailty; conditional uncertainty', 'Unit-marginal NLL'; ...
    'Bound 0.00; RMS 0', 'Bound 0.00; RMS 0 (no residual selected)'});
drawnow;

pngOut = fullfile(outDir, 'E01_Learning.png');
pdfOut = fullfile(outDir, 'E01_Learning.pdf');

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
