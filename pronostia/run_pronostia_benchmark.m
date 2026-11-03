function R = run_pronostia_benchmark(opts)
% RUN_PRONOSTIA_BENCHMARK  PRONOSTIA (IEEE PHM 2012) RUL benchmark for the
% proposed PI-DSSDM and literature comparators, from snapshot features.
%
% Protocols
%   A  Official challenge: train on the 6 learning bearings, predict once for
%      each of the 11 test bearings at the end of its truncated record, score
%      against the official RUL (Bearing1_4 also against the full record).
%   B  Leave-one-bearing-out over all 17 run-to-failure bearings, predicting
%      at 8 origins per bearing (30, 40, ..., 90, 95 % of life). The bearing
%      is the unit of inference for paired tests (n = 17).
%
% Methods (all causal: only data up to the prediction origin are used)
%   PI-DSSDM           survival-conditioned hierarchical life prior with
%                      ISO 281 load-speed scaling + post-onset exponential
%                      degradation Kalman filter with OU nuisance and a
%                      random failure level, fused as product of lognormal
%                      experts, + bounded learned discrepancy, pooled with
%                      a validation-chosen weight (0 = physics fallback)
%   PI-DSSDM ablations no discrepancy / no ISO scaling / no survival conditioning
%   Bayesian exp.      Gebraeel et al. (2005) conjugate Bayesian exponential
%                      degradation model, fixed threshold, after 3-sigma FPT
%   PF exp.            Li et al. (2015) improved exponential model,
%                      x = phi + theta exp(beta t), 3-sigma FPT, SIR particle filter
%   LSTM               life-percentage regression on 30-snapshot windows
%                      (Guo et al. 2017; Zhu et al. 2019 style), 3-seed ensemble
%
% All intervals are split-conformal 90 % intervals on a log scale, calibrated
% on out-of-fold predictions for the training bearings only and stratified by
% stage (before / after detected onset). The same wrapper is used for every
% method, so interval efficiency is compared on equal terms.

if nargin < 1, opts = struct(); end
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
def = struct('featFile', fullfile(root, 'data', 'pronostia', 'pronostia_features.mat'), ...
             'tables', fullfile(root, 'output_tables'), ...
             'figures', fullfile(root, 'output_figures_600dpi'), ...
             'cache', fullfile(root, 'data', 'pronostia', 'lstm_cache.mat'), ...
             'nSeeds', 3, 'epochs', 25, 'useCache', true);
fn = fieldnames(def);
for k = 1:numel(fn), if ~isfield(opts, fn{k}), opts.(fn{k}) = def.(fn{k}); end, end
if ~exist(opts.tables, 'dir'), mkdir(opts.tables); end
if ~exist(opts.figures, 'dir'), mkdir(opts.figures); end

S = load(opts.featFile, 'F');
B = prepare_bearings(S.F);
nB = numel(B);
officialRUL = [5730 339 1610 1460 7570 7530 1390 3090 1290 580 820];  % s, Bearing1_3 ... Bearing3_3
fracs = [0.30 0.40 0.50 0.60 0.70 0.80 0.90 0.95];
for i = 1:nB
    B(i).grid = unique(max(B(i).N0 + 1, round(fracs * B(i).n)));
end

%% LSTM jobs (the only expensive part), run once and cached
jobs = lstm_jobs(B, fracs);
lstmPred = run_lstm_jobs(B, jobs, opts);

%% Protocol A: official challenge split
trA = 1:6;
teA = 7:17;
origA = arrayfun(@(i) B(i).nTrunc, teA, 'UniformOutput', false);
PA = evaluate_split(B, trA, teA, origA, lstmPred, 'A', 0);
truthOff = officialRUL(:);
PA.trueOfficial = nan(height(PA), 1);
for k = 1:numel(teA)
    PA.trueOfficial(PA.bearing == string(B(teA(k)).name)) = truthOff(k);
end

%% Protocol B: leave-one-bearing-out, multiple origins
PB = table();
for j = 1:nB
    tr = setdiff(1:nB, j);
    PB = [PB; evaluate_split(B, tr, j, {B(j).grid}, lstmPred, 'B', j)]; %#ok<AGROW>
    fprintf('[protocol B] fold %2d/%d (%s) done\n', j, nB, B(j).name);
end

%% Tables
methods = unique(PB.method, 'stable');
TA  = summarize(PA, methods, 'trueOfficial');
PA.trueFull = PA.trueRUL;
TA2 = summarize(PA, methods, 'trueFull');
TB  = summarize(PB, methods, 'trueRUL');
TBpost = summarize(PB(PB.postOnset, :), methods, 'trueRUL');
TBpre  = summarize(PB(~PB.postOnset, :), methods, 'trueRUL');
TS = paired_tests(PB, methods, "PI-DSSDM");
TSpost = paired_tests(PB(PB.postOnset, :), methods, "PI-DSSDM");
TDS = dataset_table(B, officialRUL);

writetable(TDS, fullfile(opts.tables, 'Table12a_PRONOSTIA_Dataset.csv'));
writetable(TA,  fullfile(opts.tables, 'Table12b_PRONOSTIA_Official_Split.csv'));
writetable(TA2, fullfile(opts.tables, 'Table12b2_PRONOSTIA_Official_Split_FullRecordTruth.csv'));
writetable(TB,  fullfile(opts.tables, 'Table12c_PRONOSTIA_LOBO_All_Origins.csv'));
writetable(TBpre,  fullfile(opts.tables, 'Table12d_PRONOSTIA_LOBO_PreOnset.csv'));
writetable(TBpost, fullfile(opts.tables, 'Table12e_PRONOSTIA_LOBO_PostOnset.csv'));
writetable(TS,  fullfile(opts.tables, 'Table12f_PRONOSTIA_Paired_Tests_All.csv'));
writetable(TSpost, fullfile(opts.tables, 'Table12g_PRONOSTIA_Paired_Tests_PostOnset.csv'));
writetable(PA,  fullfile(opts.tables, 'PRONOSTIA_Predictions_ProtocolA.csv'));
writetable(PB,  fullfile(opts.tables, 'PRONOSTIA_Predictions_ProtocolB.csv'));

plot_fig13(B, PB, TB, TBpost, methods, opts.figures);

fprintf('\nProtocol A (official split, official RUL):\n'); disp(TA);
fprintf('Protocol B (LOBO, all origins):\n'); disp(TB);
fprintf('Protocol B, post-onset origins:\n'); disp(TBpost);
fprintf('Paired tests vs PI-DSSDM (bearing = unit, all origins):\n'); disp(TS);
fprintf('Paired tests vs PI-DSSDM (post-onset origins):\n'); disp(TSpost);
R = struct('PA', PA, 'PB', PB, 'TA', TA, 'TB', TB, 'TBpost', TBpost, 'TBpre', TBpre, ...
           'TS', TS, 'TSpost', TSpost, 'TDS', TDS);
end

%% ======================================================================
%% Data preparation
%% ======================================================================
function B = prepare_bearings(F)
names = {'Bearing1_1','Bearing1_2','Bearing2_1','Bearing2_2','Bearing3_1','Bearing3_2', ...
         'Bearing1_3','Bearing1_4','Bearing1_5','Bearing1_6','Bearing1_7', ...
         'Bearing2_3','Bearing2_4','Bearing2_5','Bearing2_6','Bearing2_7','Bearing3_3'};
N0 = 50;                                    % healthy baseline: first 500 s
% ISO 281 basic life scales as (C/P)^3 / n; log scale factor relative to condition 1
load_N = [4000 4200 5000]; speed = [1800 1650 1500];
gISO = log((load_N(1) ./ load_N).^3 .* (speed(1) ./ speed));
for i = 1:numel(names)
    s = F.(names{i});
    X = s.X; n = size(X, 1);
    rms = X(:, 1);
    b.name = names{i};
    b.cond = s.condition;
    b.gISO = gISO(b.cond);
    b.n = n;
    b.t = (1:n)' * 10;                       % elapsed time at each snapshot (s)
    b.life = n * 10;
    b.nTrunc = s.nTruncated;
    b.N0 = N0;
    b.phi = mean(rms(1:N0));
    b.sd0 = std(rms(1:N0));
    b.sm = movmean(rms, [4 0]);              % trailing 5-snapshot mean (causal)
    b.y = log(rms / b.phi);                  % log RMS ratio, raw
    b.ysm = log(b.sm / b.phi);
    % Li et al. (2015) 3-sigma first predicting time: 5 consecutive smoothed
    % values above the healthy-stage mean + 3 sd
    ex = b.sm > b.phi + 3 * b.sd0; ex(1:N0) = false;
    run = filter(ones(5, 1), 1, double(ex));
    det = find(run >= 5, 1);
    if isempty(det), det = inf; end
    b.det = det;                             % index at which onset becomes known
    b.fpt = det - 4;
    b.failLevel = log(prctile(rms(end-9:end), 95) / b.phi);
    b.failRMS = prctile(rms(end-9:end), 95);
    % normalised feature sequence for the LSTM and the discrepancy model
    base = mean(X(1:N0, :), 1);
    Z = [log(X(:,1)/base(1)), log(X(:,2)/base(2)), log(X(:,3)/3), log(X(:,4)/3), X(:,5), ...
         log(X(:,6)/base(6)), log(X(:,7)/base(7)), log(X(:,8)/base(8)), X(:,9:12) - base(9:12)];
    b.Z = Z;
    b.Zsm = movmean(Z, [4 0]);
    B(i) = b; %#ok<AGROW>
end
end

%% ======================================================================
%% One train/test split: fit, out-of-fold calibration, prediction
%% ======================================================================
function T = evaluate_split(B, tr, te, origins, lstmPred, protocol, fold)
% Physics-based methods on the test bearings
M = fit_models(B, tr);
Pte = predict_models(B, M, te, origins);

% Out-of-fold predictions on the training bearings (leave-one-bearing-out)
Poof = [];
for i = tr
    Mi = fit_models(B, setdiff(tr, i));
    Poof = [Poof; predict_models(B, Mi, i, {B(i).grid})]; %#ok<AGROW>
end

% Learned bounded discrepancy on top of the PI-DSSDM physics prediction
[Pte, Poof] = add_discrepancy(Pte, Poof);

% LSTM predictions from the cached jobs
[Lte, Loof] = lstm_lookup(lstmPred, protocol, fold, B, te, origins, tr);
Pte = [Pte; Lte];
Poof = [Poof; Loof];

% Split-conformal intervals, stratified by stage
T = conformalize(Pte, Poof);
T.protocol = repmat(string(protocol), height(T), 1);
T.fold = repmat(fold, height(T), 1);
end

function M = fit_models(B, tr)
L = [B(tr).life]'; g = [B(tr).gISO]'; c = [B(tr).cond]';
y = log(L);
% Hierarchical life model: log L = mu + gamma * gISO + eta, with the
% knowledge prior gamma ~ N(1, 0.5^2) (ISO 281 exponent) and a flat mu.
X = [ones(size(g)) g];
P0 = diag([1e-6, 1 / 0.5^2]); m0 = [0; 1];
s2 = var(y);
for it = 1:20
    Sig = inv(X' * X / s2 + P0);
    mu = Sig * (X' * y / s2 + P0 * m0);
    r = y - X * mu;
    s2 = max((r' * r + 0.05) / max(numel(y) - 1, 1), 0.05);
end
M.life.mu = mu; M.life.Sig = Sig; M.life.s2 = s2;
M.maxLife = max(L);
% Signal-free reference: median RUL over the training bearings' origins
M.constRUL = median(cell2mat(arrayfun(@(i) B(i).life - B(i).t(B(i).grid), tr, 'UniformOutput', false)'));
% Ablation: no ISO scaling, condition means estimated separately (no pooling)
for cc = 1:3
    k = c == cc;
    if any(k), M.lifeNoISO.m(cc) = mean(y(k)); M.lifeNoISO.n(cc) = sum(k);
    else, M.lifeNoISO.m(cc) = mean(y); M.lifeNoISO.n(cc) = 0; end
end
M.lifeNoISO.s2 = max(var(y - M.lifeNoISO.m(c)'), 0.05);

% Post-onset degradation fits on the training bearings: y = c + beta * tau
cb = []; res = {};
lx = [];
for i = tr
    b = B(i);
    if isinf(b.det), continue; end
    k = b.fpt:b.n;
    tau = (k - b.fpt)' * 10;
    A = [ones(size(tau)) tau];
    th = A \ b.y(k);
    cb(end+1, :) = th'; %#ok<AGROW>
    res{end+1} = b.y(k) - A * th; %#ok<AGROW>
    % Li et al. form: log(x - phi) = log theta + beta tau
    xr = log(max(exp(b.y(k)) * b.phi - b.phi, 0.05 * b.phi));
    lx(end+1, :) = (A \ xr)'; %#ok<AGROW>
end
M.deg.m = mean(cb, 1)';
M.deg.S = cov(cb) + diag([0.05, 1e-8]);
% Noise: OU nuisance + white noise from pooled residual autocovariances
rr = cellfun(@(r) r(:), res, 'UniformOutput', false);
g0 = mean(cellfun(@(r) mean(r.^2), rr));
g1 = mean(cellfun(@(r) mean(r(2:end) .* r(1:end-1)), rr));
g2 = mean(cellfun(@(r) mean(r(3:end) .* r(1:end-2)), rr));
a = min(max(g2 / max(g1, 1e-6), 0.05), 0.99);
sb2 = min(max(g1 / a, 0.1 * g0), 0.95 * g0);
M.deg.a = a; M.deg.sb2 = sb2; M.deg.se2 = g0 - sb2; M.deg.g0 = g0;
M.fail.m = mean([B(tr).failLevel]); M.fail.s = max(std([B(tr).failLevel]), 0.2);
M.failRMS = mean([B(tr).failRMS]);
M.pf.m = mean(lx, 1)'; M.pf.S = cov(lx) + diag([0.05, 1e-8]);
M.pf.sl = sqrt(mean(cellfun(@(r) mean(r.^2), rr)));
end

function T = predict_models(B, M, idx, origins)
rows = {};
for q = 1:numel(idx)
    b = B(idx(q));
    for k = origins{q}(:)'
        t = b.t(k);
        post = k >= b.det;
        trueR = b.life - t;
        % life experts
        [lmP, lsP] = life_cond(M.life.mu(1) + M.life.mu(2) * b.gISO, ...
            M.life.s2 + [1 b.gISO] * M.life.Sig * [1; b.gISO], t);
        nC = M.lifeNoISO.n(b.cond);
        [lmN, lsN] = life_cond(M.lifeNoISO.m(b.cond), M.lifeNoISO.s2 * (1 + 1 / max(nC, 1)), t);
        naive = max(exp(M.life.mu(1) + M.life.mu(2) * b.gISO) - t, 10);
        % PI-DSSDM degradation expert + fusion
        if post
            [dm, ds, pplus] = deg_expert(b, M, k);
            [fm, fs] = fuse(lmP, lsP, dm, ds, pplus);
            [fmN, fsN] = fuse(lmN, lsN, dm, ds, pplus);
            [nm, ns] = fuse(log(naive + 60), sqrt(M.life.s2), dm, ds, pplus);
            [gm, glo, ghi] = gebraeel(b, M, k);
            [pm, plo, phi_] = pf_li(b, M, k);
        else
            fm = lmP; fs = lsP; fmN = lmN; fsN = lsN; nm = log(naive + 60); ns = sqrt(M.life.s2);
            gm = naive; glo = NaN; ghi = NaN; pm = naive; plo = NaN; phi_ = NaN;
        end
        phys = exp(fm) - 60;
        rows(end+1, :) = {b.name, k, t, k / b.n, post, trueR, "PI-DSSDM physics", phys, ...
            exp(fm - 1.645 * fs) - 60, exp(fm + 1.645 * fs) - 60, disc_features(b, M, k, t, post, phys)}; %#ok<AGROW>
        rows(end+1, :) = {b.name, k, t, k / b.n, post, trueR, "PI-DSSDM no ISO scaling", exp(fmN) - 60, ...
            exp(fmN - 1.645 * fsN) - 60, exp(fmN + 1.645 * fsN) - 60, []}; %#ok<AGROW>
        rows(end+1, :) = {b.name, k, t, k / b.n, post, trueR, "PI-DSSDM no survival conditioning", exp(nm) - 60, ...
            exp(nm - 1.645 * ns) - 60, exp(nm + 1.645 * ns) - 60, []}; %#ok<AGROW>
        rows(end+1, :) = {b.name, k, t, k / b.n, post, trueR, "Reference: life prior only (no signal)", exp(lmP) - 60, ...
            exp(lmP - 1.645 * lsP) - 60, exp(lmP + 1.645 * lsP) - 60, []}; %#ok<AGROW>
        rows(end+1, :) = {b.name, k, t, k / b.n, post, trueR, "Reference: constant median RUL", M.constRUL, NaN, NaN, []}; %#ok<AGROW>
        rows(end+1, :) = {b.name, k, t, k / b.n, post, trueR, "Bayesian exponential (Gebraeel 2005)", gm, glo, ghi, []}; %#ok<AGROW>
        rows(end+1, :) = {b.name, k, t, k / b.n, post, trueR, "PF exponential (Li 2015)", pm, plo, phi_, []}; %#ok<AGROW>
    end
end
T = cell2table(rows, 'VariableNames', {'bearing','k','t_s','lifeFraction','postOnset','trueRUL', ...
    'method','pred','nativeLo','nativeHi','phiDisc'});
T.bearing = string(T.bearing);
T.method = string(T.method);
% One rule for every method: no RUL beyond the longest life seen in training
T.pred = min(max(T.pred, 0), M.maxLife);
T.nativeLo = min(max(T.nativeLo, 0), M.maxLife);
T.nativeHi = min(T.nativeHi, M.maxLife);
end

function [m, s] = life_cond(mu, s2, t)
% Residual life of a lognormal lifetime, conditional on survival to t.
% Returns mean and sd of log(RUL + 60) from the conditional 16/50/84 % quantiles.
sd = sqrt(s2);
Ft = min(normcdf((log(t) - mu) / sd), 1 - 1e-9);
q = [0.16 0.5 0.84];
Lq = exp(mu + sd * norminv(Ft + q * (1 - Ft)));
r = log(max(Lq - t, 0) + 60);
m = r(2);
s = max((r(3) - r(1)) / 2, 0.05);
end

function [m, s, pplus] = deg_expert(b, M, k)
% Kalman filter on y = c + beta * tau + b_OU + e from onset to origin k,
% then first passage of the trend to a random failure level.
kk = b.fpt:k;
tau = (kk - b.fpt)' * 10;
a = M.deg.a;
x = [M.deg.m; 0];
P = blkdiag(M.deg.S, M.deg.sb2);
Fm = diag([1 1 a]);
Q = diag([0 0 M.deg.sb2 * (1 - a^2)]);
for j = 1:numel(kk)
    if j > 1, x = Fm * x; P = Fm * P * Fm' + Q; end
    H = [1 tau(j) 1];
    S = H * P * H' + M.deg.se2;
    K = P * H' / S;
    x = x + K * (b.y(kk(j)) - H * x);
    P = (eye(3) - K * H) * P;
end
[m, s, pplus] = first_passage(x(1:2), P(1:2, 1:2), tau(end), M.fail.m, M.fail.s, 4000, k);
end

function [m, s, pplus] = first_passage(th, P, tauNow, fm, fs, N, seed)
rs = RandStream('twister', 'Seed', 1000 + seed);
P = (P + P') / 2;
[V, D] = eig(P);
L = V * sqrt(max(D, 0));
d = th + L * randn(rs, 2, N);
yf = fm + fs * randn(rs, 1, N);
lev = d(1, :) + d(2, :) * tauNow;
pos = d(2, :) > 0;
pplus = mean(pos);
r = max((yf(pos) - lev(pos)) ./ d(2, pos), 0);
if nnz(pos) < 50
    m = log(60); s = 10; pplus = 0;
    return
end
lr = log(r + 60);
m = median(lr);
s = max((prctile(lr, 84) - prctile(lr, 16)) / 2, 0.05);
end

function [m, s] = fuse(lm, ls, dm, ds, pplus)
% Product of lognormal experts; the degradation expert is down-weighted by
% the posterior probability that the bearing is actually degrading (beta > 0).
wl = 1 / ls^2;
wd = pplus / ds^2;
m = (wl * lm + wd * dm) / (wl + wd);
s = 1 / sqrt(wl + wd);
end

function [pm, lo, hi] = gebraeel(b, M, k)
% Conjugate Bayesian linear model on log degradation signal with i.i.d.
% noise and a fixed failure threshold (Gebraeel et al. 2005).
kk = b.fpt:k;
tau = (kk - b.fpt)' * 10;
A = [ones(size(tau)) tau];
P0 = inv(M.deg.S);
Pn = inv(P0 + A' * A / M.deg.g0);
mn = Pn * (P0 * M.deg.m + A' * b.y(kk) / M.deg.g0);
[m, s] = first_passage(mn, Pn, tau(end), M.fail.m, 1e-6, 4000, k);
pm = exp(m) - 60; lo = exp(m - 1.645 * s) - 60; hi = exp(m + 1.645 * s) - 60;
end

function [pm, lo, hi] = pf_li(b, M, k)
% Li et al. (2015): x = phi + theta exp(beta tau + e), states (log theta, beta)
% with random-walk evolution, SIR resampling, absolute failure threshold.
rs = RandStream('twister', 'Seed', 5000 + k);
N = 2000;
L = chol(M.pf.S + 1e-12 * eye(2), 'lower');
p = M.pf.m + L * randn(rs, 2, N);
w = ones(1, N) / N;
kk = b.fpt:k;
tau = (kk - b.fpt) * 10;
sl = max(M.pf.sl, 0.05);
q = [0.02; 0.02 * abs(M.pf.m(2)) + 1e-7];
x = exp(b.y(kk)) * b.phi;
for j = 1:numel(kk)
    if j > 1, p = p + q .* randn(rs, 2, N); end
    pred = b.phi + exp(p(1, :) + p(2, :) * tau(j));
    w = w .* exp(-0.5 * ((log(x(j)) - log(pred)) / sl).^2);
    if sum(w) < 1e-300, w = ones(1, N) / N; else, w = w / sum(w); end
    if 1 / sum(w.^2) < N / 2
        e = cumsum(w); e(end) = 1;
        u = (rand(rs) + (0:N-1)) / N;
        id = sum(e' < u, 1) + 1;           % systematic resampling
        p = p(:, min(id, N));
        w = ones(1, N) / N;
    end
end
xf = M.failRMS;
r = nan(1, N);
pos = p(2, :) > 0;
r(pos) = max((log(max(xf - b.phi, 1e-6)) - p(1, pos)) ./ p(2, pos) - tau(end), 0);
if nnz(pos) < 50
    pm = 1e5; lo = NaN; hi = NaN; return
end
r = r(pos); ww = w(pos);
if ~(sum(ww) > 0), ww = ones(size(r)); end
ww = ww / sum(ww);
pm = wquant(r, ww, 0.5); lo = wquant(r, ww, 0.05); hi = wquant(r, ww, 0.95);
end

function v = wquant(x, w, q)
[x, o] = sort(x); w = w(o); c = cumsum(w);
v = x(min(find(c >= q - 1e-12, 1), numel(x)));
end

function f = disc_features(b, M, k, t, post, phys)
zs = b.Zsm(k, :);
tau = 0; if post, tau = (k - b.fpt) * 10; end
f = [double(post), b.ysm(k), zs(3), zs(12) - zs(9), tau / t, ...
     log(t) - (M.life.mu(1) + M.life.mu(2) * b.gISO), log(phys + 60)];
end

%% ======================================================================
%% Learned bounded discrepancy and validation-weighted pooling
%% ======================================================================
function [Pte, Poof] = add_discrepancy(Pte, Poof)
lambdas = 0:0.25:1;
bound = 1.0;                 % authority: RUL may change by at most e^{+/-1}
ridge = 5;
mo = Poof(Poof.method == "PI-DSSDM physics", :);
mt = Pte(Pte.method == "PI-DSSDM physics", :);
Fo = cell2mat(mo.phiDisc); Ft = cell2mat(mt.phiDisc);
yo = max(min(log((mo.trueRUL + 60) ./ (mo.pred + 60)), 2), -2);
% out-of-fold discrepancy on the training bearings (leave one bearing out)
rhoO = zeros(height(mo), 1);
ub = unique(mo.bearing);
for u = ub'
    k = mo.bearing == u;
    rhoO(k) = ridge_fit_predict(Fo(~k, :), yo(~k), Fo(k, :), ridge, bound);
end
% choose the pooling weight by out-of-fold absolute error; 0 is the fallback
mae = arrayfun(@(l) mean(abs(max((mo.pred + 60) .* exp(l * rhoO) - 60, 0) - mo.trueRUL)), lambdas);
[~, ib] = min(mae);
lam = lambdas(ib);
rhoT = ridge_fit_predict(Fo, yo, Ft, ridge, bound);

mk = @(T, rho, name) setfield_tbl(T, max((T.pred + 60) .* exp(rho) - 60, 0), ...
    (T.nativeLo + 60) .* exp(rho) - 60, (T.nativeHi + 60) .* exp(rho) - 60, name);
Pte  = [Pte;  mk(mt, lam * rhoT, "PI-DSSDM")];
Poof = [Poof; mk(mo, lam * rhoO, "PI-DSSDM")];
Pte.method(Pte.method == "PI-DSSDM physics") = "PI-DSSDM no discrepancy";
Poof.method(Poof.method == "PI-DSSDM physics") = "PI-DSSDM no discrepancy";
Pte.lambda = nan(height(Pte), 1); Pte.lambda(Pte.method == "PI-DSSDM") = lam;
Poof.lambda = nan(height(Poof), 1);
Pte.phiDisc = []; Poof.phiDisc = [];
end

function T = setfield_tbl(T, p, lo, hi, name)
T.pred = p; T.nativeLo = max(lo, 0); T.nativeHi = hi; T.method(:) = name;
end

function r = ridge_fit_predict(X, y, Xn, lam, bound)
mu = mean(X, 1); sd = std(X, 0, 1); sd(sd < 1e-9) = 1;
Z = (X - mu) ./ sd; Zn = (Xn - mu) ./ sd;
w = (Z' * Z + lam * eye(size(Z, 2))) \ (Z' * (y - mean(y)));
r = bound * tanh((Zn * w + mean(y)) / bound);
end

%% ======================================================================
%% Conformal wrapper
%% ======================================================================
function T = conformalize(Pte, Poof)
alpha = 0.10;
c0 = 60;
T = Pte;
T.lo = nan(height(T), 1); T.hi = nan(height(T), 1); T.qhat = nan(height(T), 1);
for m = unique(T.method)'
    for st = [false true]
        o = Poof(Poof.method == m & Poof.postOnset == st, :);
        k = T.method == m & T.postOnset == st;
        if ~any(k), continue; end
        if height(o) < 10   % too few calibration points in this stage: pool stages
            o = Poof(Poof.method == m, :);
        end
        s = sort(abs(log((o.trueRUL + c0) ./ (o.pred + c0))));
        n = numel(s);
        kq = min(ceil((n + 1) * (1 - alpha)), n);
        q = s(kq);
        T.qhat(k) = q;
        T.lo(k) = max((T.pred(k) + c0) * exp(-q) - c0, 0);
        T.hi(k) = (T.pred(k) + c0) * exp(q) - c0;
    end
end
end

%% ======================================================================
%% LSTM: jobs, training, lookup
%% ======================================================================
function jobs = lstm_jobs(B, ~)
nB = numel(B);
jobs = struct('protocol', {}, 'fold', {}, 'role', {}, 'train', {}, 'targets', {}, 'origins', {});
% Protocol A: train on the learning bearings; inner leave-one-bearing-out
jobs(end+1) = struct('protocol', 'A', 'fold', 0, 'role', 'test', 'train', 1:6, ...
    'targets', 7:17, 'origins', {arrayfun(@(i) B(i).nTrunc, 7:17, 'UniformOutput', false)});
for i = 1:6
    jobs(end+1) = struct('protocol', 'A', 'fold', 0, 'role', 'oof', 'train', setdiff(1:6, i), ...
        'targets', i, 'origins', {{B(i).grid}}); %#ok<AGROW>
end
% Protocol B: outer leave-one-bearing-out; inner 4 grouped folds
for j = 1:nB
    tr = setdiff(1:nB, j);
    jobs(end+1) = struct('protocol', 'B', 'fold', j, 'role', 'test', 'train', tr, ...
        'targets', j, 'origins', {{B(j).grid}}); %#ok<AGROW>
    rs = RandStream('twister', 'Seed', 77 + j);
    perm = tr(randperm(rs, numel(tr)));
    grp = mod(0:numel(tr)-1, 4) + 1;
    for g = 1:4
        held = perm(grp == g);
        jobs(end+1) = struct('protocol', 'B', 'fold', j, 'role', 'oof', 'train', setdiff(tr, held), ...
            'targets', held, 'origins', {arrayfun(@(i) B(i).grid, held, 'UniformOutput', false)}); %#ok<AGROW>
    end
end
end

function out = run_lstm_jobs(B, jobs, opts)
key = sprintf('nJobs%d_seeds%d_epochs%d', numel(jobs), opts.nSeeds, opts.epochs);
if opts.useCache && exist(opts.cache, 'file')
    C = load(opts.cache);
    if isfield(C, 'key') && strcmp(C.key, key)
        out = C.out; fprintf('[LSTM] using cached predictions (%s)\n', key); return
    end
end
W = 30;
nJ = numel(jobs);
nS = opts.nSeeds;
res = cell(1, nJ * nS);
t0 = tic;
Bs = B;
ep = opts.epochs;
parfor jj = 1:nJ * nS
    [j, s] = ind2sub([nJ nS], jj);
    res{jj} = lstm_train_predict(Bs, jobs(j), W, s, ep);
end
res = reshape(res, nJ, nS);
out = jobs;
for j = 1:nJ
    P = cat(3, res{j, :});
    out(j).pred = mean(P, 3);       % seed ensemble
end
fprintf('[LSTM] %d trainings in %.0f s\n', nJ * nS, toc(t0));
save(opts.cache, 'out', 'key');
end

function pred = lstm_train_predict(B, job, W, seed, epochs)
rng(100 + seed, 'twister');
[X, Y] = lstm_windows(B, job.train, W, 3);
layers = [sequenceInputLayer(size(X, 2))
          lstmLayer(64, 'OutputMode', 'last')
          dropoutLayer(0.2)
          fullyConnectedLayer(32)
          reluLayer
          fullyConnectedLayer(1)
          sigmoidLayer];
net = dlnetwork(layers);
o = trainingOptions('adam', 'MaxEpochs', epochs, 'MiniBatchSize', 128, ...
    'InitialLearnRate', 2e-3, 'Shuffle', 'every-epoch', 'Verbose', false, ...
    'ExecutionEnvironment', 'cpu', 'InputDataFormats', 'TCB', 'TargetDataFormats', 'BC');
net = trainnet(X, Y, net, 'mse', o);
pred = [];
for q = 1:numel(job.targets)
    b = B(job.targets(q));
    ks = job.origins{q}(:)';
    Xq = zeros(W, size(b.Z, 2), numel(ks));
    for r = 1:numel(ks), Xq(:, :, r) = window(b.Z, ks(r), W); end
    p = double(extractdata(predict(net, dlarray(Xq, 'TCB'))));
    p = min(max(p(:), 0.02), 0.995);
    t = b.t(ks);
    rul = t .* (1 - p) ./ p;               % life-percentage to RUL
    pred = [pred; job.targets(q) * ones(numel(ks), 1), ks(:), rul]; %#ok<AGROW>
end
end

function [X, Y] = lstm_windows(B, idx, W, stride)
nTot = sum(arrayfun(@(i) numel(B(i).N0 + 1:stride:B(i).n), idx));
X = zeros(W, size(B(idx(1)).Z, 2), nTot, 'single'); Y = zeros(nTot, 1, 'single');
c = 0;
for i = idx
    b = B(i);
    for k = b.N0 + 1:stride:b.n
        c = c + 1;
        X(:, :, c) = window(b.Z, k, W);
        Y(c) = k / b.n;
    end
end
end

function w = window(Z, k, W)
i0 = k - W + 1;
if i0 >= 1, w = Z(i0:k, :);
else, w = [repmat(Z(1, :), 1 - i0, 1); Z(1:k, :)]; end
end

function [Lte, Loof] = lstm_lookup(out, protocol, fold, B, te, origins, tr)
sel = arrayfun(@(o) strcmp(o.protocol, protocol) && o.fold == fold, out);
J = out(sel);
Lte = table(); Loof = table();
for j = 1:numel(J)
    cap = max([B(J(j).train).life]);
    if strcmp(J(j).role, 'test'), Lte = [Lte; lstm_rows(B, J(j).pred, cap)]; %#ok<AGROW>
    else, Loof = [Loof; lstm_rows(B, J(j).pred, cap)]; end %#ok<AGROW>
end
assert(all(ismember(string({B(te).name}), Lte.bearing)) && all(ismember(string({B(tr).name}), Loof.bearing)));
assert(height(Lte) == sum(cellfun(@numel, origins)));
end

function T = lstm_rows(B, P, cap)
n = size(P, 1);
bi = P(:, 1); k = P(:, 2);
names = strings(n, 1); t = zeros(n, 1); f = t; post = false(n, 1); tr = t;
for r = 1:n
    b = B(bi(r));
    names(r) = b.name; t(r) = b.t(k(r)); f(r) = k(r) / b.n;
    post(r) = k(r) >= b.det; tr(r) = b.life - t(r);
end
T = table(names, k, t, f, post, tr, repmat("LSTM life percentage", n, 1), min(max(P(:, 3), 0), cap), ...
    nan(n, 1), nan(n, 1), nan(n, 1), 'VariableNames', ...
    {'bearing','k','t_s','lifeFraction','postOnset','trueRUL','method','pred','nativeLo','nativeHi','lambda'});
end

%% ======================================================================
%% Metrics, tests, tables, figure
%% ======================================================================
function T = summarize(P, methods, truthCol)
rows = {};
for m = methods'
    k = P.method == m;
    if ~any(k), continue; end
    y = P.(truthCol)(k); p = P.pred(k); lo = P.lo(k); hi = P.hi(k);
    e = p - y;
    Er = 100 * (y - p) ./ y;
    A = exp(log(0.5) * Er / 20);                     % early prediction (Er > 0)
    A(Er <= 0) = exp(-log(0.5) * Er(Er <= 0) / 5);   % late prediction, penalised harder
    alpha = 0.10;
    IS = (hi - lo) + 2 / alpha * (lo - y) .* (y < lo) + 2 / alpha * (y - hi) .* (y > hi);
    nl = P.nativeLo(k); nh = P.nativeHi(k);
    hasN = ~isnan(nl) & ~isnan(nh);
    covN = NaN; if any(hasN), covN = 100 * mean(y(hasN) >= nl(hasN) & y(hasN) <= nh(hasN)); end
    rows(end+1, :) = {m, nnz(k), mean(abs(e)), sqrt(mean(e.^2)), median(abs(e)), mean(abs(Er)), ...
        mean(A), 100 * mean(e > 0), 100 * mean(y >= lo & y <= hi), mean(hi - lo), mean(IS), covN, ...
        nnz(hasN)}; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'Method','N','MAE_s','RMSE_s','MedAE_s','MeanAbsEr_pct', ...
    'PHM2012_Score','Late_pct','ConformalCoverage90_pct','MeanWidth_s','IntervalScore_s', ...
    'NativeCoverage90_pct','NativeN'});
end

function T = paired_tests(P, methods, ref)
bn = unique(P.bearing, 'stable');
err = @(m) arrayfun(@(b) mean(abs(P.pred(P.method == m & P.bearing == b) - P.trueRUL(P.method == m & P.bearing == b))), bn);
eRef = err(ref);
rows = {};
for m = methods'
    if m == ref, continue; end
    e = err(m);
    ok = ~isnan(e) & ~isnan(eRef);
    d = e(ok) - eRef(ok);                     % positive = reference better
    [~, pt] = ttest(d);
    pw = signrank(d, 0, 'method', 'exact');
    se = std(d) / sqrt(numel(d));
    tq = tinv(0.975, numel(d) - 1);
    rows(end+1, :) = {m, numel(d), mean(e(ok)), mean(eRef(ok)), mean(d), mean(d) - tq * se, mean(d) + tq * se, ...
        nnz(d > 0), nnz(d < 0), pt, pw}; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'Comparator','Bearings','MAE_comparator_s','MAE_PIDSSDM_s', ...
    'Gain_s','Gain_CI95_lo','Gain_CI95_hi','PIDSSDM_better','Comparator_better','p_t','p_Wilcoxon'});
% Holm across the comparators, separately for each test
for v = ["p_t" "p_Wilcoxon"]
    p = T.(v); [ps, o] = sort(p); m = numel(p);
    adj = min(cummax((m - (0:m-1)') .* ps), 1);
    h = zeros(m, 1); h(o) = adj;
    T.(v + "_Holm") = h;
end
end

function T = dataset_table(B, officialRUL)
n = numel(B);
rows = cell(n, 9);
for i = 1:n
    b = B(i);
    offR = NaN; fullR = NaN; tT = NaN;
    if i > 6
        offR = officialRUL(i - 6); tT = b.nTrunc * 10; fullR = b.life - tT;
    end
    fptPct = NaN; if ~isinf(b.det), fptPct = 100 * b.fpt / b.n; end
    rows(i, :) = {b.name, b.cond, b.life, fptPct, exp(b.failLevel), b.failRMS, tT, offR, fullR};
end
T = cell2table(rows, 'VariableNames', {'Bearing','Condition','Life_s','OnsetFPT_pctLife', ...
    'FailRMS_over_baseline','FailRMS_g','Truncation_s','OfficialRUL_s','FullRecordRUL_s'});
end

function plot_fig13(B, PB, TB, TBpost, methods, figDir)
show = ["PI-DSSDM" "Bayesian exponential (Gebraeel 2005)" "PF exponential (Li 2015)" "LSTM life percentage"];
cols = [0.12 0.55 0.30; 0.45 0.45 0.45; 0.85 0.45 0.15; 0.18 0.45 0.80];
fig = figure('Color', 'w', 'Position', [50 50 1400 900], 'Visible', 'off');
ex = ["Bearing1_3" "Bearing2_3" "Bearing1_1" "Bearing3_3"];
for q = 1:4
    subplot(3, 4, q); hold on; box on; grid on;
    b = B(strcmp({B.name}, ex(q)));
    plot(b.t / 3600, (b.life - b.t) / 3600, 'k-', 'LineWidth', 1.4);
    for m = 1:numel(show)
        k = PB.method == show(m) & PB.bearing == ex(q);
        plot(PB.t_s(k) / 3600, PB.pred(k) / 3600, 'o-', 'Color', cols(m, :), 'MarkerFaceColor', cols(m, :), 'MarkerSize', 4);
    end
    if ~isinf(b.det), xline(b.fpt * 10 / 3600, ':', 'FPT'); end
    title(ex(q), 'Interpreter', 'none'); xlabel('Time (h)'); ylabel('RUL (h)');
    if q == 4, legend(["True" show], 'Location', 'northeast', 'FontSize', 6); end
end
sets = {TB, TBpost}; ttl = ["(e) MAE, all origins (LOBO, n = 17 bearings)" "(f) MAE, post-onset origins"];
for q = 1:2
    subplot(3, 2, 2 + q);
    T = sets{q};
    [~, o] = ismember(methods, T.Method); o = o(o > 0);
    barh(T.MAE_s(o) / 60); set(gca, 'YTick', 1:numel(o), 'YTickLabel', T.Method(o), 'YDir', 'reverse', 'FontSize', 8);
    xlabel('MAE (min)'); title(ttl(q)); grid on;
end
subplot(3, 2, 5);
[~, o] = ismember(methods, TB.Method); o = o(o > 0);
barh(TB.ConformalCoverage90_pct(o)); xline(90, 'k--');
set(gca, 'YTick', 1:numel(o), 'YTickLabel', TB.Method(o), 'YDir', 'reverse', 'FontSize', 8);
xlabel('Coverage of 90% conformal interval (%)'); title('(g) Interval coverage, all origins'); grid on;
subplot(3, 2, 6);
barh(TB.PHM2012_Score(o));
set(gca, 'YTick', 1:numel(o), 'YTickLabel', TB.Method(o), 'YDir', 'reverse', 'FontSize', 8);
xlabel('PHM 2012 score (mean A_i)'); title('(h) PHM 2012 score, all origins'); grid on;
exportgraphics(fig, fullfile(figDir, 'Fig13_PRONOSTIA_Benchmark.png'), 'Resolution', 600);
exportgraphics(fig, fullfile(figDir, 'Fig13_PRONOSTIA_Benchmark.pdf'), 'ContentType', 'vector');
close(fig);
end
