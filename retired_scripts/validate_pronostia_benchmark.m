function results = validate_pronostia_benchmark()
% VALIDATE_PRONOSTIA_BENCHMARK
% =========================================================================
% Genuine, end-to-end prognostic benchmark comparing:
%   1. Physics SSM (ISO 281 contact fatigue backbone, p = 3.0)
%   2. Deep LSTM (Deep Learning Toolbox sequence-to-one recurrent network)
%   3. Bayesian Particle Filter (SIR sequential Monte Carlo on degradation state)
%   4. Proposed KI-SSDM (Knowledge-Informed State-Space Degradation Model
%      with analytic Kalman-GLS OU nuisance marginalisation, smooth bounded
%      discrepancy, dynamic evidence pooling, and multi-truncation LOOCV
%      split-conformal calibration)
%
% Dataset: IEEE PHM 2012 Prognostic Challenge / PRONOSTIA Bearing Platform
% Evaluated strictly on 11 held-out test bearings with zero label leakage.
%
% References:
%   - Nectoux et al. (2012), "PRONOSTIA: An experimental platform for
%     bearings accelerated degradation tests", IEEE PHM 2012.
%   - ISO 281:2007, "Rolling bearings - Dynamic load ratings and rating life".
%   - Orchard & Vachtsevanos (2009), "A particle-filtering approach for
%     failure prognosis", IEEE Trans. Reliab.
% =========================================================================

    fprintf('===================================================================\n');
    fprintf('  PRONOSTIA BEARING PROGNOSTIC BENCHMARK VALIDATION (IEEE PHM 2012) \n');
    fprintf('===================================================================\n\n');

    %% 1. Load PRONOSTIA Feature Cache
    data_file = 'C:\Users\harit\Desktop\DT_FeedDrive\Induction Motor Modelling\LPV Model_file\PRONOSTIA_data\pronostia_extracted_features.mat';
    if ~exist(data_file, 'file')
        error('PRONOSTIA feature cache not found at: %s', data_file);
    end
    data_struct = load(data_file, 'features');
    feat = data_struct.features;

    trainNames = {'Bearing1_1','Bearing1_2','Bearing2_1','Bearing2_2','Bearing3_1','Bearing3_2'};
    testNames  = {'Bearing1_3','Bearing1_4','Bearing1_5','Bearing1_6','Bearing1_7', ...
                  'Bearing2_3','Bearing2_4','Bearing2_5','Bearing2_6','Bearing2_7','Bearing3_3'};

    % Official IEEE PHM 2012 Challenge ground truth RUL in seconds
    % Bearing1_4 verified as 339 s (Nectoux et al., 2012)
    true_RUL_s = [5730; 339; 1610; 1460; 7570; 7530; 1390; 3090; 1290; 580; 820];
    true_RUL_min = true_RUL_s / 60;
    N_test = numel(testNames);

    % Operating conditions:
    % Cond 1: 1800 rpm, 4000 N (Train: B1_1, B1_2; Test: B1_3 to B1_7)
    % Cond 2: 1650 rpm, 4200 N (Train: B2_1, B2_2; Test: B2_3 to B2_7)
    % Cond 3: 1500 rpm, 5000 N (Train: B3_1, B3_2; Test: B3_3)
    cond_train = [1, 1, 2, 2, 3, 3];
    cond_test  = [1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3];
    dt = 10 / 60; % 10 seconds sampling interval = 0.1667 minutes

    %% 2. Calibrate ISO 281 Physical Fatigue Model on Learning Set
    fprintf('[1/4] Calibrating ISO 281 Physical Fatigue Model on Learning_set...\n');
    dur_train_min = zeros(6, 1);
    for ib = 1:6
        dur_train_min(ib) = feat.(trainNames{ib}).duration_s / 60;
    end

    L_nom = zeros(3, 1);
    sigma_fatigue = zeros(3, 1);
    for c = 1:3
        idx_c = find(cond_train == c);
        L_nom(c) = mean(dur_train_min(idx_c));
        sigma_fatigue(c) = max(0.25, std(log(dur_train_min(idx_c))));
        fprintf('      Condition %d: L_nom = %.1f min (fatigue scatter sigma_log = %.3f)\n', ...
            c, L_nom(c), sigma_fatigue(c));
    end

    % Evaluate Physics SSM on 11 Test Bearings
    pred_Phys = zeros(N_test, 1);
    lo_Phys   = zeros(N_test, 1);
    hi_Phys   = zeros(N_test, 1);

    for it = 1:N_test
        bn = testNames{it};
        t_obs = numel(feat.(bn).rms) * dt;
        c = cond_test(it);
        
        pred_Phys(it) = max(0, L_nom(c) - t_obs);
        % 90% log-normal fatigue scatter confidence bounds
        L_05 = L_nom(c) * exp(-1.645 * sigma_fatigue(c));
        L_95 = L_nom(c) * exp(+1.645 * sigma_fatigue(c));
        lo_Phys(it) = max(0, L_05 - t_obs);
        hi_Phys(it) = max(0, L_95 - t_obs);
    end

    %% 3. Train Deep LSTM Sequence Network on Learning Set
    fprintf('\n[2/4] Training Deep LSTM Network on Learning_set rolling windows...\n');
    rng(42); % Fixed seed for exact reproducibility
    W_seq = 20; % 20-frame sequence window (200 s history)
    XTrain = {};
    YTrain = [];

    for ib = 1:6
        bn = trainNames{ib};
        r = feat.(bn).rms;
        k = feat.(bn).kurt;
        p = feat.(bn).ptp;
        nf = numel(r);
        rul_full = ((nf - (1:nf)') * 10) / 60;
        
        for j = W_seq:4:nf
            feat_win = [r(j-W_seq+1:j), k(j-W_seq+1:j), p(j-W_seq+1:j)]';
            XTrain{end+1, 1} = feat_win;
            YTrain(end+1, 1) = rul_full(j);
        end
    end

    layers = [
        sequenceInputLayer(3, 'Name', 'input')
        lstmLayer(32, 'OutputMode', 'last', 'Name', 'lstm1')
        dropoutLayer(0.2, 'Name', 'drop')
        fullyConnectedLayer(16, 'Name', 'fc1')
        reluLayer('Name', 'relu1')
        fullyConnectedLayer(1, 'Name', 'fc_out')
        regressionLayer('Name', 'out')
    ];

    opts = trainingOptions('adam', ...
        'MaxEpochs', 35, ...
        'MiniBatchSize', 32, ...
        'InitialLearnRate', 0.01, ...
        'LearnRateSchedule', 'piecewise', ...
        'LearnRateDropPeriod', 18, ...
        'LearnRateDropFactor', 0.5, ...
        'Shuffle', 'every-epoch', ...
        'Verbose', false);

    net_lstm = trainNetwork(XTrain, YTrain, layers, opts);

    % Compute empirical 90% prediction interval from learning-set residuals
    res_lstm = zeros(min(300, numel(XTrain)), 1);
    for j = 1:numel(res_lstm)
        y_hat_tr = predict(net_lstm, XTrain{j});
        res_lstm(j) = abs(double(y_hat_tr) - YTrain(j));
    end
    q90_lstm = quantile(res_lstm, 0.90);
    fprintf('      LSTM training finished. Empirical 90%% residual bound = %.2f min\n', q90_lstm);

    pred_LSTM = zeros(N_test, 1);
    lo_LSTM   = zeros(N_test, 1);
    hi_LSTM   = zeros(N_test, 1);

    for it = 1:N_test
        bn = testNames{it};
        r = feat.(bn).rms;
        k = feat.(bn).kurt;
        p = feat.(bn).ptp;
        nf = numel(r);
        
        if nf >= W_seq
            test_win = [r(end-W_seq+1:end), k(end-W_seq+1:end), p(end-W_seq+1:end)]';
        else
            pad_len = W_seq - nf;
            test_win = [repmat(r(1), pad_len, 1); r, ...
                        repmat(k(1), pad_len, 1); k, ...
                        repmat(p(1), pad_len, 1); p]';
        end
        pred_LSTM(it) = max(0, double(predict(net_lstm, test_win)));
        lo_LSTM(it)   = max(0, pred_LSTM(it) - q90_lstm);
        hi_LSTM(it)   = pred_LSTM(it) + q90_lstm;
    end

    %% 4. Execute Bayesian Particle Filter (SIR Sequential Monte Carlo)
    fprintf('\n[3/4] Running Bayesian Particle Filter (SIR) across 11 Test Bearings...\n');
    N_part = 500;
    x_fail = 2.0; % failure threshold RMS = 2.0 g
    sigma_v_pf = 0.08;

    pred_PF = zeros(N_test, 1);
    lo_PF   = zeros(N_test, 1);
    hi_PF   = zeros(N_test, 1);

    for it = 1:N_test
        bn = testNames{it};
        y_meas = feat.(bn).rms;
        nf = numel(y_meas);
        c = cond_test(it);
        
        rng(3000 + it); % Deterministic seed per bearing
        x_part = y_meas(1) + 0.01 * randn(N_part, 1);
        b_part = (1.0 / L_nom(c)) * (0.8 + 0.4 * rand(N_part, 1));
        weights = ones(N_part, 1) / N_part;
        
        for k = 2:nf
            b_part = max(1e-4, b_part + 0.0002 * randn(N_part, 1));
            x_part = max(0.01, x_part .* exp(b_part * dt) + 0.008 * randn(N_part, 1));
            
            innov = y_meas(k) - x_part;
            lik = exp(-0.5 * (innov / sigma_v_pf).^2);
            weights = weights .* lik;
            w_sum = sum(weights);
            if w_sum > 1e-12
                weights = weights / w_sum;
            else
                weights = ones(N_part, 1) / N_part;
            end
            
            N_eff = 1.0 / sum(weights.^2);
            if N_eff < N_part / 2
                edges = [0; cumsum(weights)];
                edges(end) = 1;
                u = rand() / N_part + (0:N_part-1)' / N_part;
                [~, idx] = histc(u, edges);
                idx = min(idx, N_part);
                x_part = x_part(idx);
                b_part = b_part(idx);
                weights = ones(N_part, 1) / N_part;
            end
        end
        
        rul_part = zeros(N_part, 1);
        for ip = 1:N_part
            if x_part(ip) >= x_fail
                rul_part(ip) = 0;
            else
                t_rem = log(x_fail / x_part(ip)) / max(1e-4, b_part(ip));
                rul_part(ip) = max(0, min(1000, t_rem));
            end
        end
        
        pred_PF(it) = median(rul_part);
        lo_PF(it)   = quantile(rul_part, 0.05);
        hi_PF(it)   = quantile(rul_part, 0.95);
    end

    %% 5. Proposed KI-SSDM Pipeline (Continuous-Discrete Kalman-GLS, Discrepancy & Conformal)
    fprintf('\n[4/4] Executing Proposed KI-SSDM Pipeline...\n');
    theta_ou = 0.20; % OU mean-reversion rate (min^-1)
    sigma_nu = 0.05;
    sigma_v  = 0.04;
    M_bound  = 0.35; % smooth C^infty tanh authority bound (alpha in [0.70, 1.42])

    % Fit discrepancy network rho(phi) strictly on Learning_set
    Phi_tr = [];
    Target_tr = [];
    for ib = 1:6
        bn = trainNames{ib};
        r = feat.(bn).rms;
        k = feat.(bn).kurt;
        nf = numel(r);
        c = cond_train(ib);
        r_phys = 1.0 / L_nom(c);
        
        [x_est, ~, innov] = kalman_gls_filter(r, dt, theta_ou, sigma_nu, sigma_v);
        r_base = median(r(1:min(20, nf)));
        d_vib = max(0, min(1.0, (x_est - r_base) / (x_fail - r_base)));
        innov_pwr = movmean(innov.^2, 15);
        dx_dt = movmean([0; diff(x_est) / dt], 15);
        
        % Target: positive log discrepancy when vibration accelerates
        for j = 21:5:nf
            phi_j = [d_vib(j); max(0, k(j) - 3.0)/3.0; max(0, dx_dt(j)); log(innov_pwr(j) + 1e-4)];
            % Target discrepancy from actual life vs nominal fatigue rate
            t_j = j * dt;
            rem_act = (nf - j) * dt;
            target_rho_j = log(max(0.2, min(5.0, (1.0 - t_j/L_nom(c)) / max(0.5, rem_act * r_phys))));
            
            Phi_tr = [Phi_tr, phi_j];
            Target_tr = [Target_tr; target_rho_j];
        end
    end

    loss_fn = @(param) mean((M_bound * tanh(param(1:4)' * Phi_tr + param(5))' - max(-M_bound, min(M_bound, Target_tr))).^2);
    init_param = [0.4; 0.2; 0.8; 0.02; 0.0];
    opt_param = fminsearch(loss_fn, init_param, optimset('MaxIter', 500, 'Display', 'off'));
    w_disc = opt_param(1:4);
    b_disc = opt_param(5);
    fprintf('      Fitted Discrepancy weights: w = [%.3f, %.3f, %.3f, %.3f], b = %.3f\n', ...
        w_disc(1), w_disc(2), w_disc(3), w_disc(4), b_disc);

    % Multi-Truncation Leave-One-Bearing-Out Conformal Calibration (N_cal = 60)
    fprintf('      Computing Multi-Truncation LOOCV Conformal Calibration (N_cal = 60)...\n');
    trunc_grid = 0.45:0.05:0.90; % 10 inspection points per bearing
    conf_scores = [];

    for ib_val = 1:6
        train_idx = setdiff(1:6, ib_val);
        c_val = cond_train(ib_val);
        L_nom_val = mean(dur_train_min(intersect(train_idx, find(cond_train == c_val))));
        if isempty(L_nom_val) || isnan(L_nom_val)
            L_nom_val = dur_train_min(train_idx(1));
        end
        r_phys_val = 1.0 / L_nom_val;
        
        bn = trainNames{ib_val};
        r = feat.(bn).rms;
        k = feat.(bn).kurt;
        nf = numel(r);
        
        [x_est, ~, innov] = kalman_gls_filter(r, dt, theta_ou, sigma_nu, sigma_v);
        r_base = median(r(1:min(20, nf)));
        d_vib = max(0, min(1.0, (x_est - r_base) / (x_fail - r_base)));
        innov_pwr = movmean(innov.^2, 15);
        dx_dt = movmean([0; diff(x_est) / dt], 15);
        
        for p = trunc_grid
            j_eval = round(p * nf);
            t_eval = j_eval * dt;
            true_rul_eval = (nf - j_eval) * dt;
            
            phi_eval = [d_vib(j_eval); max(0, k(j_eval) - 3.0)/3.0; max(0, dx_dt(j_eval)); log(innov_pwr(j_eval) + 1e-4)];
            rho_eval = M_bound * tanh(w_disc' * phi_eval + b_disc);
            
            % Physics prediction modulated by discrepancy
            rul_phys_eval = max(0, L_nom_val - t_eval) / exp(rho_eval);
            
            % Telemetry prediction from recent slope
            win_e = min(20, j_eval);
            p_fit = polyfit((1:win_e)' * dt, x_est(j_eval-win_e+1:j_eval), 1);
            slope_e = max(0.005, p_fit(1));
            rul_tel_eval = max(0, (x_fail - x_est(j_eval)) / slope_e);
            
            % Dynamic evidence pooling
            w_pool = 1.0 / (1.0 + exp(-10.0 * (d_vib(j_eval) - 0.20)));
            rul_pred_eval = (1 - w_pool) * rul_phys_eval + w_pool * rul_tel_eval;
            
            conf_scores(end+1, 1) = abs(rul_pred_eval - true_rul_eval);
        end
    end

    N_cal = numel(conf_scores);
    alpha_conf = 0.10;
    k_ord = ceil((N_cal + 1) * (1 - alpha_conf)); % k = ceil(61 * 0.90) = 55
    sorted_scores = sort(conf_scores);
    q_hat_90 = sorted_scores(min(k_ord, N_cal));
    fprintf('      Conformal Quantile (N_cal = %d, k = %d): q_hat_90 = %.2f minutes\n', ...
        N_cal, k_ord, q_hat_90);

    % Evaluate KI-SSDM on 11 Held-out Test Bearings (Strict Zero Leakage)
    pred_KISSDM = zeros(N_test, 1);
    lo_KISSDM   = zeros(N_test, 1);
    hi_KISSDM   = zeros(N_test, 1);

    for it = 1:N_test
        bn = testNames{it};
        r = feat.(bn).rms;
        k = feat.(bn).kurt;
        nf = numel(r);
        t_obs = nf * dt;
        c = cond_test(it);
        r_phys = 1.0 / L_nom(c);
        
        [x_est, ~, innov] = kalman_gls_filter(r, dt, theta_ou, sigma_nu, sigma_v);
        r_base = median(r(1:min(20, nf)));
        d_vib = max(0, min(1.0, (x_est - r_base) / (x_fail - r_base)));
        innov_pwr = movmean(innov.^2, 15);
        dx_dt = movmean([0; diff(x_est) / dt], 15);
        
        phi_test = [d_vib(end); max(0, k(end) - 3.0)/3.0; max(0, dx_dt(end)); log(innov_pwr(end) + 1e-4)];
        rho_test = M_bound * tanh(w_disc' * phi_test + b_disc);
        
        rul_phys = max(0, L_nom(c) - t_obs) / exp(rho_test);
        
        win_t = min(20, nf);
        p_fit = polyfit((1:win_t)' * dt, x_est(end-win_t+1:end), 1);
        slope_t = max(0.005, p_fit(1));
        rul_tel = max(0, (x_fail - x_est(end)) / slope_t);
        
        w_pool = 1.0 / (1.0 + exp(-10.0 * (d_vib(end) - 0.20)));
        pred_KISSDM(it) = (1 - w_pool) * rul_phys + w_pool * rul_tel;
        
        % Origin-stratified Conformal Prediction Interval
        lo_KISSDM(it) = max(0, pred_KISSDM(it) - q_hat_90);
        hi_KISSDM(it) = pred_KISSDM(it) + q_hat_90;
    end

    %% 6. Compute Benchmark Metrics
    calc_metrics = @(pred, lo, hi) compute_metrics(pred, lo, hi, true_RUL_min);

    [mae_Phys,  cov_Phys,  wid_Phys,  score_Phys,  perr_Phys]  = calc_metrics(pred_Phys,   lo_Phys,   hi_Phys);
    [mae_LSTM,  cov_LSTM,  wid_LSTM,  score_LSTM,  perr_LSTM]  = calc_metrics(pred_LSTM,   lo_LSTM,   hi_LSTM);
    [mae_PF,    cov_PF,    wid_PF,    score_PF,    perr_PF]    = calc_metrics(pred_PF,     lo_PF,     hi_PF);
    [mae_KISSDM,cov_KISSDM,wid_KISSDM,score_KISSDM,perr_KISSDM]= calc_metrics(pred_KISSDM, lo_KISSDM, hi_KISSDM);

    %% 7. Display Summary Results
    fprintf('\n========================================================================================================\n');
    fprintf('                          PRONOSTIA BEARING VALIDATION BENCHMARK RESULTS (11 TEST BEARINGS)             \n');
    fprintf('========================================================================================================\n');
    fprintf('%-10s | %-8s | %-16s | %-16s | %-16s | %-16s\n', ...
        'Bearing', 'True RUL', 'Physics SSM', 'Deep LSTM', 'Bayesian PF', 'Proposed KI-SSDM');
    fprintf('--------------------------------------------------------------------------------------------------------\n');
    for it = 1:N_test
        fprintf('%-10s | %6.1f m | %5.1f [%4.0f,%4.0f] | %5.1f [%4.0f,%4.0f] | %5.1f [%4.0f,%4.0f] | %5.1f [%4.0f,%4.0f]\n', ...
            testNames{it}, true_RUL_min(it), ...
            pred_Phys(it),   lo_Phys(it),   hi_Phys(it), ...
            pred_LSTM(it),   lo_LSTM(it),   hi_LSTM(it), ...
            pred_PF(it),     lo_PF(it),     hi_PF(it), ...
            pred_KISSDM(it), lo_KISSDM(it), hi_KISSDM(it));
    end
    fprintf('--------------------------------------------------------------------------------------------------------\n');
    fprintf('%-10s | %-8s | %6.2f min         | %6.2f min         | %6.2f min         | %6.2f min\n', ...
        'MAE', '-', mae_Phys, mae_LSTM, mae_PF, mae_KISSDM);
    fprintf('%-10s | %-8s | %6.1f%%            | %6.1f%%            | %6.1f%%            | %6.1f%%\n', ...
        'Coverage', '90.0%', cov_Phys, cov_LSTM, cov_PF, cov_KISSDM);
    fprintf('%-10s | %-8s | %6.1f min         | %6.1f min         | %6.1f min         | %6.1f min\n', ...
        'Mean Width', '-', wid_Phys, wid_LSTM, wid_PF, wid_KISSDM);
    fprintf('%-10s | %-8s | %6.4f             | %6.4f             | %6.4f             | %6.4f\n', ...
        'PHM Score', 'Max=1.0', score_Phys, score_LSTM, score_PF, score_KISSDM);
    fprintf('========================================================================================================\n\n');

    %% 8. Export Table 12 to CSV
    csv_file = 'C:\Users\harit\Desktop\DSSM_RUL\Table12_PRONOSTIA_Bearing_Prognostics.csv';
    tbl = table(testNames', true_RUL_min, ...
        pred_Phys, lo_Phys, hi_Phys, perr_Phys, ...
        pred_LSTM, lo_LSTM, hi_LSTM, perr_LSTM, ...
        pred_PF, lo_PF, hi_PF, perr_PF, ...
        pred_KISSDM, lo_KISSDM, hi_KISSDM, perr_KISSDM, ...
        'VariableNames', {'Bearing', 'True_RUL_min', ...
        'Phys_Pred_min', 'Phys_Lo_min', 'Phys_Hi_min', 'Phys_PctErr', ...
        'LSTM_Pred_min', 'LSTM_Lo_min', 'LSTM_Hi_min', 'LSTM_PctErr', ...
        'PF_Pred_min', 'PF_Lo_min', 'PF_Hi_min', 'PF_PctErr', ...
        'KISSDM_Pred_min', 'KISSDM_Lo_min', 'KISSDM_Hi_min', 'KISSDM_PctErr'});
    writetable(tbl, csv_file);
    fprintf('Saved Table 12 benchmark data to: %s\n', csv_file);

    %% 9. Generate Publication-Quality Figure 13 (600 DPI)
    fig_png = 'C:\Users\harit\Desktop\DSSM_RUL\Fig13_PRONOSTIA_Benchmark_Validation.png';
    fig_pdf = 'C:\Users\harit\Desktop\DSSM_RUL\Fig13_PRONOSTIA_Benchmark_Validation.pdf';
    generate_figure(testNames, true_RUL_min, ...
        pred_Phys, lo_Phys, hi_Phys, ...
        pred_LSTM, lo_LSTM, hi_LSTM, ...
        pred_PF, lo_PF, hi_PF, ...
        pred_KISSDM, lo_KISSDM, hi_KISSDM, ...
        [mae_Phys, mae_LSTM, mae_PF, mae_KISSDM], ...
        [cov_Phys, cov_LSTM, cov_PF, cov_KISSDM], ...
        [score_Phys, score_LSTM, score_PF, score_KISSDM], ...
        fig_png, fig_pdf);
    fprintf('Generated publication-quality Figure 13 at:\n  - %s\n  - %s\n\n', fig_png, fig_pdf);

    % Return results struct
    results = struct();
    results.testNames = testNames;
    results.true_RUL_min = true_RUL_min;
    results.pred_Phys = pred_Phys; results.lo_Phys = lo_Phys; results.hi_Phys = hi_Phys;
    results.pred_LSTM = pred_LSTM; results.lo_LSTM = lo_LSTM; results.hi_LSTM = hi_LSTM;
    results.pred_PF = pred_PF; results.lo_PF = lo_PF; results.hi_PF = hi_PF;
    results.pred_KISSDM = pred_KISSDM; results.lo_KISSDM = lo_KISSDM; results.hi_KISSDM = hi_KISSDM;
    results.metrics = table([mae_Phys; mae_LSTM; mae_PF; mae_KISSDM], ...
                            [cov_Phys; cov_LSTM; cov_PF; cov_KISSDM], ...
                            [wid_Phys; wid_LSTM; wid_PF; wid_KISSDM], ...
                            [score_Phys; score_LSTM; score_PF; score_KISSDM], ...
                            'RowNames', {'Physics_SSM', 'Deep_LSTM', 'Bayesian_PF', 'Proposed_KISSDM'}, ...
                            'VariableNames', {'MAE_min', 'Coverage_pct', 'Mean_Width_min', 'PHM_Score'});
end

%% Helper Functions
function [x_est, nu_est, innov] = kalman_gls_filter(r, dt, theta, sigma_nu, sigma_v)
    N = numel(r);
    x_est = zeros(N, 1);
    nu_est = zeros(N, 1);
    innov = zeros(N, 1);
    z = [r(1); 0];
    P = diag([0.05^2, 0.05^2]);
    F = [1, 0; 0, exp(-theta * dt)];
    Q = diag([(0.002)^2, (sigma_nu^2 / (2*theta)) * (1 - exp(-2*theta*dt))]);
    H = [1, 1];
    R = sigma_v^2;
    for k = 1:N
        v_k = r(k) - H * z;
        innov(k) = v_k;
        S = H * P * H' + R;
        K = P * H' / S;
        z = z + K * v_k;
        P = (eye(2) - K * H) * P;
        x_est(k) = z(1);
        nu_est(k) = z(2);
        z = F * z;
        P = F * P * F' + Q;
    end
end

function [mae, cov, wid, phm_score, pct_err] = compute_metrics(pred, lo, hi, true_rul)
    err = abs(pred - true_rul);
    mae = mean(err);
    in_interval = (true_rul >= lo & true_rul <= hi);
    cov = mean(in_interval) * 100;
    wid = mean(hi - lo);
    
    pct_err = 100 * (true_rul - pred) ./ true_rul;
    scores = zeros(numel(true_rul), 1);
    for i = 1:numel(true_rul)
        if pct_err(i) <= 0
            scores(i) = 2^(pct_err(i) / 5);
        else
            scores(i) = 2^(-pct_err(i) / 20);
        end
    end
    phm_score = mean(scores);
end

function generate_figure(names, true_rul, p_phys, l_phys, h_phys, ...
                         p_lstm, l_lstm, h_lstm, p_pf, l_pf, h_pf, ...
                         p_prop, l_prop, h_prop, maes, covs, scores, ...
                         png_path, pdf_path)

    fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [100, 100, 1300, 750], 'Visible', 'off');
    
    c_phys = [0.45, 0.45, 0.45];
    c_lstm = [0.18, 0.53, 0.82];
    c_pf   = [0.85, 0.45, 0.15];
    c_prop = [0.12, 0.65, 0.35];
    
    % Panel 1: RUL Point Forecasts vs Ground Truth
    subplot(2, 2, [1, 2]);
    x = 1:numel(names);
    plot(x, true_rul, 'ks-', 'LineWidth', 2.2, 'MarkerFaceColor', 'k', 'MarkerSize', 7, 'DisplayName', 'Ground Truth (PHM 2012)');
    hold on;
    errorbar(x - 0.22, p_phys, p_phys - l_phys, h_phys - p_phys, 'o', 'Color', c_phys, ...
        'LineWidth', 1.2, 'MarkerFaceColor', c_phys, 'MarkerSize', 5, 'CapSize', 4, 'DisplayName', 'Physics SSM (ISO 281)');
    errorbar(x - 0.07, p_lstm, p_lstm - l_lstm, h_lstm - p_lstm, '^', 'Color', c_lstm, ...
        'LineWidth', 1.2, 'MarkerFaceColor', c_lstm, 'MarkerSize', 5, 'CapSize', 4, 'DisplayName', 'Deep LSTM');
    errorbar(x + 0.07, p_pf, p_pf - l_pf, min(500, h_pf - p_pf), 'v', 'Color', c_pf, ...
        'LineWidth', 1.2, 'MarkerFaceColor', c_pf, 'MarkerSize', 5, 'CapSize', 4, 'DisplayName', 'Bayesian PF');
    errorbar(x + 0.22, p_prop, p_prop - l_prop, h_prop - p_prop, 'd', 'Color', c_prop, ...
        'LineWidth', 1.8, 'MarkerFaceColor', c_prop, 'MarkerSize', 6, 'CapSize', 5, 'DisplayName', 'Proposed KI-SSDM');
    
    set(gca, 'XTick', x, 'XTickLabel', names, 'XTickLabelRotation', 30, 'FontSize', 9.5, 'LineWidth', 1.0);
    ylabel('Remaining Useful Life (min)', 'FontSize', 11, 'FontWeight', 'bold');
    title('(a) Prognostic RUL Forecasts and 90% Prediction Intervals on IEEE PHM 2012 Held-out Bearings', ...
        'FontSize', 12, 'FontWeight', 'bold');
    grid on; box on;
    legend('Location', 'northeast', 'FontSize', 9.5, 'NumColumns', 2);
    ylim([0, 350]);
    
    % Panel 2: MAE Comparison Bar Chart
    subplot(2, 2, 3);
    b1 = bar(maes, 0.55, 'FaceColor', 'flat');
    b1.CData(1, :) = c_phys;
    b1.CData(2, :) = c_lstm;
    b1.CData(3, :) = c_pf;
    b1.CData(4, :) = c_prop;
    set(gca, 'XTick', 1:4, 'XTickLabel', {'Physics SSM', 'Deep LSTM', 'Bayesian PF', 'Proposed KI-SSDM'}, ...
        'XTickLabelRotation', 20, 'FontSize', 9.5, 'LineWidth', 1.0);
    ylabel('Mean Absolute Error (min)', 'FontSize', 10.5, 'FontWeight', 'bold');
    title('(b) Mean Absolute Error (MAE)', 'FontSize', 11, 'FontWeight', 'bold');
    grid on; box on;
    for ib = 1:4
        text(ib, maes(ib) + 8, sprintf('%.1f m', maes(ib)), 'HorizontalAlignment', 'center', ...
            'FontSize', 9.5, 'FontWeight', 'bold');
    end
    ylim([0, max(maes) * 1.18]);
    
    % Panel 3: 90% Coverage and PHM 2012 Challenge Score
    subplot(2, 2, 4);
    yyaxis left
    b2 = bar((1:4) - 0.15, covs, 0.35, 'FaceColor', [0.2, 0.6, 0.8]);
    ylabel('90% Empirical Coverage (%)', 'FontSize', 10.5, 'FontWeight', 'bold');
    yline(90.0, 'k--', 'Nominal 90% Target', 'LineWidth', 1.2, 'FontSize', 8.5);
    ylim([0, 115]);
    
    yyaxis right
    b3 = bar((1:4) + 0.15, scores, 0.35, 'FaceColor', [0.85, 0.35, 0.25]);
    ylabel('PHM 2012 Score (Asymmetric)', 'FontSize', 10.5, 'FontWeight', 'bold');
    ylim([0, max(0.20, max(scores) * 1.4)]);
    
    set(gca, 'XTick', 1:4, 'XTickLabel', {'Physics SSM', 'Deep LSTM', 'Bayesian PF', 'Proposed KI-SSDM'}, ...
        'XTickLabelRotation', 20, 'FontSize', 9.5, 'LineWidth', 1.0);
    title('(c) Statistical Coverage and PHM 2012 Asymmetric Score', 'FontSize', 11, 'FontWeight', 'bold');
    grid on; box on;
    
    % Export
    exportgraphics(fig, png_path, 'Resolution', 600);
    exportgraphics(fig, pdf_path, 'ContentType', 'vector');
    close(fig);
end
