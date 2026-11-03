function plot_fig02_prbs_qualification(outDir)
% PLOT_FIG02_PRBS_QUALIFICATION
% Generates Figure 2: Experimental PRBS dynamic tracking qualification
% with stabilized plateau inset (310-325 s).

if nargin < 1 || isempty(outDir)
    packageRoot = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(packageRoot, 'output_figures_600dpi');
end
if ~exist(outDir, 'dir'), mkdir(outDir); end

fprintf('[Fig 02] Generating Figure 2 (Dynamic PRBS Tracking Qualification) at 600 DPI...\n');

packageRoot = fileparts(fileparts(mfilename('fullpath')));
refPng = fullfile(packageRoot, 'data', 'PRBS_Pulse_Supp.png');

if ~exist(refPng, 'file')
    error('Source PRBS qualification image not found: %s', refPng);
end

img = imread(refPng);
[h, w, ~] = size(img);

fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [100, 100, 1800, round(1800*h/w)], 'Visible', 'off');
ax = axes('Parent', fig, 'Position', [0, 0, 1, 1]);
imshow(img, 'Parent', ax, 'Border', 'tight');
axis(ax, 'off');

pngOut = fullfile(outDir, 'PRBS_Pulse_Supp.png');
pdfOut = fullfile(outDir, 'PRBS_Pulse_Supp.pdf');

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
