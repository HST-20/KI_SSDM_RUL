# PI-DSSDM 17.2.0 results: FULL

- Run folder: `C:\Users\harit\Desktop\FD_ALT_DATA\Vibration Data\runs\run_20261025_153330_671_full`
- Source SHA-256: `6f349da7915f53589b5061e2d2a505b5aab289c48d4ab31a44a9d73ca5f7b0f8`
- Seed: 2028102201; profile: fast
- Experiments completed: 30/30 (independent fleets); TRAIN/VAL/CAL/TEST units 24/10/24/16
- Evidence gate: **HOLD** (see `Evidence_gate.csv`)
- Total staged wall time: 18.8 h

Gain = comparator MAE - PI-DSSDM MAE (h); positive favours PI-DSSDM. The fleet is the unit of inference. p-values are two-sided. Holm adjustment is across comparators within each scenario x duty family.

## All scenarios, planned duty

| Comparator | Fleets | PI-DSSDM MAE | Comparator MAE | Gain [95% CI] (h) | Gain % | t p (Holm) | Wilcoxon p | W/L |
|---|---|---|---|---|---|---|---|---|
| Basis hybrid | 30 | 16.40 | 16.65 | +0.26 [-0.38, +0.90] | +1.1 | 0.418 (0.418) | 0.734 | 8/10 |
| Bayesian PF | 30 | 16.40 | 17.38 | +0.99 [+0.04, +1.93] | +5.1 | 0.0411 (0.107) | 0.0293 | 19/11 |
| Inverse PINN | 30 | 16.40 | 17.17 | +0.77 [+0.31, +1.24] | +5.1 | 0.00198 (0.00792) | 0.00123 | 22/8 |
| LSTM | 30 | 16.40 | 29.41 | +13.01 [+10.42, +15.61] | +42.7 | 3.64e-11 (1.82e-10) | 1.86e-09 | 30/0 |
| Physics SSM | 30 | 16.40 | 17.41 | +1.02 [+0.07, +1.96] | +5.3 | 0.0358 (0.107) | 0.0138 | 16/8 |

## All scenarios, probabilistic duty

| Comparator | Fleets | PI-DSSDM MAE | Comparator MAE | Gain [95% CI] (h) | Gain % | t p (Holm) | Wilcoxon p | W/L |
|---|---|---|---|---|---|---|---|---|
| Basis hybrid | 30 | 18.29 | 18.47 | +0.18 [-0.18, +0.54] | +1.1 | 0.316 (0.316) | 0.33 | 13/7 |
| Bayesian PF | 30 | 18.29 | 18.85 | +0.56 [-0.13, +1.25] | +3.0 | 0.11 (0.29) | 0.119 | 17/13 |
| Inverse PINN | 30 | 18.29 | 18.81 | +0.52 [+0.04, +1.00] | +3.0 | 0.0341 (0.136) | 0.0345 | 19/11 |
| LSTM | 30 | 18.29 | 29.82 | +11.53 [+9.41, +13.66] | +37.3 | 5.72e-12 (2.86e-11) | 1.86e-09 | 30/0 |
| Physics SSM | 30 | 18.29 | 18.87 | +0.58 [-0.11, +1.27] | +3.2 | 0.0968 (0.29) | 0.107 | 16/8 |

## By scenario (planned duty, gain vs Physics SSM and Inverse PINN)

| Scenario | vs Physics SSM | vs Inverse PINN | vs Basis hybrid |
|---|---|---|---|
| fatigue_matched | -0.01 [-0.23, +0.20] | +0.97 [-0.20, +2.14] | -0.01 [-0.23, +0.20] |
| fatigue_discrepancy | +0.21 [-0.24, +0.67] | +0.33 [-0.82, +1.48] | +0.08 [-0.19, +0.36] |
| fatigue_emission_mismatch | +0.20 [-0.21, +0.62] | +1.76 [+0.12, +3.40] | +0.10 [-0.27, +0.48] |
| fatigue_combined_mismatch | +0.24 [-0.11, +0.59] | +0.86 [-0.41, +2.14] | +0.05 [-0.26, +0.36] |
| fatigue_weak_gap | -0.53 [-2.42, +1.36] | -0.27 [-2.19, +1.65] | -0.36 [-1.88, +1.17] |
| fatigue_load_exponent | +5.99 [+2.92, +9.06] | +0.98 [-0.46, +2.43] | +1.68 [-3.33, +6.69] |

## Files

- `Table_metrics_by_scenario.csv`: mean and SD over fleets of MAE, RMSE, bias, coverage, width, interval score
- `Table_paired_tests.csv`: every scenario x duty x comparator test
- `Table_runtime_by_stage.csv`: wall time per stage
- `Fig1`-`Fig6`: PNG (300 dpi), vector PDF and editable FIG

Synthetic benchmark. Neither completion nor a passing test establishes physical validity; ties, losses and ineligible fits are retained.
