function out = compute_benchmark_tables()
% COMPUTE_BENCHMARK_TABLES
% Builds the benchmark tables from the v17.2.0 run outputs in data/v17_run.
% Every number is computed here; nothing is typed in.
%
%   Table05_Benchmark_Paired_Tests.csv   fleet-mean MAE, paired gain, 95% CI,
%       W/L/T, paired t, exact Wilcoxon and Holm-adjusted p (5 comparators per duty)
%   Table06_Scenario_MAE.csv             fleet-mean MAE per scenario x duty x method
%   Table07_Coverage_Sharpness.csv       pointwise and unit-simultaneous coverage,
%       mean width and interval score per method x duty
%   Table08_Residual_Ablation.csv        the ablation actually run in v17:
%       discrepancy residual ON vs OFF, same posterior and random draws
%   Table_Evidence_Gate_Summary.csv      pass/fail counts of the v17 evidence gate
%
% Inference unit = fleet (30 independent fleets). Tie = |fleet gain| <= 0.05 h.

P = pkg_paths();
M = readtable(fullfile(P.v17, 'v17_metrics_by_experiment.csv'), 'TextType', 'string');
M.scenario = extractBetween(M.evidence, "SYNTHETIC:", ":rep");
methods = ["PI_DSSDM", "Inverse_PINN", "Bayesian_PF", "Physics_SSM", "Basis_hybrid", "LSTM"];
policies = ["planned", "probabilistic"];
tieTol = 0.05;

% ---------------- Table 5: paired tests across 30 fleets ----------------
rows = {};
for p = policies
    ref = fleet_values(M, "PI_DSSDM", p, "MAE_h");
    fam = {};
    for m = methods(2:end)
        cmp = fleet_values(M, m, p, "MAE_h");
        g = cmp - ref;
        [lo, hi, pt] = paired_t(g);
        pw = signrank_exact(g);
        fam(end+1, :) = {p, m, mean(ref), mean(cmp), mean(g), lo, hi, ...
            sum(g > tieTol), sum(g < -tieTol), sum(abs(g) <= tieTol), pt, pw, numel(g)}; %#ok<AGROW>
    end
    padj = holm([fam{:, 11}]);
    fam(:, 14) = num2cell(padj(:));
    rows = [rows; fam]; %#ok<AGROW>
end
T5 = cell2table(rows, 'VariableNames', {'Duty', 'Comparator', 'PI_DSSDM_MAE_h', 'Comparator_MAE_h', ...
    'Gain_h', 'Gain95Low_h', 'Gain95High_h', 'PI_Wins', 'PI_Losses', 'Ties', 'p_t', 'p_Wilcoxon', 'Fleets', 'p_t_Holm'});
T5.Verdict = verdict(T5.Gain95Low_h, T5.p_t_Holm);
writetable(T5, fullfile(P.tables, 'Table05_Benchmark_Paired_Tests.csv'));

% ---------------- Table 6: scenario x duty x method MAE ----------------
scen = unique(M.scenario, 'stable');
rows = {};
for s = scen'
    for p = policies
        r = {s, p};
        for m = methods
            r{end+1} = mean(M.MAE_h(M.scenario == s & M.policy == p & M.method == m)); %#ok<AGROW>
        end
        rows(end+1, :) = r; %#ok<AGROW>
    end
end
T6 = cell2table(rows, 'VariableNames', [{'Scenario', 'Duty'}, cellstr(methods + "_MAE_h")]);
T6.PI_Gain_vs_Physics_h = T6.Physics_SSM_MAE_h - T6.PI_DSSDM_MAE_h;
T6.PI_Gain_vs_Physics_pct = 100 * T6.PI_Gain_vs_Physics_h ./ T6.Physics_SSM_MAE_h;
writetable(T6, fullfile(P.tables, 'Table06_Scenario_MAE.csv'));

% Scenario-level paired tests (5 fleets each), Holm within scenario x duty
rows = {};
for s = scen'
    for p = policies
        sub = M(M.scenario == s, :);
        ref = fleet_values(sub, "PI_DSSDM", p, "MAE_h");
        fam = {};
        for m = methods(2:end)
            g = fleet_values(sub, m, p, "MAE_h") - ref;
            [lo, hi, pt] = paired_t(g);
            fam(end+1, :) = {s, p, m, mean(g), lo, hi, pt}; %#ok<AGROW>
        end
        fam(:, 8) = num2cell(holm([fam{:, 7}])');
        rows = [rows; fam]; %#ok<AGROW>
    end
end
T6b = cell2table(rows, 'VariableNames', {'Scenario', 'Duty', 'Comparator', 'Gain_h', 'Gain95Low_h', 'Gain95High_h', 'p_t', 'p_t_Holm'});
writetable(T6b, fullfile(P.tables, 'Table06b_Scenario_Paired_Tests.csv'));

% ---------------- Table 7: coverage and sharpness ----------------
rows = {};
for m = methods
    for p = policies
        k = M.method == m & M.policy == p;
        rows(end+1, :) = {m, p, 100 * mean(M.coverage(k)), 100 * mean(M.unitSimultaneousCoverage(k)), ...
            mean(M.meanWidth_h(k)), mean(M.intervalScore_h(k))}; %#ok<AGROW>
    end
end
T7 = cell2table(rows, 'VariableNames', {'Method', 'Duty', 'PointwiseCoverage_pct', ...
    'UnitSimultaneousCoverage_pct', 'MeanWidth_h', 'IntervalScore_h'});
writetable(T7, fullfile(P.tables, 'Table07_Coverage_Sharpness.csv'));

% ---------------- Table 8: residual ON/OFF ablation ----------------
files = dir(fullfile(P.v17, 'discrepancy_ablation', 'Discrepancy_ablation_*.csv'));
rows = {};
for p = policies
    on = zeros(numel(files), 1); off = on;
    for i = 1:numel(files)
        A = readtable(fullfile(files(i).folder, files(i).name), 'TextType', 'string');
        A = A(A.policy == p & isfinite(A.trueRUL_h), :);
        on(i) = mean(abs(A.residualOnRUL_h - A.trueRUL_h));
        off(i) = mean(abs(A.residualOffRUL_h - A.trueRUL_h));
    end
    g = off - on;
    [lo, hi, pt] = paired_t(g);
    rows(end+1, :) = {p, mean(on), mean(off), mean(g), lo, hi, sum(g > tieTol), sum(g < -tieTol), pt, signrank_exact(g)}; %#ok<AGROW>
end
T8 = cell2table(rows, 'VariableNames', {'Duty', 'MAE_ResidualOn_h', 'MAE_ResidualOff_h', 'Gain_h', ...
    'Gain95Low_h', 'Gain95High_h', 'FleetsOnBetter', 'FleetsOffBetter', 'p_t', 'p_Wilcoxon'});
writetable(T8, fullfile(P.tables, 'Table08_Residual_Ablation.csv'));

% ---------------- Evidence gate ----------------
G = readtable(fullfile(P.v17, 'Evidence_gate.csv'), 'TextType', 'string');
cats = unique(G.category, 'stable');
rows = {};
for c = cats'
    k = G.category == c;
    rows(end+1, :) = {c, sum(k), sum(G.passed(k) == 1), sum(G.passed(k) == 0)}; %#ok<AGROW>
end
TG = cell2table(rows, 'VariableNames', {'Category', 'Criteria', 'Passed', 'Failed'});
writetable(TG, fullfile(P.tables, 'Table_Evidence_Gate_Summary.csv'));
writetable(G(G.passed == 0, :), fullfile(P.tables, 'Table_Evidence_Gate_Failures.csv'));

out = struct('T5', T5, 'T6', T6, 'T6b', T6b, 'T7', T7, 'T8', T8, 'gate', TG);
fprintf('[Benchmark] Tables 5-8 and evidence-gate summary computed from v17 outputs.\n');
end

function v = fleet_values(M, method, policy, col)
k = M.method == method & M.policy == policy;
S = sortrows(M(k, :), 'experiment');
v = S.(col);
end

function [lo, hi, p] = paired_t(g)
n = numel(g); m = mean(g); se = std(g) / sqrt(n); df = n - 1;
tc = tinv_base(0.975, df);
lo = m - tc * se; hi = m + tc * se;
t = m / se;
p = betainc(df / (df + t^2), df / 2, 0.5);               % two-sided
end

function x = tinv_base(pr, df)
% Inverse Student-t CDF by bisection (base MATLAB only).
lo = 0; hi = 50;
for k = 1:200
    x = (lo + hi) / 2;
    c = 1 - 0.5 * betainc(df / (df + x^2), df / 2, 0.5);
    if c < pr, lo = x; else, hi = x; end
end
end

function p = signrank_exact(g)
% Exact two-sided Wilcoxon signed-rank p-value; zero differences dropped,
% tied magnitudes get mid-ranks (distribution on doubled ranks).
g = g(g ~= 0); n = numel(g);
if n == 0, p = 1; return; end
r = tiedrank_base(abs(g));
r2 = round(2 * r);
W = sum(r2(g > 0));
tot = sum(r2);
cnt = zeros(1, tot + 1); cnt(1) = 1;
for k = 1:n
    cnt = cnt + [zeros(1, r2(k)), cnt(1:end - r2(k))];
end
pr = cnt / 2^n;
c = tot / 2;
d = abs(W - c);
vals = 0:tot;
p = min(1, sum(pr(abs(vals - c) >= d - 1e-9)));
end

function r = tiedrank_base(x)
[s, i] = sort(x(:)); r = zeros(size(s));
k = 1;
while k <= numel(s)
    j = k;
    while j < numel(s) && s(j + 1) == s(k), j = j + 1; end
    r(k:j) = (k + j) / 2; k = j + 1;
end
r(i) = r;
end

function pa = holm(p)
p = p(:)'; m = numel(p);
[ps, i] = sort(p);
adj = min(1, cummax((m - (0:m - 1)) .* ps));
pa = zeros(1, m); pa(i) = adj;
end

function v = verdict(lo, pholm)
v = strings(numel(lo), 1);
for k = 1:numel(lo)
    if pholm(k) < 0.05 && lo(k) > 0
        v(k) = "PI-DSSDM better (Holm p < 0.05)";
    elseif lo(k) > 0
        v(k) = "PI-DSSDM better before multiplicity correction only";
    else
        v(k) = "No significant difference";
    end
end
end
