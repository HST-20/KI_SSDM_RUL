# Manuscript values to update from package v2

All values below come from `output_tables/` after `main_reproduce_all`. Tables are numbered as in the third-version manuscript.

## Unchanged (already genuine)

- Fleet-mean MAE: 16.40 h (planned) and 18.29 h (probabilistic). All comparator MAEs, gains and 95% CIs in Table 5.
- Every Table 6 scenario MAE.
- Table 7 pointwise coverage, widths and interval scores for the four methods shown.

## Table 5: verdicts and counts

| Duty | Comparator | W/L/T (tie ≤ 0.05 h) | p_t | Holm p | Verdict |
| --- | --- | --- | --- | --- | --- |
| Planned | Inverse PINN | 22/8/0 | 0.0020 | 0.0079 | Better (Holm) |
| Planned | Bayesian PF | 17/8/5 | 0.0411 | 0.107 | Not significant after Holm |
| Planned | Physics SSM | 16/6/8 | 0.0358 | 0.107 | Not significant after Holm |
| Planned | Basis hybrid | 8/8/14 | 0.418 | 0.418 | No difference |
| Planned | LSTM | 30/0/0 | <1e-10 | <1e-9 | Better (Holm) |
| Probabilistic | Inverse PINN | 18/10/2 | 0.0341 | 0.136 | Not significant after Holm |
| Probabilistic | Bayesian PF | 16/9/5 | 0.110 | 0.290 | No difference |
| Probabilistic | Physics SSM | 15/6/9 | 0.0968 | 0.290 | No difference |
| Probabilistic | Basis hybrid | 10/6/14 | 0.316 | 0.316 | No difference |
| Probabilistic | LSTM | 30/0/0 | <1e-11 | <1e-10 | Better (Holm) |

Also correct the drifted raw p-values (PF planned 0.0411, Basis planned 0.4175, PINN probabilistic 0.0341, PF probabilistic 0.1099). Abstract and conclusions: "outperforming physics SSM, Bayesian filtering, inverse PINN" holds after correction only for Inverse PINN (planned) and LSTM.

## S6 (load-exponent) text

- The per-scenario Holm p = 0.028 against Physics SSM (planned) is correct within the S6 family. However, the v17 evidence gate fails S6 for every comparator under its stricter multiplicity rule (adjusted lower gain −0.73 h). Say so.
- Probabilistic S6: +3.40 h, p = 0.077, Holm 0.30, not significant.
- "Decisively outperforms Deep LSTM" in S6: Holm p = 0.096. "Outperforms Inverse PINN": p = 0.13.
- The planned-duty gains over Physics SSM summed across the six scenarios total +6.11 h (the two-decimal values shown in Table 6 sum to +6.10 h), not +6.12 h, so S6's share is 98.2%. Under probabilistic duty they total +3.49 h, so S6's share is 97.4%, not 97.1%.

## Table 7: additions

- Add unit-simultaneous coverage: PI-DSSDM 79.0% (planned) and 79.2% (probabilistic); comparators 74–83%.
- Add Basis hybrid (93.0% / 81.47 h / 94.01 planned). It is narrower than PI-DSSDM and has a lower planned interval score.
- Add Bayesian PF (93.0% / 88.47 h / 100.05 planned).

## Table 8: replace entirely

| Duty | Residual ON MAE | Residual OFF MAE | Gain [95% CI] | Fleets ON / OFF better | p_t | p_Wilcoxon |
| --- | --- | --- | --- | --- | --- | --- |
| Planned | 16.40 h | 18.21 h | +1.81 [−0.004, +3.63] h | 12 / 7 | 0.050 | 0.092 |
| Probabilistic | 18.29 h | 20.02 h | +1.74 [+0.37, +3.10] h | 16 / 6 | 0.015 | 0.0019 |

The w ≡ 1, polynomial, κ = 0, two-tier and global-band rows have no source and must be removed unless those variants are actually run.

## Evidence gate (new text, Results or Limitations)

Overall status: HOLD. Predictive criteria passed 40/60; the failures are all of S2 and S6. Numerical criteria passed 0/3, estimation 0/1, inference 5/6 and uncertainty 12/13. The failure list is in `Table_Evidence_Gate_Failures.csv`.

## Table 10: replace (480 test units; 1,776 unit-origin decisions per duty where the unit is still alive at the origin)

| Strategy (planned duty) | Failure rate | Discarded life | E[C], cw = 1e-4 | Saving vs periodic |
| --- | --- | --- | --- | --- |
| Corrective | 100% | 0% | 9.00 | −347% |
| Periodic (CAL L10 age) | 12.6% | 24.2% | 2.01 | 0 |
| PI-DSSDM point | 45.6% | 3.7% | 4.65 | −131% |
| PI-DSSDM conformal lower | 3.9% | 9.0% | 1.31 | +34.7% |
| Inverse PINN conformal lower | 4.8% | 9.1% | 1.39 | +31.1% |
| Bayesian PF conformal lower | 4.3% | 9.4% | 1.35 | +33.2% |
| Physics SSM conformal lower | 4.2% | 9.4% | 1.34 | +33.4% |
| Basis hybrid conformal lower | 4.1% | 8.9% | 1.33 | +33.8% |
| LSTM conformal lower | 3.9% | 18.1% | 1.32 | +34.3% |

Under probabilistic duty, PI-DSSDM lower gives 4.7% / 9.6% / 1.38 (+31.6%), and LSTM lower gives 1.32 (+34.3%). Main message to revise: the cost saving comes from scheduling at a conformal lower bound, and every method achieves 30–35% with it. PI-DSSDM is narrowly best only under planned duty. Replace "54.0%" and "37.4%" in the abstract and conclusions. Also note that the one-sided lower bound of a two-sided 90% band targets ≤ 5% failures.

## Table 9 / Fig 11 / Section 6.10: replace

- Measured steady-speed torque RMS (N·m) at 5k/10k/15k/20k mm/min: unladen 1.30 / 1.76 / 2.39 / 3.06; laden 1.26 / 1.88 / 2.49 / 3.24. Mean temperature (°C): unladen 31.1 / 36.6 / 49.3 / 56.1; laden 46.2 / 47.3 / 55.3 / 67.1.
- ISO 3408-5 preloaded double nut: the 1.2 kN preload dominates. The 150 kg payload raises the per-nut equivalent load by at most about 1.4% (1,216.6 N vs 1,202.1 N at 20k). Relative rated life (unladen 10k = 1): unladen 1.65 / 1.00 / 0.76 / 0.67; laden 1.67 / 1.00 / 0.76 / 0.65. Life therefore shortens markedly with speed. That contradicts the nearly flat 8,056–8,271 h in the current Table 9.
- Absolute hours need the catalogue Ca. The current per-method RULs (KI-SSDM, PINN, LSTM, PF) have no computation behind them and must be removed. None of those models was trained on or applied to bench data.
- Same-day Dec 2025 runs: torque RMS falls from cold to warm by 30.7% (5k), 38.7% (10k) and 45.4% (15k), as temperature rises 8–17 °C. Torque level is temperature-dominated, so the "+31.6% torque growth = Stage II wear" and "17.4% life consumed" claims are not supported by these data. Remove them, or support them with temperature-matched comparisons.

## Fig 6: regenerated from fleet 6 (replace text and caption)

`plot_fig06_prognosis_combined` now uses experiment 6 (S6, replicate 1), one of the two S6 fleets where validation selected the deep correction. Every number below is in `output_tables/Table_Fig6_Source_Check.csv`, re-derived from `v17_test_predictions.csv` (max difference from the plotted values 4e-13).

Replacement for the paragraph before the figure:

> Fig.~\ref{fig:prognosis_combined} shows RUL forecasts for one S6 fleet (Experiment~6, load-exponent misspecification), in which validation selected the stacked deep discrepancy under both duties. Under planned duty KI-SSDM reduced the fleet MAE from 24.24~h (Physics SSM and Basis hybrid) to 15.36~h, with 88.7\% calibrated coverage at a mean band width of 81.6~h against 93.5\% at 133.6~h for Physics SSM. Inverse PINN was more accurate in this fleet (14.39~h). Under probabilistic duty the corresponding MAEs are 18.66~h (KI-SSDM), 23.08~h (Physics SSM) and 15.88~h (Inverse PINN), with KI-SSDM coverage 90.3\% at 104.7~h. In three of the five S6 fleets the basis correction, not the deep one, was selected.

Replacement caption:

> RUL prognosis for one S6 fleet (Experiment~6: load-exponent misspecification, replicate~1), in which validation selected the stacked deep discrepancy ($w = 0.75$ planned, $0.50$ probabilistic). Panels per row: (i) forecasts for test unit fatigue\_load\_exponent\_021 at calendar origins 80, 160, 240 and 320~h with the KI-SSDM 90\% conformal band (widths 151, 130, 66 and 73~h planned; 155, 124, 78 and 83~h probabilistic), which misses the true RUL at 240~h under both duties; (ii) predicted against true RUL for the fleet's 62 unit-origin forecasts (16 test units); (iii) share of forecasts within $\pm$20\% of true RUL by life quarter; (iv) row coverage of the raw, fleet-calibrated and unit-calibrated bands; (v) mean calibrated band width; (vi) forecasts with the discrepancy on and off under identical posterior draws. (a) Planned duty: fleet MAE 15.36~h (KI-SSDM), 24.24~h (Physics SSM, Basis hybrid), 14.39~h (Inverse PINN); KI-SSDM calibrated coverage 88.7\% at mean width 81.6~h. (b) Probabilistic duty: MAE 18.66~h, 23.08~h and 15.88~h; coverage 90.3\% at 104.7~h. Physics SSM, Basis hybrid and Bayesian PF forecasts nearly coincide and overlap in the plots. PI-DSSDM in the panels denotes KI-SSDM.

Also delete "maintaining empirical fleet coverage above 92.5%" from the current paragraph: it is not true for this fleet.

## Remove or measure

- **Jetson latency table and text** (76.3 ms, median 74.8, P95 89.2, max 108.4, 184.2 ms PF): measure on the device or remove.
- **Fig 12:** remove.
- **PRONOSTIA (Table 12 / Fig 13):** replace them with the rebuilt benchmark in `pronostia/RESULTS_PRONOSTIA.md` (Tables 12a–g, Fig13_PRONOSTIA_Benchmark), or drop them. If you keep them, the claim has to be this:
  - PI-DSSDM beats the Bayesian-exponential and PF-exponential baselines significantly (Holm p ≤ 0.0013, 17/17 bearings).
  - It ties the LSTM (p = 0.50).
  - It ties a signal-free constant-RUL predictor (p = 0.67).
  - So it cannot be presented as accurate bearing prognosis.
- **Data availability:** state MATLAB only; the GitHub link and Zenodo DOI must resolve before submission.
