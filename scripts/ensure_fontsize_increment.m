function ensure_fontsize_increment(figHandle, ptDelta)
% ENSURE_FONTSIZE_INCREMENT
% Increases font size of all text objects, axes tick labels, legends,
% and colorbars by ptDelta exactly once, preventing double-incrementation.

if nargin < 2, ptDelta = 3; end
if isempty(figHandle) || ~ishandle(figHandle), return; end

% 1. Axes tick labels (axes FontProperties)
allAxes = findall(figHandle, 'type', 'axes');
for ax = allAxes'
    cur = get(ax, 'FontSize');
    set(ax, 'FontSize', cur + ptDelta);
end

% 2. All text objects (titles, axis labels, text annotations) - incremented once
allText = findall(figHandle, 'type', 'text');
for tx = allText'
    cur = get(tx, 'FontSize');
    set(tx, 'FontSize', cur + ptDelta);
end

% 3. Legends
allLegends = findall(figHandle, 'type', 'legend');
for lg = allLegends'
    cur = get(lg, 'FontSize');
    set(lg, 'FontSize', cur + ptDelta);
end

% 4. Colorbars
allColorbars = findall(figHandle, 'type', 'colorbar');
for cb = allColorbars'
    cur = get(cb, 'FontSize');
    set(cb, 'FontSize', cur + ptDelta);
end

drawnow;
end
