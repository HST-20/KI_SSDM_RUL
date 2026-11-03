function relabel_method_names(figHandle, titleMap)
% RELABEL_METHOD_NAMES
% Shows the proposed method as KI-SSDM (the manuscript name) and the
% comparators without underscores, in every text object, legend, tick label
% and line DisplayName. Plotted data are not touched.
% titleMap (optional): n-by-2 cell of {old text, new text} for panel titles.

if nargin < 2, titleMap = cell(0, 2); end
if isempty(figHandle) || ~ishandle(figHandle), return; end

for tx = findall(figHandle, '-property', 'String')'
    if isa(tx, 'matlab.graphics.illustration.Legend'), continue; end
    s = tx.String;
    if ischar(s) || iscellstr(s) || isstring(s)
        new = rename(s);
        for k = 1:size(titleMap, 1)
            if isequal(cellstr(new), cellstr(titleMap{k, 1})), new = titleMap{k, 2}; end
        end
        tx.String = new;
    end
end
for lg = findall(figHandle, 'Type', 'legend')'
    lg.String = rename(lg.String);
end
% Only rewrite tick labels that change, so numeric ticks stay automatic
for ax = findall(figHandle, 'Type', 'axes')'
    for p = ["XTickLabel", "YTickLabel"]
        new = rename(ax.(p));
        if ~isequal(new, ax.(p)), ax.(p) = new; end
    end
end
for h = findall(figHandle, '-property', 'DisplayName')'
    h.DisplayName = rename(h.DisplayName);
end
end

function s = rename(s)
s = regexprep(s, 'PI[-_ ]DSSDM', 'KI-SSDM');
s = regexprep(s, '\<(Inverse|Physics|Basis|Bayesian)_(PINN|SSM|hybrid|PF)\>', '$1 $2');
end
