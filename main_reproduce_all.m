function results = main_reproduce_all()
% MAIN_REPRODUCE_ALL  Recompute every table and figure of the manuscript
% that this package can support, from data shipped in data/.
%
%   Tables 1, 3, 4   specifications (Table 4 counts checked against v17 outputs)
%   Tables 5-8       computed from the v17.2.0 benchmark run outputs
%   Table 9, Fig 11  computed from raw OPC UA bench telemetry
%   Table 10         Eq. 41-43 decision costs on the v17 test predictions
%   Figs 1-10        re-exported from source images and the v17 .fig files
%
% Not produced (see README): Table 2 (PRBS data not shipped), Jetson latency
% (must be measured on the device), PRONOSTIA (retired), Fig 12 (retired).
% Outputs go only to output_tables/ and output_figures_600dpi/.

clc; close all;
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root, 'scripts'));
P = pkg_paths();
t0 = tic;

steps = { ...
  'Specification tables 1, 3, 4',          @() generate_specification_tables(); ...
  'Benchmark tables 5-8 and evidence gate', @() compute_benchmark_tables(); ...
  'Decision costs (Table 10)',              @() compute_decision_costs(); ...
  'Bench telemetry (Table 9, Fig 11)',      @() analyze_physical_telemetry(); ...
  'Fig 1 test bench',                       @() plot_fig01_testbench_setup(P.figures); ...
  'Fig 2 PRBS qualification',               @() plot_fig02_prbs_qualification(P.figures); ...
  'Fig 3 framework',                        @() plot_fig03_framework_architecture(P.figures); ...
  'Fig 4 state filter',                     @() plot_fig04_states_filter(P.figures); ...
  'Fig 5 learning dynamics',                @() plot_fig05_learning_dynamics(P.figures); ...
  'Fig 6 prognosis',                        @() plot_fig06_prognosis_combined(P.figures); ...
  'Fig 7 MAE by scenario',                  @() plot_fig07_mae_by_scenario(P.figures); ...
  'Fig 8 hierarchical inference',           @() plot_fig08_hierarchical_inference(P.figures); ...
  'Fig 9 paired gain forest',               @() plot_fig09_paired_gain_forest(P.figures); ...
  'Fig 10 calibration and sharpness',       @() plot_fig10_calibration_sharpness(P.figures)};

status = strings(size(steps, 1), 1);
for k = 1:size(steps, 1)
    fprintf('\n=== %s ===\n', steps{k, 1});
    try
        steps{k, 2}();
        status(k) = "OK";
    catch ME
        status(k) = "FAILED: " + ME.message;
        fprintf(2, '%s\n', status(k));
    end
end

fprintf('\n%-42s %s\n', 'Step', 'Status');
for k = 1:size(steps, 1), fprintf('%-42s %s\n', steps{k, 1}, status(k)); end
fprintf('Total time %.1f s\n', toc(t0));
results = table(string(steps(:, 1)), status, 'VariableNames', {'Step', 'Status'});
end
