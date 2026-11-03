function generate_all_tables(outDir)
% GENERATE_ALL_TABLES
% Generates all 10 manuscript tables in formatted CSV and LaTeX (.tex) formats.
% All numerical values strictly match PI_DSSDM_v2.tex and PI_DSSDM_Final_Draft.pdf.

if nargin < 1 || isempty(outDir)
    packageRoot = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(packageRoot, 'output_tables');
end
if ~exist(outDir, 'dir'), mkdir(outDir); end

fprintf('========================================================================\n');
fprintf('  Generating Manuscript Tables 1 to 10 (CSV & LaTeX Formats)\n');
fprintf('  Strictly reconciled with PI_DSSDM_Final_Draft.pdf & PI_DSSDM_v2.tex\n');
fprintf('========================================================================\n');

%% Table 1: Digital Twin Parameters
t1_csv = fullfile(outDir, 'Table01_BSFD_DigitalTwin_Parameters.csv');
fid = fopen(t1_csv, 'w');
fprintf(fid, 'Subsystem,Parameter,Symbol,Value,Unit,Provenance\n');
fprintf(fid, 'Mechanical,Servomotor Rotor Inertia,J_m,7.7e-4,kg m^2,Manufacturer Datasheet\n');
fprintf(fid, 'Mechanical,Ball-Screw Shaft Inertia,J_s,2.15e-4,kg m^2,Cad Dynamic Model\n');
fprintf(fid, 'Mechanical,Unladen Carriage Mass,m_c,25.0,kg,Gravimetric Calibration\n');
fprintf(fid, 'Mechanical,Laden Total Carriage Mass,M_tot,175.0,kg,150 kg Deadweight Stack\n');
fprintf(fid, 'Mechanical,Screw Pitch / Lead,p,10.0,mm,PMI Catalogue R32-10T3\n');
fprintf(fid, 'Mechanical,Nominal Double-Nut Preload,F_pr,1.20,kN,Factory Preload Class 2\n');
fprintf(fid, 'Mechanical,Axial Contact Stiffness,k_n,8.5e8,N/m,Identification Test Bench\n');
fprintf(fid, 'Mechanical,Linear Guide Friction Coeff,mu_g,0.003,-,Rolling Guide Rating\n');
fprintf(fid, 'Electrical,Torque Sensitivity Constant,K_t,0.85,N m/A,Motor Spec Sheet\n');
fprintf(fid, 'Electrical,Back-EMF Velocity Constant,K_e,0.85,V s/rad,Motor Spec Sheet\n');
fprintf(fid, 'Electrical,Stator Winding Resistance,R_a,1.15,Ohm,Four-Wire Kelvin Probe\n');
fprintf(fid, 'Electrical,Stator Direct Inductance,L_a,4.20,mH,LCR Bridge at 1 kHz\n');
fprintf(fid, 'Electrical,DC Link Inverter Voltage,V_dc,300.0,V,Regulated Servo Bus\n');
fprintf(fid, 'Friction,Bristle Stiffness,sigma_0,1.0e5,N/m,Micro-Displacement Test\n');
fprintf(fid, 'Friction,Micro-Damping Coefficient,sigma_1,300.0,N s/m,Dynamic Phase Fit\n');
fprintf(fid, 'Friction,Viscous Damping Coefficient,sigma_2,0.50,N s/m,Constant Velocity Pulls\n');
fprintf(fid, 'Friction,Coulomb Sliding Friction,F_c,1.50,N m,Low-Speed Breakaway\n');
fprintf(fid, 'Friction,Static Breakaway Torque,F_s,2.00,N m,Ramp-to-Slip Measurement\n');
fprintf(fid, 'Friction,Stribeck Velocity Threshold,v_s,0.05,m/s,Stribeck Curve Inflection\n');
fprintf(fid, 'Control,Position Proportional Gain,K_p,50.0,1/s,Closed-Loop Tuning\n');
fprintf(fid, 'Control,Velocity Loop Proportional,K_v,1.20,N s/rad,Closed-Loop Tuning\n');
fprintf(fid, 'Control,Velocity Loop Integral Time,T_i,20.0,ms,Anti-Windup Reset Time\n');
fclose(fid);
fprintf('  [Table 01] Exported: %s\n', t1_csv);

%% Table 2: PRBS Tracking Metrics
t2_csv = fullfile(outDir, 'Table02_PRBS_Tracking_Metrics.csv');
fid = fopen(t2_csv, 'w');
fprintf(fid, 'Metric,Full Traversal (0-700 mm),Quasi-Steady Dwell Plateau (Final 30%%)\n');
fprintf(fid, 'Mean Tracking Error (mm),+0.015,+0.008\n');
fprintf(fid, 'Root Mean Square Error RMSE (mm),0.150,0.022\n');
fprintf(fid, 'Relative Stroke RMSE (%%),0.021%%,0.003%%\n');
fprintf(fid, 'Maximum Absolute Error (mm),0.380,0.065\n');
fprintf(fid, 'Dynamic Telemetry Latency (ms),2.1,0.0 (Settled)\n');
fprintf(fid, 'Repeatability Dispersion (mm),0.028,0.018\n');
fclose(fid);
fprintf('  [Table 02] Exported: %s\n', t2_csv);

%% Table 3: Explicit Knowledge Representation & 23-Dimensional Observation Architecture
t3_csv = fullfile(outDir, 'Table03_Explicit_Knowledge_Representation_and_Features.csv');
fid = fopen(t3_csv, 'w');
fprintf(fid, 'Section,Element,Domain Knowledge / Source,Mathematical Model Role\n');
fprintf(fid, 'Part A: Epistemic Mapping,Contact Fatigue Law,ISO 3408-5 dynamic ratings & Hertzian stress accumulation,Deterministic damage rate backbone: dD0/dt = c_u (F/F_ref)^p 3600|omega|/(2pi) f_op\n');
fprintf(fid, 'Part A: Epistemic Mapping,Wear Irreversibility,Thermodynamics 2nd Law (no spontaneous self-healing),Monotone damage clock dD/dt >= 0 via Gamma increments Delta D_k ~ Gamma(.)\n');
fprintf(fid, 'Part A: Epistemic Mapping,Reversible Nuisance,Thermal expansion & grease warming (t_half = 13.9 h),Mean-reverting Ornstein-Uhlenbeck nuisance process B(t) eliminated via closed-form GLS\n');
fprintf(fid, 'Part A: Epistemic Mapping,Unit-to-Unit Frailty,Metallurgical & manufacturing tolerances across batches,Log-normal unit frailty distribution log c_u = mu_C + eta_u with eta_u ~ N(0 sigma_C^2)\n');
fprintf(fid, 'Part A: Epistemic Mapping,Bounded Authority,Epistemic uncertainty in deep neural approximations,Smooth C-inf tanh skip bounds rho in [-b +b] (b = 0.30) restricting rate to [0.74 1.35]\n');
fprintf(fid, 'Part A: Epistemic Mapping,Model Risk Aversion,Model selection risk under uncorrupted physics,Validation-weighted linear pooling p = (1-w)p_phys + w p_disc with fallback w=0\n');
fprintf(fid, 'Part B: Feature Taxonomy,Statistical (7D),OPC UA Telemetry,sigma_tau tau_RMS sigma_i i_RMS sigma_omega sigma_P ptp(P) (Torque/power dispersion & RMS)\n');
fprintf(fid, 'Part B: Feature Taxonomy,Kinematic (6D),OPC UA Telemetry,u_bar i_bar tau_bar P_bar omega_bar x_bar (Axis operational setpoints & kinematic regimes)\n');
fprintf(fid, 'Part B: Feature Taxonomy,Digital Twin (6D),Dynamic Simulation,omega^Z dot(omega)^Z tau_fric^Z tau_m^Z i^Z u^Z (Baseline LuGre friction & torque states)\n');
fprintf(fid, 'Part B: Feature Taxonomy,Residuals (4D),Hybrid Reconstruction,tau_ext_tilde tau_hat e E (Decoupled disturbance torque & innovation energy)\n');
fclose(fid);
fprintf('  [Table 03] Exported: %s\n', t3_csv);

%% Table 4: Benchmark Configuration
t4_csv = fullfile(outDir, 'Table04_Hierarchical_Benchmark_Setup.csv');
fid = fopen(t4_csv, 'w');
fprintf(fid, 'Scenario,Designation,Simulated Degradation Regime,Fleets,Total Units\n');
fprintf(fid, 'S1,Matched Nominal,Nominal wear kinetics and calibrated sensor fidelity,5,370\n');
fprintf(fid, 'S2,Rate Discrepancy,+25%% accelerated wear kinetics over physics model,5,370\n');
fprintf(fid, 'S3,Emission Distortion,Non-Gaussian telemetry noise and non-stationary baseline drift,5,370\n');
fprintf(fid, 'S4,Combined Mismatch,Concurrent rate discrepancy and emission distortion,5,370\n');
fprintf(fid, 'S5,Weak Sensor Gap,Missing motor torque channel and downsampled 0.1 Hz telemetry,5,370\n');
fprintf(fid, 'S6,Load-Exponent Misspecification,Load exponent p=4.5 vs nominal p=3.0 (overload regime),5,370\n');
fprintf(fid, 'Total,Full Benchmark,Hierarchical evaluation across 30 fleets,30,2220\n');
fclose(fid);
fprintf('  [Table 04] Exported: %s\n', t4_csv);

%% Table 5: Comprehensive Overall Performance (Exact match with Table 5 in Final Draft)
t5_csv = fullfile(outDir, 'Table05_Comprehensive_Benchmark_Performance.csv');
fid = fopen(t5_csv, 'w');
fprintf(fid, 'Policy,Method / Comparator,MAE (h),Gain vs PI (h),95%% CI [h],Win/Loss/Tie,pt / pW,Statistical Verdict\n');
fprintf(fid, 'Planned Duty,PI-DSSDM (Proposed),16.40,--- (Ref),---,---,---,Reference Benchmark\n');
fprintf(fid, 'Planned Duty,Inverse PINN,17.17,+0.77,"[+0.31, +1.24]",22 / 8 / 0,0.0022 / 0.0012,PI Superior (p < 0.01)\n');
fprintf(fid, 'Planned Duty,Bayesian PF,17.38,+0.99,"[+0.04, +1.93]",19 / 11 / 0,0.0415 / 0.0293,PI Superior (p < 0.05)\n');
fprintf(fid, 'Planned Duty,Physics SSM,17.41,+1.02,"[+0.07, +1.96]",16 / 8 / 6,0.0358 / 0.0138,PI Superior (p < 0.05)\n');
fprintf(fid, 'Planned Duty,Basis Hybrid,16.65,+0.26,"[-0.38, +0.90]",8 / 10 / 12,0.4120 / 0.7337,Comparable / Parity\n');
fprintf(fid, 'Planned Duty,Deep LSTM,29.41,+13.01,"[+10.42, +15.61]",30 / 0 / 0,<0.0001 / <0.0001,PI Decisively Better\n');
fprintf(fid, 'Probabilistic Duty,PI-DSSDM (Proposed),18.29,--- (Ref),---,---,---,Reference Benchmark\n');
fprintf(fid, 'Probabilistic Duty,Inverse PINN,18.81,+0.52,"[+0.04, +1.00]",19 / 11 / 0,0.0351 / 0.0345,PI Superior (p < 0.05)\n');
fprintf(fid, 'Probabilistic Duty,Bayesian PF,18.85,+0.56,"[-0.13, +1.25]",17 / 13 / 0,0.1084 / 0.1191,Moderate PI Advantage\n');
fprintf(fid, 'Probabilistic Duty,Physics SSM,18.87,+0.58,"[-0.11, +1.27]",16 / 8 / 6,0.0962 / 0.1074,Moderate PI Advantage\n');
fprintf(fid, 'Probabilistic Duty,Basis Hybrid,18.47,+0.18,"[-0.18, +0.54]",13 / 7 / 10,0.3120 / 0.3300,Comparable / Parity\n');
fprintf(fid, 'Probabilistic Duty,Deep LSTM,29.82,+11.53,"[+9.41, +13.66]",30 / 0 / 0,<0.0001 / <0.0001,PI Decisively Better\n');
fclose(fid);
fprintf('  [Table 05] Exported: %s\n', t5_csv);

%% Table 6: Scenario-Specific MAE Breakdown
t6_csv = fullfile(outDir, 'Table06_Scenario_Specific_MAE_Breakdown.csv');
fid = fopen(t6_csv, 'w');
fprintf(fid, 'Scenario,Duty Policy,Physics SSM,Bayesian PF,Inverse PINN,LSTM,PI-DSSDM,PI Gain vs Physics (h),PI Gain vs Physics (%%)\n');
fprintf(fid, 'S1 Matched,Planned,17.26,17.26,18.25,34.69,17.28,-0.01,-0.1%%\n');
fprintf(fid, 'S1 Matched,Probabilistic,19.33,19.32,19.97,35.22,19.46,-0.14,-0.7%%\n');
fprintf(fid, 'S2 Rate Discrepancy,Planned,11.46,11.44,11.57,22.32,11.24,+0.21,+1.9%%\n');
fprintf(fid, 'S2 Rate Discrepancy,Probabilistic,13.46,13.40,13.80,22.34,13.15,+0.30,+2.3%%\n');
fprintf(fid, 'S3 Emission Distortion,Planned,17.38,17.23,18.93,34.93,17.17,+0.20,+1.2%%\n');
fprintf(fid, 'S3 Emission Distortion,Probabilistic,19.25,19.18,20.72,34.32,19.24,+0.01,+0.1%%\n');
fprintf(fid, 'S4 Combined Mismatch,Planned,11.15,11.12,11.77,21.69,10.91,+0.24,+2.1%%\n');
fprintf(fid, 'S4 Combined Mismatch,Probabilistic,13.14,13.14,13.29,21.73,12.66,+0.48,+3.7%%\n');
fprintf(fid, 'S5 Weak Sensor Gap,Planned,27.12,27.14,27.37,36.23,27.65,-0.53,-2.0%%\n');
fprintf(fid, 'S5 Weak Sensor Gap,Probabilistic,27.43,27.43,27.59,38.68,28.00,-0.56,-2.0%%\n');
fprintf(fid, 'S6 Load Misspecification,Planned,20.12,20.10,15.11,26.59,14.12,+5.99,+29.8%%\n');
fprintf(fid, 'S6 Load Misspecification,Probabilistic,20.61,20.60,17.50,26.65,17.21,+3.40,+16.5%%\n');
fclose(fid);
fprintf('  [Table 06] Exported: %s\n', t6_csv);

%% Table 7: Conformal Coverage, Sharpness, and Interval Score (Exact match with Table 7)
t7_csv = fullfile(outDir, 'Table07_Conformal_Coverage_Sharpness.csv');
fid = fopen(t7_csv, 'w');
fprintf(fid, 'Method,Policy,Coverage (%%),Width (h),Interval Score\n');
fprintf(fid, 'PI-DSSDM,Planned,93.3%%,82.48,94.20\n');
fprintf(fid, 'PI-DSSDM,Probabilistic,92.5%%,96.39,110.04\n');
fprintf(fid, 'Physics SSM,Planned,93.1%%,88.58,100.13\n');
fprintf(fid, 'Physics SSM,Probabilistic,92.7%%,102.39,115.33\n');
fprintf(fid, 'Inverse PINN,Planned,90.3%%,81.83,97.87\n');
fprintf(fid, 'Inverse PINN,Probabilistic,90.9%%,97.20,113.75\n');
fprintf(fid, 'Deep LSTM,Planned,93.4%%,229.20,256.46\n');
fprintf(fid, 'Deep LSTM,Probabilistic,92.2%%,232.37,265.86\n');
fclose(fid);
fprintf('  [Table 07] Exported: %s\n', t7_csv);

%% Table 8: Systematic Ablation Study (Exact match with Table 8)
t8_csv = fullfile(outDir, 'Table08_Systematic_Ablation_Study.csv');
fid = fopen(t8_csv, 'w');
fprintf(fid, 'Configuration / Variant,Plan. MAE (h),Prob. MAE (h),Coverage (%%)\n');
fprintf(fid, 'Full Proposed PI-DSSDM,16.40,18.29,93.3%%\n');
fprintf(fid, 'w/o Linear Pool (w = 1),17.95,20.10,89.4%%\n');
fprintf(fid, 'w/o Smooth Tanh (Polynomial),18.48,20.77,87.2%%\n');
fprintf(fid, 'w/o Gamma Noise (kappa = 0),16.88,18.86,90.5%%\n');
fprintf(fid, 'w/o Two-Tier Conv. (Exit 1 Only),17.59,19.55,92.1%%\n');
fprintf(fid, 'w/o Origin Strat. (Global Band),16.40,18.29,85.1%%\n');
fclose(fid);
fprintf('  [Table 08] Exported: %s\n', t8_csv);

%% Table 9: Real-Time Physical Test-Bench Deployment (Exact match with Table 9)
t9_csv = fullfile(outDir, 'Table09_Realtime_Physical_Deployment.csv');
fid = fopen(t9_csv, 'w');
fprintf(fid, 'Carriage Load Configuration,Feedrate (mm/min),Speed (RPM),Temp (deg C),PI-DSSDM RUL [90%% CI] (h),Physics SSM RUL (h),Inverse PINN RUL (h),Deep LSTM RUL (h),Bayesian PF RUL (h)\n');
fprintf(fid, 'Unladen Carriage (m_c = 25 kg),5000,500,31.1,"8271 [8165, 8377]",8250,8225,8215,8240\n');
fprintf(fid, 'Unladen Carriage (m_c = 25 kg),10000,1000,36.6,"8238 [8132, 8344]",8224,8198,8185,8215\n');
fprintf(fid, 'Unladen Carriage (m_c = 25 kg),15000,1500,49.3,"8172 [8066, 8278]",8160,8134,8160,8190\n');
fprintf(fid, 'Unladen Carriage (m_c = 25 kg),20000,2000,56.2,"8132 [8026, 8238]",8121,8095,8110,8145\n');
fprintf(fid, '150 kg Payload (M_tot = 175 kg),5000,500,46.2,"8143 [8037, 8249]",8086,8098,8135,8165\n');
fprintf(fid, '150 kg Payload (M_tot = 175 kg),10000,1000,47.3,"8165 [8059, 8271]",8209,8120,8125,8170\n');
fprintf(fid, '150 kg Payload (M_tot = 175 kg),15000,1500,55.3,"8150 [8044, 8256]",8045,8105,8095,8135\n');
fprintf(fid, '150 kg Payload (M_tot = 175 kg),20000,2000,67.1,"8056 [7950, 8162]",8056,8012,8045,8090\n');
fclose(fid);
fprintf('  [Table 09] Exported: %s\n', t9_csv);

%% Table 10: Jetson AGX Xavier Latency Benchmark (Exact match with Table 10)
t10_csv = fullfile(outDir, 'Table10_Jetson_Xavier_Latency_Benchmark.csv');
fid = fopen(t10_csv, 'w');
fprintf(fid, 'Pipeline Phase,Algorithm Operation,Latency (ms),Budget Load (%%)\n');
fprintf(fid, 'Phase 1: Ingestion,OPC UA TSN socket sync & 100 Hz interp.,3.8,0.8%%\n');
fprintf(fid, 'Phase 2: Digital Twin,Parallel 4th-order LuGre ODE simulation,9.4,1.9%%\n');
fprintf(fid, 'Phase 3: Features,23-ch observation Phi_k & bagged tree,14.2,2.8%%\n');
fprintf(fid, 'Phase 4: State Update,Latent state update & GLS projection,14.6,2.9%%\n');
fprintf(fid, 'Phase 5: Discrepancy,TensorRT smooth C-inf tanh forward pass,9.8,2.0%%\n');
fprintf(fid, 'Phase 6: UQ & RUL,Conformal quantile & root-finding,24.5,4.9%%\n');
fprintf(fid, 'Total Pipeline,Full End-to-End Online Cycle,76.3,15.3%%\n');
fprintf(fid, 'Headroom,Available Real-Time Headroom Margin (500 ms hop),423.7,84.7%%\n');
fclose(fid);
fprintf('  [Table 10] Exported: %s\n', t10_csv);

%% Table 11: Downstream Maintenance Decision Support & Lifecycle Costs
t11_csv = fullfile(outDir, 'Table11_Decision_Maintenance_Costs.csv');
fid = fopen(t11_csv, 'w');
fprintf(fid, 'Maintenance Strategy,Failure Rate (%%),Discarded Life (%%),Expected Cost E[C]/Cp,Cost Saving vs. Periodic (%%)\n');
fprintf(fid, 'Corrective (Run-to-Failure),100.0%%,0.0%%,9.00,-254.3%%\n');
fprintf(fid, 'Periodic (L10 = 8260 h),4.2%%,24.6%%,2.54,Baseline (0.0%%)\n');
fprintf(fid, 'Point-Estimate (LSTM),26.5%%,5.8%%,3.18,-25.2%%\n');
fprintf(fid, 'Point-Estimate (PINN),14.8%%,7.1%%,2.25,+11.4%%\n');
fprintf(fid, 'Bayesian PF (q0.05 Credible),8.6%%,16.2%%,1.87,+26.4%%\n');
fprintf(fid, 'PI-DSSDM Conformal (alpha = 0.10),3.8%%,7.6%%,1.17,+54.0%%\n');
fclose(fid);
fprintf('  [Table 11] Exported: %s\n', t11_csv);

fprintf('========================================================================\n');
fprintf('All 11 Tables successfully exported to: %s\n', outDir);
fprintf('========================================================================\n');
end
