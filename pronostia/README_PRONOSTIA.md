# PRONOSTIA benchmark (v2)

This folder replaces `retired_scripts/validate_pronostia_benchmark.m`. Every number it reports is computed from the raw FEMTO-ST accelerometer records. Nothing is typed in.

```matlab
cd pronostia
F = extract_pronostia_features(<Learning_set>, <Full_Test_Set>, <Test_set>, '../data/pronostia/pronostia_features.mat');  % once, about 1 min
R = run_pronostia_benchmark();   % about 30-60 min on 24 cores; LSTM results are cached in data/pronostia/lstm_cache.mat
```

Requires the Deep Learning, Statistics and Machine Learning, and Parallel Computing toolboxes. Outputs: `output_tables/Table12*_PRONOSTIA_*.csv`, the per-prediction CSVs, and `output_figures_600dpi/Fig13_PRONOSTIA_Benchmark.*`.

## 1. Root causes in the retired script

| # | Problem in the retired script | Effect | Fix in v2 |
| --- | --- | --- | --- |
| 1 | "Physics SSM" was `L_nom(c) − t`, the mean training life minus elapsed time. It never used the test bearing's signal and went to 0 once t passed the mean. | This is not a state-space model, and it guarantees large errors on long-lived bearings. | Life is lognormal and conditioned on survival to t, with a hierarchical ISO 281 load–speed scaling. A Kalman degradation model takes over after onset. |
| 2 | Particle filter: an exponential on raw RMS with an arbitrary 2 g threshold, no first predicting time (FPT), hand-set priors and a 1,000-min cap. | This is not the published method, so the comparison is not credible. | Li et al. (2015) improved exponential model: x = φ + θ·exp(βτ), 3σ FPT, priors from training bearings, SIR filter, threshold taken from training failures. |
| 3 | LSTM trained on raw RUL in minutes, pooled across bearings whose lives differ 5-fold; interval from in-sample residuals. | Targets are not comparable across bearings, and the intervals are over-confident. | Life-percentage target (as in the PHM 2012 deep-learning literature), per-bearing baseline normalisation, a 3-seed ensemble and out-of-fold conformal intervals. |
| 4 | "KI-SSDM": a sigmoid pooling weight with hand-set constants (10, 0.20); the discrepancy target used `L_nom`; the conformal set came from 6 bearings with interchangeable origins. | Constants were tuned by hand; calibration ignores the stage. | Pooling weight is chosen by out-of-fold error with 0 as the physics fallback. Discrepancy is a ridge model, tanh-bounded. Conformal calibration is stratified by stage. |
| 5 | One prediction per test bearing (n = 11). No paired test. Bearing1_4 truth entered as 2,890 s while the official value is 339 s. | Too few points for inference, and the wrong ground truth. | Protocol A reproduces the official split with both truths. Protocol B adds leave-one-bearing-out (LOBO) over all 17 run-to-failure bearings at 8 origins each, with bearing-level paired tests and Holm correction. |
| 6 | Hard-coded comparator interval widths; the figure clipped to 350 min. | Interval results were not genuine. | Every interval is computed, and one conformal wrapper is used for every method. |

## 2. What the data imply (Table 12a)

- **Life varies widely within one condition.** Condition 1 lives run from 8,710 to 28,030 s. A life-only model therefore cannot be accurate before degradation starts.
- **Degradation onset is late and abrupt in most bearings.** The 3σ FPT falls after 95% of life for 9 of the 17 bearings. Early warning exists for only about half of them.
- **There is no consistent failure level.** The challenge states a 20 g stop rule, but the final peak acceleration ranges from 4 to 48 g, and the final RMS ranges from 1.1× to 32× the healthy baseline. Every threshold-based method must treat the failure level as uncertain.
- **Bearing1_4 has two ground truths.** The full record gives RUL = 2,890 s at the truncation point; the official answer key says 339 s. Both are reported.
- **Recording gap in Bearing1_1.** There is a 21,272 s gap in its time-of-day stamps. As is usual in the literature, time is counted as snapshots × 10 s.

## 3. The proposed method on bearings (PI-DSSDM)

This maps the manuscript's elements onto rolling bearings:

1. **Physics backbone, healthy stage.** ISO 281 basic life scales as (C/P)³/n. The lifetime model is hierarchical: log Lᵤ = μ + γ·g_c + ηᵤ, where g_c = log[(P₁/P_c)³(n₁/n_c)]. The knowledge prior is γ ~ N(1, 0.5²), so the ISO exponent is the prior and the data can adjust it. Unit frailty is ηᵤ ~ N(0, σ²). The prediction is the residual-life distribution conditional on survival to t.
2. **Degradation stage, after the 3σ FPT.** The model is y = log(RMS/RMS₀) = c + βτ + b_OU + e. It is a Kalman filter on (c, β) with population priors from the training bearings, plus an Ornstein–Uhlenbeck nuisance whose parameters come from the residual autocovariance at lags 1 and 2. RUL is the first passage of the trend to a random failure level drawn from the training failures.
3. **Fusion.** The two experts are fused as a product of lognormal experts. The degradation expert is weighted by P(β > 0).
4. **Bounded learned discrepancy.** ρ = tanh(ridge(φ)), with |ρ| ≤ 1, on causal features: stage, log-RMS ratio, kurtosis, high-to-low band energy ratio, time since onset, and log(t / prior median life).
5. **Validation-weighted pooling.** RUL = RUL_phys · exp(λρ), with λ ∈ {0, 0.25, …, 1} chosen by leave-one-bearing-out error on the training bearings. λ = 0 is the physics fallback.
6. **Split-conformal 90% interval** on log(RUL + 60 s), stratified by stage.

**Ablations:** no discrepancy (λ = 0); no ISO scaling (each condition's mean estimated alone, with no pooling); no survival conditioning (the median prior life minus t).

## 4. Comparators and their sources

| Method | Implementation | Source |
| --- | --- | --- |
| Bayesian exponential | Conjugate Bayesian linear model on log degradation signal, population prior, i.i.d. noise, fixed threshold; after 3σ FPT | Gebraeel, Lawley, Li & Ryan (2005), *IIE Trans.* 37:543–557 |
| PF exponential | x = φ + θ·exp(βτ), random-walk (log θ, β), SIR with systematic resampling, 3σ FPT, absolute threshold | Li, Lei, Lin & Ding (2015), *IEEE TIE* 62(12):7762–7773 |
| LSTM | 30-snapshot windows of 12 normalised features, LSTM(64)–FC(32)–sigmoid predicting life percentage, RUL = t(1−p)/p, 3-seed ensemble | Guo et al. (2017), *Neurocomputing* 240:98–109; Zhu, Chen & Peng (2019), *IEEE TIE* 66(4):3208–3216 |

Before onset, the Bayesian-exponential and PF methods are undefined, as they are in their papers. Before onset they use the population rule (median life − t). This affects only pre-onset origins, which are reported separately.

**Rules common to every method:**
- Every computation is causal: it uses only data up to the prediction origin.
- Failure levels and priors come from training bearings only.
- Each prediction is capped at the longest training life.
- Intervals use the same conformal wrapper, calibrated on out-of-fold predictions for the training bearings.

**Score** (PHM 2012 challenge, Nectoux et al. 2012):
- Er = 100·(ActRUL − RUL̂)/ActRUL.
- A = exp(−ln 0.5·Er/5) if Er ≤ 0 (late prediction), and exp(+ln 0.5·Er/20) if Er > 0 (early prediction).
- The score is the mean of A.

**Signal-free references:**
- The life prior alone, with no degradation stage and no discrepancy.
- A constant: the median RUL over the training bearings' origins.

Any method that cannot beat the constant extracts no prognostic information from the vibration signal.

**Not implemented:** a physics-informed neural network for bearings, for example a Paris-law residual LSTM. It needs its own design and tuning and is listed as future work.

## 5. Results

See `RESULTS_PRONOSTIA.md` (written from the run outputs).
