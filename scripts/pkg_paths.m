function P = pkg_paths()
% PKG_PATHS  Package-relative folders used by every script (no absolute paths).
P.root      = fileparts(fileparts(mfilename('fullpath')));
P.data      = fullfile(P.root, 'data');
P.v17       = fullfile(P.data, 'v17_run');
P.bench30   = fullfile(P.data, 'benchmark_30fleets');
P.telemetry = fullfile(P.data, 'physical_telemetry');
P.tables    = fullfile(P.root, 'output_tables');
P.figures   = fullfile(P.root, 'output_figures_600dpi');
if ~exist(P.tables, 'dir'),  mkdir(P.tables);  end
if ~exist(P.figures, 'dir'), mkdir(P.figures); end
end
