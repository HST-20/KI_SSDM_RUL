# KI-SSDM RUL Reproducibility Package

Every table and figure this package produces is computed from data shipped in `data/`. No result is typed into a script. Run in MATLAB R2022b or later (base MATLAB only; no toolboxes needed):

```matlab
cd KI_SSDM_RUL
main_reproduce_all
```

Outputs are written only to `output_tables/` and `output_figures_600dpi/`. Nothing is copied elsewhere. A full run takes about 4–5 minutes.

## Contents

| Folder | What it holds |
| --- | --- |
| `src_v17/` | `Source_BSFD_PI_DSSDM_Hierarchical_v17.m`, the benchmark code (v17.2.0, SHA-256 `6f349da7…f0f8`) |
| `data/v17_run/` | Outputs of run `run_20261025_153330_671_full`: test and calibration predictions, per-fleet metrics, the evidence gate, the residual ablation and the console log |
| `data/benchmark_30fleets/` | Summary CSVs and the `.fig` files saved by the same run |
| `data/physical_telemetry/` | Raw OPC UA bench telemetry (Aug 2025 speed/load matrix; Dec 2025 same-day initial/final runs) |
| `scripts/` | The computation and figure scripts called by `main_reproduce_all.m` |
| `retired_scripts/` | Scripts from v1 that wrote typed-in results; kept for the record and not called |

## What each output comes from

| Manuscript item | Script | Source |
| --- | --- | --- |
| Tables 1, 3 | `generate_specification_tables.m` | Declared bench and model specifications (not results) |
| Table 4 | `generate_specification_tables.m` | Fleet and unit counts checked against the v17 outputs |
| Table 5 (+ Holm) | `compute_benchmark_tables.m` | `v17_metrics_by_experiment.csv`; paired over 30 fleets |
| Table 6, 6b | `compute_benchmark_tables.m` | Same; 6b adds per-scenario paired tests |
| Table 7 | `compute_benchmark_tables.m` | Pointwise and unit-simultaneous coverage, width, interval score |
| Table 8 | `compute_benchmark_tables.m` | `discrepancy_ablation/`: residual ON vs OFF, the only ablation v17 ran |
| Evidence gate | `compute_benchmark_tables.m` | `Evidence_gate.csv` (overall status HOLD) |
| Table 9, 9b, Fig 11 | `analyze_physical_telemetry.m` | Raw telemetry; ISO 3408-5 preloaded double-nut life |
| Table 10 | `compute_decision_costs.m` | Eq. 41–43 on the 1,776 test decisions per duty |
| Figs 1–3 | `plot_fig01..03` | Source images in `data/` |
| Figs 4–10 | `plot_fig04..10` | `.fig` files saved by the v17 run |

## Not produced, and why

- **Table 2 (PRBS metrics):** the PRBS telemetry is not in the package. Add it and a script, or cite the metrics as measured elsewhere.
- **Jetson latency table:** it must be measured on the Jetson; no timing code or logs exist.
- **Absolute bench RUL in hours:** needs the screw's dynamic load rating `Ca` from the PMI catalogue. Pass it as `analyze_physical_telemetry(struct('Ca_N', <value>))`. Without it only the relative life index is computed.
- **Fig 12 (health-index curves):** retired; it was an analytic curve drawn through typed-in RULs.
- **PRONOSTIA:** the v1 script is retired; it did not implement the proposed method or genuine baselines. The rebuilt benchmark is in `pronostia/`; see `pronostia/README_PRONOSTIA.md` and `pronostia/RESULTS_PRONOSTIA.md`. It is not called by `main_reproduce_all` because it needs the Deep Learning, Statistics and Parallel Computing toolboxes. Run `pronostia/run_pronostia_benchmark` separately: about 4 minutes with the cached LSTM results, about 25 minutes from scratch on 24 cores.

## Assumptions to state in the manuscript

- Benchmark: inference unit = fleet (n = 30); ties = |fleet gain| ≤ 0.05 h; Holm correction across the 5 comparators within each duty.
- Decision costs: Cp = 1, Cu = 8; periodic age = 10th percentile of calibration-unit failure ages per fleet; discarded life = (T − τ)/(t0 + T). Costs are given with the manuscript's cw = 1e-4 /h and with a fleet-scale cw = Cp / mean calibration-unit life.
- Bench: Fpr = 1.2 kN, μg = 0.003, masses 25/175 kg, no cutting force; acceleration from the measured speed signal; torque-equivalent load given as an upper-bound sensitivity.
- The v17 configuration records `physicalAnchorsVerified = 0` and `dynamicLoadRatingN = NaN`: the benchmark is a synthetic, dimensionless study and is not calibrated to the physical screw.
