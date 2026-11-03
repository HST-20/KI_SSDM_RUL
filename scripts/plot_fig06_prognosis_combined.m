function plot_fig06_prognosis_combined(outDir, experiment)
% PLOT_FIG06_PROGNOSIS_COMBINED
% Generates Figure 6: RUL Prognosis and Uncertainty Calibration under
% Operational Duty Protocols (Panel a + b) at 600 DPI.
% The panels are the per-fleet prognosis figures the v17 run saved
% (data/benchmark_30fleets/Exx_Prognosis_*.fig), restyled only. The default
% fleet is experiment 6 (S6 load-exponent misspecification, replicate 1),
% where validation selected the stacked deep correction under both duties.
% Every plotted number is re-derived from v17_test_predictions.csv and
% written to output_tables/Table_Fig6_Source_Check.csv for the caption.
if nargin < 1 || isempty(outDir)
    packageRoot = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(packageRoot, 'output_figures_600dpi');
end
if nargin < 2 || isempty(experiment), experiment = 6; end
if ~exist(outDir, 'dir'), mkdir(outDir); end

packageRoot = fileparts(fileparts(mfilename('fullpath')));
srcFolder = fullfile(packageRoot, 'data', 'benchmark_30fleets');
tag = sprintf('E%02d', experiment);
if ~exist(fullfile(srcFolder, [tag '_Prognosis_planned.fig']), 'file')
    error('Source figure %s_Prognosis_planned.fig not found at: %s', tag, srcFolder);
end
% Generates:
%   1. Exx_Prognosis_planned.png & .pdf         (600 DPI, Panel a)
%   2. Exx_Prognosis_probabilistic.png & .pdf   (600 DPI, Panel b)
%   3. Fig6_Prognosis_Combined.png & .pdf       (600 DPI, Unified Panel a + b)

figConfigs = {
    fullfile(srcFolder, [tag '_Prognosis_planned.fig']), ...
    '(a) Planned Operational Duty Protocol', ...
    [tag '_Prognosis_planned'], 'planned';

    fullfile(srcFolder, [tag '_Prognosis_probabilistic.fig']), ...
    '(b) Probabilistic Markovian Duty Protocol', ...
    [tag '_Prognosis_probabilistic'], 'probabilistic'
};
checks = {};

% Consistent Q1 color palette for comparative methodologies
modelOrder = {'PI_DSSDM', 'Inverse_PINN', 'LSTM', 'Physics_SSM', 'Basis_hybrid', 'Bayesian_PF'};

cMap = containers.Map();
cMap('PI_DSSDM')     = [0.04 0.33 0.85]; % Vibrant Deep Blue (Hero Proposed Model)
cMap('Inverse_PINN') = [0.85 0.35 0.05]; % Vibrant Orange/Amber
cMap('LSTM')         = [0.88 0.65 0.10]; % Amber Gold
cMap('Physics_SSM')  = [0.52 0.15 0.78]; % Deep Purple
cMap('Basis_hybrid') = [0.18 0.65 0.25]; % Emerald Green
cMap('Bayesian_PF')  = [0.12 0.70 0.86]; % Teal / Cyan

% Formal publication naming dictionary (cleans LaTeX underscore subscripts)
modelNamesMap = containers.Map(...
    {'PI_DSSDM', 'Inverse_PINN', 'LSTM', 'Physics_SSM', 'Basis_hybrid', 'Bayesian_PF'}, ...
    {'KI-SSDM', 'Inverse-PINN', 'LSTM', 'Physics-SSM', 'Basis-Hybrid', 'Bayesian-PF'});

barLegMap = containers.Map(...
    {'Raw row', 'Calibrated row', 'Calibrated unit'}, ...
    {'Raw Fleet', 'Fleet-Calibrated', 'Unit-Calibrated'});

exportedPNGs = cell(size(figConfigs, 1), 1);

fprintf('========================================================================\n');
fprintf('  Generating Figure 6: Prognosis Combined (600 DPI Publication Pass)\n');
fprintf('========================================================================\n');

for fIdx = 1:size(figConfigs, 1)
    figPath = figConfigs{fIdx, 1};
    superTitle = figConfigs{fIdx, 2};
    baseName = figConfigs{fIdx, 3};
    
    fprintf('[%d/2] Processing %s ...\n', fIdx, baseName);
    
    f = openfig(figPath, 'invisible');
    checks{end+1} = check_against_predictions(f, experiment, figConfigs{fIdx, 4}, packageRoot); %#ok<AGROW>
    set(f, 'Units', 'pixels', 'Position', [100 100 1650 1000], 'Color', 'w');
    
    % Adjust TiledLayout
    tl = findall(f, 'type', 'tiledlayout');
    if ~isempty(tl)
        tl.TileSpacing = 'compact';
        tl.Padding = 'compact';
        tl.Title.String = superTitle;
        tl.Title.FontSize = 21;
        tl.Title.FontWeight = 'bold';
        tl.Title.FontName = 'Helvetica';
        tl.Title.Color = [0.05 0.05 0.05];
    end
    
    axList = findall(f, 'type', 'axes');
    for k = 1:numel(axList)
        ax = axList(k);
        tile = get(ax, 'Layout').Tile;
        
        % Global typography & axis frame styling
        ax.FontName = 'Helvetica';
        ax.FontSize = 13.5;
        ax.FontWeight = 'bold';
        ax.LineWidth = 1.25;
        ax.Box = 'on';
        ax.XGrid = 'on';
        ax.YGrid = 'on';
        ax.GridAlpha = 0.22;
        ax.GridLineStyle = ':';
        ax.TickDir = 'in';
        ax.TickLength = [0.013 0.024];
        ax.TickLabelInterpreter = 'tex';
        
        switch tile
            case 1 % Subplot 1: Point Forecasts & Conformal Uncertainty Band
                ax.Title.String = 'RUL Point Forecasts & 90% Conformal Band';
                ax.Title.FontSize = 16.5;
                ax.Title.FontWeight = 'bold';
                ax.Title.FontName = 'Helvetica';
                ax.XLabel.String = 'Forecast Origin (h)';
                ax.XLabel.FontSize = 15;
                ax.XLabel.FontWeight = 'bold';
                ax.YLabel.String = 'Remaining Useful Life (h)';
                ax.YLabel.FontSize = 15;
                ax.YLabel.FontWeight = 'bold';
                
                lines = findall(ax, 'type', 'line');
                trueRulLine = [];
                pidssdmLine = [];
                for l = 1:numel(lines)
                    ln = lines(l);
                    name = ln.DisplayName;
                    if strcmp(name, 'True RUL')
                        ln.LineWidth = 3.0;
                        ln.LineStyle = '--';
                        ln.Color = [0 0 0];
                        ln.Marker = 'o';
                        ln.MarkerSize = 6.5;
                        ln.MarkerFaceColor = [0.1 0.1 0.1];
                        trueRulLine = ln;
                    elseif isKey(modelNamesMap, name)
                        ln.DisplayName = modelNamesMap(name);
                        if strcmp(name, 'PI_DSSDM')
                            ln.LineWidth = 3.2;
                            ln.Color = cMap(name);
                            ln.Marker = 's';
                            ln.MarkerSize = 5.5;
                            ln.MarkerFaceColor = cMap(name);
                            pidssdmLine = ln;
                        else
                            ln.LineWidth = 2.0;
                            ln.Color = cMap(name);
                        end
                    end
                end
                
                % Soft sage-green shaded prediction envelope (matching manuscript text)
                p = findall(ax, 'type', 'patch');
                if ~isempty(p)
                    set(p, 'FaceColor', [0.22 0.68 0.38], 'FaceAlpha', 0.18, 'EdgeColor', 'none');
                end
                
                if ~isempty(pidssdmLine), uistack(pidssdmLine, 'top'); end
                if ~isempty(trueRulLine), uistack(trueRulLine, 'top'); end
                
            case 2 % Subplot 2: Predicted RUL vs Independent True RUL
                ax.Title.String = 'Predicted vs. Independent True RUL';
                ax.Title.FontSize = 16.5;
                ax.Title.FontWeight = 'bold';
                ax.Title.FontName = 'Helvetica';
                ax.XLabel.String = 'Independent True RUL (h)';
                ax.XLabel.FontSize = 15;
                ax.XLabel.FontWeight = 'bold';
                ax.YLabel.String = 'Predicted RUL (h)';
                ax.YLabel.FontSize = 15;
                ax.YLabel.FontWeight = 'bold';
                
                % 45-degree identity reference line
                lines = findall(ax, 'type', 'line');
                for l = 1:numel(lines)
                    set(lines(l), 'LineWidth', 2.0, 'LineStyle', '--', 'Color', [0.35 0.35 0.35]);
                end
                
                scats = findall(ax, 'type', 'scatter');
                scatHandles = containers.Map();
                for s = 1:numel(scats)
                    sc = scats(s);
                    name = sc.DisplayName;
                    sc.SizeData = 48;
                    if isKey(modelNamesMap, name)
                        cleanName = modelNamesMap(name);
                        sc.DisplayName = cleanName;
                        sc.MarkerEdgeColor = cMap(name);
                        sc.MarkerFaceColor = cMap(name);
                        sc.MarkerFaceAlpha = 0.60;
                        if strcmp(name, 'PI_DSSDM')
                            sc.MarkerFaceAlpha = 0.85;
                            sc.SizeData = 54;
                        end
                        scatHandles(name) = sc;
                    end
                end
                if isKey(scatHandles, 'PI_DSSDM')
                    uistack(scatHandles('PI_DSSDM'), 'top');
                end
                
                legScats = [];
                legNames = {};
                for m = 1:numel(modelOrder)
                    mKey = modelOrder{m};
                    if isKey(scatHandles, mKey)
                        legScats(end+1) = scatHandles(mKey); %#ok<AGROW>
                        legNames{end+1} = modelNamesMap(mKey); %#ok<AGROW>
                    end
                end
                if ~isempty(legScats)
                    leg2 = legend(ax, legScats, legNames, 'Location', 'southeast');
                    set(leg2, 'FontSize', 11.5, 'FontWeight', 'bold', 'Box', 'on', ...
                        'LineWidth', 0.8, 'EdgeColor', [0.75 0.75 0.75]);
                end
                
            case 3 % Subplot 3: Prognostic Accuracy within +/- 20% True RUL Band
                ax.Title.String = 'Prognostic Accuracy within \pm 20% Band';
                ax.Title.FontSize = 16.5;
                ax.Title.FontWeight = 'bold';
                ax.Title.FontName = 'Helvetica';
                ax.XLabel.String = 'Elapsed Lifetime Fraction';
                ax.XLabel.FontSize = 15;
                ax.XLabel.FontWeight = 'bold';
                ax.YLabel.String = 'Within \pm 20% True RUL (%)';
                ax.YLabel.FontSize = 15;
                ax.YLabel.FontWeight = 'bold';
                ax.YLim = [0 102];
                
                lines = findall(ax, 'type', 'line');
                lineHandles = containers.Map();
                for l = 1:numel(lines)
                    ln = lines(l);
                    col = ln.Color;
                    if norm(col - [0.07 0.44 0.74]) < 0.1 || norm(col - cMap('PI_DSSDM')) < 0.1
                        ln.DisplayName = 'KI-SSDM';
                        ln.LineWidth = 3.2;
                        ln.Color = cMap('PI_DSSDM');
                        ln.Marker = 's';
                        ln.MarkerSize = 5.5;
                        ln.MarkerFaceColor = cMap('PI_DSSDM');
                        lineHandles('PI_DSSDM') = ln;
                    elseif norm(col - [0.87 0.33 0.00]) < 0.1 || norm(col - cMap('Inverse_PINN')) < 0.1
                        ln.DisplayName = 'Inverse-PINN';
                        ln.LineWidth = 2.0;
                        ln.Color = cMap('Inverse_PINN');
                        lineHandles('Inverse_PINN') = ln;
                    elseif norm(col - [0.93 0.69 0.12]) < 0.1 || norm(col - cMap('LSTM')) < 0.1
                        ln.DisplayName = 'LSTM';
                        ln.LineWidth = 2.2;
                        ln.Color = cMap('LSTM');
                        ln.Marker = 'o';
                        ln.MarkerSize = 5;
                        lineHandles('LSTM') = ln;
                    elseif norm(col - [0.52 0.09 0.82]) < 0.1 || norm(col - cMap('Physics_SSM')) < 0.1
                        ln.DisplayName = 'Physics-SSM';
                        ln.LineWidth = 2.0;
                        ln.Color = cMap('Physics_SSM');
                        lineHandles('Physics_SSM') = ln;
                    elseif norm(col - [0.23 0.67 0.20]) < 0.1 || norm(col - cMap('Basis_hybrid')) < 0.1
                        ln.DisplayName = 'Basis-Hybrid';
                        ln.LineWidth = 2.0;
                        ln.Color = cMap('Basis_hybrid');
                        lineHandles('Basis_hybrid') = ln;
                    elseif norm(col - [0.18 0.74 0.94]) < 0.1 || norm(col - cMap('Bayesian_PF')) < 0.1
                        ln.DisplayName = 'Bayesian-PF';
                        ln.LineWidth = 2.0;
                        ln.Color = cMap('Bayesian_PF');
                        lineHandles('Bayesian_PF') = ln;
                    else
                        ln.LineWidth = 2.0;
                    end
                end
                if isKey(lineHandles, 'PI_DSSDM')
                    uistack(lineHandles('PI_DSSDM'), 'top');
                end
                
                legLines = [];
                legNames = {};
                for m = 1:numel(modelOrder)
                    mKey = modelOrder{m};
                    if isKey(lineHandles, mKey)
                        legLines(end+1) = lineHandles(mKey); %#ok<AGROW>
                        legNames{end+1} = modelNamesMap(mKey); %#ok<AGROW>
                    end
                end
                if ~isempty(legLines)
                    leg3 = legend(ax, legLines, legNames, 'Location', 'southwest');
                    set(leg3, 'FontSize', 10.5, 'FontWeight', 'bold', 'Box', 'on', ...
                        'LineWidth', 0.8, 'EdgeColor', [0.75 0.75 0.75]);
                end
                
            case 4 % Subplot 4: Empirical Coverage Rate across Evaluation Models
                ax.Title.String = 'Empirical Coverage Rate across Models';
                ax.Title.FontSize = 16.5;
                ax.Title.FontWeight = 'bold';
                ax.Title.FontName = 'Helvetica';
                ax.XLabel.String = '';
                ax.YLabel.String = 'Coverage (%)';
                ax.YLabel.FontSize = 15;
                ax.YLabel.FontWeight = 'bold';
                ax.YLim = [0 105];
                
                cleanTicks = {'KI-SSDM', 'Inverse-PINN', 'LSTM', 'Physics-SSM', 'Basis-Hybrid', 'Bayesian-PF'};
                ax.XTickLabel = cleanTicks;
                ax.XTickLabelRotation = 25;
                ax.FontSize = 12.5;
                
                cLine = findall(ax, 'type', 'constantline');
                if ~isempty(cLine)
                    set(cLine, 'LineWidth', 2.0, 'LineStyle', '--', 'Color', [0.85 0.15 0.15]);
                end
                
                text(ax, 0.60, 92.5, '90% Nominal Target', 'Color', [0.85 0.15 0.15], ...
                    'FontSize', 11.5, 'FontWeight', 'bold', 'FontName', 'Helvetica');
                
                bars = findall(ax, 'type', 'bar');
                for b = 1:numel(bars)
                    br = bars(b);
                    br.LineWidth = 0.9;
                    br.EdgeColor = [0.2 0.2 0.2];
                    if isKey(barLegMap, br.DisplayName)
                        br.DisplayName = barLegMap(br.DisplayName);
                    end
                end
                
            case 5 % Subplot 5: Mean Calibrated Prediction Band Width
                ax.Title.String = 'Mean Calibrated Prediction Band Width';
                ax.Title.FontSize = 16.5;
                ax.Title.FontWeight = 'bold';
                ax.Title.FontName = 'Helvetica';
                ax.XLabel.String = '';
                ax.YLabel.String = 'Mean Calibrated Width (h)';
                ax.YLabel.FontSize = 15;
                ax.YLabel.FontWeight = 'bold';
                
                cleanTicks = {'KI-SSDM', 'Inverse-PINN', 'LSTM', 'Physics-SSM', 'Basis-Hybrid', 'Bayesian-PF'};
                ax.XTickLabel = cleanTicks;
                ax.XTickLabelRotation = 25;
                ax.FontSize = 12.5;
                
                bars = findall(ax, 'type', 'bar');
                if ~isempty(bars)
                    br = bars(1);
                    br.LineWidth = 1.0;
                    br.EdgeColor = [0.15 0.15 0.15];
                    br.FaceColor = 'flat';
                    for mIdx = 1:numel(modelOrder)
                        br.CData(mIdx, :) = cMap(modelOrder{mIdx});
                    end
                    yVals = br.YData;
                    for vIdx = 1:numel(yVals)
                        val = yVals(vIdx);
                        text(ax, vIdx, val + max(yVals)*0.03, sprintf('%.0f h', val), ...
                            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                            'FontSize', 11.5, 'FontWeight', 'bold', 'FontName', 'Helvetica', ...
                            'Color', [0.15 0.15 0.15]);
                    end
                    ax.YLim = [0, max(yVals) * 1.18];
                end
                
            case 6 % Subplot 6: Paired Forecast Ablation (Residual Dynamics)
                ax.Title.String = 'Forecast Ablation: Residual Dynamics';
                ax.Title.FontSize = 16.5;
                ax.Title.FontWeight = 'bold';
                ax.Title.FontName = 'Helvetica';
                ax.XLabel.String = 'Residual OFF RUL (h)';
                ax.XLabel.FontSize = 15;
                ax.XLabel.FontWeight = 'bold';
                ax.YLabel.String = 'Residual ON RUL (h)';
                ax.YLabel.FontSize = 15;
                ax.YLabel.FontWeight = 'bold';
                
                lines = findall(ax, 'type', 'line');
                for l = 1:numel(lines)
                    set(lines(l), 'LineWidth', 2.0, 'LineStyle', '--', 'Color', [0.35 0.35 0.35]);
                end
                
                scats = findall(ax, 'type', 'scatter');
                for s = 1:numel(scats)
                    sc = scats(s);
                    sc.SizeData = 48;
                    sc.MarkerEdgeColor = [0.03 0.25 0.65];
                    sc.MarkerFaceColor = [0.05 0.35 0.85];
                    sc.MarkerFaceAlpha = 0.65;
                end
                
                text(ax, 0.04, 0.94, 'y = x line: residual preservation', 'Units', 'normalized', ...
                    'FontSize', 11.5, 'FontWeight', 'bold', 'FontName', 'Helvetica', ...
                    'Color', [0.25 0.25 0.25]);
        end
    end
    
    legs = findall(f, 'type', 'legend');
    for l = 1:numel(legs)
        lg = legs(l);
        tileNum = get(lg.Axes, 'Layout').Tile;
        if tileNum == 1 || tileNum == 4
            lg.FontSize = 11.5;
            lg.FontWeight = 'bold';
            lg.FontName = 'Helvetica';
            lg.Box = 'on';
            lg.LineWidth = 0.8;
            lg.EdgeColor = [0.75 0.75 0.75];
            
            oldStrs = lg.String;
            newStrs = cell(size(oldStrs));
            for s = 1:numel(oldStrs)
                str = oldStrs{s};
                if isKey(modelNamesMap, str)
                    newStrs{s} = modelNamesMap(str);
                elseif isKey(barLegMap, str)
                    newStrs{s} = barLegMap(str);
                else
                    newStrs{s} = strrep(str, '_', '-');
                end
            end
            lg.String = newStrs;
        end
    end
    
    drawnow;
    
    % Export 600 DPI individual PNG & vector PDF
    outPNG = fullfile(outDir, [baseName '.png']);
    outPDF = fullfile(outDir, [baseName '.pdf']);
    
    exportgraphics(f, outPNG, 'Resolution', 600);
    try
        exportgraphics(f, outPDF, 'ContentType', 'vector');
    catch
        exportgraphics(f, outPDF, 'Resolution', 600);
    end
    
    exportedPNGs{fIdx} = outPNG;
    close(f);
    fprintf('     -> Exported: %s (600 DPI PNG & PDF)\n', baseName);
end

% =========================================================================
% Create Native MATLAB Unified Fig6_Prognosis_Combined (Panel a + b)
% =========================================================================
fprintf('\nConstructing unified Fig6_Prognosis_Combined.png ...\n');

imgPlanned = imread(exportedPNGs{1});
imgProb    = imread(exportedPNGs{2});

% Ensure equal width
targetW = max(size(imgPlanned, 2), size(imgProb, 2));
if size(imgPlanned, 2) < targetW
    pad = uint8(255 * ones(size(imgPlanned, 1), targetW - size(imgPlanned, 2), size(imgPlanned, 3)));
    imgPlanned = [imgPlanned, pad];
end
if size(imgProb, 2) < targetW
    pad = uint8(255 * ones(size(imgProb, 1), targetW - size(imgProb, 2), size(imgProb, 3)));
    imgProb = [imgProb, pad];
end

% 3.5% crisp white separator gap between panel (a) and panel (b)
gapHeight = round(size(imgPlanned, 1) * 0.035);
gapPad = uint8(255 * ones(gapHeight, targetW, size(imgPlanned, 3)));

combinedImg = [imgPlanned; gapPad; imgProb];

combinedPNG = fullfile(outDir, 'Fig6_Prognosis_Combined.png');
combinedPDF = fullfile(outDir, 'Fig6_Prognosis_Combined.pdf');

imwrite(combinedImg, combinedPNG, 'png', 'ResolutionUnit', 'meter', 'XResolution', 600 * 39.3701, 'YResolution', 600 * 39.3701);

fComb = figure('Visible', 'off', 'Color', 'w');
axComb = axes('Parent', fComb, 'Position', [0 0 1 1]);
imshow(combinedImg, 'Parent', axComb, 'Border', 'tight');
axis(axComb, 'off');
exportgraphics(fComb, combinedPDF, 'Resolution', 600);
close(fComb);

fprintf('SUCCESS: Fig6_Prognosis_Combined.png and .pdf saved at 600 DPI to:\n');
fprintf('  - %s\n', combinedPNG);
fprintf('  - %s\n', combinedPDF);

T = vertcat(checks{:});
writetable(T, fullfile(packageRoot, 'output_tables', 'Table_Fig6_Source_Check.csv'));
fprintf('Source check (figure vs v17_test_predictions.csv): max |difference| %.3g\n', max(T.AbsDiff));
fprintf('========================================================================\n');
end

function T = check_against_predictions(f, experiment, policy, packageRoot)
% Re-derive every number shown in the saved figure from the prediction rows
% and return figure value, recomputed value and difference, one row each.
X = readtable(fullfile(packageRoot, 'data', 'v17_run', 'v17_test_predictions.csv'), 'TextType', 'string');
X = X(X.experiment == experiment & X.policy == policy & X.available == 1, :);
methods = ["PI_DSSDM" "Inverse_PINN" "LSTM" "Physics_SSM" "Basis_hybrid" "Bayesian_PF"];
rows = {};
add = @(q, figV, recV) {q, figV, recV, abs(figV - recV)};

ax = findall(f, 'type', 'axes');
tileOf = arrayfun(@(a) a.Layout.Tile, ax);

% Panel 1: the plotted unit, identified by its PI-DSSDM forecasts
a1 = ax(tileOf == 1); L = findall(a1, 'type', 'line');
piLine = L(strcmp({L.DisplayName}, 'PI_DSSDM')); tru = L(strcmp({L.DisplayName}, 'True RUL'));
P = X(X.method == "PI_DSSDM", :);
units = unique(P.unit); best = Inf;
for u = units'
    Q = sortrows(P(P.unit == u, :), 'origin_h');
    if height(Q) == numel(piLine.YData)
        d = max(abs(Q.predictedRUL_h' - piLine.YData));
        if d < best, best = d; U = Q; end
    end
end
rows(end+1, :) = {sprintf('panel a unit = %s', U.unit(1)), NaN, NaN, best};
for k = 1:height(U)
    rows(end+1, :) = add(sprintf('true RUL at %g h', U.origin_h(k)), tru.YData(k), U.trueRUL_h(k)); %#ok<AGROW>
end
pa = findall(a1, 'type', 'patch'); n = numel(U.lower_h);
rows(end+1, :) = add('band lower, max over origins', max(pa.YData(1:n)), max(U.lower_h));
rows(end+1, :) = add('band upper, max over origins', max(flipud(pa.YData(n+1:end))), max(U.upper_h));
for k = 1:n
    rows(end+1, :) = {sprintf('band width at %g h', U.origin_h(k)), NaN, U.upper_h(k) - U.lower_h(k), 0}; %#ok<AGROW>
end

% Panels 4 and 5: calibrated row coverage and mean width per method
b4 = findall(ax(tileOf == 4), 'type', 'bar'); cal = b4(strcmp({b4.DisplayName}, 'Calibrated row'));
b5 = findall(ax(tileOf == 5), 'type', 'bar');
for m = 1:numel(methods)
    M = X(X.method == methods(m), :);
    rows(end+1, :) = add(sprintf('%s row coverage %%', methods(m)), cal.YData(m), ...
        100 * mean(M.lower_h <= M.trueRUL_h & M.trueRUL_h <= M.upper_h)); %#ok<AGROW>
    rows(end+1, :) = add(sprintf('%s mean width h', methods(m)), b5(1).YData(m), mean(M.upper_h - M.lower_h)); %#ok<AGROW>
    rows(end+1, :) = {sprintf('%s MAE h', methods(m)), NaN, mean(abs(M.predictedRUL_h - M.trueRUL_h)), 0}; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'Quantity', 'Figure', 'Recomputed', 'AbsDiff'});
T.Policy = repmat(string(policy), height(T), 1);
T = T(:, [5 1 2 3 4]);
end
