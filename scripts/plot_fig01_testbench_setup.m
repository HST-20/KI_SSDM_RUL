function plot_fig01_testbench_setup(outDir)
% PLOT_FIG01_TESTBENCH_SETUP
% Reproduces Figure 1: Industrial ball-screw feed drive (BSFD) experimental
% test bench for controller-telemetry RUL validation.

if nargin < 1 || isempty(outDir)
    packageRoot = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(packageRoot, 'output_figures_600dpi');
end
if ~exist(outDir, 'dir'), mkdir(outDir); end

packageRoot = fileparts(fileparts(mfilename('fullpath')));
srcImg = fullfile(packageRoot, 'data', 'BSFD_ALT_Testsetup.png');

if ~exist(srcImg, 'file')
    error('Source image BSFD_ALT_Testsetup.png not found at: %s', srcImg);
end

fprintf('[Fig 01] Generating Figure 1 (BSFD Experimental Test Bench Layout) at 600 DPI...\n');

img = imread(srcImg);
[h, w, ~] = size(img);

fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [100, 100, 1600, round(1600*h/w)], 'Visible', 'off');
ax = axes('Parent', fig, 'Position', [0, 0, 1, 1]);
imshow(img, 'Parent', ax, 'Border', 'tight');
axis(ax, 'off');

pngOut = fullfile(outDir, 'BSFD_ALT_Testsetup.png');
pdfOut = fullfile(outDir, 'BSFD_ALT_Testsetup.pdf');

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
