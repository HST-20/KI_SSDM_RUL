# PRONOSTIA results (run of 2026-11-01)

These numbers come from `run_pronostia_benchmark.m` (log in `data/pronostia/run_log.txt`; tables in `output_tables/Table12*`; figure `Fig13_PRONOSTIA_Benchmark`). RUL is in seconds. The PHM 2012 score is the challenge's mean A_i, where 1 is perfect.

## Headline

1. **Against the published comparators.** PI-DSSDM has the lowest error of the four prognostic methods under leave-one-bearing-out (LOBO) over all 17 bearings: MAE 3,828 s, against 4,811 s for the LSTM, 6,696 s for the Bayesian exponential and 7,201 s for the PF exponential. After Holm correction it is significantly better than the Bayesian exponential and the PF exponential. It is **not** significantly better than the LSTM (Holm p = 0.50).
2. **Against a constant prediction.** A predictor that ignores the vibration signal and always outputs the median training RUL does as well as PI-DSSDM: MAE 3,744 s vs 3,828 s, p = 0.67 (all origins). The same holds after onset: 2,935 s vs 3,099 s. On the official split the constant beats every method (MAE 2,400 s). **On PRONOSTIA, no method here, the proposed one included, extracts usable prognostic information beyond the typical RUL.** The cause is the data, not the code:
   - Degradation onset is abrupt and late; the 3σ FPT falls after 95% of life for 9 of 17 bearings.
   - The final RMS varies 1.1–32× baseline across bearings.
   - Lives under one condition differ by 3×.
3. **Ablations (LOBO, all origins, n = 17).**
   - Removing survival conditioning raises MAE by 2,132 s (Holm p = 0.0002).
   - Removing the learned discrepancy raises it by 1,783 s (Holm p_t = 0.049; p_Wilcoxon = 0.25).
   - Removing ISO load–speed scaling raises it by 1,463 s, which is not significant (p = 0.31).
   - The pooling weight picked by validation was λ = 1 in every fold.
4. **Intervals.** The split-conformal 90% intervals reach 88–93% coverage for every method, but they are very wide: about 31,000 s for PI-DSSDM and about 23,000 s for the constant. They are honest about how uncertain RUL is, but too wide to drive maintenance decisions.

## Protocol A: official challenge split (6 training bearings, 11 test bearings, one prediction each, official RUL)

| Method | MAE (s) | PHM 2012 score | Coverage 90 % | Mean width (s) |
| --- | --- | --- | --- | --- |
| PI-DSSDM | 4,463 | 0.082 | 81.8 % | 51,987 |
| PI-DSSDM, no discrepancy | 6,205 | 0.142 | 81.8 % | 213,350 |
| Bayesian exponential (Gebraeel 2005) | 6,224 | 0.128 | 81.8 % | 499,510 |
| PF exponential (Li 2015) | 7,300 | 0.089 | 90.9 % | 422,360 |
| LSTM life percentage | 12,785 | 0.104 | 54.5 % | 119,880 |
| Reference: life prior only | 4,648 | 0.129 | 90.9 % | 119,770 |
| Reference: constant median RUL | 2,400 | 0.094 | 90.9 % | 22,587 |

With 11 points and five post-onset bearings, this split cannot separate the methods. The scores are below the challenge winner's reported 0.31. Bearing1_4 is scored against the official 339 s; scoring it against the full-record 2,890 s instead is in `Table12b2`.

## Protocol B: leave-one-bearing-out, 17 bearings × 8 origins

| Method | MAE all (s) | MAE post-onset (s) | PHM score | Coverage 90 % | Width (s) |
| --- | --- | --- | --- | --- | --- |
| **PI-DSSDM** | **3,828** | **3,099** | **0.139** | 88.2 % | 31,402 |
| PI-DSSDM, no discrepancy | 5,611 | 4,971 | 0.098 | 89.7 % | 109,800 |
| PI-DSSDM, no ISO scaling | 5,292 | 5,884 | 0.121 | 89.7 % | 88,118 |
| PI-DSSDM, no survival conditioning | 5,961 | 4,095 | 0.045 | 92.6 % | 425,150 |
| Bayesian exponential (Gebraeel 2005) | 6,696 | 6,661 | 0.040 | 90.4 % | 631,500 |
| PF exponential (Li 2015) | 7,201 | 8,420 | 0.036 | 93.4 % | 436,490 |
| LSTM life percentage | 4,811 | 5,201 | 0.136 | 93.4 % | 63,334 |
| Reference: life prior only | 5,471 | 4,482 | 0.102 | 89.7 % | 109,070 |
| Reference: constant median RUL | 3,744 | 2,935 | 0.130 | 90.4 % | 22,634 |

Paired tests vs PI-DSSDM (bearing-level MAE, n = 17, Holm across 8 comparators):

| Comparator | Gain (s) [95 % CI] | PI-DSSDM better / worse | Holm p_t | Holm p_Wilcoxon |
| --- | --- | --- | --- | --- |
| Bayesian exponential | +2,868 [1,931, 3,805] | 17 / 0 | 6e-5 | 1.2e-4 |
| PF exponential | +3,373 [1,869, 4,876] | 17 / 0 | 0.0013 | 1.2e-4 |
| LSTM | +983 [−761, 2,727] | 11 / 6 | 0.50 | 0.73 |
| Constant median RUL | −84 [−490, 322] | 11 / 6 | 0.67 | 0.85 |

Post-onset comparisons cover only the 7 bearings with early onset, and none is significant after Holm.

## Caveats to state in the manuscript

- Before onset, the Bayesian-exponential and PF methods are undefined in their source papers. Here they use median life − t, a rule that is often 10 s once t passes the median life. Part of PI-DSSDM's all-origin advantage over them is therefore its survival-conditioned life model, not its degradation filter. The post-onset rows compare the degradation models directly.
- PI-DSSDM's predictions are nearly flat over life (Fig 13a–d): the discrepancy shrinks them toward the typical RUL. That is why it ties the constant.
- The 3σ FPT rule fires early on transients in Bearing1_4 (4% of life) and Bearing2_3 (14%). It is reported as published, without re-tuning.
- No method was tuned on the test bearings. Every hyper-parameter is fixed in the code: N0 = 50, window 30, ridge 5, bound 1, priors γ ~ N(1, 0.5²).
