function plot_fig03_framework_architecture(outDir)
% PLOT_FIG03_FRAMEWORK_ARCHITECTURE
% Generates Figure 3: End-to-end KI-SSDM architectural workflow at 600 DPI.

if nargin < 1 || isempty(outDir)
    packageRoot = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(packageRoot, 'output_figures_600dpi');
end
if ~exist(outDir, 'dir'), mkdir(outDir); end

fprintf('[Fig 03] Generating Figure 3 (KI-SSDM Framework Architecture) at 600 DPI...\n');

packageRoot = fileparts(fileparts(mfilename('fullpath')));
srcImg = fullfile(packageRoot, 'data', 'PI_DSSDM_Framework.png');

if ~exist(srcImg, 'file')
    error('Could not find canonical framework architecture image at: %s', srcImg);
end

img = imread(srcImg);

% Target 600 DPI width for a full double-column A4 figure (7.16 inches = 4300 px)
targetW = 4300;
targetH = round(size(img, 1) * targetW / size(img, 2));

if size(img, 2) ~= targetW
    img_600 = imresize(img, [targetH, targetW], 'lanczos3');
else
    img_600 = img;
end

pngPath = fullfile(outDir, 'PI_DSSDM_Framework.png');
pdfPath = fullfile(outDir, 'PI_DSSDM_Framework.pdf');

% Write 600 DPI metadata PNG
imwrite(img_600, pngPath, 'png', 'ResolutionUnit', 'meter', 'XResolution', 600 * 39.3701, 'YResolution', 600 * 39.3701);

% Generate Vector/Container PDF
fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [100, 100, 1600, round(1600*targetH/targetW)], 'Visible', 'off');
ax = axes('Parent', fig, 'Position', [0, 0, 1, 1]);
imshow(img_600, 'Parent', ax, 'Border', 'tight');
axis(ax, 'off');
try
    exportgraphics(fig, pdfPath, 'ContentType', 'vector');
catch
    exportgraphics(fig, pdfPath, 'Resolution', 600);
end
close(fig);

fprintf('         Saved: %s (600 DPI, %d x %d px)\n', pngPath, targetW, targetH);
fprintf('         Saved: %s\n', pdfPath);
end
