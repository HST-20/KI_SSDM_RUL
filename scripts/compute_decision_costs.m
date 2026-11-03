function T = compute_decision_costs(opts)
% COMPUTE_DECISION_COSTS
% Evaluates the maintenance cost model of manuscript Eq. (41)-(43) on the
% v17 held-out test predictions (data/v17_run/v17_test_predictions.csv).
%
% Decision instance = one test unit at one forecast origin t0 under one duty
% policy; T = true RUL, tau = scheduled lead time.
%   cost = Cp + cw*(T - tau)   if tau <= T   (planned overhaul, life discarded)
%        = Cp + Cu             if tau >  T   (in-service failure)
% Strategies:
%   Corrective        tau = Inf
%   Periodic          replace at age A = 10th percentile of CALIBRATION-unit
%                     failure ages of the same fleet: tau = max(0, A - t0)
%   <method> point    tau = predicted RUL
%   <method> lower    tau = lower bound of the 90% conformal band (Eq. 42)
% Discarded life = (T - tau)/(t0 + T), the share of the unit's total life
% thrown away, averaged over planned overhauls.
% Two discarded-life prices are reported: the manuscript's cw = 1e-4 /h
% (= Cp / 10,000 h) and a fleet-scale cw = Cp / mean CAL failure age.
%
% Output: output_tables/Table10_Decision_Costs.csv (+ per-fleet file, and
% Table10c_Decision_Cost_Sensitivity.csv over Cu/Cp = 4, 8, 16 and both cw)

if nargin < 1, opts = struct(); end
if ~isfield(opts, 'Cp'), opts.Cp = 1; end
if ~isfield(opts, 'Cu'), opts.Cu = 8; end
if ~isfield(opts, 'cw_manuscript'), opts.cw_manuscript = 1e-4; end

P = pkg_paths();
X = readtable(fullfile(P.v17, 'v17_test_predictions.csv'), 'TextType', 'string');
C = readtable(fullfile(P.v17, 'v17_calibration_predictions.csv'), 'TextType', 'string');
X = X(X.available == 1 & isfinite(X.trueRUL_h) & isfinite(X.predictedRUL_h), :);

% Fleet periodic age and fleet-scale cw from calibration units only
exps = unique(X.experiment);
A = zeros(max(exps), 1); cwFleet = A;
for e = exps'
    c = C(C.experiment == e & C.method == "Physics_SSM" & C.policy == "planned", :);
    [~, iu] = unique(c.unit);
    life = c.origin_h(iu) + c.trueRUL_h(iu);
    A(e) = quantile_base(life, 0.10);
    cwFleet(e) = opts.Cp / mean(life);
end

methods = ["PI_DSSDM", "Inverse_PINN", "Bayesian_PF", "Physics_SSM", "Basis_hybrid", "LSTM"];
policies = ["planned", "probabilistic"];
rows = {}; fleetRows = {};
for p = policies
    B = X(X.policy == p & X.method == "PI_DSSDM", :);       % one row per decision
    base = {"Corrective (run-to-failure)", inf(height(B), 1), B; ...
            "Periodic (CAL-fleet L10 age)", max(0, A(B.experiment) - B.origin_h), B};
    strat = base;
    for m = methods
        Bm = X(X.policy == p & X.method == m, :);
        strat(end+1, :) = {m + " point", Bm.predictedRUL_h, Bm}; %#ok<AGROW>
        strat(end+1, :) = {m + " conformal lower", max(0, Bm.lower_h), Bm}; %#ok<AGROW>
    end
    res = cell(size(strat, 1), 1);
    for s = 1:size(strat, 1)
        res{s} = evaluate(strat{s, 2}, strat{s, 3}, opts, cwFleet);
    end
    per = res{2};
    for s = 1:size(strat, 1)
        r = res{s};
        rows(end+1, :) = {p, strat{s, 1}, r.n, 100 * r.fail, 100 * r.discard, r.costM, ...
            100 * (per.costM - r.costM) / per.costM, r.costF, 100 * (per.costF - r.costF) / per.costF}; %#ok<AGROW>
        for e = exps'
            fleetRows(end+1, :) = {p, strat{s, 1}, e, r.fleetCostF(e)}; %#ok<AGROW>
        end
    end
end
T = cell2table(rows, 'VariableNames', {'Duty', 'Strategy', 'Decisions', 'FailureRate_pct', ...
    'DiscardedLife_pct', 'ExpectedCost_cwManuscript', 'Saving_vs_Periodic_cwManuscript_pct', ...
    'ExpectedCost_cwFleet', 'Saving_vs_Periodic_cwFleet_pct'});
writetable(T, fullfile(P.tables, 'Table10_Decision_Costs.csv'));
TF = cell2table(fleetRows, 'VariableNames', {'Duty', 'Strategy', 'Fleet', 'ExpectedCost_cwFleet'});
writetable(TF, fullfile(P.tables, 'Table10b_Decision_Costs_by_Fleet.csv'));

% Sensitivity of Table 10 to the failure penalty Cu/Cp and the price of
% discarded life (manuscript cw = 1e-4 /h vs fleet-scale cw = Cp / mean CAL life)
sens = {};
for Cu = [4 8 16]
    o = opts; o.Cu = Cu;
    for p = policies
        B = X(X.policy == p & X.method == "PI_DSSDM", :);
        names = ["Periodic (CAL-fleet L10 age)", methods + " point", methods + " conformal lower"];
        taus = {max(0, A(B.experiment) - B.origin_h)}; data = {B};
        for m = methods
            Bm = X(X.policy == p & X.method == m, :);
            taus{end+1} = Bm.predictedRUL_h; data{end+1} = Bm; %#ok<AGROW>
        end
        for m = methods
            Bm = X(X.policy == p & X.method == m, :);
            taus{end+1} = max(0, Bm.lower_h); data{end+1} = Bm; %#ok<AGROW>
        end
        per = evaluate(taus{1}, data{1}, o, cwFleet);
        for s = 1:numel(names)
            r = evaluate(taus{s}, data{s}, o, cwFleet);
            sens(end+1, :) = {Cu / o.Cp, p, names(s), 100 * r.fail, r.costM, ...
                100 * (per.costM - r.costM) / per.costM, r.costF, ...
                100 * (per.costF - r.costF) / per.costF}; %#ok<AGROW>
        end
    end
end
TS = cell2table(sens, 'VariableNames', {'Cu_over_Cp', 'Duty', 'Strategy', 'FailureRate_pct', ...
    'ExpectedCost_cwManuscript', 'Saving_vs_Periodic_cwManuscript_pct', ...
    'ExpectedCost_cwFleet', 'Saving_vs_Periodic_cwFleet_pct'});
writetable(TS, fullfile(P.tables, 'Table10c_Decision_Cost_Sensitivity.csv'));
fprintf('[Decision] Eq. 41-43 evaluated on %d test decisions per duty.\n', height(X) / numel(methods) / numel(policies));
end

function r = evaluate(tau, B, opts, cwFleet)
Tt = B.trueRUL_h; t0 = B.origin_h;
fail = tau > Tt;
slack = max(0, Tt - tau);
r.n = numel(Tt);
r.fail = mean(fail);
r.discard = mean(slack(~fail) ./ (t0(~fail) + Tt(~fail)));
if ~any(~fail), r.discard = 0; end
costM = opts.Cp + opts.cw_manuscript * slack .* ~fail + opts.Cu * fail;
cwF = cwFleet(B.experiment);
costF = opts.Cp + cwF .* slack .* ~fail + opts.Cu * fail;
r.costM = mean(costM); r.costF = mean(costF);
r.fleetCostF = accumarray(B.experiment, costF, [], @mean);
end

function q = quantile_base(x, p)
x = sort(x(:)); n = numel(x);
h = (n - 1) * p + 1; lo = floor(h); hi = min(ceil(h), n);
q = x(lo) + (h - lo) * (x(hi) - x(lo));
end
