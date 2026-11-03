function R=BSFD_PI_DSSDM_Hierarchical_v17(mode,overrides)
% PI-DSSDM 17.2.0, unit-marginal hierarchical fatigue state-space methodology.
% v17 methodology revision (see v17_methodology_configuration and CHANGELOG):
% smooth discrepancy features, gradient refresh and labelled resolution-
% limited stationarity, multi-start/larger discrepancy, one-gate linear-pool
% selection, VAL-selected gamma damage increments, origin-stratified bands,
% bootstrap re-draws, and a load-exponent misspecification scenario.
% Inherited constrained event-time estimator; exitflag 1 keeps the original gate.
% Full run: R=RUN_FULL_v17(); preliminary: R=RUN_PRELIMINARY_v17();
% Performance is measured honestly. Physics fallback, ties and losses remain.
% D: monotone effective fatigue exposure; B: optional residual OU dynamics.
% Physical pitting identity requires independent load/failure calibration.
% Base MATLAB R2020b+; actual LSTM requires Deep Learning Toolbox.
% Default is SCREEN, not the multi-day full run. Read README.txt.
if nargin<1 || isempty(mode), mode='screen'; end
if nargin<2, overrides=struct(); end
v17_deadline('start',Inf);
mode=lower(char(mode));
if startsWith(mode,'config:'),R=v17_configuration(extractAfter(mode,'config:'),configuration());return;end
c=v17_configuration(mode,configuration());
f=fieldnames(overrides);
for j=1:numel(f)
    assert(isfield(c,f{j}),'pi17:config','Unknown option %s',f{j});
    c.(f{j})=overrides.(f{j});
end
if strcmp(mode,'workflowcheck'),R=v17_workflow_tests(c);disp(R);return;end
if strcmp(mode,'pinntiming'),R=v17_pinn_timing_check(c);return;end
if strcmp(mode,'bootstrapcheck'),R=v17_bootstrap_check(c);return;end
if strcmp(mode,'eventcheck'),R=v17_event_tests(c);disp(R);return;end
if strcmp(mode,'config'), R=c; return; end
if strcmp(mode,'parallelcheck'), R=v17_parallel_check(c); disp(R); return; end
if strcmp(mode,'revisioncheck'), R=v17_revision_tests(c); disp(R); return; end
if strcmp(mode,'hierarchyparallel'),R=v17_hierarchy_parallel_check(c);return;end
if strcmp(mode,'covariancefit'),R=v17_covariance_fit_diagnostic(c,f);return;end
if strcmp(mode,'covariancecheck'),R=v17_covariance_tests(c);disp(R);return;end
if strcmp(mode,'hierarchycheck'),R=v17_hierarchy_tests(c);disp(R);return;end
if strcmp(mode,'statecheck'),R=v17_state_hypothesis_check(c);return;end
if strcmp(mode,'enginecheck'), R=v17_engine_check(c); disp(R); return; end
if strcmp(mode,'telemetry'), R=telemetry_inventory(c); return; end
if strcmp(mode,'selftest'), R=selftest(c); disp(R); return; end
if strcmp(mode,'publication')
    % Presentation only: rebuild publication tables/figures from a saved run.
    assert(exist(c.dataFile,'file')==2,'pi17:publication','Set dataFile to a v17 Results.mat or checkpoint.mat');
    S=load(c.dataFile,'R');R0=S.R;R0.config.makePlots=c.makePlots;R0.config.showFigures=false;
    for name={'plotFontIncrement','figureResolution','figureSize'},R0.config.(name{1})=c.(name{1});end
    R=v17_publication_outputs(R0);fprintf('Publication outputs written to %s\n',R.outputDir);return;
end
if c.calibratedFatigueRate
    assert(c.axialLoadCalibrationVerified && all(isfinite([c.dynamicLoadRatingN c.referenceAxialLoadN c.referenceSpeedRPM])) && all([c.dynamicLoadRatingN c.referenceAxialLoadN c.referenceSpeedRPM]>0),'pi17:rating','Verified positive load/rating/speed are required.');
    rate=60*c.referenceSpeedRPM/1e6*(c.loadFactor*c.referenceAxialLoadN/c.dynamicLoadRatingN)^3;
    c.nominalRate=rate*exp(-sqrt(2)*erfinv(2*c.ratedLifeReliability-1)*c.unitSD);
end
if strcmp(mode,'gate'), S=load(c.dataFile,'R'); R=v17_evidence_gate(S.R); disp(R); return; end
if strcmp(mode,'resume')
    assert(exist(c.dataFile,'file')==2,'pi17:resume','Set dataFile to a v17 checkpoint.mat');
    S=load(c.dataFile,'R'); R=S.R;
    assert(strcmp(R.version,'17.2.0'),'pi17:resume','Only v17 checkpoints can resume. v14 and earlier require their original source.');
    currentHash=hash_file([mfilename('fullpath') '.m']);
    assert(strcmp(currentHash,R.sourceSHA256),'pi17:resume','Source differs from the saved run. Do not mix estimator versions.');
    previous=R.config; allow={'dataFile','maxRunSeconds','showFigures','parallelMode','startParallelPool','maxGradientWorkers'};
    assert(all(ismember(f,allow)),'pi17:resume','Resume permits checkpoint path, time budget, figure visibility and parallel execution options only.');
    for ii=1:numel(f), if ~strcmp(f{ii},'dataFile'), previous.(f{ii})=overrides.(f{ii}); end, end
    c=previous; mode=c.workflowMode; runDir=R.outputDir; R.status='running';
    if isfield(R,'lastError'), R=rmfield(R,'lastError'); end
else
    assert(ismember(mode,{'smoke','screen','controls','confirm','full','full_exhaustive','benchmark','data','assess'}),'pi17:mode','Unknown mode');
    if ismember(mode,{'benchmark','full_exhaustive'}), mode='full'; end
    c.workflowMode=mode;
    runDir=fullfile(c.outputDir,['run_' datestr(now,'yyyymmdd_HHMMSS_FFF') '_' mode]);
    if ~exist(runDir,'dir'), mkdir(runDir); end
    selftestConsole=evalc('runTests=selftest(c);');
    R=struct('version','17.2.0','config',c,'outputDir',runDir,'tests',runTests, ...
        'experiments',{{}},'metrics',table(),'predictions',table(),'alphaLambda',table(), ...
        'sourceSHA256',hash_file([mfilename('fullpath') '.m']),'status','running');
    R.selftestConsole=selftestConsole;
    R.provenance=source_provenance(c);
    copyfile([mfilename('fullpath') '.m'],fullfile(runDir,'Source_BSFD_PI_DSSDM_Hierarchical_v17.m'));
end
validate_config(c);
assert(numel(c.BtauBounds)==2 && c.BtauBounds(1)>0 && c.BtauBounds(2)>c.BtauBounds(1) && c.BloadingCoordinateScale>0 && c.BstartScreenSteps>=1 && c.BrefineFinalists>=1 && c.BrefineCycles>=1,'pi17:covarianceConfig','Invalid covariance configuration');
assert(c.marginalTraining && c.marginalDiagnosticUnits>=1 && c.marginalQuadrature>=5,'pi17:hierarchy','v17 requires marginal training and positive quadrature/audit settings.');
assert(strcmp(c.architecture,'observed') && c.profileObserved,'pi17:architecture','The public v17 workflow uses the profiled observed architecture.');
old=rng; cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
diary(fullfile(runDir,'console.txt')); dc=onCleanup(@()diary('off')); %#ok<NASGU>
v17_deadline('start',c.maxRunSeconds); v17_score_bank('reset');
c=v17_parallel_setup(c); v17_fast_cache('reset');
R.execution=struct('activeGradientWorkers',c.activeGradientWorkers,'fastExactProfile',c.fastProfile);
fprintf('\nPI-DSSDM 17.2.0 | %s | seed %d\n',upper(mode),c.seed);
fprintf('TRAIN/VAL/CAL/TEST %d/%d/%d/%d; %d fleet replicates per scenario.\n',c.trainUnits,c.validationUnits,c.calibrationUnits,c.testUnits,c.replicates);
fprintf('B integrated analytically; proper failure-time density and censored survival likelihood identify the TRAIN population.\n');
fprintf('v17: direct constrained coordinates, effective B loadings, TRAIN-only covariance multistart.\n');
fprintf('B is standardized to unit stationary variance; loadings carry its sensor-scale amplitude.\n');
fprintf('Point estimates remain MEDIAN first passage; conservative RUL and risk are separate diagnostics.\n');
fprintf('All methods receive common causal prefixes and future-duty samples.\n');
fprintf('SCREEN is developmental evidence. CONFIRM uses a different fixed seed family.\n');
fprintf('No favorable result is guaranteed; ties, losses and unresolved convergence are retained.\n');
if isinf(c.maxRunSeconds),fprintf('Automatic wall-time pausing DISABLED. All configured experiments will be attempted.\n');
else,fprintf('USER-SPECIFIED wall budget %.0f s; optimizer checkpoints are retained.\n',c.maxRunSeconds);end
fprintf('Point forecasts precede population refits; ineligible base models skip bootstrap and remain flagged.\n');
fprintf('Convergence-aware selection=%d; fast exact GLS=%d; gradient workers=%d.\n',c.requireConvergedSelection,c.fastProfile,c.activeGradientWorkers);
disp(R.tests);
fleets={}; labels={};
if strcmp(mode,'data')
    assert(c.axialLoadCalibrationVerified && c.fatigueCriterionVerified,'pi17:physical','Physical RUL requires independent load and fatigue criterion calibration.');
    inputHash=hash_file(c.dataFile);
    if isfield(R,'inputDataSHA256'), assert(strcmp(R.inputDataSHA256,inputHash),'pi17:dataIdentity','Measured data changed since the saved run; start a new run.'); end
    R.inputDataSHA256=inputHash;
    S=load(c.dataFile,'units'); fleets={validate_units(S.units,c)}; labels={c.dataEvidence};
else
    for rep=1:c.replicates
        for ss=1:numel(c.scenarios)
            fleets{end+1}=generate_fleet(c,c.scenarios{ss},c.seed+100000*rep); %#ok<AGROW>
            labels{end+1}=sprintf('SYNTHETIC:%s:rep%d',c.scenarios{ss},rep); %#ok<AGROW>
        end
    end
end
R.plannedExperiments=numel(fleets); v17_save(fullfile(runDir,'checkpoint.mat'),struct('R',R));
try
    for e=1:numel(fleets)
        if e<=numel(R.experiments) && ~isempty(R.experiments{e}), continue; end
        v17_deadline('check'); v17_score_bank('reset');
        fprintf('\nExperiment %d/%d: %s\n',e,numel(fleets),labels{e}); started=tic;
        try
            E=experiment(fleets{e},c,e,labels{e},runDir);
        catch experimentError
            % 17.2: one retry after a non-budget failure (typically a lost
            % parallel worker in a day-long run). Completed stages and
            % optimizer checkpoints are reused, so the retry continues the
            % same deterministic computation; a second failure stops safely.
            if ~v17_flag(c,'retryFailedExperiment') || ismember(experimentError.identifier,{'pi17:budget','pi17:unresolvedPopulation'}), rethrow(experimentError); end
            fprintf(2,'\nExperiment %d failed: %s\nRestarting the parallel pool and retrying once from saved stages.\n',e,experimentError.message);
            v17_log_experiment_error(runDir,e,labels{e},experimentError);
            c=v17_restart_pool(c);
            E=experiment(fleets{e},c,e,labels{e},runDir);
        end
        E.elapsedSeconds=toc(started);
        R.experiments{e}=E; R.metrics=[R.metrics;E.metrics]; %#ok<AGROW>
        R.predictions=[R.predictions;E.predictions]; R.alphaLambda=[R.alphaLambda;E.alphaLambda]; %#ok<AGROW>
        v17_save(fullfile(runDir,'checkpoint.mat'),struct('R',R));
        v17_export_current(R);
    end
    R.status='complete'; R.fleetComparisons=fleet_comparisons(R);
    R.evidenceGate=v17_evidence_gate(R); disp(R.evidenceGate.table);
    writetable(R.evidenceGate.table,fullfile(runDir,'Evidence_gate.csv'));
    if c.makePlots, plot_benchmark(R); end
    try
        R.publication=v17_publication_outputs(R);
        fprintf('Publication tables, figures and Results_summary.md: %s\n',R.publication.outputDir);
    catch err
        fprintf(2,'Publication outputs skipped (results are unaffected): %s\n',err.message);
    end
    v17_export_current(R); v17_save(fullfile(runDir,'Results.mat'),struct('R',R));
    v17_save(fullfile(runDir,'checkpoint.mat'),struct('R',R));
    fprintf('\nCOMPLETED %d/%d experiments. Gate: %s.\n%s\n',numel(R.experiments),R.plannedExperiments,R.evidenceGate.decision,runDir);
    fprintf('Completion means all computations finished; consult estimationEligible and Evidence_gate.csv before interpreting comparisons.\n');
catch err
    R.status='error'; if strcmp(err.identifier,'pi17:budget'), R.status='paused_budget'; elseif strcmp(err.identifier,'pi17:unresolvedPopulation'),R.status='paused_estimation';end
    R.lastError=struct('identifier',err.identifier,'message',err.message);
    v17_save(fullfile(runDir,'checkpoint.mat'),struct('R',R)); v17_export_current(R);
    fprintf('\nStopped safely: %s\nCompleted stages are reusable; checkpoint: %s\n',err.message,fullfile(runDir,'checkpoint.mat'));
    if ~ismember(err.identifier,{'pi17:budget','pi17:unresolvedPopulation'}), rethrow(err); end
end
end

function c=configuration()
c=struct(); c.seed=20261007;
c.outputDir=fullfile(fileparts(mfilename('fullpath')),'runs');
c.originalSource=fullfile(fileparts(mfilename('fullpath')),'Reference','BSFD_PI_DSSDM_TwoState_v8e.txt');
c.telemetryDir='C:\Users\harit\Desktop\FD_ALT_DATA\Vibration Data';
c.dataFile=''; c.dataEvidence='MEASURED: independently verified labels';
c.label='Configured synthetic research benchmark';
c.trainUnits=24; c.validationUnits=10; c.calibrationUnits=24; c.testUnits=16;
c.replicates=3; c.scenarios={'matched','state_mismatch','weak_sensor_gap'};
c.policies={'planned','probabilistic'}; c.originFractions=[.25 .45 .65 .80]; c.splitIds=struct();
c.Dcrit=1; c.initialD=0; c.inspectionSD=.025; c.physicalAnchorsVerified=false;
c.nominalRate=.002; c.nominalLoadExponent=3; c.nominalTempCoefficient=.08; c.nominalAging=.3;
c.rateLogPriorSD=1.5; c.exponentPriorSD=.8; c.tempPriorSD=.3; c.agingPriorSD=1;
c.unitSD=.22; c.unitEffectMax=2; c.tauHours=18; c.initialGamma=[.35;.15;.4];
c.kappaHours=.06; c.kappaMin=.002; c.kappaMax=2; c.BnoiseSD=.10;
c.sensorSD=.08; c.sensorFloor=.015; c.sensorCeiling=.6; c.BnoiseFloor=.02;
c.emissionRidge=.01; c.noiseShrinkageObservations=5;
c.emIterations=12; c.mStepIterations=120; c.emDamping=.7;
c.emTolerance=.015; c.emMinIterations=4; c.gradientTolerance=2e-4;
c.fitParticles=220; c.smoothingPaths=12; c.particles=300; c.forecastPaths=200;
c.essFraction=.55; c.rejuvenationSteps=2; c.etaProposalSD=.055;
c.validationPaths=60; c.validationParticles=130; c.validationEvery=2;
c.hidden1=6; c.hidden2=4; c.residualBounds=[0 .15 .30];
c.residualCycles=4; c.networkSteps=160; c.networkLearningRate=.01;
c.residualPenalty=.02; c.networkPenalty=1e-5; c.unitResidualPenalty=.04;
c.BfeatureScale=.15; c.loadFeatureScale=.2; c.speedFeatureScale=.2; c.temperatureFeatureScale=.8;
c.projectionTolerance=1e-9;
c.forecastHorizonHours=1600; c.dutyStepHours=8; c.integrationStepHours=2;
c.intervalAlpha=.10; c.relativeFloorHours=1; c.alpha=.20; c.lambdaGrid=[0 .25 .5 .75 1];
c.profilePoints=5; c.profileIterations=100; c.jacobianStep=1e-4; c.rankTolerance=1e-6;
c.enableLSTM=true; c.requireLSTM=false; c.lstmHidden=[24 48]; c.lstmEpochs=120;
c.lstmLearningRate=.002; c.lstmBatch=16; c.lstmDutyBins=8;
c.pinnIterations=220; c.pinnStarts=2; c.pinnPhysicsWeight=1;
c.pinnHidden1=3; c.pinnHidden2=2;
c.simStepHours=8; c.simMaxHours=2000;
c.makePlots=true; c.showFigures=true; c.figureResolution=160;
c.architecture='observed'; c.observedIterations=6; c.observedFitSteps=140;
c.jointSteps=90; c.etaGridPoints=501; c.selectionSeeds=2; c.oneSEMultiplier=1;
c.hidden1=3; c.hidden2=2; c.residualCycles=2; c.observationSEMultiplier=1;
c.lstmTrainingFractions=.10:.05:.90; c.lstmValidationFractions=c.originFractions;
c.fatigueLinearDamage=false; c.axialLoadCalibrationVerified=false;
c.fatigueCriterionVerified=false; c.dynamicLoadRatingN=NaN;
c.referenceAxialLoadN=NaN; c.referenceSpeedRPM=NaN; c.loadFactor=1;
c.referenceRequiredForPhysicalBaseline=true; c.opcWindowRows=500;
c.ratedLifeReliability=.90; c.calibratedFatigueRate=false; c.fitLoadExponent=true; c.fitTemperatureCoefficient=true;
c.selectionCriterion='logRUL'; c.transitionStepHours=2; c.refineEmission=true;
c.diagnosticUnit=1; c.maxDiagnosticUnits=3;
c.fatigueLinearDamage=true; c.nominalAging=0; c.nominalTempCoefficient=0;
c.fitLoadExponent=false; c.fitTemperatureCoefficient=false;
c.scenarios={'fatigue_matched','fatigue_discrepancy','fatigue_weak_gap','fatigue_combined_mismatch'};
c.edgeResultsFile=''; c.edgeExperiment=1; c.edgeExportFile='';
% Prospective origin/sampling schedules are defined before lifetime is known.
c.originMode='calendar'; c.originHours=[80 160 240 320];
c.lstmTrainingHours=40:20:400;
c.inspectionMode='none'; c.inspectionEveryHours=64;
c.sensorGapHours=[120 240]; c.simIntegrationStepHours=2;
c.truthRate=.002; c.truthLoadExponent=3; c.truthTemperatureCoefficient=0;
c.truthUnitSD=.18; c.truthBtau=18; c.truthBsd=.09;
c.protectFixedLoadSpeed=true; c.protectFixedTemperature=false;
c.primaryFamily='deep'; c.includeBasisComparator=true;
c.optimizerPasses=2; c.jointRefineEmission=true;
c.minimumValidationGain=0; c.minimumBEmissionSingularValue=.05;
c.replicates=5; c.enableScheduleAudit=true;
c.numericalAuditPolicies={'planned'};
% Global parameter posterior and an independent fatigue-process noise model
% are not manufactured from missing evidence. Raw bands explicitly omit them.
c.requireMeasuredInspectionProvenance=true; c.terminalDamageTolerance=.025;
end

function validate_config(c)
assert(c.Dcrit>0 && c.initialD>=0 && c.initialD<c.Dcrit,'pi17:config','Invalid damage scale');
assert(c.intervalAlpha>0 && c.intervalAlpha<1 && c.alpha>0,'pi17:config','Invalid coverage');
assert(c.kappaMin>0 && c.kappaMax>=c.kappaMin && c.sensorFloor>0,'pi17:config','Invalid noise');
assert(c.particles>=20 && c.fitParticles>=20 && c.forecastPaths>=10,'pi17:config','Too few particles');
assert(c.smoothingPaths>=2 && c.emIterations>=1 && c.networkSteps>=1,'pi17:config','Invalid fit budgets');
assert(all(c.residualBounds>=0) && any(c.residualBounds==0),'pi17:config','Include physics-only candidate');
assert(c.integrationStepHours>0 && c.dutyStepHours>0 && c.forecastHorizonHours>0,'pi17:config','Invalid steps');
assert(all(c.originFractions>0 & c.originFractions<1),'pi17:config','Origins must precede endpoint');
assert(all(ismember(c.policies,{'planned','probabilistic'})),'pi17:config','Unsupported duty policy');
assert(ismember(c.originMode,{'calendar','life_fraction'}),'pi17:config','Unknown origin protocol');
assert(all(c.originHours>0) && all(diff(c.originHours)>0),'pi17:config','Calendar origins must increase');
assert(ismember(c.inspectionMode,{'none','calendar'}),'pi17:config','Outcome-dependent inspection schedules are prohibited');
assert(c.inspectionEveryHours>0 && c.simIntegrationStepHours>0,'pi17:config','Invalid simulator schedule');
assert(numel(c.sensorGapHours)==2 && c.sensorGapHours(2)>c.sensorGapHours(1),'pi17:config','Invalid fixed gap');
assert(ismember(c.primaryFamily,{'deep','fixed_basis'}),'pi17:config','Unknown discrepancy family');
assert(c.terminalDamageTolerance>0,'pi17:criterion','Positive endpoint fitting tolerance required');
assert(c.optimizerPasses>=1 && c.optimizerPasses==fix(c.optimizerPasses),'pi17:config','Invalid retry budget');
end

function M=initial_model(train,c)
p=size(train(1).y,2); M=struct('kind','ssm','label','Physics_SSM','available',true);
M.k=c.nominalRate; M.p=c.nominalLoadExponent; M.betaT=c.nominalTempCoefficient;
M.a=c.nominalAging; M.tau=c.tauHours; M.gamma=c.initialGamma;
M.kappa=c.kappaHours; M.sigmaB=c.BnoiseSD; M.unitSD=c.unitSD;
M.sensorSD=ones(1,p).*c.sensorSD; M.bound=0; M.reference=[]; M.projection=[];
M.nn=init_network(c.hidden1,c.hidden2,5); M.C=zeros(p,7); M.C(:,2)=1;
M.C(2,2)=0; M.C(2,3)=1;
% Initialization only, not the fitting objective: inspection-guided damage and
% residual sensor-2 B provide a starting emission for stochastic smoothing.
rowsD=[]; rowsB=[]; rowsU=[]; rowsY=[];
for i=1:numel(train)
    U=train(i); good=isfinite(U.inspection); anchors=U.inspection(good);
    if sum(good)>=2
        D=interp1(U.t(good),anchors,U.t,'linear','extrap');
    else
        D=zeros(size(U.t));
        for t=2:numel(D), D(t)=advance_D(D(t-1),physics_rate(M,U.u(t-1,:)),M.a,U.t(t)-U.t(t-1)); end
    end
    D=max(U.initialD,min(c.Dcrit,D)); D=cummax(D);
    B=U.y(:,2); B(~isfinite(B))=0; B=B-mean(B(isfinite(B)));
    rowsD=[rowsD;D]; rowsB=[rowsB;B]; rowsU=[rowsU;U.u]; rowsY=[rowsY;U.y]; %#ok<AGROW>
end
M.C=emission_fit(rowsD,rowsB,rowsU,rowsY,M.C,c);
if strcmp(c.architecture,'observed')
    M.kind='observed'; M.config=c; M.gamma=zeros(3,1); M.kappa=0;
    M.initialC=M.C; M.trainingEta=zeros(numel(train),1); M.useB=true;
    M.Bdefinition='Zero-mean residual dynamics after measured operating effects; not the v7 forced physical B';
    if c.fatigueLinearDamage, M.a=0; end
end
end

function M=fit_population(train,val,Q,c,eid)
if strcmp(c.architecture,'observed'), M=fit_observed_population(train,val,Q,c,eid); return; end
M=initial_model(train,c); best=M; bestScore=Inf; rows=cell(0,10); stabilized=false;
for it=1:c.emIterations
    rng(c.seed+eid*10000+it,'twister'); S=smooth_training(M,train,c);
    before=parameter_vector(M); beforeC=M.C; z=encode_population(M,c);
    fun=@(v) population_objective(decode_population(v,M,c),S,c);
    [znew,loss,opt]=bfgs_fd(fun,z,c.mStepIterations,c.gradientTolerance);
    updated=decode_population(znew,M,c);
    newC=emission_fit(S.obsD,S.obsB,S.obsU,S.obsY,M.C,c);
    updated.C=(1-c.emDamping)*M.C+c.emDamping*newC;
    pred=emission_features(S.obsD,S.obsB,S.obsU)*updated.C';
    for j=1:size(pred,2)
        ok=isfinite(S.obsY(:,j)); r=pred(ok,j)-S.obsY(ok,j);
        variance=(sum(r.^2)+c.noiseShrinkageObservations*M.sensorSD(j)^2)/ ...
            (numel(r)+c.noiseShrinkageObservations);
        updated.sensorSD(j)=min(c.sensorCeiling,max(c.sensorFloor,sqrt(variance)));
    end
    updated.unitSD=min(.6,max(.04,sqrt(mean(S.etas.^2))));
    M=updated; change=max(norm(parameter_vector(M)-before)/max(norm(before),1),norm(M.C-beforeC,'fro')/max(norm(beforeC,'fro'),1));
    score=NaN;
    if mod(it-1,c.validationEvery)==0 || it==c.emIterations
        score=forecast_score(M,val,Q,c,eid);
        if score<bestScore, bestScore=score; best=M; best.selectedIteration=it; best.selectedMStep=opt; end
    end
    rows(end+1,:)={it,loss,S.logEvidence/numel(train),score,change,opt.exitflag,opt.gradientNorm, ...
        S.meanESS,S.etaAcceptance,mean(M.sensorSD)}; %#ok<AGROW>
    fprintf('  EM %2d: Q/N %.5g | PF log evidence/unit %.5g | causal VAL %.5g | change %.3g | M-step %d\n', ...
        it,loss,S.logEvidence/numel(train),score,change,opt.exitflag);
    fprintf('         sensor SD %s | B SD %.4g | gamma kappa %.4g h | ESS %.1f | eta MH %.1f%%\n', ...
        mat2str(M.sensorSD,3),M.sigmaB,M.kappa,S.meanESS,100*S.etaAcceptance);
    if it>=c.emMinIterations && change<c.emTolerance && opt.exitflag>0
        stabilized=true; break;
    end
end
M=best; M.fitTrace=cell2table(rows,'VariableNames',{'iteration','expectedCompleteNLL', ...
    'logEvidencePerUnit','causalValidationLoss','relativeParameterChange','mStepExitflag', ...
    'mStepGradientNorm','meanESS','etaAcceptance','meanSensorSD'});
M.validationScore=bestScore;
M.optimization=struct('status','Monte Carlo EM','stabilized',stabilized,'iterations',height(M.fitTrace), ...
    'validationLogRULLoss',bestScore,'lastMStepExitflag',opt.exitflag, ...
    'selectedIteration',M.selectedIteration,'selectedMStepExitflag',M.selectedMStep.exitflag);
if ~stabilized, fprintf('  DIAGNOSIS: EM stabilization criterion not reached; inspect traces and budgets.\n'); end
end

function S=smooth_training(M,train,c)
S=struct('D0',[],'D1',[],'B0',[],'B1',[],'u',[],'dt',[],'eta',[],'unit',[], ...
    'obsD',[],'obsB',[],'obsU',[],'obsY',[],'etas',[],'initialB',[], ...
    'logEvidence',0,'meanESS',0,'etaAcceptance',0);
for i=1:numel(train)
    U=train(i); P=particle_filter(M,U,c,true,c.fitParticles);
    ix=systematic_resample(P.weights,c.smoothingPaths); L=numel(ix); K=numel(U.t);
    D=P.pathD(ix,:)'; B=P.pathB(ix,:)'; eta=P.eta(ix)';
    S.D0=[S.D0;reshape(D(1:end-1,:),[],1)]; S.D1=[S.D1;reshape(D(2:end,:),[],1)]; %#ok<AGROW>
    S.B0=[S.B0;reshape(B(1:end-1,:),[],1)]; S.B1=[S.B1;reshape(B(2:end,:),[],1)]; %#ok<AGROW>
    S.u=[S.u;repmat(U.u(1:end-1,:),L,1)]; S.dt=[S.dt;repmat(diff(U.t),L,1)]; %#ok<AGROW>
    S.eta=[S.eta;reshape(repmat(eta,K-1,1),[],1)]; S.unit=[S.unit;i*ones((K-1)*L,1)]; %#ok<AGROW>
    S.obsD=[S.obsD;D(:)]; S.obsB=[S.obsB;B(:)]; %#ok<AGROW>
    S.obsU=[S.obsU;repmat(U.u,L,1)]; S.obsY=[S.obsY;repmat(U.y,L,1)]; %#ok<AGROW>
    S.etas=[S.etas;eta(:)]; S.initialB=[S.initialB;B(1,:)']; %#ok<AGROW>
    S.logEvidence=S.logEvidence+P.logEvidence; S.meanESS=S.meanESS+mean(P.ESS)/numel(train);
    S.etaAcceptance=S.etaAcceptance+P.etaAcceptance/numel(train);
end
end

function z=encode_population(M,c)
z=[log(M.k/c.nominalRate);M.p;M.betaT;log(M.a+.01);log(M.tau);M.gamma;log(M.kappa);log(M.sigmaB)];
end

function M=decode_population(z,M,c)
M.k=c.nominalRate*exp(max(-5,min(5,z(1)))); M.p=max(1,min(5,z(2)));
M.betaT=max(-.6,min(.8,z(3))); M.a=max(0,min(3,exp(z(4))-.01));
M.tau=max(2,min(200,exp(z(5)))); M.gamma=max(-2,min(2,z(6:8)));
M.kappa=max(c.kappaMin,min(c.kappaMax,exp(z(9)))); M.sigmaB=max(c.BnoiseFloor,min(.8,exp(z(10))));
end

function v=parameter_vector(M)
v=[log(M.k);M.p;M.betaT;M.a;log(M.tau);M.gamma;log(max(M.kappa,1e-12));log(max(M.sigmaB,1e-12));M.sensorSD(:);M.unitSD];
end

function loss=population_objective(M,S,c)
dx=exposure(S.D1,M.a)-exposure(S.D0,M.a); dx=max(dx,realmin);
r=physics_rate(M,S.u).*exp(S.eta+discrepancy(M,S.D0,S.B0,S.u)); sh=S.dt/M.kappa; sc=M.kappa*r;
ld=(sh-1).*log(dx)-dx./sc-sh.*log(sc)-gammaln(sh)-log1p(M.a*S.D1);
phi=exp(-S.dt/M.tau); target=[log(max(S.u(:,1:2),1e-8)) S.u(:,3)]*M.gamma;
vb=M.sigmaB^2*max(1-phi.^2,1e-10); rb=S.B1-phi.*S.B0-(1-phi).*target;
lb=-.5*(log(2*pi*vb)+rb.^2./vb);
prior=(log(M.k/c.nominalRate)/c.rateLogPriorSD)^2+((M.p-c.nominalLoadExponent)/c.exponentPriorSD)^2+ ...
    ((M.betaT-c.nominalTempCoefficient)/c.tempPriorSD)^2+((M.a-c.nominalAging)/c.agingPriorSD)^2;
loss=mean(-ld-lb)+.5*prior*c.smoothingPaths/numel(S.dt)+.5*mean(S.initialB.^2/M.sigmaB^2+log(M.sigmaB^2))/ ...
    max(numel(S.dt)/numel(S.initialB),1);
if ~isfinite(loss), loss=1e30; end
end

function C=emission_fit(D,B,u,Y,previous,c)
X=emission_features(D,B,u); p=size(Y,2); C=previous;
pen=c.emissionRidge*diag([1e-6 ones(1,6)]);
for j=1:p
    ok=isfinite(Y(:,j)); if sum(ok)<8, continue; end
    xx=X(ok,:); yy=Y(ok,j);
    if j==2
        cols=[1 2 4 5 6 7]; yy=yy-xx(:,3); C(j,3)=1;
        C(j,cols)=((xx(:,cols)'*xx(:,cols)+pen(cols,cols))\(xx(:,cols)'*yy))';
    else, C(j,:)=((xx'*xx+pen)\(xx'*yy))'; end
end
end

function x=exposure(D,a)
if a<1e-8, x=D; else, x=log1p(a*D)/a; end
end

function D=damage_from_exposure(x,a)
if a<1e-8, D=x; else, D=expm1(min(a*x,80))/a; end
end

function r=physics_rate(M,u)
r=M.k*u(:,1).^M.p.*u(:,2).*exp(M.betaT*u(:,3));
end

function P=particle_filter(M,H,c,storePaths,N)
if nargin<4, storePaths=false; end
if nargin<5, N=c.particles; end
if isfield(M,'kind') && strcmp(M.kind,'observed'), P=observed_prefix(M,H,c,storePaths,N); return; end
K=numel(H.t); D=H.initialD*ones(N,1); B=M.sigmaB*randn(N,1);
eta=sqrt(2)*M.unitSD*erfinv((2*rand(N,1)-1)*erf(c.unitEffectMax/(sqrt(2)*M.unitSD)));
w=ones(N,1)/N; filtered=zeros(K,3); ESS=zeros(K,1); eventMass=ones(K,1);
innov=nan(K,size(H.y,2)); logEvidence=0; resamples=0; accepted=0; attempted=0;
statC=zeros(N,1); statA=0; floorEvents=0;
if storePaths, pathD=zeros(N,K); pathB=pathD; else, pathD=[]; pathB=[]; end
for k=1:K
    logEvent=zeros(N,1);
    if k>1
        dt=H.t(k)-H.t(k-1); u=H.u(k-1,:); oldD=D;
        rho=discrepancy(M,oldD,B,u); base=physics_rate(M,u).*exp(rho);
        rate=base.*exp(eta); sh=dt/M.kappa; scale=M.kappa*rate;
        cap=max(exposure(c.Dcrit,M.a)-exposure(oldD,M.a),realmin);
        dead=isfield(H,'failureObserved') && H.failureObserved && k==K;
        if dead, mass=gammainc(cap./scale,sh,'upper'); tail='upper';
        else, mass=gammainc(cap./scale,sh,'lower'); tail='lower'; end
        eventMass(k)=sum(w.*mass); floorEvents=floorEvents+sum(mass<1e-280);
        logEvent=log(max(mass,realmin));
        prob=max(realmin,min(1-eps,rand(N,1).*max(mass,realmin)));
        dx=scale.*gammaincinv(prob,sh,tail);
        rare=mass<1e-280;
        if any(rare)
            % Importance proposals remain on the correct event support when
            % the gamma CDF underflows. Their true density/proposal ratio is
            % retained in log weights; no arbitrary probability floor is used.
            if dead
                hazard=max(1./scale(rare)-(sh-1)./cap(rare),.01./scale(rare));
                excess=-log(max(rand(sum(rare),1),realmin))./hazard;
                dx(rare)=cap(rare)+excess;
                logq=log(hazard)-hazard.*excess;
            else
                dx(rare)=cap(rare).*max(rand(sum(rare),1),eps);
                logq=-log(cap(rare));
            end
            zdx=dx(rare); sdx=scale(rare);
            logEvent(rare)=(sh-1)*log(zdx)-zdx./sdx-sh*log(sdx)-gammaln(sh)-logq;
        end
        if ~dead, dx=min(dx,cap*(1-1e-12)); end % numerical open-endpoint guard
        D=damage_from_exposure(exposure(oldD,M.a)+dx,M.a);
        if ~dead
            D=min(D,c.Dcrit-eps(c.Dcrit)); % machine-rounding guard only
            assert(all(D<c.Dcrit+1e-10),'pi17:survival','Survival proposal violated threshold');
        end
        phi=exp(-dt/M.tau); target=[log(max(u(1:2),1e-8)) u(3)]*M.gamma;
        B=phi*B+(1-phi)*target+M.sigmaB*sqrt(1-phi^2)*randn(N,1);
        statA=statA+sh; statC=statC+dx./(M.kappa*base);
    end
    pred=emission_features(D,B,repmat(H.u(k,:),N,1))*M.C'; obs=H.y(k,:); ok=isfinite(obs);
    logLike=zeros(N,1);
    if any(ok)
        standardized=(pred(:,ok)-obs(ok))./M.sensorSD(ok);
        logLike=-.5*sum(standardized.^2,2)-sum(log(sqrt(2*pi)*M.sensorSD(ok)));
        innov(k,ok)=(obs(ok)-sum(w.*pred(:,ok),1))./M.sensorSD(ok);
    end
    if isfinite(H.inspection(k))
        logLike=logLike-.5*((D-H.inspection(k))/c.inspectionSD).^2-log(sqrt(2*pi)*c.inspectionSD);
    end
    lw=log(max(w,realmin))+logEvent+logLike; mx=max(lw);
    assert(isfinite(mx),'pi17:filter','All particle log likelihoods nonfinite');
    logZ=mx+log(sum(exp(lw-mx))); logEvidence=logEvidence+logZ;
    w=exp(lw-logZ); w=w/sum(w); ESS(k)=1/sum(w.^2);
    filtered(k,:)=[sum(w.*D) sum(w.*B) sum(w.*eta)];
    if storePaths, pathD(:,k)=D; pathB(:,k)=B; end
    if ESS(k)<c.essFraction*N || k==K
        ix=systematic_resample(w,N); D=D(ix); B=B(ix); eta=eta(ix); statC=statC(ix);
        if storePaths, pathD=pathD(ix,:); pathB=pathB(ix,:); end
        w=ones(N,1)/N; resamples=resamples+1;
        for sweep=1:c.rejuvenationSteps
            proposal=eta+c.etaProposalSD*randn(N,1);
            logRatio=-statA*(proposal-eta)-statC.*(exp(-proposal)-exp(-eta))- ...
                .5*(proposal.^2-eta.^2)/M.unitSD^2;
            accept=log(rand(N,1))<logRatio & abs(proposal)<c.unitEffectMax;
            eta(accept)=proposal(accept); accepted=accepted+sum(accept); attempted=attempted+N;
        end
    end
end
P=struct('D',D,'B',B,'eta',eta,'weights',w,'filteredMean',filtered,'ESS',ESS, ...
    'eventMass',eventMass,'logEvidence',logEvidence,'resamples',resamples, ...
    'distinctRateParticles',numel(unique(eta)),'etaAcceptance',accepted/max(attempted,1), ...
    'pathD',pathD,'pathB',pathB,'innovations',innov,'cdfUnderflowParticles',floorEvents);
end

function nn=init_network(h,g,d)
if nargin<3, d=2; end
nn=struct('W1',1.5*randn(h,d)/sqrt(d/2),'b1',linspace(-1,1,h)','W2',randn(g,h)/sqrt(h), ...
    'b2',.2*randn(g,1),'w',zeros(g,1));
end

function [H,A]=hidden_features(nn,D,B,u,c)
d=D(:)/c.Dcrit; bb=tanh(B(:)/c.BfeatureScale);
Z=[2*d-1 bb d.*tanh(log(max(u(:,1),1e-8))/c.loadFeatureScale) ...
 d.*tanh(log(max(u(:,2),1e-8))/c.speedFeatureScale) bb.*tanh(u(:,3)/c.temperatureFeatureScale)];
if strcmp(c.architecture,'observed')
 tl=tanh(log(max(u(:,1),1e-8))/c.loadFeatureScale);ts=tanh(log(max(u(:,2),1e-8))/c.speedFeatureScale);
 % v17: load/speed enter as main effects so a load-exponent error is
 % representable; damage interactions arise through the hidden layers.
 if ~v17_flag(c,'residualOperatingMain'),tl=d.*tl;ts=d.*ts;end
 Z=[2*d-1 2*d.^2-1 tl ts tanh(u(:,3)/c.temperatureFeatureScale)];
end
H1=tanh(Z*nn.W1'+nn.b1'); H2=tanh(H1*nn.W2'+nn.b2'); H=H2;
if numel(nn.w)==size(nn.W2,1)+3
 % Bounded damage-shape skip paths make curvature accessible without first
 % discovering it through saturated deep layers. They share the same physical
 % score projection and ONE joint log-rate bound with the deep features.
 % v17 uses bounded C-infinity shapes: the old clamp put a derivative kink
 % exactly at the failure-clock endpoint D=Dcrit, which broke line searches.
 % |feature|<1 for every D, so the analytic log-rate bound still holds.
 if v17_flag(c,'smoothDamageFeatures')
  t=tanh(2*d-1); H=[H t 2*t.^2-1 tanh(d).*tanh(u(:,3)/c.temperatureFeatureScale)];
 else
  dd=max(0,min(1,d)); H=[H 2*dd-1 2*(2*dd-1).^2-1 dd.*tanh(u(:,3)/c.temperatureFeatureScale)];
 end
end
if nargout>1,A=struct('Z',Z,'H1',H1,'H2',H2);end
end

function G=physical_scores(M,D,u,c)
D=max(0,min(c.Dcrit,D(:)));
allG=[ones(numel(D),1) log(max(u(:,1:2),1e-8)) u(:,3) D./(1+M.a*D)];
G=allG(:,score_columns(c));
end

function ix=score_columns(c)
if ~strcmp(c.architecture,'observed'), ix=1:5; return; end
ix=1; % Constant log-rate is always protected from residual/frailty confounding.
if c.fitLoadExponent || c.protectFixedLoadSpeed, ix(end+1)=2; end
if c.protectFixedLoadSpeed, ix(end+1)=3; end
if c.fitTemperatureCoefficient || c.protectFixedTemperature, ix(end+1)=4; end
if ~c.fatigueLinearDamage, ix(end+1)=5; end
end

function g=score_envelope(M,lo,hi,c)
g=[1 max(abs(log(max([lo(1) hi(1)],1e-8)))) ...
    max(abs(log(max([lo(2) hi(2)],1e-8)))) max(abs([lo(3) hi(3)])) c.Dcrit/(1+M.a*c.Dcrit)];
g=g(score_columns(c));
end

function ref=make_reference(M,S,c)
u=S.u; ref=struct('D',S.D0,'B',S.B0,'u',u,'unit',S.unit);
ref.lo=min(u,[],1); ref.hi=max(u,[],1); pad=.1*(ref.hi-ref.lo)+[.025 .025 .05];
ref.lo=max([.01 .01 -Inf],ref.lo-pad); ref.hi=ref.hi+pad;
ref.G=physical_scores(M,ref.D,u,c); ref.pinvG=pinv(ref.G,c.projectionTolerance);
ref.gmax=score_envelope(M,ref.lo,ref.hi,c);
end

function [M,F,Hcache]=project_network(M,c)
[H,Hcache]=residual_features(M,M.reference.D,M.reference.B,M.reference.u,c);
A=M.reference.pinvG*H;
% Smooth upper envelope is at least the old absolute-value bound.
sup=1+M.reference.gmax*sqrt(A.^2+c.projectionSmoothEpsilon^2);
F=(H-M.reference.G*A)./sup;
M.projection=struct('A',A,'sup',sup,'lo',M.reference.lo,'hi',M.reference.hi, ...
 'referenceOrthogonality',norm(M.reference.G'*F,'fro')/max(size(F,1),1));
end

function [rho,outside]=discrepancy(M,D,B,u)
if isfield(M,'Bdefinition'), B=zeros(size(B)); end
rho=zeros(numel(D),1); outside=false(size(rho));
if M.bound==0 || isempty(M.projection), return; end
if size(u,1)==1, u=repmat(u,numel(D),1); end
outside=any(u<M.projection.lo | u>M.projection.hi,2);
% Declared support controls extrapolation. No unit ID or future sensor enters.
uc=max(M.projection.lo,min(M.projection.hi,u));
G=physical_scores(M,D,uc,M.config); H=residual_features(M,D,B,uc,M.config);
rho=((H-G*M.projection.A)./M.projection.sup)*M.nn.w;
rho(outside)=0;
% The exact invariant of the projected map is |rho| <= sum|w| (|feature|<1).
% Fitted models satisfy sum|w| <= bound via the L1 projection; finite-
% difference probes on the active L1 face may sit h outside it, which is a
% legitimate trial point, not a model violation (v17.1.1 fix).
assert(all(abs(rho)<=max(M.bound,sum(abs(M.nn.w)))+1e-9),'pi17:bound','Log discrepancy bound violated');
end

function M=fit_primary(train,val,Q,base,c,eid)
if strcmp(c.architecture,'observed'), M=fit_observed_primary(train,val,Q,base,c,eid); return; end
base.config=c; M=base; M.label='PI_DSSDM'; best=base.validationScore;
rows={0,0,best,0,0,0}; selectedTrace=table();
for bound=c.residualBounds(c.residualBounds>0)
    candidate=base; candidate.bound=bound; candidate.nn=init_network(c.hidden1,c.hidden2,5);
    if strcmp(c.primaryFamily,'fixed_basis'), candidate.nn.W1(:)=0; candidate.nn.W2(:)=0; candidate.nn.b1(:)=0; candidate.nn.b2(:)=0; end
    candidate.config=c; trace=cell(0,6);
    for cycle=1:c.residualCycles
        rng(c.seed+eid*10000+700+cycle,'twister'); S=smooth_training(candidate,train,c);
        candidate.reference=make_reference(base,S,c);
        [candidate,netTrace]=train_network(candidate,S,c);
        score=forecast_score(candidate,val,Q,c,eid);
        rho=discrepancy(candidate,S.D0,S.B0,S.u);
        rows(end+1,:)={bound,cycle,score,sqrt(mean(rho.^2)),max(abs(rho)),netTrace.gradientNorm(end)}; %#ok<AGROW>
        trace(end+1,:)={cycle,netTrace.loss(end),score,sqrt(mean(rho.^2)),max(abs(rho)),netTrace.gradientNorm(end)}; %#ok<AGROW>
        fprintf('  residual bound %.2f cycle %d: causal VAL %.5g | rho RMS %.4g/max %.4g | grad %.3g\n', ...
            bound,cycle,score,sqrt(mean(rho.^2)),max(abs(rho)),netTrace.gradientNorm(end));
        if score<best, best=score; M=candidate; M.networkTrace=netTrace; selectedTrace=cell2table(trace, ...
                'VariableNames',{'cycle','expectedRateNLL','causalValidationLoss','rhoRMS','rhoMaxAbs','gradientNorm'}); end
    end
end
M.label='PI_DSSDM'; M.config=c; M.validationScore=best;
M.selection=cell2table(rows,'VariableNames',{'bound','cycle','causalValidationLoss','rhoRMS','rhoMaxAbs','gradientNorm'});
M.residualTrace=selectedTrace; if ~isfield(M,'networkTrace'), M.networkTrace=table(); end
M.optimization=struct('status','Staged projected-gradient Monte Carlo residual fit', ...
    'selectedBound',M.bound,'validationLogRULLoss',best,'physicsFrozen',true);
fprintf('  Selected bound %.2f. Physical coefficients and emission identical to PF reference.\n',M.bound);
end

function [M,T]=train_network(M,S,c)
M=project_network(M,c); x=pack_network(M.nn); m=zeros(size(x)); v=m; rows=zeros(c.networkSteps,3);
for it=1:c.networkSteps
    [loss,g]=network_objective(M,S,c); normg=norm(g);
    if normg>10, g=g*10/normg; end
    m=.9*m+.1*g; v=.999*v+.001*g.^2;
    x=x-c.networkLearningRate*(m/(1-.9^it))./(sqrt(v/(1-.999^it))+1e-8);
    M.nn=unpack_network(x,size(M.nn.W1,1),size(M.nn.W2,1),size(M.nn.W1,2));
    M.nn.w=project_l1(M.nn.w,M.bound); x=pack_network(M.nn); M=project_network(M,c);
    rows(it,:)=[it loss normg];
end
T=array2table(rows,'VariableNames',{'iteration','loss','gradientNorm'});
end

function [loss,g]=network_objective(M,S,c)
[M,F,A]=project_network(M,c); rho=F*M.nn.w;
dx=max(exposure(S.D1,M.a)-exposure(S.D0,M.a),realmin);
sh=S.dt/M.kappa; term=dx./(M.kappa*physics_rate(M,S.u).*exp(S.eta+rho)); N=numel(rho);
loss=mean(sh.*rho+term)+c.residualPenalty*mean(rho.^2);
q=(sh-term+2*c.residualPenalty*rho)/N;
units=unique(S.unit); unitMeans=zeros(size(units));
for j=1:numel(units)
    ix=S.unit==units(j); unitMeans(j)=mean(rho(ix));
    q(ix)=q(ix)+2*c.unitResidualPenalty*unitMeans(j)/(numel(units)*sum(ix));
end
loss=loss+c.unitResidualPenalty*mean(unitMeans.^2);
gradw=F'*q+2*c.networkPenalty*M.nn.w;
sup=M.projection.sup; raw=A.H2-M.reference.G*M.projection.A;
gradH=q*(M.nn.w'./sup);
gradSup=-sum(q.*raw.*M.nn.w',1)./sup.^2;
gradProjection=-M.reference.G'*gradH+M.reference.gmax'*gradSup.*sign(M.projection.A);
% Differentiate the TRAIN projection itself, not just the unprojected network.
gradH=gradH+M.reference.pinvG'*gradProjection;
back2=gradH.*(1-A.H2.^2); dW2=back2'*A.H1; db2=sum(back2,1)';
back1=(back2*M.nn.W2).*(1-A.H1.^2); dW1=back1'*A.Z; db1=sum(back1,1)';
gn=struct('W1',dW1,'b1',db1,'W2',dW2,'b2',db2,'w',gradw);
x=pack_network(M.nn); g=pack_network(gn)+2*c.networkPenalty*x;
% Output weight penalty counted once.
g(end-numel(M.nn.w)+1:end)=gradw;
loss=loss+c.networkPenalty*sum(x.^2);
end

function w=project_l1(w,radius)
if sum(abs(w))<=radius, return; end
v=sort(abs(w),'descend'); cs=cumsum(v); j=find(v>(cs-radius)./(1:numel(v))',1,'last');
theta=(cs(j)-radius)/j; w=sign(w).*max(abs(w)-theta,0);
end

function x=pack_network(n)
x=[n.W1(:);n.b1(:);n.W2(:);n.b2(:);n.w(:)];
end

function n=unpack_network(x,h,g,d)
if nargin<4,d=2;end
j=0;n.W1=reshape(x(j+1:j+h*d),h,d);j=j+h*d;
n.b1=x(j+1:j+h);j=j+h;n.W2=reshape(x(j+1:j+g*h),g,h);j=j+g*h;
n.b2=x(j+1:j+g);j=j+g;n.w=x(j+1:end);
assert(ismember(numel(n.w),[g g+3]),'pi17:network','Invalid network output layout');
end

function [x,f,out]=bfgs_fd(fun,x,maxIter,tol)
% Base-MATLAB BFGS + central differences + Armijo line search.
started=tic; evaluations=1+2*numel(x);
f=fun(x); g=fd_gradient(fun,x); H=eye(numel(x)); flag=0; trace=zeros(maxIter,3);
for it=1:maxIter
    if v17_deadline('expired'), flag=-3; break; end
    trace(it,:)=[f norm(g,Inf) 0];
    if norm(g,Inf)<tol, flag=1; break; end
    d=-H*g; if g'*d>=0 || any(~isfinite(d)), H=eye(numel(x)); d=-g; end
    if norm(d)>2, d=d*2/norm(d); end
    step=1; accepted=false;
    for ls=1:20
        candidate=x+step*d; nf=fun(candidate); evaluations=evaluations+1;
        if isfinite(nf) && nf<=f+1e-4*step*(g'*d), accepted=true; break; end
        step=step/2;
    end
    if ~accepted, flag=-2; break; end
    ng=fd_gradient(fun,candidate); evaluations=evaluations+2*numel(x); s=candidate-x; y=ng-g; sy=s'*y;
    if sy>1e-10*norm(s)*max(norm(y),eps)
        V=eye(numel(x))-s*y'/sy; H=V*H*V'+s*s'/sy;
    else, H=eye(numel(x)); end
    x=candidate; f=nf; g=ng; trace(it,3)=step;
end
if norm(g,Inf)<tol, flag=1; end % Check the final accepted update too.
out=struct('exitflag',flag,'iterations',it,'gradientNorm',norm(g,Inf),'trace',trace(1:it,:),'functionEvaluations',evaluations,'elapsedSeconds',toc(started));
end

function g=fd_gradient(fun,x)
g=zeros(size(x));
for j=1:numel(x)
    h=2e-5*max(1,abs(x(j))); p=x; m=x; p(j)=p(j)+h; m(j)=m(j)-h;
    g(j)=(fun(p)-fun(m))/(2*h);
end
end

function [score,unitScores]=forecast_score(M,val,Q,c,eid)
% Identical causal-prefix log-RUL criterion for every selectable model.
old=rng; cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
cv=c; cv.particles=c.validationParticles; cv.forecastPaths=c.validationPaths;
unitScores=nan(numel(val),1); counts=zeros(numel(val),1);
if v17_flag(c,'parallelForecasts') && isfield(c,'activeGradientWorkers') && c.activeGradientWorkers>0 && numel(val)>1 && ~strcmp(M.kind,'lstm')
    % Per-unit seeds make the parallel result identical to the serial loop.
    cv.activeGradientWorkers=0;
    parfor (i=1:numel(val),c.activeGradientWorkers)
        [unitScores(i),counts(i)]=v17_unit_validation_error(M,val(i),i,Q,cv,eid);
    end
else
    for i=1:numel(val), [unitScores(i),counts(i)]=v17_unit_validation_error(M,val(i),i,Q,cv,eid); end
end
assert(sum(counts)>0,'pi17:validation','Independent validation failure labels required for RUL model selection');
score=mean(unitScores(isfinite(unitScores)));
end

function [score,count]=v17_unit_validation_error(M,U,i,Q,cv,eid)
c=cv; errors=[]; score=NaN; count=0;
if ~U.failureObserved, return; end
[ks,zs]=origin_nodes(U,c);
for iz=1:numel(ks)
    z=zs(iz); k=ks(iz); H=causal_prefix(U,k);
    rng(c.seed+eid*100000+i*100+z); P=model_posterior(M,H,cv);
    for p=1:numel(c.policies)
        rng(c.seed+eid*100000+i*100+z+p*1000); bank=v17_score_bank(H,c.policies{p},Q,cv,cv.forecastPaths,eid);
        rng(c.seed+eid*100000+i*100+z+9000); [samples,fi]=model_samples(M,H,P,bank,cv);
        pred=v17_quantile(samples,fi,.5); truth=U.failureTime-H.t(end);
        if isfinite(pred)
            errors(end+1)= (log1p(pred/c.relativeFloorHours)-log1p(truth/c.relativeFloorHours))^2; %#ok<AGROW>
        else
            % A censored median remains Inf in exported forecasts. Selection
            % uses a declared conservative penalty, never a fabricated death.
            errors(end+1)= (log1p(c.forecastHorizonHours/c.relativeFloorHours)- ...
                log1p(truth/c.relativeFloorHours))^2+1; %#ok<AGROW>
        end
    end
end
count=numel(errors); if count>0, score=mean(errors); end
end

function M=fit_pinn(train,val,Q,base,c,eid)
if c.profileObserved, M=v17_fit_pinn(train,val,Q,base,c,eid); return; end
% Positive integrated neural trajectory plus physical ODE collocation. TRAIN
% sensor likelihood analytically integrates B. Same network forecasts RUL.
rng(c.seed+eid*10000+400); n=numel(train); h=c.pinnHidden1; g=c.pinnHidden2;
start=[log(base.k/c.nominalRate);base.p;base.betaT;log(base.a+.01); ...
    base.trainingEta(1:max(n-1,0));pack_network(init_network(h,g,5))];
free=1:numel(start);
if c.fatigueLinearDamage, free(free==4)=[]; end
if ~c.fitLoadExponent, free(free==2)=[]; end
if ~c.fitTemperatureCoefficient, free(free==3)=[]; end
best=Inf; rows=cell(0,6); M=base;
for st=1:c.pinnStarts
    x=start; if st>1, x(free)=x(free)+.05*randn(numel(free),1); end
    fun=@(v)pinn_free_objective(v,x,free,base,train,c);
    [v,loss,opt]=robust_bfgs(fun,x(free),c.pinnIterations,c); x(free)=v;
    candidate=decode_pinn(x,base,n,c); candidate.kind='pinn'; candidate.config=c;
    candidate.pinnTrace=opt.trace; candidate.pinnX=x;
    if c.jointRefineEmission, candidate=observed_emission_update(candidate,train,c); end
    opt.phaseGradientNorm=opt.gradientNorm; opt.phaseExitflag=opt.exitflag;
    finalFun=@(v)pinn_free_objective(v,x,free,candidate,train,c);
    opt.gradientNorm=norm(fd_gradient(finalFun,x(free)),Inf);
    if opt.gradientNorm>=c.gradientTolerance && opt.exitflag>0, opt.exitflag=0; opt.status='emission_changed_after_phase_convergence'; end
    [~,rmsODE]=pinn_objective(x,base,train,{},c);
    score=forecast_score(candidate,val,Q,c,eid);
    rows(end+1,:)={st,loss,score,opt.exitflag,rmsODE,opt.gradientNorm}; %#ok<AGROW>
    fprintf('  inverse PINN start %d: VAL %.5g | ODE RMS %.4g | flag %d/grad %.3g (%s)\n', ...
        st,score,rmsODE,opt.exitflag,opt.gradientNorm,opt.status);
    if score<best, best=score; M=candidate; M.optimization=opt; M.optimization.relativeODEResidualRMS=rmsODE; end
end
M.label='Inverse_PINN'; M.available=true; M.validationScore=best;
M.selection=cell2table(rows,'VariableNames',{'start','objective','causalValidationLoss','exitflag','relativeODEResidualRMS','gradientNorm'});
end

function f=pinn_free_objective(v,x,free,base,train,c)
x(free)=v; f=pinn_objective(x,base,train,{},c);
end

function M=decode_pinn(x,base,n,c)
M=base; M.k=c.nominalRate*exp(max(-5,min(5,x(1)))); M.p=max(1,min(5,x(2)));
M.betaT=max(-.6,min(.8,x(3))); M.a=max(0,min(3,exp(x(4))-.01));
if n>1, eta=[x(5:3+n);-sum(x(5:3+n))]; else, eta=0; end
M.trainingEta=eta; % Exact centering; the objective penalizes out-of-support effects.
M.pinnNN=unpack_network(x(4+n:end),c.pinnHidden1,c.pinnHidden2,5);
M.bound=0; M.projection=[];
if c.fatigueLinearDamage, M.a=0; end
if ~c.fitLoadExponent, M.p=c.nominalLoadExponent; end
if ~c.fitTemperatureCoefficient, M.betaT=c.nominalTempCoefficient; end
end

function [D,q,E]=pinn_trajectory(M,H,eta,c)
if isfield(c,'fastPinnClock') && ~c.fastPinnClock
 [D,q,E]=v17_scalar_pinn_trajectory_reference(M,H,eta,c);
else,[D,q,E]=v17_pinn_vector_trajectory(M,H,eta,c);end
end

function [rate,exposureRate]=pinn_rate(M,E,time,u,eta,c)
% Positive neural trajectory derivative. Physical parameters are inferred in
% the ODE collocation objective. This identical function is called in forecast.
if isscalar(time), time=repmat(time,numel(E),1); end
Z=[E(:)/c.Dcrit time(:)/500 ...
    tanh(log(max(u(:,1),1e-8))/c.loadFeatureScale) ...
    tanh(log(max(u(:,2),1e-8))/c.speedFeatureScale) tanh(u(:,3)/c.temperatureFeatureScale)];
N=M.pinnNN;
h1=tanh(Z*N.W1'+N.b1'); h2=tanh(h1*N.W2'+N.b2');
multiplier=exp(1.5*tanh(h2*N.w));
exposureRate=c.nominalRate*u(:,1).^c.nominalLoadExponent.*u(:,2).* ...
    exp(c.nominalTempCoefficient*u(:,3));
rate=exposureRate.*exp(eta(:)).*multiplier;
end

function [loss,rmsODE]=pinn_objective(x,base,train,unused,c) %#ok<INUSD>
M=decode_pinn(x,base,numel(train),c); nll=0; count=0; ode=[]; event=[];
for i=1:numel(train)
    U=train(i); [D,q]=pinn_trajectory(M,U,M.trainingEta(i),c);
    nll=nll+observed_kalman(M,U,D,c); count=count+sum(isfinite(U.y(:)))+sum(isfinite(U.inspection));
    if U.failureObserved
        event=[event;(D(end)-c.Dcrit)/c.terminalDamageTolerance; ...
            sqrt(10)*max(D(1:end-1)-c.Dcrit,0)/c.terminalDamageTolerance]; %#ok<AGROW>
    end
    target=physics_rate(M,U.u).*exp(M.trainingEta(i)).*(1+M.a*D);
    % Log-rate residual is dimensionless, symmetric and numerically stable.
    active=q>0 & target>0;
    ode=[ode;log(q(active)./target(active))]; %#ok<AGROW>
end
rmsODE=sqrt(mean(ode.^2));
prior=(log(M.k/c.nominalRate)/c.rateLogPriorSD)^2+ ...
    ((M.p-c.nominalLoadExponent)/c.exponentPriorSD)^2+ ...
    ((M.betaT-c.nominalTempCoefficient)/c.tempPriorSD)^2+sum((M.trainingEta/base.unitSD).^2);
barrier=100*sum(max(abs(M.trainingEta)-c.unitEffectMax,0).^2);
loss=(nll+.5*sum(event.^2)+.5*prior)/max(count,1)+ ...
    c.pinnPhysicsWeight*mean(ode.^2)+c.networkPenalty*sum(pack_network(M.pinnNN).^2)+barrier;
if ~isfinite(loss), loss=1e30; end
end

function P=inverse_prefix(M,H,c)
eta=linspace(-c.unitEffectMax,c.unitEffectMax,c.etaGridPoints)';
[D,~,E]=pinn_trajectory(M,H,eta,c); [nll,KF]=observed_kalman(M,H,D,c,false);
lp=-.5*(eta'/M.unitSD).^2; lp=lp-logsumexp_base(lp); lw=lp-nll;
lw(~all(D<c.Dcrit,1))=-Inf;
assert(any(isfinite(lw)),'pi17:pinn','PINN has no surviving prefix; inspect physics/trajectory fit.');
w=normalized_weights(lw'); ix=systematic_resample(w,c.particles); n=c.particles;
K=numel(H.t); filtered=zeros(K,3); ess=zeros(K,1); eventMass=zeros(K,1);
for k=1:K
    prior=lp; if k>1, prior=prior-KF.cumulativeNLL(k-1,:); prior(any(D(1:k-1,:)>=c.Dcrit,1))=-Inf; end
    wp=normalized_weights(prior'); live=D(k,:)'<c.Dcrit; eventMass(k)=sum(wp(live));
    current=lp-KF.cumulativeNLL(k,:); current(~live')=-Inf; ww=normalized_weights(current');
    filtered(k,:)=[D(k,:)*ww KF.mean(k,:)*ww eta'*ww]; ess(k)=1/sum(ww.^2);
end
P=struct('D',D(end,ix)','B',KF.mean(end,ix)'+sqrt(max(KF.variance(end),0))*randn(n,1), ...
    'eta',eta(ix),'weights',ones(n,1)/n,'exposure',E(end,ix)', ...
    'filteredMean',filtered, ...
    'ESS',ess,'etaAcceptance',NaN, ...
    'distinctRateParticles',numel(unique(eta(ix))),'eventMass',eventMass, ...
    'cdfUnderflowParticles',0,'etaGrid',eta,'etaWeights',w, ...
    'status','PINN conditional eta posterior with B integrated; global parameters plug-in');
end

function M=fit_lstm(train,val,c,eid)
M=struct('kind','lstm','label','LSTM','available',false,'status','disabled','optimization',struct('status','disabled'));
if ~c.enableLSTM,return;end
if exist('trainNetwork','file')~=2 || ~license('test','Neural_Network_Toolbox')
 M.status='unavailable: Deep Learning Toolbox';M.optimization.status=M.status;
 assert(~c.requireLSTM,'pi17:lstm','Actual LSTM requires Deep Learning Toolbox');return;
end
M.scale=fit_sensor_scaling(train);
if isfield(c,'runtimeDutyModel'),M.dutyModel=c.runtimeDutyModel;else,M.dutyModel=fit_duty_model(train);end
ct=c;ct.originFractions=c.lstmTrainingFractions;ct.originHours=c.lstmTrainingHours;[X,Y]=lstm_examples(train,M,ct);
cv=c;cv.originFractions=c.lstmValidationFractions;[XV,YV]=lstm_examples(val,M,cv);
assert(~isempty(Y)&&~isempty(YV),'pi17:lstm','Independent labelled TRAIN and VAL units required');
best=Inf;rows=cell(0,5);archive={};
for hidden=c.lstmHidden
 for lr=c.lstmLearningRates
  for start=1:c.lstmStarts
   v17_deadline('check');rng(c.seed+eid*10000+800+hidden*31+round(lr*1e6)+start,'twister');
   tag=sprintf('lstm_h%03d_lr%04d_start%02d',hidden,round(lr*1e6),start);path=v17_candidate_path(c,tag);
   if ~isempty(path)&&isfile(path)
    S=load(path,'candidate','info','score');candidate=S.candidate;info=S.info;score=S.score;
   else
    layers=[sequenceInputLayer(size(X{1},1),'Normalization','none');lstmLayer(hidden,'OutputMode','last'); ...
     fullyConnectedLayer(hidden);reluLayer;fullyConnectedLayer(1);regressionLayer];
    options=trainingOptions('adam','MaxEpochs',c.lstmEpochs,'MiniBatchSize',c.lstmBatch, ...
     'InitialLearnRate',lr,'Shuffle','every-epoch','GradientThreshold',1,'ExecutionEnvironment','cpu', ...
     'SequencePaddingDirection','left','Verbose',false,'Plots','none','ValidationData',{XV,YV}, ...
     'ValidationFrequency',max(1,ceil(numel(Y)/c.lstmBatch)),'ValidationPatience',c.lstmValidationPatience, ...
     'OutputNetwork','best-validation-loss');
    [net,info]=trainNetwork(X,Y,layers,options);candidate=M;candidate.net=net;candidate.available=true;
    score=forecast_score(candidate,val,M.dutyModel,c,eid);
    if ~isempty(path),v17_save(path,struct('candidate',candidate,'info',info,'score',score));end
   end
   candidate.hidden=hidden;candidate.learningRate=lr;candidate.selectedStart=start;candidate.trainingInfo=info;candidate.available=true;
   candidate.optimization=struct('status','validation-selected actual LSTM');archive{end+1}=candidate; %#ok<AGROW>
   rows(end+1,:)={hidden,score,numel(info.TrainingLoss),lr,start}; %#ok<AGROW>
   if score<best,best=score;M.net=candidate.net;M.trainingInfo=info;M.hidden=hidden;M.learningRate=lr;M.selectedStart=start;end
   fprintf('  LSTM hidden %d, lr %.4g, start %d, causal VAL %.6g.\n',hidden,lr,start,score);
  end
 end
end
M.policyArchive=archive;M.available=true;M.status='trained';M.selection=cell2table(rows,'VariableNames',{'hiddenUnits','causalValidationLoss','iterations','learningRate','start'});
M.optimization=struct('status','validation-selected actual LSTM; no mechanistic stationarity claim','validationLogRULLoss',best, ...
 'independentTrainingUnits',numel(train),'trainingExamples',numel(Y));
end

function [X,Y]=lstm_examples(units,M,c)
old=rng; cleanup=onCleanup(@()rng(old)); rng(c.seed+456); %#ok<NASGU>
X={}; Y=[];
for i=1:numel(units)
    U=units(i); if ~U.failureObserved, continue; end
    [ks,~]=origin_nodes(U,c);
    for k=ks
        H=causal_prefix(U,k);
        for p=1:numel(c.policies)
            bank=future_bank(H,c.policies{p},M.dutyModel,c,1);
            X{end+1,1}=lstm_sequence(H,bank,M.scale,c); %#ok<AGROW>
            Y(end+1,1)=log1p((U.failureTime-H.t(end))/100); %#ok<AGROW>
        end
    end
end
end

function X=lstm_sequence(H,bank,S,c)
% History only: future-duty descriptors condition every past token. No 200-token
% sensor-free tail can overwrite the final recurrent history representation.
y=(H.y-S.mean)./S.sd; mask=isfinite(y); y(~mask)=0;
ins=H.inspection/c.Dcrit; im=isfinite(ins); ins(~im)=0;
up=([log(max(H.u(:,1:2),1e-8)) H.u(:,3)]-S.uMean)./S.uSD;
uf=reshape(bank.u(:,1,:),numel(bank.dt),3); n=numel(bank.dt); descriptor=[];
edges=round(linspace(0,n,c.lstmDutyBins+1));
for j=1:c.lstmDutyBins
    ix=(edges(j)+1):edges(j+1); if isempty(ix), ix=min(n,edges(j)+1); end
    z=([log(max(uf(ix,1:2),1e-8)) uf(ix,3)]-S.uMean)./S.uSD;
    descriptor=[descriptor mean(z,1) mean(uf(ix,1).^c.nominalLoadExponent.*uf(ix,2))]; %#ok<AGROW>
end
history=[y double(mask) ins double(im) up H.t/c.forecastHorizonHours ...
    repmat(descriptor,numel(H.t),1)];
X=single(history'); assert(all(isfinite(X(:))),'pi17:lstm','Nonfinite LSTM input');
end

function H=causal_prefix(U,k)
assert(k>=1 && k<=numel(U.t),'pi17:prefix','Invalid origin');
H=struct('id',U.id,'t',U.t(1:k),'u',U.u(1:k,:),'y',U.y(1:k,:), ...
    'inspection',U.inspection(1:k),'initialD',U.initialD,'plan',[], ...
    'failureObserved',false,'failureTime',NaN);
if ~isempty(U.plan) && U.plan.issuedAt<=H.t(end), H.plan=U.plan; end
end

function P=model_posterior(M,H,c)
if isfield(M,'stackPartner') && isfield(M,'stackWeight'),P=v17_stack_posterior(M,H,c);return;end
if isfield(M,'populationMembers') && ~isempty(M.populationMembers),P=v17_population_posterior(M,H,c);return;end
if strcmp(M.kind,'smc'), P=v17_smc_prefix(M,H,c); return; end
if isfield(M,'processKappa') && M.processKappa>0 && ~ismember(M.kind,{'lstm','pinn'}),P=v17_noisy_prefix(M,H,c);return;end
if c.profileObserved && ~strcmp(M.kind,'lstm'), P=v17_grid_prefix(M,H,c); return; end
if strcmp(M.kind,'lstm'), P=[];
elseif strcmp(M.kind,'pinn'), P=inverse_prefix(M,H,c);
else, P=particle_filter(M,H,c,false,c.particles); end
end

function [samples,info]=model_samples(M,H,P,bank,c)
if isfield(M,'stackPartner') && isfield(M,'stackWeight'),[samples,info]=v17_stack_samples(M,H,P,bank,c);return;end
if isfield(M,'populationMembers') && ~isempty(M.populationMembers),[samples,info]=v17_population_samples(M,H,P,bank,c);return;end
if c.exactPlanned && strcmp(bank.policy,'planned') && ~strcmp(M.kind,'lstm')
    bank.u=repmat(bank.u(:,1,:),1,numel(P.eta),1); cc=c; cc.forceGridPassage=true;
    if strcmp(M.kind,'pinn'), [samples,info]=pinn_first_passage(M,P,bank,cc);
    else, [samples,info]=first_passage(M,P,bank,cc); end
    info.sampleWeights=P.weights; return;
end
if strcmp(M.kind,'lstm')
    seq=cell(size(bank.u,2),1);
    for j=1:numel(seq), b=bank; b.u=bank.u(:,j,:); seq{j}=lstm_sequence(H,b,M.scale,c); end
    pred=predict(M.net,seq,'MiniBatchSize',c.lstmBatch,'ExecutionEnvironment','cpu','SequencePaddingDirection','left');
    samples=max(0,100*expm1(double(pred(:)))); info=struct();
elseif strcmp(M.kind,'pinn'), [samples,info]=pinn_first_passage(M,P,bank,c);
else, [samples,info]=first_passage(M,P,bank,c); end
end

function [samples,info]=first_passage(M,P,bank,c)
n=size(bank.u,2);if c.forceGridPassage,ix=(1:n)';else,ix=systematic_resample(P.weights,n);end
D=P.D(ix);B=P.B(ix);eta=P.eta(ix);samples=inf(n,1);samples(D>=c.Dcrit)=0;
elapsed=0;sq=0;count=0;maxrho=0;outsideCount=0;
kp=0;if isfield(M,'processKappa') && ~isempty(M.processKappa),kp=M.processKappa;end
for k=1:numel(bank.dt)
 ns=max(1,ceil(bank.dt(k)/c.integrationStepHours));h=bank.dt(k)/ns;u=reshape(bank.u(k,:,:),n,3);
 for s=1:ns
  live=isinf(samples);if ~any(live),break;end
  [rho,outside]=discrepancy(M,D,B,u);base=physics_rate(M,u).*exp(eta);
  if M.kappa==0
   r=base.*exp(rho).*(1+M.a*D);mid=D+.5*h*r;
   [rhoMid,outsideMid]=discrepancy(M,mid,B,u);
   dx=h*base.*exp(rhoMid).*(1+M.a*mid);
   if kp>0
    % v17 gamma damage increments: same midpoint mean, variance kp*rate*mean.
    dx=kp*(dx/h).*randg(h/kp,n,1);
   end
   cap=c.Dcrit-D;hit=live & dx>=cap & dx>0;
   samples(hit)=elapsed+h*max(0,cap(hit))./dx(hit);D=D+dx;
   rho=rhoMid;outside=outside|outsideMid;
  else
   % Legacy gamma exposure branch, not the default deterministic fatigue model.
   dx=M.kappa*base.*exp(rho).*randg(h/M.kappa,n,1);x=exposure(D,M.a);cap=exposure(c.Dcrit,M.a)-x;
   hit=live & dx>=cap & dx>0;samples(hit)=elapsed+h*max(0,cap(hit))./dx(hit);D=damage_from_exposure(x+dx,M.a);
  end
  sq=sq+sum(rho(live).^2);count=count+sum(live);maxrho=max(maxrho,max(abs(rho(live))));
  outsideCount=outsideCount+sum(outside(live));elapsed=elapsed+h;
 end
 if ~any(isinf(samples)),break;end
end
info=struct('rhoRMS',sqrt(sq/max(count,1)),'rhoMaxAbs',maxrho,'outOfSupportFraction',outsideCount/max(count,1),'censoredFraction',mean(isinf(samples)));
end

function [T,F,A]=predict_group(units,ids,models,names,Q,c,eid,evidence,diagnose)
if c.policySpecificSelection,[T,F,A]=v17_predict_policy_group(units,ids,models,names,Q,c,eid,evidence,diagnose);return;end
old=rng;cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
rows=cell(0,33);fr=cell(0,12);ar=cell(0,9);
for j=1:numel(ids)
 U=units(ids(j));[ks,zs]=origin_nodes(U,c);
 for iz=1:numel(ks)
  z=zs(iz);H=causal_prefix(U,ks(iz));seed=c.seed+eid*1000000+ids(j)*1000+z*10;post=cell(1,numel(models));
  for m=setdiff(1:numel(models),3)
   rng(seed,'twister');post{m}=model_posterior(models{m},H,c);
   if diagnose
    P=post{m};fr(end+1,:)={eid,U.id,names{m},z,H.t(end),min(P.ESS),mean(P.ESS),P.etaAcceptance,P.distinctRateParticles,min(P.eventMass),sum(P.D>=c.Dcrit),P.cdfUnderflowParticles}; %#ok<AGROW>
   end
  end
  for pol=1:numel(c.policies)
   R=c.forecastReplicates;if strcmp(c.policies{pol},'planned'),R=1;end
   banks=cell(1,R);
   for r=1:R,rng(seed+pol+10000*(r-1),'twister');banks{r}=future_bank(H,c.policies{pol},Q,c,c.forecastPaths);end
   for m=1:numel(models)
    pred=NaN;lo=NaN;hi=NaN;cp=NaN;d=NaN;b=NaN;rr=NaN;rm=NaN;os=NaN;safe=NaN;p24=NaN;p48=NaN;dsd=NaN;esd=NaN;ratio=NaN;warn=false;gc=NaN;gp=NaN;mc=NaN;
    status='unavailable';
    if models{m}.available
     [samples,fi]=v17_forecast_distribution(models{m},H,post{m},banks,c,seed+pol+100);
     pred=v17_quantile(samples,fi,.5);lo=v17_quantile(samples,fi,c.intervalAlpha/2);hi=v17_quantile(samples,fi,1-c.intervalAlpha/2);
     safe=v17_quantile(samples,fi,c.conservativeQuantile);p24=sum(fi.sampleWeights(samples<=24));p48=sum(fi.sampleWeights(samples<=48));
     cp=sum(fi.sampleWeights(isinf(samples)));mc=fi.replicateMedianSD_h;
     if m==3,status='LSTM conditional duty spread; raw event probabilities not calibrated';
     else
      P=post{m};d=P.weights'*P.D;b=P.weights'*P.B;
      dsd=sqrt(max(0,P.weights'*(P.D-d).^2));em=P.weights'*P.eta;esd=sqrt(max(0,P.weights'*(P.eta-em).^2));
      ratio=dsd/max(c.Dcrit-d,eps);warn=ratio>=c.posteriorInformationWarningRatio;
      if isfield(P,'gridConverged'),gc=P.gridConverged;gp=P.gridPointsUsed;end
      rr=fi.rhoRMS;rm=fi.rhoMaxAbs;os=fi.outOfSupportFraction;status='median first passage; conditional plug-in global parameters';
      if isinf(pred),status='right_censored_median';end
     end
     if m==1 && diagnose
      off=models{1};off.bound=0;[ss,ii]=v17_forecast_distribution(off,H,post{1},banks,c,seed+pol+100);
      offPred=v17_quantile(ss,ii,.5);truth=NaN;if U.failureObserved,truth=U.failureTime-H.t(end);end
      ar(end+1,:)={eid,U.id,c.policies{pol},z,H.t(end),truth,pred,offPred,pred-offPred}; %#ok<AGROW>
     end
    end
    truth=NaN;fraction=NaN;if U.failureObserved,truth=U.failureTime-H.t(end);fraction=H.t(end)/U.failureTime;end
    rows(end+1,:)={eid,evidence,U.id,names{m},c.policies{pol},z,H.t(end),fraction,truth,pred,lo,hi,NaN,NaN,cp,d,b,status,models{m}.available,rr,rm,os, ...
     safe,p24,p48,dsd,esd,ratio,warn,gc,gp,R,mc}; %#ok<AGROW>
   end
  end
 end
 fprintf('  Forecasted %d/%d units, %d prefixes, %d duty policies; uncertainty warnings retained.\n',j,numel(ids),numel(ks),numel(c.policies));
end

T=cell2table(rows,'VariableNames',{'experiment','evidence','unit','method','policy','originIndex','origin_h','lifeFraction','trueRUL_h','predictedRUL_h', ...
 'rawLower_h','rawUpper_h','lower_h','upper_h','censoredPathFraction','estimatedD','estimatedB','status','available','forecastRhoRMS','forecastRhoMaxAbs','residualOutOfSupportFraction', ...
 'conservativeRUL_h','rawFailureProbability24h','rawFailureProbability48h','estimatedDSD','estimatedEtaSD','damageUncertaintyToMargin','originDamageUncertain','posteriorGridConverged','posteriorGridPoints','dutyReplicates','replicateMedianSD_h'});
F=cell2table(fr,'VariableNames',{'experiment','unit','method','originIndex','origin_h','minimumESS','meanESS','etaAcceptance','distinctEtaParticles','minimumEventMass','liveFailedParticles','CDFunderflowParticles'});
A=cell2table(ar,'VariableNames',{'experiment','unit','policy','originIndex','origin_h','trueRUL_h','residualOnRUL_h','residualOffRUL_h','difference_h'});
end

function I=v17_legacy_identifiability(M,train,c,eid)
if strcmp(c.architecture,'observed'), I=observed_identifiability(M,train,c,eid); return; end
rng(c.seed+eid*10000+999); S=smooth_training(M,train,c);
N=numel(S.D0); n=max(S.unit); z=encode_population(M,c); nw=pack_network(M.nn);
x=[z(1:8);zeros(max(n-1,0),1);nw]; names={'logRate','loadExponent','temperatureCoefficient', ...
    'logAgingPlusFloor','logTau','BloadGain','BspeedGain','BtemperatureGain'};
for j=1:n-1, names{end+1}=sprintf('centeredUnit_%d',j); end %#ok<AGROW>
for j=1:numel(nw), names{end+1}=sprintf('network_%d',j); end %#ok<AGROW>
J=zeros(2*N,numel(x));
for j=1:numel(x)
    h=c.jacobianStep*max(1,abs(x(j))); p=x; m=x; p(j)=p(j)+h; m(j)=m(j)-h;
    J(:,j)=(conditional_residual(p,M,S,c)-conditional_residual(m,M,S,c))/(2*h);
end
norms=sqrt(sum(J.^2,1)); active=norms>c.rankTolerance*max(norms);
scaled=J(:,active)./max(norms(active),eps); ss=svd(scaled,'econ');
rankActive=sum(ss>c.rankTolerance*max(ss)); corrFull=nan(sum(active));
if rankActive==sum(active)
    C=pinv(scaled'*scaled); sd=sqrt(diag(C)); corrFull=C./(sd*sd');
end
nu=J(:,5:end); conditional=J(:,1:4)-nu*(pinv(nu)*J(:,1:4));
sp=svd(conditional,'econ'); physicsRank=sum(sp>c.rankTolerance*max(svd(J(:,1:4),'econ')));
physicsCorr=nan(4);
if physicsRank==4
    V=inv(conditional'*conditional); d=sqrt(diag(V)); physicsCorr=V./(d*d');
end
cosines=(J'*J)./max(norms'*norms,eps); pairs=cell(0,3);
for i=1:numel(x)
    for j=i+1:numel(x)
        if norms(i)>0 && norms(j)>0 && abs(cosines(i,j))>.95
            pairs(end+1,:)={names{i},names{j},cosines(i,j)}; %#ok<AGROW>
        end
    end
end
rankEmission=2; minEmission=Inf;
for j=round(linspace(1,N,min(N,100)))
    H=[M.C(:,2)+2*S.D0(j)*M.C(:,7) M.C(:,3)]./M.sensorSD'; sh=svd(H);
    rankEmission=min(rankEmission,sum(sh>c.rankTolerance*max(sh))); minEmission=min(minEmission,min(sh));
end
profiles=profile_checks(M,S,c); rho=discrepancy(M,S.D0,S.B0,S.u);
unitMeans=accumarray(S.unit,rho,[],@mean); G=physical_scores(M,S.D0,S.u,c);
overlap=G'*rho/max(numel(rho),1);
I=struct('names',{names},'parameters',numel(x),'activeParameters',sum(active),'activeRank',rankActive, ...
    'activeMask',active,'singularValues',ss,'Jacobian',J,'informationSurrogate',J'*J, ...
    'activeCorrelations',corrFull,'physicsConditionalRank',physicsRank,'physicsCorrelations',physicsCorr, ...
    'physicsConditionalSingularValues',sp,'sensitivityCosines',cosines, ...
    'confoundedPairs',cell2table(pairs,'VariableNames',{'parameter1','parameter2','sensitivityCosine'}), ...
    'minimumEmissionRank',rankEmission,'minimumEmissionSingularValue',minEmission, ...
    'rhoRMS',sqrt(mean(rho.^2)),'rhoMaxAbs',max(abs(rho)),'physicalScoreOverlap',overlap, ...
    'unitMeanResidualRMS',sqrt(mean(unitMeans.^2)),'profiles',profiles,'smoothingSummary',S, ...
    'note','Conditional standardized-transition innovation Jacobian, latent paths/emission fixed, priors excluded. Not marginal observed-data Fisher information.');
I.referencePhysicalOverlap=0;
if M.bound>0, I.referencePhysicalOverlap=M.projection.referenceOrthogonality; end
end

function r=conditional_residual(x,M,S,c)
n=max(S.unit); z=encode_population(M,c); z(1:8)=x(1:8); mm=decode_population(z,M,c);
eta=S.eta;
if n>1
    offsets=[x(9:7+n);-sum(x(9:7+n))]; eta=eta+offsets(S.unit);
end
nn=x(8+n:end); mm.nn=unpack_network(nn,c.hidden1,c.hidden2,5);
if mm.bound>0, mm=project_network(mm,c); end
mu=physics_rate(mm,S.u).*exp(eta+discrepancy(mm,S.D0,S.B0,S.u)).*S.dt;
dx=exposure(S.D1,mm.a)-exposure(S.D0,mm.a);
rd=(dx-mu)./max(sqrt(mm.kappa*S.dt).*mu./S.dt,1e-10);
phi=exp(-S.dt/mm.tau); target=[log(max(S.u(:,1:2),1e-8)) S.u(:,3)]*mm.gamma;
rb=(S.B1-phi.*S.B0-(1-phi).*target)./(mm.sigmaB*sqrt(max(1-phi.^2,1e-10)));
r=[rd;rb]/sqrt(numel(rd));
end

function T=profile_checks(M,S,c)
z=encode_population(M,c); rows=cell(0,7);
for coordinate=[1 2 4]
    values=z(coordinate)+linspace(-.35,.35,c.profilePoints);
    for value=values
        fixed=z; fixed(coordinate)=value; free=setdiff(1:numel(z),coordinate);
        fun=@(v) profile_objective(v,fixed,free,M,S,c);
        [v,loss,out]=bfgs_fd(fun,fixed(free),c.profileIterations,c.gradientTolerance);
        fixed(free)=v; mm=decode_population(fixed,M,c);
        physical=[mm.k mm.p mm.a]; ii=find([1 2 4]==coordinate);
        rows(end+1,:)={coordinate,value,physical(ii),loss,out.exitflag,out.iterations,out.gradientNorm}; %#ok<AGROW>
    end
end
T=cell2table(rows,'VariableNames',{'coordinate','transformedValue','physicalValue', ...
    'penalizedUnitMarginalNLLPerObservation','exitflag','iterations','gradientNorm'});
end

function loss=profile_objective(v,z,free,M,S,c)
z(free)=v; mm=decode_population(z,M,c); loss=population_objective(mm,S,c);
end

function print_diagnostics(E,c)
if strcmp(c.architecture,'observed'), print_observed_diagnostics(E,c); return; end
M=E.models{1}; P=E.models{4}; I=E.identifiability;
fprintf('\nPHYSICAL/OBSERVATION PARAMETERS (rates in h^-1 for normalized duty):\n');
disp(table({'rate k';'load exponent';'temperature beta';'aging a';'B relaxation tau'; ...
    'gamma kappa (h)';'B stationary SD';'unit SD'}, ...
    [M.k;M.p;M.betaT;M.a;M.tau;M.kappa;M.sigmaB;M.unitSD], ...
    [P.k;P.p;P.betaT;P.a;P.tau;P.kappa;P.sigmaB;P.unitSD], ...
    'VariableNames',{'parameter','PI_DSSDM','Physics_SSM'}));
fprintf('Sensor SD: %s | B gains: %s | fixed emission gauge C(2,B)=%.3g\n', ...
    mat2str(M.sensorSD,4),mat2str(M.gamma',4),M.C(2,3));
fprintf('Emission C: sensor rows, columns [intercept D B logLoad logSpeed T D^2]:\n'); disp(M.C);
fprintf('Selected physics checkpoint EM %d / M-step flag %d; EM-process stabilized %d.\n', ...
    P.optimization.selectedIteration,P.optimization.selectedMStepExitflag,P.optimization.stabilized);
fprintf('Physics identical across primary/PF: %d. Sensor-noise floor hits: %d.\n', ...
    isequal([M.k M.p M.betaT M.a],[P.k P.p P.betaT P.a]),sum(M.sensorSD<=c.sensorFloor+1e-8));
fprintf('IDENTIFIABILITY: active transition-Jacobian rank %d/%d; conditional physics %d/4; emission %d/2.\n', ...
    I.activeRank,I.activeParameters,I.physicsConditionalRank,I.minimumEmissionRank);
fprintf('%s\n',I.note); fprintf('Conditional physical parameter correlations:\n'); disp(I.physicsCorrelations);
fprintf('Confounded sensitivity pairs >0.95: %d. Conditional profile successes: %d/%d.\n', ...
    height(I.confoundedPairs),sum(I.profiles.exitflag>0),height(I.profiles));
fprintf('RESIDUAL: bound %.3g | post-fit smoothed TRAIN rho RMS %.5g/max %.5g\n',M.bound,I.rhoRMS,I.rhoMaxAbs);
fprintf('Exact reference projection overlap %.3g; new smoothed-state score overlap %.3g.\n', ...
    I.referencePhysicalOverlap,norm(I.physicalScoreOverlap));
fprintf('Unit mean-residual RMS %.5g (penalized; not claimed exactly orthogonal).\n',I.unitMeanResidualRMS);
if M.bound==0, fprintf('DIAGNOSIS: causal validation selected physics-only. No learned-correction benefit established.\n'); end
fprintf('Primary selection table:\n'); disp(M.selection);
if ~isempty(E.filterDiagnostics)
    F=E.filterDiagnostics; fprintf('FILTER: impossible live particles %d; CDF underflow importance proposals %d; mean eta MH %.1f%%.\n', ...
        sum(F.liveFailedParticles),sum(F.CDFunderflowParticles),100*mean(F.etaAcceptance));
    if any(F.CDFunderflowParticles>0), fprintf('DIAGNOSIS: rare-event likelihoods occurred; inspect minimum event mass and model mismatch.\n'); end
end
ex=E.example; PM=ex.posterior; H=ex.prefix;
fprintf('Representative prefix: unit %s, %d past nodes, D %.4g, B %.4g, eta %.4g.\n', ...
    H.id,numel(H.t),sum(PM.weights.*PM.D),sum(PM.weights.*PM.B),sum(PM.weights.*PM.eta));
innovationRMS=zeros(1,size(PM.innovations,2));
for j=1:numel(innovationRMS)
    v=PM.innovations(:,j); v=v(isfinite(v)); innovationRMS(j)=sqrt(mean(v.^2));
end
fprintf('Pre-update standardized innovation RMS per sensor: %s\n',mat2str(innovationRMS,4));
if startsWith(E.evidence,'SYNTHETIC:') && isfield(ex.unit,'truth')
    dd=mean(PM.pathD,1)'-ex.unit.truth.D(1:numel(H.t));
    bb=mean(PM.pathB,1)'*M.C(:,3)'-ex.unit.truth.B(1:numel(H.t))*[.25 1 -.25];bb=bb(:);
    fprintf('SYNTHETIC diagnostic only: representative smoothed D RMSE %.4g, sensor-space B contribution RMSE %.4g (scale/sign invariant).\n', ...
        sqrt(mean(dd.^2)),sqrt(mean(bb.^2)));
end
for policy=c.policies
    pq=E.predictions(strcmp(E.predictions.method,'PI_DSSDM')&strcmp(E.predictions.policy,policy{1}),:);
    fprintf('Future residual %s: maximum |rho| %.4g, mean RMS %.4g, outside-support %.2f%%, mean censored paths %.2f%%.\n', ...
        policy{1},max(pq.forecastRhoMaxAbs),mean(pq.forecastRhoRMS), ...
        100*mean(pq.residualOutOfSupportFraction),100*mean(pq.censoredPathFraction));
end
fprintf('First-passage step %.3g h, within-step exposure interpolation; raw bands omit parameter uncertainty.\n',c.integrationStepHours);
fprintf('FORECAST METRICS: positive bias is optimistic. Intervals are conditional/raw or unit-calibrated.\n');
disp(E.metrics); fprintf('ALPHA-LAMBDA (within %.0f%% true RUL, binned lifetime windows):\n',100*c.alpha); disp(E.alphaLambda);
fprintf('CALIBRATION: per-unit maximum log error, policy-specific simultaneous-grid target %.0f%%.\n',100*(1-c.intervalAlpha)); disp(E.calibration);
fprintf('FORECAST-ONLY ABLATION: same posterior/physics/emission/random draws; no refitting.\n');
for policy=c.policies
    ix=strcmp(E.ablation.policy,policy{1}); A=E.ablation(ix,:); good=isfinite(A.trueRUL_h);
    fprintf('  %s: residual ON MAE %.4g h | OFF %.4g h | median paired shift %.4g h.\n', ...
        policy{1},mean(abs(A.residualOnRUL_h(good)-A.trueRUL_h(good))), ...
        mean(abs(A.residualOffRUL_h(good)-A.trueRUL_h(good))),median(A.difference_h(isfinite(A.difference_h))));
end
fprintf('Raw bands include successful configured unit-bootstrap refits; omitted components are flagged. Conditional profiles are not confidence limits.\n');
end

function export_experiment(E,e,dir)
writetable(E.optimizerAudit,fullfile(dir,sprintf('Selected_model_optimisation_%02d.csv',e)));
writetable(E.scheduleAudit,fullfile(dir,sprintf('Schedule_audit_%02d.csv',e)));
writetable(E.innovationAudit,fullfile(dir,sprintf('Causal_innovation_audit_%02d.csv',e)));
writetable(E.methodNumerics,fullfile(dir,sprintf('All_method_numerics_%02d.csv',e)));
if numel(E.models)>4 && strcmp(E.methodNames{5},'Basis_hybrid'), writetable(E.models{5}.selection,fullfile(dir,sprintf('Basis_selection_%02d.csv',e))); end
if isfield(E,'numericalAudit'), writetable(E.numericalAudit,fullfile(dir,sprintf('Numerical_origin_audit_%02d.csv',e))); end
if isfield(E,'stateOriginAudit'), writetable(E.stateOriginAudit,fullfile(dir,sprintf('State_origin_audit_%02d.csv',e))); end
if isfield(E.models{4},'Bselection'), writetable(E.models{4}.Bselection,fullfile(dir,sprintf('B_retention_%02d.csv',e))); end
writetable(E.models{4}.fitTrace,fullfile(dir,sprintf('Physics_EM_trace_%02d.csv',e)));
writetable(E.models{1}.selection,fullfile(dir,sprintf('Primary_selection_%02d.csv',e)));
if ~isempty(E.models{1}.networkTrace), writetable(E.models{1}.networkTrace,fullfile(dir,sprintf('Network_trace_%02d.csv',e))); end
writetable(E.models{2}.selection,fullfile(dir,sprintf('PINN_selection_%02d.csv',e)));
writetable(E.filterDiagnostics,fullfile(dir,sprintf('Filter_diagnostics_%02d.csv',e)));
writetable(E.ablation,fullfile(dir,sprintf('Discrepancy_ablation_%02d.csv',e)));
writetable(E.calibration,fullfile(dir,sprintf('Calibration_%02d.csv',e)));
writetable(E.identifiability.profiles,fullfile(dir,sprintf('Conditional_profiles_%02d.csv',e)));
writetable(E.identifiability.confoundedPairs,fullfile(dir,sprintf('Sensitivity_pairs_%02d.csv',e)));
writematrix(E.identifiability.singularValues,fullfile(dir,sprintf('Active_singular_values_%02d.csv',e)));
writematrix(E.identifiability.physicsCorrelations,fullfile(dir,sprintf('Physics_correlations_%02d.csv',e)));
if isfield(E.identifiability,'fullInformation')
    F=E.identifiability.fullInformation;
    writematrix(F.information,fullfile(dir,sprintf('Joint_predictive_information_%02d.csv',e)));
    writematrix(F.physicsCorrelations,fullfile(dir,sprintf('Joint_physics_correlations_%02d.csv',e)));
    writetable(table(F.names',F.activeMask','VariableNames',{'coordinate','active'}),fullfile(dir,sprintf('Joint_information_coordinates_%02d.csv',e)));
end
writematrix(E.identifiability.informationSurrogate,fullfile(dir,sprintf('Conditional_information_surrogate_%02d.csv',e)));
M=E.models{1}; I=E.identifiability;
writetable(array2table(M.C,'VariableNames',{'intercept','D','B','logLoad','logSpeed','thermal','D2'}), ...
    fullfile(dir,sprintf('Emission_coefficients_%02d.csv',e)));
writetable(table((1:numel(M.sensorSD))',M.sensorSD',M.sensorSD'.^2, ...
    'VariableNames',{'sensor','standardDeviation','variance'}),fullfile(dir,sprintf('Sensor_noise_%02d.csv',e)));
parameters=table(M.k,M.p,M.betaT,M.a,M.tau,M.kappa,M.sigmaB,M.unitSD,M.bound, ...
    I.rhoRMS,I.rhoMaxAbs,I.activeRank,I.activeParameters,I.physicsConditionalRank, ...
    'VariableNames',{'rate','loadExponent','temperatureCoefficient','aging','tau','kappaHours','Bsd','unitSD', ...
    'residualBound','trainingRhoRMS','trainingRhoMaxAbs','activeRank','activeParameters','conditionalPhysicsRank'});
writetable(parameters,fullfile(dir,sprintf('Fitted_parameters_%02d.csv',e)));
end

function f=new_figure(c,name)
visible='off'; if c.showFigures, visible='on'; end
sz=[1680 1000];if isfield(c,'figureSize'),sz=c.figureSize;end
f=figure('Name',name,'NumberTitle','off','Visible',visible,'Color','w','Position',[50 50 sz]);
end

function save_plot(f,dir,name,c,vector)
if nargin<5,vector=v17_flag(c,'exportVectorFigures');end
increment=0;if isfield(c,'plotFontIncrement'),increment=c.plotFontIncrement;end
v17_publication_style(f,increment);
drawnow; exportgraphics(f,fullfile(dir,[name '.png']),'Resolution',c.figureResolution);
if vector
 try,exportgraphics(f,fullfile(dir,[name '.pdf']),'ContentType','vector');
 catch err,fprintf('Vector export skipped for %s: %s\n',name,err.message);end
end
savefig(f,fullfile(dir,[name '.fig'])); if ~c.showFigures, close(f); end
end

function v17_publication_style(f,increment)
% Adds `increment` points to EVERY font in the figure: axes tick labels,
% titles, axis labels, legends, colorbars, text annotations, reference-line
% labels and layout titles. Sizes are recorded before any change, so the
% result is exactly the drawn default plus `increment` (no compounding
% through title/label multipliers). Idempotent: a figure is styled once.
if increment==0 || isappdata(f,'pi17PublicationStyle'),return;end
objects=findall(f,'-property','FontSize');sizes=get(objects,'FontSize');
if ~iscell(sizes),sizes={sizes};end
isAxes=arrayfun(@(h)isa(h,'matlab.graphics.axis.AbstractAxes'),objects);
order=[find(isAxes);find(~isAxes)];
for j=order'
 try,set(objects(j),'FontSize',sizes{j}+increment);catch,end
end
for ax=findall(f,'Type','axes')'
 try,ax.LineWidth=max(ax.LineWidth,1);ax.Box='on';catch,end
end
% Figure-level (tiled layout) titles: bold and never smaller than the
% largest axes title.
largest=0;for ax=findall(f,'Type','axes')',try,largest=max(largest,ax.Title.FontSize);catch,end,end
for tl=findall(f,'Type','tiledlayout')'
 try,tl.Title.FontWeight='bold';tl.Title.FontSize=max(tl.Title.FontSize,largest+1);catch,end
end
setappdata(f,'pi17PublicationStyle',increment);
end

function plot_experiment(E,c,e,dir)
M=E.models{1}; base=E.models{4}; I=E.identifiability;
f=new_figure(c,sprintf('E%d learning and residual',e)); tiledlayout(2,3,'TileSpacing','compact');
T=base.fitTrace; nexttile; plot(T.iteration,T.unitMarginalNLLPerObservation,'-o'); xlabel('Observed-fit cycle'); ylabel('Penalized unit-marginal NLL / observation'); grid on;
title('Integrated B and unit frailty; conditional uncertainty');
nexttile; plot(T.iteration,T.causalValidationLoss,'-o'); xlabel('Iteration'); ylabel('Causal validation log-RUL loss'); grid on;
nexttile; semilogy(T.iteration,max(T.mStepGradientNorm,eps),'-o'); ylabel('M-step gradient norm'); xlabel('Iteration'); grid on;
nexttile; if ~isempty(M.networkTrace), plot(M.networkTrace.iteration,M.networkTrace.loss); else, text(.1,.5,'No residual selected'); end
xlabel('Network step'); ylabel('Profiled observed objective'); grid on;
nexttile; S=I.smoothingSummary; rho=discrepancy(M,S.D0,S.B0,S.u);
scatter(S.D0,rho,9,S.B0,'filled'); colorbar; xlabel('Smoothed TRAIN D'); ylabel('Actual log discrepancy'); grid on;
title(sprintf('Bound %.2f; RMS %.3g',M.bound,I.rhoRMS));
nexttile; bar(M.sensorSD); hold on; yline(c.sensorSD,'--'); xlabel('Sensor'); ylabel('Fitted measurement SD'); grid on;
sgtitle(E.evidence,'Interpreter','none'); save_plot(f,dir,sprintf('E%02d_Learning',e),c);

f=new_figure(c,sprintf('E%d state inference',e)); tiledlayout(2,3,'TileSpacing','compact');
U=E.example.unit; H=E.example.prefix; P=E.example.posterior; K=numel(H.t);
Dmean=mean(P.pathD,1)'; Bmean=mean(P.pathB,1)'; sortedD=sort(P.pathD,1); sortedB=sort(P.pathB,1);
lo=max(1,round(.05*size(sortedD,1))); hi=min(size(sortedD,1),round(.95*size(sortedD,1)));
nexttile; fill([H.t;flipud(H.t)],[sortedD(lo,:)';flipud(sortedD(hi,:)')],[.8 .9 1],'EdgeColor','none'); hold on;
plot(H.t,Dmean,'b','LineWidth',1.5); plot(H.t,P.filteredMean(:,1),'--','LineWidth',1);
if startsWith(E.evidence,'SYNTHETIC:') && isfield(U,'truth'), plot(H.t,U.truth.D(1:K),'k','LineWidth',1.3); end
plot(H.t,H.inspection,'ro'); yline(c.Dcrit,':'); xlabel('Elapsed h'); ylabel('D'); grid on;
title('Smoothed paths, filtered mean, independent anchors');
nexttile; fill([H.t;flipud(H.t)],[sortedB(lo,:)';flipud(sortedB(hi,:)')],[.9 .85 .8],'EdgeColor','none'); hold on;
plot(H.t,Bmean,'LineWidth',1.5);
if ~strcmp(c.architecture,'observed') && startsWith(E.evidence,'SYNTHETIC:') && isfield(U,'truth'), plot(H.t,U.truth.B(1:K),'k'); end
xlabel('Elapsed h'); ylabel('B'); grid on; title('Standardized residual B; sensor-scale amplitude in loading');
nexttile; X=emission_features(Dmean,Bmean,H.u); X(:,7)=mean(P.pathD.^2,1)'; y=X*M.C';
plot(H.t,H.y(:,1),'k.'); hold on; plot(H.t,y(:,1),'b','LineWidth',1.3);
plot(H.t,y(:,1)+1.645*M.sensorSD(1),'b:'); plot(H.t,y(:,1)-1.645*M.sensorSD(1),'b:');
xlabel('Elapsed h'); ylabel('Sensor 1'); grid on; title('Emission mean and measurement-noise bands');
nexttile; plot(H.t,P.ESS); xlabel('Elapsed h'); ylabel('Eta quadrature effective support'); grid on;
nexttile; histogram(P.eta,25); xlabel('Individual log-rate effect'); ylabel('Particles');
title(sprintf('Unit-effect grid, MH N/A %.1f, distinct %d',100*P.etaAcceptance,P.distinctRateParticles));
nexttile; plot(H.t,P.innovations); xlabel('Elapsed h'); ylabel('Pre-update standardized innovations'); grid on;
sgtitle(sprintf('%s | %s',E.evidence,U.id),'Interpreter','none'); save_plot(f,dir,sprintf('E%02d_States_filter',e),c);

f=new_figure(c,sprintf('E%d identifiability',e)); tiledlayout(2,3,'TileSpacing','compact');
nexttile; semilogy(max(I.singularValues,eps),'o-'); xlabel('Scaled active direction'); ylabel('Singular value'); grid on;
title(sprintf('Observed innovation rank %d/%d',I.activeRank,I.activeParameters));
nexttile; correlation_image(I.physicsCorrelations); colorbar; axis square; xticks(1:4); yticks(1:4);
xticklabels({'k','p','T','a'}); yticklabels({'k','p','T','a'}); title('Observed sensitivity correlations, NaN if deficient');
nexttile; imagesc(I.sensitivityCosines,[-1 1]); colorbar; xlabel('Coordinate'); ylabel('Coordinate'); title('Sensitivity cosines');
for coordinate=[1 2 4]
    nexttile; q=I.profiles(I.profiles.coordinate==coordinate,:);
    if isempty(q), text(.1,.5,'Fixed or profile not computed; inspect configuration'); axis off;
    else
        plot(q.physicalValue,q.penalizedUnitMarginalNLLPerObservation,'-o'); hold on;
        bad=q.exitflag<=0; plot(q.physicalValue(bad),q.penalizedUnitMarginalNLLPerObservation(bad),'rx','MarkerSize',9);
        xlabel(sprintf('Physical parameter, coordinate %d',coordinate)); ylabel('Penalized unit-marginal NLL / observation'); grid on;
        title('Penalized profile; not a confidence interval');
    end
end
sgtitle(E.evidence,'Interpreter','none'); save_plot(f,dir,sprintf('E%02d_Identifiability',e),c);

for ip=1:numel(c.policies)
f=new_figure(c,sprintf('E%d prognosis calibration %s',e,c.policies{ip})); tiledlayout(2,3,'TileSpacing','compact');
names=E.methodNames; nm=numel(names); palette=lines(nm); policy=c.policies{ip}; Q=E.predictions(strcmp(E.predictions.policy,policy),:);
nexttile; row=strcmp(Q.unit,U.id) & strcmp(Q.method,'PI_DSSDM'); qu=Q(row,:);
displayUpper=qu.upper_h; displayUpper(isinf(displayUpper))=c.forecastHorizonHours;
fill([qu.origin_h;flipud(qu.origin_h)],[qu.lower_h;flipud(displayUpper)],[.85 .9 1],'EdgeColor','none'); hold on;
trueHandle=plot(qu.origin_h,qu.trueRUL_h,'k-o','LineWidth',1.3); methodHandles=gobjects(nm,1);
for j=1:nm, ix=strcmp(Q.unit,U.id)&strcmp(Q.method,names{j}); methodHandles(j)=plot(Q.origin_h(ix),Q.predictedRUL_h(ix),'-o','Color',palette(j,:)); end
xlabel('Forecast origin h'); ylabel('RUL h'); grid on; title('Unit-calibrated primary band and all point forecasts');
legend([trueHandle;methodHandles],[{'True RUL'} names],'Interpreter','none','Location','best','FontSize',8);
if any(isinf(qu.upper_h)), title('Infinite band displayed at horizon; CSV retains Inf'); end
nexttile; hold on;
for j=1:nm, ix=strcmp(Q.method,names{j}) & Q.available; scatter(Q.trueRUL_h(ix),Q.predictedRUL_h(ix),16,palette(j,:)); end
v=Q.trueRUL_h(isfinite(Q.trueRUL_h)); if ~isempty(v), plot([0 max(v)],[0 max(v)],'k--'); end
xlabel('Independent true RUL h'); ylabel('Predicted RUL h'); grid on; legend(names,'Interpreter','none','Location','best');
nexttile; hold on;
for j=1:nm
    A=E.alphaLambda(strcmp(E.alphaLambda.policy,policy)&strcmp(E.alphaLambda.method,names{j}),:);
    plot((A.lambdaLower+A.lambdaUpper)/2,100*A.alphaLambdaAccuracy,'-o','Color',palette(j,:));
end
xlabel('Elapsed lifetime fraction'); ylabel(sprintf('Within %.0f%% true RUL (%%)',100*c.alpha)); ylim([0 100]); grid on;
nexttile; metrics=E.metrics(strcmp(E.metrics.policy,policy),:); vals=nan(nm,3);
for j=1:nm
    q=metrics(strcmp(metrics.method,names{j}),:); if ~isempty(q), vals(j,:)=[q.rawCoverage q.coverage q.unitSimultaneousCoverage]*100; end
end
bar(vals); yline(100*(1-c.intervalAlpha),'k:'); xticks(1:nm); xticklabels(names); xtickangle(15);
ylabel('Coverage %'); ylim([0 105]); legend({'Raw row','Calibrated row','Calibrated unit'},'Location','best'); grid on;
nexttile; widths=nan(nm,1);
for j=1:nm, q=metrics(strcmp(metrics.method,names{j}),:); if ~isempty(q), widths(j)=q.meanWidth_h; end; end
bar(widths); xticks(1:nm); xticklabels(names); xtickangle(15); ylabel('Mean calibrated width h'); grid on;
finiteWidth=widths(isfinite(widths)); top=1; if ~isempty(finiteWidth), top=max(1,1.12*max(finiteWidth)); end; ylim([0 top]);
for j=1:nm, if isinf(widths(j)), text(j,.04*top,'Inf','HorizontalAlignment','center'); elseif isnan(widths(j)), text(j,.04*top,'N/A','HorizontalAlignment','center'); end; end
nexttile; A=E.ablation(strcmp(E.ablation.policy,policy),:);
scatter(A.residualOffRUL_h,A.residualOnRUL_h,18,A.originIndex,'filled'); hold on;
v=[A.residualOffRUL_h;A.residualOnRUL_h]; v=v(isfinite(v)); if ~isempty(v), plot([0 max(v)],[0 max(v)],'k--'); end
xlabel('Residual OFF RUL h'); ylabel('Residual ON RUL h'); grid on; title({'Forecast-only paired ablation','Same origin posterior and random draws'});
sgtitle(sprintf('%s | %s duty',E.evidence,policy),'Interpreter','none'); save_plot(f,dir,sprintf('E%02d_Prognosis_%s',e,policy),c);
end
end

function plot_benchmark(R)
c=R.config; f=new_figure(c,'All experiments MAE'); set(f,'Position',[30 30 1350 max(600,220*numel(R.experiments))]);
tiledlayout(numel(R.experiments),numel(c.policies),'TileSpacing','compact');
names=R.experiments{1}.methodNames; nm=numel(names);
for e=1:numel(R.experiments)
    for p=1:numel(c.policies)
        nexttile; Q=R.metrics(R.metrics.experiment==e & strcmp(R.metrics.policy,c.policies{p}),:); v=nan(nm,1);
        for j=1:nm, q=Q(strcmp(Q.method,names{j}),:); if ~isempty(q), v(j)=q.MAE_h; end; end
        bar(v); xticks(1:nm); xticklabels(names); ylabel('MAE h'); grid on;
        title(sprintf('%s | %s',R.experiments{e}.evidence,c.policies{p}),'Interpreter','none');
    end
end
save_plot(f,R.outputDir,'Benchmark_all_MAE',c);
end

function P=v17_publication_outputs(R,outDir)
% 17.2 publication layer: presentation and fleet-level statistics only. It
% never refits, re-forecasts or changes a stored prediction. The unit of
% inference is the independent fleet. For each fleet, the paired gain is
% comparator MAE - PI-DSSDM MAE (positive favours PI-DSSDM). Reported:
% mean, SD, 95% t interval, two-sided t p-value, exact Wilcoxon signed-rank
% and sign-test p-values, and Holm-adjusted p-values across comparators
% within each scenario x duty family.
if nargin<2,outDir=fullfile(R.outputDir,'Publication');end
if ~exist(outDir,'dir'),mkdir(outDir);end
c=R.config;T=R.metrics;P=struct('outputDir',outDir);
if isempty(T),return;end
T.scenario=regexprep(T.evidence,'^SYNTHETIC:([^:]+):.*$','$1');
methods=unique(T.method,'stable');methods=[{'PI_DSSDM'};setdiff(methods(:),{'PI_DSSDM'},'stable')];
methods=methods(ismember(methods,T.method));comparators=methods(2:end);
scenarios=unique(T.scenario,'stable');groups=[{'ALL'};scenarios(:)];policies=c.policies;
vars=intersect({'MAE_h','RMSE_h','bias_h','coverage','meanWidth_h','intervalScore_h','unitSimultaneousCoverage','meanRelativeAccuracy'},T.Properties.VariableNames,'stable');
% Table 1: fleet-level summaries.
rows={};
for g=1:numel(groups)
 for p=1:numel(policies)
  for m=1:numel(methods)
   z=strcmp(T.policy,policies{p}) & strcmp(T.method,methods{m});if ~strcmp(groups{g},'ALL'),z=z & strcmp(T.scenario,groups{g});end
   if ~any(z),continue;end
   r={groups{g},policies{p},v17_display_name(methods{m}),sum(z)};
   for v=1:numel(vars),x=T.(vars{v})(z);x=x(isfinite(x));r=[r {mean(x),std(x)}];end %#ok<AGROW>
   rows(end+1,:)=r; %#ok<AGROW>
  end
 end
end
names={'scenario','policy','method','fleets'};for v=1:numel(vars),names=[names {['mean_' vars{v}],['sd_' vars{v}]}];end %#ok<AGROW>
S1=cell2table(rows,'VariableNames',names);writetable(S1,fullfile(outDir,'Table_metrics_by_scenario.csv'));
% Table 2: paired fleet-level tests.
rows={};
for g=1:numel(groups)
 for p=1:numel(policies)
  first=size(rows,1)+1;
  for m=1:numel(comparators)
   gain=[];a=[];b=[];
   for e=unique(T.experiment)'
    if ~strcmp(groups{g},'ALL') && ~any(strcmp(T.scenario(T.experiment==e),groups{g})),continue;end
    x=T(T.experiment==e & strcmp(T.policy,policies{p}) & strcmp(T.method,'PI_DSSDM'),:);
    y=T(T.experiment==e & strcmp(T.policy,policies{p}) & strcmp(T.method,comparators{m}),:);
    if isempty(x) || isempty(y) || ~isfinite(x.MAE_h(1)) || ~isfinite(y.MAE_h(1)),continue;end
    a(end+1)=x.MAE_h(1);b(end+1)=y.MAE_h(1);gain(end+1)=y.MAE_h(1)-x.MAE_h(1); %#ok<AGROW>
   end
   n=numel(gain);if n==0,continue;end
   [lo,hi,tp]=v17_t_interval(gain);
   rows(end+1,:)={groups{g},policies{p},v17_display_name(comparators{m}),n,mean(a),mean(b),mean(gain),std(gain),lo,hi, ...
    100*mean(gain./max(b,eps)),tp,v17_signrank_p(gain),v17_sign_p(gain),NaN,sum(gain>1e-9),sum(gain<-1e-9)}; %#ok<AGROW>
  end
  ix=first:size(rows,1);if ~isempty(ix),adj=v17_holm([rows{ix,12}]);for j=1:numel(ix),rows{ix(j),15}=adj(j);end,end
 end
end
S2=cell2table(rows,'VariableNames',{'scenario','policy','comparator','fleets','PI_MAE_h','comparator_MAE_h','meanGain_h','sdGain_h', ...
 'gain95Low_h','gain95High_h','meanGainPercent','tTestP','wilcoxonExactP','signTestP','holmAdjustedTP','PIwins','PIlosses'});
writetable(S2,fullfile(outDir,'Table_paired_tests.csv'));
P.metrics=S1;P.paired=S2;
runtime=v17_stage_runtime(R);if ~isempty(runtime),writetable(runtime,fullfile(outDir,'Table_runtime_by_stage.csv'));end
P.runtime=runtime;
if c.makePlots
 v17_publication_figures(R,T,methods,scenarios,policies,S2,runtime,outDir,c);
end
v17_write_results_markdown(R,S1,S2,runtime,outDir);
end

function name=v17_display_name(name)
name=strrep(char(name),'PI_DSSDM','PI-DSSDM');name=strrep(name,'_',' ');
end

function [lo,hi,p]=v17_t_interval(x)
n=numel(x);lo=NaN;hi=NaN;p=NaN;if n<2,return;end
nu=n-1;s=std(x);critical=sqrt(nu*(1/betaincinv(.05,nu/2,.5)-1));half=critical*s/sqrt(n);lo=mean(x)-half;hi=mean(x)+half;
if s>0,t=mean(x)/(s/sqrt(n));p=betainc(nu/(nu+t^2),nu/2,.5);else,p=double(mean(x)==0);end
end

function p=v17_sign_p(x)
w=sum(x>1e-9);l=sum(x<-1e-9);k=min(w,l);n=w+l;p=1;
if n>0,p=min(1,2*sum(arrayfun(@(j)nchoosek(n,j),0:k))/2^n);end
end

function p=v17_signrank_p(x)
% Exact two-sided Wilcoxon signed-rank p-value; zeros dropped, ties get
% midranks (doubled to integers for the exact null distribution).
x=x(abs(x)>1e-9);n=numel(x);p=1;if n==0,return;end
[~,order]=sort(abs(x));r=zeros(1,n);r(order)=1:n;ax=abs(x);
for v=unique(ax),k=ax==v;r(k)=mean(r(k));end
r2=round(2*r);w=sum(r2(x>0));total=sum(r2);dist=zeros(1,total+1);dist(1)=1;
for j=1:n,shifted=[zeros(1,r2(j)) dist(1:end-r2(j))];dist=dist+shifted;end
dist=dist/sum(dist);cdf=cumsum(dist);lower=cdf(w+1);upper=1-(w>0)*cdf(max(w,1));
if w==0,upper=1;end
p=min(1,2*min(lower,upper));
end

function adj=v17_holm(p)
adj=nan(size(p));ok=isfinite(p);q=p(ok);m=numel(q);if m==0,return;end
[s,order]=sort(q);a=min(1,cummax((m-(1:m)+1).*s));out=zeros(1,m);out(order)=a;adj(ok)=out;
end

function T=v17_stage_runtime(R)
T=table();d=fullfile(R.outputDir,'stages');if ~exist(d,'dir'),return;end
files=dir(fullfile(d,'E*_*.mat'));rows=cell(0,3);
for j=1:numel(files)
 t=regexp(files(j).name,'^E(\d+)_(.+)\.mat$','tokens','once');if isempty(t),continue;end
 try,S=load(fullfile(d,files(j).name),'stageElapsedSeconds');s=S.stageElapsedSeconds;catch,s=NaN;end
 rows(end+1,:)={str2double(t{1}),t{2},s/60}; %#ok<AGROW>
end
if ~isempty(rows),T=sortrows(cell2table(rows,'VariableNames',{'experiment','stage','minutes'}),{'experiment','stage'});end
end

function v17_publication_figures(R,T,methods,scenarios,policies,S2,runtime,outDir,c)
nm=numel(methods);palette=lines(nm);labels=cellfun(@v17_display_name,methods,'UniformOutput',false);
ns=numel(scenarios);
% Figure 1: fleet MAE by method, scenario and duty protocol.
f=new_figure(c,'Fleet-level MAE');tiledlayout(numel(policies),ns,'TileSpacing','compact','Padding','compact');
for p=1:numel(policies)
 for s=1:ns
  nexttile;hold on;
  for m=1:nm
   z=strcmp(T.policy,policies{p}) & strcmp(T.method,methods{m}) & strcmp(T.scenario,scenarios{s});x=T.MAE_h(z);x=x(isfinite(x));
   if isempty(x),continue;end
   jitter=m+.18*linspace(-1,1,numel(x))';scatter(jitter,x,28,palette(m,:),'filled','MarkerFaceAlpha',.55);
   [lo,hi]=v17_t_interval(x(:)');mu=mean(x);
   if isfinite(lo),errorbar(m,mu,mu-lo,hi-mu,'k','LineWidth',1.4,'CapSize',8);end
   plot(m,mu,'kd','MarkerFaceColor',palette(m,:),'MarkerSize',8);
  end
  xlim([.4 nm+.6]);xticks(1:nm);xticklabels(labels);xtickangle(40);grid on;
  if s==1,ylabel(sprintf('%s duty: MAE (h)',policies{p}));end
  title(strrep(regexprep(scenarios{s},'^fatigue_',''),'_',' '));
 end
end
sgtitle('Test-unit RUL MAE per independent fleet (dots), mean and 95% t interval');
save_plot(f,outDir,'Fig1_MAE_by_scenario',c,true);
% Figure 2: paired gain forest plot (LSTM excluded from the axis; see table).
f=new_figure(c,'Paired gain forest');tiledlayout(1,numel(policies),'TileSpacing','compact','Padding','compact');
for p=1:numel(policies)
 nexttile;Q=S2(strcmp(S2.policy,policies{p}) & ~strcmp(S2.comparator,'LSTM'),:);n=height(Q);
 y=n:-1:1;hold on;xline(0,'k-');
 for j=1:n
  m=find(strcmp(labels,Q.comparator{j}),1);col=palette(max(1,m),:);
  if isfinite(Q.gain95Low_h(j)),plot([Q.gain95Low_h(j) Q.gain95High_h(j)],[y(j) y(j)],'-','Color',col,'LineWidth',2);end
  plot(Q.meanGain_h(j),y(j),'o','MarkerFaceColor',col,'MarkerEdgeColor','k','MarkerSize',7);
 end
 rowLabels=cellfun(@(s,k)sprintf('%s | %s',strrep(regexprep(s,'^fatigue_',''),'_',' '),k),Q.scenario,Q.comparator,'UniformOutput',false);
 yticks(fliplr(y));yticklabels(flipud(rowLabels));ylim([.4 n+.6]);
 xlabel('Paired MAE gain (h), comparator - PI-DSSDM');grid on;title(sprintf('%s duty',policies{p}));
end
sgtitle('Fleet-level paired gains with 95% t intervals; > 0 favours PI-DSSDM (LSTM gains in Table\_paired\_tests.csv)');
save_plot(f,outDir,'Fig2_paired_gain_forest',c,true);
% Figure 3: calibration and sharpness of the primary (origin-stratified) band.
f=new_figure(c,'Calibration');tiledlayout(2,numel(policies),'TileSpacing','compact','Padding','compact');
metricsShown={'coverage','meanWidth_h'};ylabelsShown={'Coverage of 90% band (dashed: nominal)','Mean band width (h)'};
for k=1:2
 for p=1:numel(policies)
  nexttile;V=nan(ns,nm);
  for s=1:ns,for m=1:nm
   z=strcmp(T.policy,policies{p}) & strcmp(T.method,methods{m}) & strcmp(T.scenario,scenarios{s});x=T.(metricsShown{k})(z);x=x(isfinite(x));
   if ~isempty(x),V(s,m)=mean(x);end
  end,end
  b=bar(v17_bar_rows(V),'grouped');for m=1:min(nm,numel(b)),b(m).FaceColor=palette(m,:);end;xlim([.5 ns+.5]);
  if k==1,yline(.9,'k--','LineWidth',1.5);ylim([0 1.05]);end
  xticks(1:ns);xticklabels(strrep(regexprep(scenarios,'^fatigue_',''),'_',' '));xtickangle(25);ylabel(ylabelsShown{k});grid on;
  title(sprintf('%s duty',policies{p}));if k==1 && p==numel(policies),legend(labels,'Location','southeastoutside');end
 end
end
sgtitle('Calibrated prediction bands: coverage (top) and sharpness (bottom), mean over fleets');
save_plot(f,outDir,'Fig3_calibration_sharpness',c,true);
% Figure 4: alpha-lambda accuracy versus life fraction.
A=R.alphaLambda;
if ~isempty(A) && all(ismember({'lambdaLower','lambdaUpper','alphaLambdaAccuracy'},A.Properties.VariableNames))
 f=new_figure(c,'Alpha-lambda');tiledlayout(1,numel(policies),'TileSpacing','compact','Padding','compact');
 bins=unique([A.lambdaLower A.lambdaUpper],'rows');mid=mean(bins,2);
 for p=1:numel(policies)
  nexttile;hold on;
  for m=1:nm
   v=nan(size(bins,1),1);
   for k=1:size(bins,1)
    z=strcmp(A.policy,policies{p}) & strcmp(A.method,methods{m}) & A.lambdaLower==bins(k,1) & A.lambdaUpper==bins(k,2);
    x=A.alphaLambdaAccuracy(z);x=x(isfinite(x));if ~isempty(x),v(k)=mean(x);end
   end
   plot(mid,v,'-o','Color',palette(m,:),'MarkerFaceColor',palette(m,:),'LineWidth',1.8);
  end
  xlabel('Life fraction at forecast origin');ylabel('\alpha-\lambda accuracy (\alpha = 0.20)');ylim([0 1.02]);grid on;
  title(sprintf('%s duty',policies{p}));if p==numel(policies),legend(labels,'Location','southeastoutside');end
 end
 sgtitle('Fraction of forecasts within \pm20% of true RUL, by life fraction, mean over fleets');
 save_plot(f,outDir,'Fig4_alpha_lambda',c,true);
end
% Figure 5: PI-DSSDM applied model family (transparency of the correction).
Pr=R.predictions;
if ismember('selectedFamily',Pr.Properties.VariableNames)
 Pr=Pr(strcmp(Pr.method,'PI_DSSDM'),:);Pr.scenario=regexprep(Pr.evidence,'^SYNTHETIC:([^:]+):.*$','$1');
 known={'physics','basis','stack basis','deep','stack deep'};
 found=unique(regexprep(Pr.selectedFamily,'^stack_','stack '),'stable');
 families=[known(ismember(known,found)) setdiff(found(:)',known,'stable')];
 familyColor=containers.Map(known,{[.62 .62 .62],[.49 .18 .56],[.75 .6 .85],[0 .45 .74],[.55 .78 .95]});
 f=new_figure(c,'Applied family');tiledlayout(1,numel(policies),'TileSpacing','compact','Padding','compact');
 for p=1:numel(policies)
  nexttile;V=zeros(ns,numel(families));
  for s=1:ns,for k=1:numel(families)
   z=strcmp(Pr.policy,policies{p}) & strcmp(Pr.scenario,scenarios{s});
   V(s,k)=sum(strcmp(regexprep(Pr.selectedFamily(z),'^stack_','stack '),families{k}))/max(1,sum(z));
  end,end
  b=bar(v17_bar_rows(V),'stacked');xlim([.5 ns+.5]);
  for k=1:min(numel(families),numel(b)),if isKey(familyColor,families{k}),b(k).FaceColor=familyColor(families{k});end,end
  xticks(1:ns);xticklabels(strrep(regexprep(scenarios,'^fatigue_',''),'_',' '));xtickangle(25);
  ylabel('Fraction of PI-DSSDM forecasts');ylim([0 1]);grid on;title(sprintf('%s duty',policies{p}));
  if p==numel(policies),legend(families,'Location','southeastoutside','Interpreter','none');end
 end
 sgtitle('VAL-selected PI-DSSDM family per scenario (physics = no correction applied)');
 save_plot(f,outDir,'Fig5_applied_family',c,true);
end
% Figure 6: computational cost.
if ~isempty(runtime)
 pipeline={'physics','primary','pinn','lstm','basis','policy_models','point_forecasts','bootstrap','forecasts','information','hierarchical_audits'};
 found=unique(runtime.stage,'stable');stages=[pipeline(ismember(pipeline,found)) setdiff(found(:)',pipeline,'stable')];
 f=new_figure(c,'Runtime');ex=unique(runtime.experiment);V=zeros(numel(ex),numel(stages));
 for j=1:height(runtime),V(ex==runtime.experiment(j),strcmp(stages,runtime.stage{j}))=runtime.minutes(j);end
 V(~isfinite(V))=0;b=barh(v17_bar_rows(V),'stacked');ylim([.5 numel(ex)+.5]);
 colors=turbo(numel(stages)+2);for k=1:min(numel(stages),numel(b)),b(k).FaceColor=colors(k+1,:);end
 yticks(1:numel(ex));yticklabels(compose('E%02d',ex));set(gca,'YDir','reverse');
 xlabel('Wall time (min)');legend(strrep(stages,'_',' '),'Location','southeastoutside');grid on;
 title(sprintf('Wall time by stage; total %.1f h over %d experiments',sum(V(:))/60,numel(ex)));
 save_plot(f,outDir,'Fig6_runtime_by_stage',c,true);
end
end

function V=v17_bar_rows(V)
% bar/barh treat a one-row matrix as ONE series; a hidden NaN row keeps one
% series per column (one experiment or one scenario still plots correctly).
if size(V,1)==1,V=[V;nan(1,size(V,2))];end
end

function v17_write_results_markdown(R,S1,S2,runtime,outDir)
f=fopen(fullfile(outDir,'Results_summary.md'),'w');cleanup=onCleanup(@()fclose(f));c=R.config;
fprintf(f,'# PI-DSSDM %s results: %s\n\n',R.version,upper(c.workflowMode));
fprintf(f,'- Run folder: `%s`\n- Source SHA-256: `%s`\n- Seed: %d; profile: %s\n',R.outputDir,R.sourceSHA256,c.seed,v17_text_field(c,'fullProfile','n/a'));
fprintf(f,'- Experiments completed: %d/%d (independent fleets); TRAIN/VAL/CAL/TEST units %d/%d/%d/%d\n',numel(R.experiments),R.plannedExperiments,c.trainUnits,c.validationUnits,c.calibrationUnits,c.testUnits);
if isfield(R,'evidenceGate') && isfield(R.evidenceGate,'decision'),fprintf(f,'- Evidence gate: **%s** (see `Evidence_gate.csv`)\n',R.evidenceGate.decision);end
if ~isempty(runtime),fprintf(f,'- Total staged wall time: %.1f h\n',sum(runtime.minutes(isfinite(runtime.minutes)))/60);end
fprintf(f,'\nGain = comparator MAE - PI-DSSDM MAE (h); positive favours PI-DSSDM. The fleet is the unit of inference. p-values are two-sided. Holm adjustment is across comparators within each scenario x duty family.\n');
for p=1:numel(c.policies)
 fprintf(f,'\n## All scenarios, %s duty\n\n| Comparator | Fleets | PI-DSSDM MAE | Comparator MAE | Gain [95%% CI] (h) | Gain %% | t p (Holm) | Wilcoxon p | W/L |\n|---|---|---|---|---|---|---|---|---|\n',c.policies{p});
 Q=S2(strcmp(S2.scenario,'ALL') & strcmp(S2.policy,c.policies{p}),:);
 for j=1:height(Q)
  fprintf(f,'| %s | %d | %.2f | %.2f | %+.2f [%+.2f, %+.2f] | %+.1f | %.3g (%.3g) | %.3g | %d/%d |\n',Q.comparator{j},Q.fleets(j),Q.PI_MAE_h(j),Q.comparator_MAE_h(j), ...
   Q.meanGain_h(j),Q.gain95Low_h(j),Q.gain95High_h(j),Q.meanGainPercent(j),Q.tTestP(j),Q.holmAdjustedTP(j),Q.wilcoxonExactP(j),Q.PIwins(j),Q.PIlosses(j));
 end
end
fprintf(f,'\n## By scenario (planned duty, gain vs Physics SSM and Inverse PINN)\n\n| Scenario | vs Physics SSM | vs Inverse PINN | vs Basis hybrid |\n|---|---|---|---|\n');
sc=unique(S2.scenario(~strcmp(S2.scenario,'ALL')),'stable');
for s=1:numel(sc)
 cells=cell(1,3);names={'Physics SSM','Inverse PINN','Basis hybrid'};
 for k=1:3
  q=S2(strcmp(S2.scenario,sc{s}) & strcmp(S2.policy,c.policies{1}) & strcmp(S2.comparator,names{k}),:);
  if isempty(q),cells{k}='n/a';else,cells{k}=sprintf('%+.2f [%+.2f, %+.2f]',q.meanGain_h,q.gain95Low_h,q.gain95High_h);end
 end
 fprintf(f,'| %s | %s | %s | %s |\n',sc{s},cells{:});
end
fprintf(f,['\n## Files\n\n- `Table_metrics_by_scenario.csv`: mean and SD over fleets of MAE, RMSE, bias, coverage, width, interval score\n' ...
 '- `Table_paired_tests.csv`: every scenario x duty x comparator test\n- `Table_runtime_by_stage.csv`: wall time per stage\n' ...
 '- `Fig1`-`Fig6`: PNG (300 dpi), vector PDF and editable FIG\n\n' ...
 'Synthetic benchmark. Neither completion nor a passing test establishes physical validity; ties, losses and ineligible fits are retained.\n']);
end

function v=v17_text_field(c,name,default)
v=default;if isfield(c,name) && ~isempty(c.(name)),v=char(c.(name));end
end

function P=source_provenance(c)
P=struct('sourcePath',c.originalSource,'sourceSHA256','','newSHA256',hash_file([mfilename('fullpath') '.m']), ...
    'basis','Version 9 source and audited interrupted run 20261012_072620_478', ...
    'scope','Observed-data fitting, operating baseline, residual B selection, centered frailty, joint constrained discrepancy and fatigue evidence gates');
if exist(c.originalSource,'file')==2, P.sourceSHA256=hash_file(c.originalSource); end
end

function write_report(R)
if strcmp(R.config.architecture,'observed'), write_observed_report(R); return; end
f=fopen(fullfile(R.outputDir,'Run_report.txt'),'w'); cleanup=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'PI-DSSDM 17.2.0\n%s\nSource SHA256: %s\n\n',R.config.label,R.provenance.newSHA256);
fprintf(f,['Approximate Monte Carlo generalized EM from ancestral particle smoothing paths.\n' ...
    'Not exact marginal MLE; inspect M-step gradients, EM stabilization and causal validation.\n' ...
    'Common TRAIN physical-score projection, no unit-ID coefficients in runtime.\n' ...
    'Primary discrepancy fitted with physics/emission/noise frozen to PF reference.\n' ...
    'Gamma cumulative exposure increments maintain irreversible damage sample paths.\n' ...
    'Survival/failure-conditioned proposals include event likelihood and rare-event importance weights.\n' ...
    'Static unit effects have a separate population prior and MH rejuvenation.\n' ...
    'Inverse PINN origin uncertainty is a conditional profile approximation.\n' ...
    'LSTM is actual recurrent supervised RUL regression with causal history and ex ante duty descriptors.\n' ...
    'Raw forecast bands condition on fitted global parameters. Unit calibration assumes exchangeability.\n' ...
    'Conditional innovation information/profile checks are not observed-data likelihood confidence intervals.\n' ...
    'Crossings are resolved on the integration grid, interpolated in cumulative exposure.\n' ...
    'Inf means horizon censoring. Synthetic truth appears only in post-fit diagnostic plots.\n' ...
    'Nominal fatigue-life consumption does not establish physical wear/preload state identification.\n\n']);
for e=1:numel(R.experiments)
    E=R.experiments{e}; M=E.models{1}; I=E.identifiability;
    fprintf(f,'%s: selected bound %.3g, training rho RMS %.5g/max %.5g, active rank %d/%d, physics %d/4.\n', ...
        E.evidence,M.bound,I.rhoRMS,I.rhoMaxAbs,I.activeRank,I.activeParameters,I.physicsConditionalRank);
    fprintf(f,'Physics EM stabilized: %d. Selected checkpoint %d / M-step flag %d. Last M-step flag: %d. PINN BFGS flag: %d.\n', ...
        E.models{4}.optimization.stabilized,E.models{4}.optimization.selectedIteration, ...
        E.models{4}.optimization.selectedMStepExitflag,E.models{4}.optimization.lastMStepExitflag,E.models{2}.optimization.exitflag);
end
end

function T=selftest(c)
eventConfig=c;c.trainingLikelihood='anchor_reference';c.directNeuralCoordinates=false;c.policySpecificSelection=false;
c.gradientTolerance=2e-4;c.optimizerL1Indices=[];c.optimizerL1Radius=Inf;
old=rng; cleanup=onCleanup(@()rng(old)); rng(91); %#ok<NASGU>
names={}; cc=c; cc.architecture='legacy_gamma'; cc.trainUnits=3; cc.validationUnits=2; cc.calibrationUnits=12; cc.testUnits=2;
cc.particles=50; cc.fitParticles=50; cc.forecastPaths=20; cc.rejuvenationSteps=1;
U=generate_fleet(cc,'state_mismatch',11); train=strip_truth(U(1:3)); M=initial_model(train,cc); M.config=cc;
for a=[0 .3 1.5]
    D=[0;.2;.8]; r=[.001;.003;.01]; dt=[1;3;8]; next=advance_D(D,r,a,dt);
    assert(all(next>=D)); t=crossing_time(D,r,a,1); assert(max(abs(advance_D(D,r,a,t)-1))<1e-9);
end
names{end+1}='positive deterministic damage and analytic exposure crossing';
samples=.1*.003*randg(8/.1,6000,1);
assert(all(samples>0) && abs(mean(samples)-8*.003)/(8*.003)<.03);
assert(abs(var(samples)-.1*.003^2*8)/(.1*.003^2*8)<.08);
names{end+1}='gamma exposure increments match declared mean and variance';
H=causal_prefix(U(4),max(3,round(numel(U(4).t)*.65)));
P=particle_filter(M,H,cc,true,50);
assert(all(P.D<cc.Dcrit) && all(diff(P.pathD,1,2)>=-1e-12,'all'));
assert(all(isfinite(P.weights)) && abs(sum(P.weights)-1)<1e-12);
names{end+1}='survival-conditioned stochastic paths are monotone and live';
HH=H; HH.y(:)=100; PH=particle_filter(M,HH,cc,false,50); assert(all(PH.D<cc.Dcrit));
names{end+1}='extreme sensors cannot imply already-failed live particles';
S=struct('D0',linspace(0,.95,120)','D1',linspace(.01,.96,120)', ...
    'B0',.15*sin((1:120)'),'B1',.15*cos((1:120)'), ...
    'u',[1+.1*sin((1:120)') 1+.1*cos((1:120)') .3*sin((1:120)'/3)], ...
    'dt',8*ones(120,1),'eta',zeros(120,1),'unit',repelem((1:3)',40));
M.bound=.3; M.nn=init_network(cc.hidden1,cc.hidden2,5); M.nn.w=project_l1(.05*randn(cc.hidden2,1),M.bound);
M.reference=make_reference(M,S,cc); [M,F]=project_network(M,cc);
rho=discrepancy(M,S.D0,S.B0,S.u);
assert(max(abs(rho-F*M.nn.w))<1e-12 && norm(M.reference.G'*rho)/numel(rho)<1e-8);
names{end+1}='ACTUAL portable runtime residual matches projection and physical orthogonality';
dr=rand(300,1); br=3*randn(300,1); ur=M.reference.lo+rand(300,3).*(M.reference.hi-M.reference.lo);
assert(all(abs(discrepancy(M,dr,br,ur))<=M.bound+1e-10));
names{end+1}='analytic global residual bound preserves projected form';
[~,gradient]=network_objective(M,S,cc); x=pack_network(M.nn); fd=zeros(size(x)); h=1e-5;
for j=1:numel(x)
    p=x; m=x; p(j)=p(j)+h; m(j)=m(j)-h; mp=M; mm=M;
    mp.nn=unpack_network(p,cc.hidden1,cc.hidden2,5); mm.nn=unpack_network(m,cc.hidden1,cc.hidden2,5);
    fd(j)=(network_objective(mp,S,cc)-network_objective(mm,S,cc))/(2*h);
end
assert(norm(fd-gradient)/max(norm(fd),1)<2e-5,'pi17:gradient','Projection-aware network gradient incorrect');
names{end+1}='deep residual gradient includes projection/envelope and matches finite differences';
V=U(4); k=numel(H.t); V.y(k+1:end,:)=1e8; V.u(k+1:end,:)=4; V.inspection(k+1:end)=1e8;
V.failureTime=1e7; V.truth.D(:)=1e7; H2=causal_prefix(V,k); assert(isequaln(H,H2));
Q=fit_duty_model(train); rng(123); b1=future_bank(H,'probabilistic',Q,cc,20);
rng(123); b2=future_bank(H2,'probabilistic',Q,cc,20); assert(isequaln(b1,b2));
M.bound=0; rng(81); p1=particle_filter(M,H,cc,false,50); f1=first_passage(M,p1,b1,cc);
rng(81); p2=particle_filter(M,H2,cc,false,50); f2=first_passage(M,p2,b2,cc); assert(isequaln(f1,f2));
names{end+1}='future sensor/duty/inspection/truth corruption cannot alter fixed-origin forecasts';
HH=H; HH.plan.issuedAt=H.t(end)+1; rejected=false;
try, future_bank(HH,'planned',Q,cc,10); catch, rejected=true; end
assert(rejected); names{end+1}='future-issued plan rejected';
MM=M; MM.k=0; f0=first_passage(MM,p1,b1,cc); assert(all(isinf(f0)));
names{end+1}='forecast horizon remains censoring, never an invented failure';
assert(isinf(quantile_base([1 2 Inf Inf],.75))); names{end+1}='quantiles retain censored probability mass';
scale=fit_sensor_scaling(train); seq=lstm_sequence(H,b1,scale,cc);
assert(size(seq,2)==numel(H.t)); names{end+1}='LSTM contains only historical sensor tokens, with known duty conditioning';
ids=split_units(numel(U),cc); allIds=[ids.train ids.validation ids.calibration ids.test];
assert(numel(unique(allIds))==numel(allIds)); names{end+1}='independent unit splits are disjoint';
fun=@(x)sum((x-[2;-1]).^2); [xx,~,out]=bfgs_fd(fun,[0;0],40,1e-6);
assert(out.exitflag==1 && norm(xx-[2;-1])<1e-4); names{end+1}='Base MATLAB optimizer converges on a known reference objective';
T=table(names',true(numel(names),1),'VariableNames',{'test','passed'});
T=[T;observed_selftests(c);revision_selftests(c);v17_selftests(c);v17_regression_tests(c);v17_revision_tests(c);v17_hierarchy_tests(c);v17_covariance_tests(c);v17_event_tests(eventConfig);v17_workflow_tests(eventConfig);v17_methodology_tests(eventConfig)];
end

function T=v17_methodology_tests(c)
% Checks for the v17 methodology additions: analytic feature derivatives,
% resolution-limited optimizer labelling, stochastic-increment filter and
% forecast, linear-pool mixtures, origin-stratified conformal bands, scenario.
names={};cc=c;cc.parallelMode='off';cc.activeGradientWorkers=0;cc.runtimeCandidateDir='';cc.gridRefinementLevels=0;
cc.trainUnits=3;cc.validationUnits=2;cc.calibrationUnits=10;cc.testUnits=2;cc.coarseEtaPoints=41;cc.etaGridPoints=81;
U=generate_fleet(cc,'fatigue_matched',170331);train=strip_truth(U(1:3));M=initial_model(train,cc);
M.useB=true;M.baselineFixed=false;M.config=cc;M.trainingEta=zeros(3,1);
% Analytic damage derivative of the deep (smooth skip) and radial-basis maps.
for family={'deep','fixed_basis'}
 N=M;N.bound=.3;N.residualFamily=family{1};rng(5);N.nn=init_network(cc.hidden1,cc.hidden2,5);
 if strcmp(family{1},'deep'),N.nn.w=.1*randn(cc.hidden2+3,1);else,N.nn.w=.1*randn(v17_basis_size(cc),1);end
 N.nn.w=project_l1(N.nn.w,.9*N.bound);
 N.reference=observed_reference(M,train,cc);N=project_network(N,cc);
 D=linspace(.05,1.08,40)';u=repmat(train(1).u(5,:),40,1);[~,dr]=v17_damage_discrepancy_sensitivity(N,D,u,cc);
 h=1e-6;fd=(discrepancy(N,D+h,zeros(40,1),u)-discrepancy(N,D-h,zeros(40,1),u))/(2*h);
 assert(max(abs(fd-dr))<1e-6,'pi17:test','%s discrepancy derivative mismatch',family{1});
end
names{end+1}='deep smooth-skip and radial-basis discrepancies: analytic dD derivative matches FD, including D>Dcrit';
% Finite-difference probe just outside the active L1 face must evaluate.
P=N;P.nn.w=sign(P.nn.w+eps).*(1+2e-5)*P.bound/numel(P.nn.w);P.nn.w(1:2:end)=-P.nn.w(1:2:end);
rp=discrepancy(P,linspace(0,1.2,60)',zeros(60,1),repmat(train(1).u(5,:),60,1));
assert(all(abs(rp)<=sum(abs(P.nn.w))+1e-9));
names{end+1}='finite-difference probe slightly outside the L1 face evaluates instead of aborting the run';
% Resolution-limited stop is labelled exitflag 2, never exitflag 1.
ct=cc;ct.gradientTolerance=1e-14;ct.resolutionGradientTolerance=1e-3;ct.stallWindow=3;ct.optimizerLowerBound=[];ct.optimizerUpperBound=[];
ct.optimizerL1Indices=[];ct.runtimeFitLabel='resolution_test';
noisy=@(x)sum((x-[1;2]).^2)+1e-9*sign(sin(1e7*x(1)));[~,~,out]=v17_bfgs(noisy,[0;0],60,ct,'');
assert(out.exitflag~=1 && (out.exitflag~=2 || out.gradientNorm<1e-3));
assert(v17_converged(struct('exitflag',2,'gradientNorm',5e-4),cc)==(5e-4<cc.resolutionGradientTolerance));
assert(~v17_converged(struct('exitflag',0,'gradientNorm',1e-9*cc.gradientTolerance+cc.gradientTolerance),cc));
names{end+1}='resolution-limited stationarity is a distinct exitflag and keeps a declared tolerance';
% 17.1.2: anisotropic objective whose minimiser lies on the L1 face with a
% zero coordinate (the SCREEN 17.1.1 stall geometry). Reference: long
% projected-gradient iteration with step 1/L.
ct=cc;ct.gradientTolerance=5e-5;ct.optimizerLowerBound=-ones(4,1);ct.optimizerUpperBound=ones(4,1);
ct.optimizerL1Indices=(1:4)';ct.optimizerL1Radius=1;ct.runtimeFitLabel='L1_face_regression';ct.progressEveryIterations=1000;
assert(norm(v17_project_parameters([6;1.9;0;0],ct)-[1;0;0;0])<1e-14,'pi17:test','Box-and-ball projection is not exact');
a=[1;30;900;5];t=[3;-2;1;.02];quad=@(x)sum(a.*(x-t).^2);xr=zeros(4,1);
for k=1:40000,xr=v17_project_parameters(xr-a.*(xr-t)/max(a),ct);end
[xf,~,of]=v17_bfgs(quad,zeros(4,1),80,ct,'');
% The 17.1.1 path (clip, then ball) reaches the same point but reports a
% false projected gradient of about 0.6 there, so it can never certify it.
co=ct;co.l1FaceDirection=false;co.earlyStallStop=false;co.exactL1Projection=false;[~,~,oo]=v17_bfgs(quad,zeros(4,1),80,co,'');
assert(oo.gradientNorm>.1,'pi17:test','Legacy projection no longer reproduces the false-gradient defect');
assert(of.exitflag==1 && norm(xf-xr,Inf)<1e-5 && of.l1ConstraintActive && abs(xr(1))+abs(xr(4))<1e-12,'pi17:test','L1-face BFGS did not reach the KKT reference');
names{end+1}='projected BFGS reaches the KKT point on an anisotropic active L1 face with a zero coordinate';
% Early stall stop: a non-improving objective with an unmet gradient test
% gets one curvature reset, then exitflag -3 well before the budget; a
% sub-resolution gradient becomes the separately labelled exitflag 2.
ct=cc;ct.optimizerLowerBound=-1e6*ones(2,1);ct.optimizerUpperBound=1e6*ones(2,1);ct.optimizerL1Indices=[];
ct.stallStopWindow=3;ct.stallStopRelativeTolerance=1;ct.runtimeFitLabel='stall_regression';ct.progressEveryIterations=1000;
[~,~,os]=v17_bfgs(@(x)1e-3*sum(x),[0;0],60,ct,'');
assert(os.exitflag==-3 && strcmp(os.status,'objective_stalled') && os.stallRescues==1 && os.iterations<20 && ~v17_converged(os,ct));
[~,~,os]=v17_bfgs(@(x)1e-4*sum(x),[0;0],60,ct,'');
assert(os.exitflag==2 && os.iterations<20 && v17_converged(os,ct));
names{end+1}='stalled objective stops early as exitflag -3 (or 2 below resolution tolerance) after one curvature reset';
% Stochastic increments: normalized causal posterior, kappa->0 approaches the
% deterministic forecast, and the gamma forecast preserves the midpoint mean.
H=causal_prefix(U(4),12);Q=fit_duty_model(train);bank=future_bank(H,'planned',Q,cc,20);
cs=cc;cs.processEtaNodes=31;cs.processParticles=32;cs.processOutputParticles=512;
K=M;K.processKappa=1e-6;rng(3);PK=model_posterior(K,H,cs);P0=v17_grid_prefix(M,H,cs);
assert(abs(sum(PK.weights)-1)<1e-10 && all(PK.D<cs.Dcrit) && abs(PK.weights'*PK.eta-P0.weights'*P0.eta)<.02);
[a,ia]=model_samples(M,H,P0,bank,cs);rng(4);[b,ib]=model_samples(K,H,PK,bank,cs);
assert(abs(v17_quantile(a,ia,.5)-v17_quantile(b,ib,.5))<.03*max(1,v17_quantile(a,ia,.5)));
V=U(4);V.y(13:end,:)=1e9;V.u(13:end,:)=9;K.processKappa=2;rng(8);PA=model_posterior(K,H,cs);rng(8);PB=model_posterior(K,causal_prefix(V,12),cs);
assert(isequaln(PA,PB));
names{end+1}='gamma-increment filter is normalized, causal, and converges to the deterministic clock as kappa->0';
% Linear pool: weights, eligibility and family bookkeeping.
A=M;A.bound=0;A.selectedMStep=struct('exitflag',1,'gradientNorm',0);A.available=true;S=v17_make_stack(A,A,.25);
PS=model_posterior(S,H,cc);assert(abs(sum(PS.weights)-1)<1e-12 && isequal(PS.stackWeights,[.25 .75]));
[s,is]=model_samples(S,H,PS,bank,cc);assert(abs(sum(is.sampleWeights)-1)<1e-12 && numel(s)==numel(is.sampleWeights));
assert(strcmp(v17_model_family(S),'stack_physics') && v17_candidate_eligible(S,cc) && ~isfield(v17_strip_model_archive(S),'stackPartner'));
names{end+1}='linear-pool PI-DSSDM mixes complete predictive distributions with VAL weights';
% Kappa safeguard: a tiny, noisy VAL improvement must not switch on kappa.
ck=cc;ck.processKappaGrid=[0 2];ck.processKappaSEMultiplier=1e6;ck.processEtaNodes=11;ck.processParticles=8;ck.processOutputParticles=64;
ck.selectionSeeds=1;ck.validationPaths=10;ck.particles=40;ck.policies={'planned'};Vk=strip_truth(U(4:5));Qk=fit_duty_model(train);
[NK,~]=v17_select_process_kappa(A,Vk,Qk,ck,1,'test','planned');
assert(~isfield(NK,'processKappa') && NK.processKappaSelection.selected(1));
names{end+1}='kappa stays at the deterministic clock unless its paired VAL gain clears the declared SE multiple';
% Origin-stratified conformal band uses per-origin CAL quantiles and nests raw bands.
n=24;truthRUL=[(10:9+n)';(10:9+n)'];pred=truthRUL+[zeros(n-2,1);8;9;zeros(n,1)];
cal=table(repmat({'A'},2*n,1),repmat({'planned'},2*n,1),repmat(arrayfun(@(k)sprintf('u%d',k),(1:n)','UniformOutput',false),2,1), ...
 [ones(n,1);2*ones(n,1)],truthRUL,pred,true(2*n,1),pred-1,pred+1, ...
 'VariableNames',{'method','policy','unit','originIndex','trueRUL_h','predictedRUL_h','available','rawLower_h','rawUpper_h'});
tt=cal([1 n+1],:);tt.lower_h=nan(2,1);tt.upper_h=nan(2,1);cb=cc;cb.calibrationScales=table();cb.bandMethod='origin_stratified';
[tt,ct2]=calibrate_bands(cal,tt,cb);
assert(ct2.originStratifiedPrimaryBand && all(tt.lower_h<=tt.rawLower_h+1e-12 & tt.upper_h>=tt.rawUpper_h-1e-12));
assert(all(tt.lowerUnitMax_h<=tt.lower_h+1e-12 & tt.upperUnitMax_h>=tt.upper_h-1e-12));
assert(tt.upper_h(1)>tt.rawUpper_h(1)+1e-9 && abs(tt.upper_h(2)-tt.rawUpper_h(2))<1e-9 && tt.upperUnitMax_h(2)>tt.upper_h(2)+1e-9);
names{end+1}='origin-stratified bands nest raw bands and lie inside the unit-max band';
L=generate_fleet(cc,'fatigue_load_exponent',129072);B0=generate_fleet(cc,'fatigue_matched',129072);
common=min(numel(L(1).t),numel(B0(1).t))-1;
assert(isequal(L(1).u(1:common,:),B0(1).u(1:common,:)) && isequal(L(1).plan,B0(1).plan));
assert(L(1).truth.loadExponent==cc.truthAlternativeLoadExponent && L(1).failureTime~=B0(1).failureTime);
names{end+1}='load-exponent scenario changes only the transition law, with identical duty';
T=table(names',true(numel(names),1),'VariableNames',{'test','passed'});
end

function ids=split_units(n,c)
if isempty(fieldnames(c.splitIds))
    assert(n>=c.trainUnits+c.validationUnits+c.calibrationUnits+c.testUnits,'pi2:split','Not enough units.');
    r=randperm(n); ns=[c.trainUnits c.validationUnits c.calibrationUnits c.testUnits];
    edges=[0 cumsum(ns)]; labs={'train','validation','calibration','test'};
    for j=1:4, ids.(labs{j})=r(edges(j)+1:edges(j+1)); end
else, ids=c.splitIds;
end
labs={'train','validation','calibration','test'}; allIds=[];
for j=1:4
    assert(isfield(ids,labs{j}) && ~isempty(ids.(labs{j})),'pi2:split','Missing split.');
    v=ids.(labs{j}); assert(all(v>=1 & v<=n & v==fix(v)),'pi2:split','Invalid unit index.');
    allIds=[allIds v(:)']; %#ok<AGROW>
end
assert(numel(unique(allIds))==numel(allIds),'pi2:split','Unit leakage across splits.');
end


function units=strip_truth(units)
% Training has measured y/inspections/failure endpoints, never simulator truth.
if isfield(units,'truth'), units=rmfield(units,'truth'); end
end


function units=validate_units(units,c)
assert(isstruct(units) && numel(units)>=4,'pi2:data','At least four independent units required.');
for i=1:numel(units)
    U=units(i); required={'id','t','u','y','inspection','failureTime','failureObserved','plan','initialD'};
    assert(all(isfield(U,required)),'pi2:data','Unit %d lacks canonical fields.',i);
    n=numel(U.t); units(i).t=U.t(:); units(i).inspection=U.inspection(:);
    if c.requireMeasuredInspectionProvenance && any(isfinite(U.inspection))
        assert(isfield(U,'inspectionScheduleIndependent') && U.inspectionScheduleIndependent, ...
            'pi17:inspection','Measured inspection timing must have outcome-independent provenance.');
    end
    assert(n>=4 && U.t(1)==0 && all(diff(U.t)>0),'pi2:data','Time must start at zero and increase.');
    assert(isequal(size(U.u),[n 3]) && size(U.y,1)==n && size(U.y,2)>=2,'pi2:data','u or y shape invalid.');
    assert(all(isfinite(U.u(:))) && all(U.u(:,1:2)>=0,'all'),'pi2:data','Nonnegative calibrated load/speed ratios needed.');
    assert(numel(U.inspection)==n && ~any(isinf(U.y(:))) && ~any(isinf(U.inspection)), ...
        'pi2:data','Use NaN for missing observations.');
    assert(U.initialD>=0 && U.initialD<c.Dcrit,'pi2:data','Independent initial damage required.');
    if U.failureObserved
        assert(isfinite(U.failureTime) && abs(U.failureTime-U.t(end))<1e-7,'pi2:data', ...
            'Observed failure must be the last timeline node, with known intervening duty and NaN for missing telemetry.');
    end
    assert(isempty(U.plan) || all(isfield(U.plan,{'issuedAt','t','u'})),'pi2:data','Plan fields invalid.');
end
assert(numel(unique({units.id}))==numel(units),'pi2:data','Duplicate unit IDs.');
assert(c.physicalAnchorsVerified,'pi2:anchors', ...
    'Measured fitting needs verified damage anchors or failure labels and a justified Dcrit. Set physicalAnchorsVerified only after verification.');
end


function units=generate_fleet(c,scenario,seed)
old=rng; cleaner=onCleanup(@()rng(old)); rng(seed,'twister'); %#ok<NASGU>
n=c.trainUnits+c.validationUnits+c.calibrationUnits+c.testUnits;
units=repmat(struct('id','','t',[],'u',[],'y',[],'inspection',[], ...
    'failureTime',NaN,'failureObserved',true,'initialD',c.initialD,'plan',[], 'truth',[]),n,1);
fatigue=startsWith(scenario,'fatigue_');
for i=1:n
    if isfield(c,'pairedFactorial') && c.pairedFactorial,rng(seed+7919*i,'twister');end
    phase=2*pi*rand; tt=(0:c.simStepHours:c.simMaxHours)';
    tp=(0:c.simStepHours:c.simMaxHours+c.forecastHorizonHours)';
    plan=struct('issuedAt',0,'t',tp,'u',scenario_duty(tp,phase,scenario));
    up=scenario_duty(tt,phase,scenario);
    eta=c.truthUnitSD*randn; D=c.initialD; B=0;
    if fatigue, B=c.truthBsd*randn; end % Stationary zero-mean OU initial nuisance.
    yy=zeros(numel(tt),3); DD=zeros(size(tt)); BB=DD;
    failure=Inf; last=numel(tt); YYnoise=.045;
    weak=ismember(scenario,{'weak_sensor_gap','fatigue_weak_gap'});
    if weak, YYnoise=.16; end
    beta=c.truthTemperatureCoefficient;
    if strcmp(scenario,'fatigue_missing_temperature'), beta=.08; end
    exponent=c.truthLoadExponent;
    % v17: load-exponent misspecification (true p differs from nominal 3, as
    % for other contact geometries or near-threshold fatigue). The log-rate
    % error (p-3)*log(load) varies with duty, so a constant k cannot absorb it.
    if strcmp(scenario,'fatigue_load_exponent'), exponent=c.truthAlternativeLoadExponent; end
    for k=1:numel(tt)
        if k>1
            u=up(k-1,:); dt=tt(k)-tt(k-1); a=0;
            if ~fatigue, a=.45; end
            ns=ceil(dt/c.simIntegrationStepHours); h=dt/ns;
            for j=1:ns
                r=c.truthRate*u(1)^exponent*u(2)*exp(beta*u(3)+eta);
                if ismember(scenario,{'state_mismatch','weak_sensor_gap','fatigue_discrepancy','fatigue_weak_gap','fatigue_combined_mismatch'})
                    % Independent analytical discrepancy, not the fitted network.
                    r=r*exp(.28*sin(3*D)+.10*D*tanh(u(3)));
                    if ~fatigue, a=.7; end
                end
                next=advance_D(D,r,a,h);
                if next>=c.Dcrit
                    failure=tt(k-1)+(j-1)*h+crossing_time(D,r,a,c.Dcrit);
                    D=c.Dcrit; break;
                end
                D=next;
            end
            ph=exp(-v17_B_elapsed_interval(dt,tt(k-1),failure,c)/c.truthBtau);
            target=0;
            if ~fatigue, target=.35*log(u(1))+.15*log(u(2))+.4*u(3); end
            B=ph*B+(1-ph)*target+c.truthBsd*sqrt(1-ph^2)*randn;
            if isfinite(failure), tt(k)=failure; last=k; end
        end
        DD(k)=D; BB(k)=B; u=up(k,:); q=log(max(u(1:2),1e-8));
        yy(k,:)=[.05+D+.25*B+.10*q(1)+.05*u(3)+.10*D^2, ...
            -.03-.1*D+B+.08*q(2)+.04*u(3), .02+.65*D-.25*B+.06*q(1)];
        if ismember(scenario,{'fatigue_emission_mismatch','fatigue_combined_mismatch'})
            % Diagnostic misspecification affects observation only, not the input protocol.
            yy(k,1)=yy(k,1)+.15*D^3; yy(k,3)=yy(k,3)-.08*D^3;
        end
        yy(k,:)=yy(k,:)+YYnoise*randn(1,3);
        if isfinite(failure), break; end
    end
    assert(isfinite(failure),'pi17:simulation','Simulation horizon must include failure; increase simMaxHours.');
    tt=tt(1:last); up=up(1:last,:); yy=yy(1:last,:); DD=DD(1:last); BB=BB(1:last);
    insp=nan(size(tt));
    if strcmp(c.inspectionMode,'calendar')
        % Calendar is declared without knowing failure. No terminal D anchor is
        % inserted as an inspection; TRAIN failure likelihood is separate.
        due=tt<failure & abs(tt/c.inspectionEveryHours-round(tt/c.inspectionEveryHours))<1e-8;
        insp(due)=DD(due)+c.inspectionSD*randn(sum(due),1);
    end
    if weak
        gap=tt>=c.sensorGapHours(1) & tt<c.sensorGapHours(2);
        yy(gap,:)=NaN; insp(gap)=NaN; % Fixed calendar interval, never fraction of death.
    end
    units(i)=struct('id',sprintf('%s_%03d',scenario,i),'t',tt,'u',up,'y',yy, ...
        'inspection',insp,'failureTime',failure,'failureObserved',true, ...
        'initialD',c.initialD,'plan',plan,'truth',struct('scenario',scenario,'D',DD,'B',BB,'eta',eta, ...
        'rate',c.truthRate,'loadExponent',exponent,'temperatureCoefficient',beta, ...
        'inspectionProtocol',c.inspectionMode,'gapHours',c.sensorGapHours));
end
end

function u=scenario_duty(t,phase,scenario)
u=planned_duty(t,phase);
if strcmp(scenario,'fatigue_duty_shift')
    ix=t>=320; u(ix,1)=1.30*u(ix,1); u(ix,2)=1.15*u(ix,2);
end
end

function u=planned_duty(t,phase)
u=[1+.16*sin(t/70+phase)+.08*(t>180), ...
    1+.12*cos(t/90+phase), .8*sin(t/130+phase)+.35*(t>200)];
end


function Dnew=advance_D(D,r,a,dt)
% Exact positive increment for dD/dt=r*(1+aD), conditional on frozen rho/r.
if a<1e-9, Dnew=D+r.*dt;
else, Dnew=D+(1+a*D).*expm1(min(a*r.*dt,50))/a; end
end


function t=crossing_time(D,r,a,threshold)
t=inf(size(D)); failed=D>=threshold; t(failed)=0;
active=~failed & r>0;
if a<1e-9, t(active)=(threshold-D(active))./r(active);
else, t(active)=log((1+a*threshold)./(1+a*D(active)))./(a*r(active)); end
end


function X=emission_features(D,B,u)
X=[ones(numel(D),1) D(:) B(:) log(max(u(:,1:2),1e-8)) u(:,3) D(:).^2];
end


function S=fit_sensor_scaling(train)
y=vertcat(train.y); u=vertcat(train.u); p=size(y,2); S.mean=zeros(1,p); S.sd=ones(1,p);
for j=1:p
    v=y(isfinite(y(:,j)),j); if isempty(v), S.mean(j)=0; S.sd(j)=1; else, S.mean(j)=mean(v); S.sd(j)=max(std(v),.01); end
end
z=[log(max(u(:,1:2),1e-8)) u(:,3)]; S.uMean=mean(z,1); S.uSD=max(std(z,0,1),.01);
end


function Q=fit_duty_model(train)
% Empirical multivariate one-step Markov duty model fitted only on TRAIN.
% It preserves joint load/speed/temperature transitions. It is a research
% model, not a certified future mission model; deployment needs validation.
Q.current=[]; Q.next=[];
for j=1:numel(train)
    u=train(j).u; Q.current=[Q.current;u(1:end-1,:)]; Q.next=[Q.next;u(2:end,:)]; %#ok<AGROW>
end
z=[log(max(Q.current(:,1:2),1e-8)) Q.current(:,3)]; Q.mean=mean(z,1); Q.sd=max(std(z,0,1),.02);
Q.z=(z-Q.mean)./Q.sd;
Q.nextNeighbors=zeros(size(Q.next,1),min(20,size(Q.current,1)));
zn=([log(max(Q.next(:,1:2),1e-8)) Q.next(:,3)]-Q.mean)./Q.sd;
for j=1:size(Q.next,1)
    [~,ord]=sort(sum((Q.z-zn(j,:)).^2,2),'ascend');
    Q.nextNeighbors(j,:)=ord(1:size(Q.nextNeighbors,2));
end
end


function bank=future_bank(H,policy,Q,c,npaths)
dt=repmat(c.dutyStepHours,ceil(c.forecastHorizonHours/c.dutyStepHours),1);
dt(end)=c.forecastHorizonHours-sum(dt(1:end-1));
bank=struct('dt',dt,'u',zeros(numel(dt),npaths,3),'policy',policy,'origin',H.t(end));
if strcmp(policy,'planned')
    assert(~isempty(H.plan),'pi2:plan','Planned policy requires a plan issued before the origin.');
    P=H.plan; assert(P.issuedAt<=H.t(end),'pi2:plan','Plan was not available at origin.');
    assert(all(diff(P.t)>0) && size(P.u,1)==numel(P.t) && size(P.u,2)==3,'pi2:plan','Invalid planned schedule.');
    tf=H.t(end)+[0;cumsum(dt(1:end-1))];
    assert(P.t(1)<=tf(1) && P.t(end)>=tf(end),'pi2:plan','Plan must cover the forecast horizon.');
    uf=interp1(P.t,P.u,tf,'previous');
    bank.u=repmat(reshape(uf,numel(dt),1,3),1,npaths,1);
else
    assert(~isempty(Q.current),'pi2:duty','Train-only duty model is empty.');
    % Known input at origin controls the FIRST held interval.
    bank.u(1,:,:)=repmat(reshape(H.u(end,:),1,1,3),1,npaths,1);
    z=([log(max(H.u(end,1:2),1e-8)) H.u(end,3)]-Q.mean)./Q.sd;
    [~,ord]=sort(sum((Q.z-z).^2,2),'ascend'); near=ord(1:min(20,numel(ord)));
    index=near(randi(numel(near),npaths,1));
    for k=2:numel(dt)
        bank.u(k,:,:)=reshape(Q.next(index,:),1,npaths,3);
        if isfield(Q,'family') && strcmp(Q.family,'conditional_blocks') && mod(k-2,c.dutyBlockLength)~=c.dutyBlockLength-1
            following=Q.blockNext(index);reset=following==0;
            if any(reset),nn=Q.nextNeighbors(index(reset),:);choose=randi(size(nn,2),sum(reset),1);following(reset)=nn(sub2ind(size(nn),(1:sum(reset))',choose));end
            index=following;
        elseif isfield(Q,'nextNeighbors')
            nn=Q.nextNeighbors(index,:); choose=randi(size(nn,2),npaths,1);
            index=nn(sub2ind(size(nn),(1:npaths)',choose));
        else
            for j=1:npaths
                zz=([log(max(Q.next(index(j),1:2),1e-8)) Q.next(index(j),3)]-Q.mean)./Q.sd;
                [~,oo]=sort(sum((Q.z-zz).^2,2),'ascend'); index(j)=oo(randi(min(20,numel(oo))));
            end
        end
    end
end
assert(all(isfinite(bank.u(:))) && all(bank.u(:,:,1:2)>=0,'all'),'pi2:duty','Invalid future duty.');
end

function w=normalized_weights(logw)
m=max(logw); assert(isfinite(m),'pi2:filter','All particle likelihoods are nonfinite.');
w=exp(logw-m); w=w/sum(w);
end


function ix=systematic_resample(w,n)
positions=((0:n-1)'+rand)/n; cw=cumsum(w(:)); cw(end)=1;
ix=zeros(n,1); j=1;
for k=1:n
    while positions(k)>cw(j), j=j+1; end
    ix(k)=j;
end
end


function q=quantile_base(x,p)
% Inverse empirical CDF preserves probability mass at +Inf.
x=sort(x(:)); x=x(~isnan(x));
if isempty(x), q=NaN; else, q=x(max(1,min(numel(x),ceil(p*numel(x))))); end
end


function [test,C]=calibrate_bands(cal,test,c)
% Unit-max conformal EXPANSION of raw intervals in log(1+RUL), with a
% nonnegative score. Calibration cannot shrink a raw posterior/duty band.
rows=cell(0,6);
for method=unique(test.method)'
    for policy=unique(test.policy)'
        Q=cal(strcmp(cal.method,method{1}) & strcmp(cal.policy,policy{1}) & cal.available,:);
        [lo,hi]=v17_initial_log_band(Q,c); scale=v17_band_scale(Q,c); y=log(Q.trueRUL_h+c.relativeFloorHours);
        score=max([zeros(height(Q),1) (lo-y)./scale (y-hi)./scale],[],2); names=unique(Q.unit); unitScore=[];
        for i=1:numel(names)
            ix=strcmp(Q.unit,names{i}); if all(isfinite(Q.trueRUL_h(ix))) && all(~isnan(score(ix))), unitScore(end+1,1)=max(score(ix)); end %#ok<AGROW>
        end
        q=v17_conformal_quantile(unitScore,c.intervalAlpha);
        ix=strcmp(test.method,method{1}) & strcmp(test.policy,policy{1}) & test.available; T=test(ix,:);
        [lo,hi]=v17_initial_log_band(T,c); scale=v17_band_scale(T,c);
        [lower,upper]=v17_expand_band(lo,hi,q*ones(height(T),1),scale,c);
        stratified=isfield(c,'bandMethod') && strcmp(c.bandMethod,'origin_stratified') && ...
            ismember('originIndex',Q.Properties.VariableNames) && ismember('originIndex',T.Properties.VariableNames);
        if stratified
            % v17 primary band: split conformal at each fixed calendar origin.
            % At one origin the CAL units are exchangeable with a TEST unit, so
            % marginal coverage holds per origin without the unit-max penalty.
            if ~ismember('lowerUnitMax_h',test.Properties.VariableNames), test.lowerUnitMax_h=nan(height(test),1); test.upperUnitMax_h=nan(height(test),1); end
            test.lowerUnitMax_h(ix)=lower; test.upperUnitMax_h(ix)=upper;
            qo=nan(height(T),1); origins=unique(T.originIndex);
            for o=origins(:)'
                good=Q.originIndex==o & isfinite(Q.trueRUL_h) & ~isnan(score);
                qq=v17_conformal_quantile(score(good),c.intervalAlpha);
                % Too few surviving CAL units at a late origin give an infinite
                % rank; fall back to the (valid, conservative) unit-max quantile.
                if ~isfinite(qq), qq=q; end
                qo(T.originIndex==o)=qq;
            end
            [lower,upper]=v17_expand_band(lo,hi,qo,scale,c);
        end
        test.lower_h(ix)=lower; test.upper_h(ix)=upper;
        rows(end+1,:)={method{1},policy{1},numel(unitScore),q,1-c.intervalAlpha,stratified}; %#ok<AGROW>
    end
end
C=cell2table(rows,'VariableNames',{'method','policy','independentCalibrationUnits','standardizedUnitQuantile','nominalCoverage','originStratifiedPrimaryBand'});
end

function q=v17_conformal_quantile(score,alpha)
q=NaN; score=score(:);
if isempty(score), return; end
k=ceil((numel(score)+1)*(1-alpha));
if k>numel(score), q=Inf; else, z=sort(score); q=z(k); end
end

function [lower,upper]=v17_expand_band(lo,hi,q,scale,c)
lower=nan(size(lo)); upper=lower; fin=isfinite(q); inf_=isinf(q);
lower(fin)=max(0,exp(lo(fin)-q(fin).*scale(fin))-c.relativeFloorHours); upper(fin)=exp(hi(fin)+q(fin).*scale(fin))-c.relativeFloorHours;
lower(inf_)=0; upper(inf_)=Inf;
end

function [T,A]=metrics(P,c)
rows=cell(0,22); arows=cell(0,7); meth=unique(P.method); pol=unique(P.policy);
for m=1:numel(meth)
    for p=1:numel(pol)
        z=strcmp(P.method,meth{m}) & strcmp(P.policy,pol{p}); Q=P(z,:);
        ok=Q.available & isfinite(Q.trueRUL_h) & ~isnan(Q.predictedRUL_h);
        y=Q.trueRUL_h(ok); pred=Q.predictedRUL_h(ok); err=pred-y;
        denom=max(y,c.relativeFloorHours);
        if isempty(err), mae=NaN; rmse=NaN; bias=NaN; mre=NaN; ra=NaN; else
            mae=mean(abs(err)); rmse=sqrt(mean(err.^2)); bias=mean(err);
            mre=mean(abs(err)./denom); ra=mean(1-abs(err)./denom);
        end
        lo=Q.lower_h(ok); hi=Q.upper_h(ok); bi=~isnan(lo) & ~isnan(hi);
        coverage=NaN; width=NaN; intervalScore=NaN; simultaneous=NaN;
        if any(bi)
            cover=y(bi)>=lo(bi) & y(bi)<=hi(bi); coverage=mean(cover);
            width=mean(hi(bi)-lo(bi));
            sc=hi(bi)-lo(bi); lowerMiss=y(bi)<lo(bi); upperMiss=y(bi)>hi(bi);
            yy=y(bi); ll=lo(bi); hh=hi(bi);
            sc(lowerMiss)=sc(lowerMiss)+2/c.intervalAlpha*(ll(lowerMiss)-yy(lowerMiss));
            sc(upperMiss)=sc(upperMiss)+2/c.intervalAlpha*(yy(upperMiss)-hh(upperMiss));
            intervalScore=mean(sc);
            qu=Q.unit(ok); qu=qu(bi); uq=unique(qu); uc=false(numel(uq),1);
            for j=1:numel(uq), uc(j)=all(cover(strcmp(qu,uq{j}))); end
            simultaneous=mean(uc);
        end
        rawLo=Q.rawLower_h(ok); rawHi=Q.rawUpper_h(ok); rok=~isnan(rawLo)&~isnan(rawHi);
        rawCoverage=NaN; rawWidth=NaN;
        if any(rok), rawCoverage=mean(y(rok)>=rawLo(rok)&y(rok)<=rawHi(rok)); rawWidth=mean(rawHi(rok)-rawLo(rok)); end
        umCoverage=NaN; umSimultaneous=NaN; umWidth=NaN;
        if ismember('lowerUnitMax_h',Q.Properties.VariableNames)
            ul=Q.lowerUnitMax_h(ok); uh=Q.upperUnitMax_h(ok); ub=~isnan(ul)&~isnan(uh);
            if any(ub)
                uc=y(ub)>=ul(ub) & y(ub)<=uh(ub); umCoverage=mean(uc); umWidth=mean(uh(ub)-ul(ub));
                qu=Q.unit(ok); qu=qu(ub); uq=unique(qu); all_=false(numel(uq),1);
                for j=1:numel(uq), all_(j)=all(uc(strcmp(qu,uq{j}))); end
                umSimultaneous=mean(all_);
            end
        end
        rows(end+1,:)={Q.experiment(1),Q.evidence{1},meth{m},pol{p},height(Q),sum(ok), ...
            sum(~Q.available),sum(isinf(pred)),mae,rmse,bias,mre,ra,coverage,width,intervalScore, ...
            simultaneous,rawCoverage,rawWidth,umCoverage,umSimultaneous,umWidth}; %#ok<AGROW>
        for j=1:numel(c.lambdaGrid)-1
            ix=ok & Q.lifeFraction>=c.lambdaGrid(j) & Q.lifeFraction<c.lambdaGrid(j+1);
            yy=Q.trueRUL_h(ix); pp=Q.predictedRUL_h(ix); acc=NaN;
            if ~isempty(yy), acc=mean(abs(pp-yy)<=c.alpha*yy); end
            arows(end+1,:)={Q.experiment(1),meth{m},pol{p},c.lambdaGrid(j),c.lambdaGrid(j+1),numel(yy),acc}; %#ok<AGROW>
        end
    end
end
T=cell2table(rows,'VariableNames',{'experiment','evidence','method','policy','forecastRows','evaluatedRows', ...
    'unavailableRows','censoredMedianRows','MAE_h','RMSE_h','bias_h','meanAbsRelativeError','meanRelativeAccuracy', ...
    'coverage','meanWidth_h','intervalScore_h','unitSimultaneousCoverage','rawCoverage','rawMeanWidth_h', ...
    'unitMaxBandCoverage','unitMaxBandSimultaneousCoverage','unitMaxBandMeanWidth_h'});
A=cell2table(arows,'VariableNames',{'experiment','method','policy','lambdaLower','lambdaUpper','forecasts','alphaLambdaAccuracy'});
end


function h=hash_file(path)
f=fopen(path,'rb'); assert(f>=0,'pi2:file','Cannot read source.');
clean=onCleanup(@()fclose(f)); b=fread(f,Inf,'*uint8'); %#ok<NASGU>
if usejava('jvm')
    md=java.security.MessageDigest.getInstance('SHA-256'); md.update(b);
    bytes=typecast(md.digest(),'uint8'); h=lower(reshape(dec2hex(bytes,2)',1,[]));
else, h='unavailable: JVM disabled'; end
end


function R=telemetry_inventory(c)
R=opc_operating_analysis(c); return; %#ok<UNRCH>
% Raw INIT/POST are windows from one campaign, not independent fleet units.
% They contain no calibrated axial load, damage anchors, or failure timeline.
% This mode preserves that evidentiary boundary and does not invent a fit.
files={'Initial_data_20000.csv','Post_ALT_data_20000.csv','Before_failure_20000.csv','Failure_Mode_data_20000.csv'};
rows=cell(0,6);
for j=1:numel(files)
    path=fullfile(c.telemetryDir,files{j}); if exist(path,'file')~=2, continue; end
    T=readtable(path,'VariableNamingRule','preserve');
    vars=T.Properties.VariableNames;
    has=all(ismember({'torque','current','temperature','speed','times'},vars));
    rows(end+1,:)={files{j},height(T),width(T),has,false,'Recorded telemetry, no independent degradation/RUL labels asserted'}; %#ok<AGROW>
end
R=struct('inventory',cell2table(rows,'VariableNames',{'record','rows','columns','expectedChannels', ...
    'physicalRUL_evaluable','evidence'}),'instructions', ...
    'Build canonical units with verified continuous elapsed exposure (including ALT gaps), calibrated load and independent health/failure anchors. Do not treat INIT and POST as separate units.');
disp(R.inventory);
if ~exist(c.outputDir,'dir'), mkdir(c.outputDir); end
writetable(R.inventory,fullfile(c.outputDir,'Raw_telemetry_inventory.csv'));
end


function [x,free]=observed_encode(M,n,c)
x=[v17_bounded_encode(log(M.k/c.nominalRate),-5,5); ...
 v17_bounded_encode(M.p,1,5);v17_bounded_encode(M.betaT,-.6,.8); ...
 log(M.a+.01);v17_bounded_encode(log(M.tau),log(2),log(200)); ...
 v17_bounded_encode(log(max(M.sigmaB,.001)),log(.001),log(.8));M.trainingEta(1:max(0,n-1))];
free=1:numel(x);
if c.fatigueLinearDamage,free(free==4)=[];end
if ~c.fitLoadExponent,free(free==2)=[];end
if ~c.fitTemperatureCoefficient,free(free==3)=[];end
if ~M.useB,free(ismember(free,[5 6]))=[];end
end

function M=observed_decode(x,M,n,c)
M.k=c.nominalRate*exp(v17_bounded_decode(x(1),-5,5));
M.p=v17_bounded_decode(x(2),1,5); M.betaT=v17_bounded_decode(x(3),-.6,.8);
M.a=max(0,min(3,exp(x(4))-.01));
M.tau=exp(v17_bounded_decode(x(5),log(2),log(200)));
M.sigmaB=exp(v17_bounded_decode(x(6),log(.001),log(.8)));
if n>1,M.trainingEta=[x(7:end);-sum(x(7:end))];else,M.trainingEta=0;end
if c.fatigueLinearDamage,M.a=0;end
if ~c.fitLoadExponent,M.p=c.nominalLoadExponent;end
if ~c.fitTemperatureCoefficient,M.betaT=c.nominalTempCoefficient;end
if ~M.useB,M.sigmaB=0;M.C(:,3)=0;end
M.gamma=zeros(3,1);M.kappa=0;
if M.bound>0
 M.reference.G=physical_scores(M,M.reference.D,M.reference.u,c);
 M.reference.pinvG=pinv(M.reference.G,c.projectionTolerance);
 M.reference.gmax=score_envelope(M,M.reference.lo,M.reference.hi,c);
 M=project_network(M,c);
end
end

function D=observed_trajectory(M,H,eta,c)
% Positive midpoint integration, shared by fitting, filtering and first passage.
eta=eta(:);K=numel(H.t);D=zeros(K,numel(eta))+H.initialD;
for k=2:K
 dt=H.t(k)-H.t(k-1);ns=max(1,ceil(dt/c.transitionStepHours));h=dt/ns;
 d=D(k-1,:)';u=repmat(H.u(k-1,:),numel(eta),1);base=physics_rate(M,u).*exp(eta);
 for j=1:ns
  r=base.*exp(discrepancy(M,d,zeros(size(d)),u)).*(1+M.a*d);
  mid=d+.5*h*r;
  rmid=base.*exp(discrepancy(M,mid,zeros(size(d)),u)).*(1+M.a*mid);
  d=d+h*rmid;
 end
 D(k,:)=d';
end
end

function [nll,KF,r]=observed_kalman(M,H,D,c,smooth)
% Scalar latent B, multiple observed OPC-UA/sensor channels. Rank-one Gaussian
% algebra exactly integrates B conditional on a damage trajectory and eta.
if nargin<5, smooth=false; end
[K,L]=size(D); cb=M.C(:,3)'; R=M.sensorSD.^2;
m=zeros(1,L); v=M.sigmaB^2; nll=zeros(1,L); bm=zeros(K,L); bv=zeros(K,1);
pm=bm; pv=bv; cumulativeNLL=zeros(K,L); innovations=nan(K,size(H.y,2)); residuals=[];
for k=1:K
    if k>1
        phi=exp(-(H.t(k)-H.t(k-1))/M.tau); m=phi*m;
        v=phi^2*v+M.sigmaB^2*(1-phi^2);
    end
    pm(k,:)=m; pv(k)=v;
    u=H.u(k,:); base=M.C(:,1)'+log(max(u(1:2),1e-8))*M.C(:,4:5)'+u(3)*M.C(:,6)';
    mu=base+D(k,:)'.*M.C(:,2)'+D(k,:)'.^2.*M.C(:,7)';
    ok=isfinite(H.y(k,:));
    if any(ok)
        cc=cb(ok); rr=R(ok); e=H.y(k,ok)-mu(:,ok)-m'.*cc;
        q=sum(cc.^2./rr); b=sum(e.*(cc./rr),2); denom=1+v*q;
        nll=nll+.5*(sum(log(2*pi*rr))+log(denom)+sum(e.^2./rr,2)'-v/denom*b'.^2);
        % Cholesky-whitened innovations support an observed sensitivity audit.
        if nargout>2
            V=diag(rr)+v*(cc'*cc); A=chol(V,'lower'); er=A\e'; residuals=[residuals;er(:)]; %#ok<AGROW>
        end
        if L==1, innovations(k,ok)=e./sqrt(rr+v*cc.^2); end
        % Multi-eta innovations require PRIOR predictive mixture weights. They
        % are computed in observed_prefix, never an unweighted grid average.
        m=m+v/denom*b'; v=v/denom;
    end
    if isfinite(H.inspection(k))
        e=(D(k,:)-H.inspection(k))/c.inspectionSD;
        nll=nll+.5*e.^2+log(sqrt(2*pi)*c.inspectionSD);
        if nargout>2, residuals=[residuals;e(:)]; end %#ok<AGROW>
    end
    bm(k,:)=m; bv(k)=v; cumulativeNLL(k,:)=nll;
end
if smooth
    for k=K-1:-1:1
        phi=exp(-(H.t(k+1)-H.t(k))/M.tau); gain=bv(k)*phi/max(pv(k+1),eps);
        bm(k,:)=bm(k,:)+gain*(bm(k+1,:)-pm(k+1,:));
        bv(k)=max(0,bv(k)+gain^2*(bv(k+1)-pv(k+1)));
    end
end
KF=struct('mean',bm,'variance',bv,'predictedMean',pm,'predictedVariance',pv,'innovations',innovations,'cumulativeNLL',cumulativeNLL);
r=residuals;
end

function [loss,r]=observed_loss(M,train,c,penalize)
if nargin<4, penalize=true; end
loss=0; count=0; r=[];
for i=1:numel(train)
    U=train(i); D=observed_trajectory(M,U,M.trainingEta(i),c);
    if nargout>1, [v,~,rr]=observed_kalman(M,U,D,c); r=[r;rr]; %#ok<AGROW>
    else, v=observed_kalman(M,U,D,c); end
    loss=loss+v; count=count+sum(isfinite(U.y(:)))+sum(isfinite(U.inspection));
    if U.failureObserved
        terminal=(D(end)-c.Dcrit)/c.terminalDamageTolerance;
        survival=max(D(1:end-1)-c.Dcrit,0)/c.terminalDamageTolerance;
        loss=loss+.5*terminal^2+5*sum(survival.^2); count=count+1;
        if nargout>1, r=[r;terminal;sqrt(10)*survival]; end %#ok<AGROW>
    end
end
if penalize
    prior=(log(M.k/c.nominalRate)/c.rateLogPriorSD)^2+ ...
        ((M.p-c.nominalLoadExponent)/c.exponentPriorSD)^2+ ...
        ((M.betaT-c.nominalTempCoefficient)/c.tempPriorSD)^2+ ...
        ((M.a-c.nominalAging)/c.agingPriorSD)^2+sum((M.trainingEta/M.unitSD).^2);
    loss=loss+.5*prior+100*max(count,1)*sum(max(abs(M.trainingEta)-c.unitEffectMax,0).^2);
    if M.bound>0
        ref=M.reference; rho=discrepancy(M,ref.D,zeros(size(ref.D)),ref.u);
        means=accumarray(ref.unit,rho,[],@mean);
        loss=loss+count*(c.residualPenalty*mean(rho.^2)+c.unitResidualPenalty*mean(means.^2)+ ...
            c.networkPenalty*sum(pack_network(M.nn).^2));
    end
end
loss=loss/max(count,1); if ~isfinite(loss), loss=1e30; end
end

function loss=observed_coordinates(v,x,free,M,train,c)
x(free)=v; mm=observed_decode(x,M,numel(train),c); loss=observed_loss(mm,train,c);
end

function [M,opt]=observed_parameter_fit(M,train,c,steps)
[x,free]=observed_encode(M,numel(train),c);
fun=@(v)observed_coordinates(v,x,free,M,train,c);
[v,~,opt]=robust_bfgs(fun,x(free),steps,c); x(free)=v;
M=observed_decode(x,M,numel(train),c);
end

function M=observed_emission_update(M,train,c)
% Expected sufficient statistics include posterior B variance, avoiding the
% regression/noise shrinkage bias from treating estimated B as observed truth.
P=size(M.C,1); C=M.C; oldSD=M.sensorSD;
for j=1:P
    XX=zeros(7); XY=zeros(7,1); n=0;
    for i=1:numel(train)
        U=train(i); D=fitting_trajectory(M,U,M.trainingEta(i),c);
        [~,K]=observed_kalman(M,U,D,c,true);
        X=emission_features(D,K.mean,U.u); ok=isfinite(U.y(:,j)); V=K.variance(ok);
        A=X(ok,:); XX=XX+A'*A; XX(3,3)=XX(3,3)+sum(V); XY=XY+A'*U.y(ok,j); n=n+sum(ok);
    end
    pen=c.emissionRidge*diag([1e-6 1 1 1 1 1 1]);
    fixed=[]; values=[];
    if M.useB && j==2, fixed=3; values=1; elseif ~M.useB, fixed=3; values=0; end
    if isfield(M,'baselineFixed') && M.baselineFixed
        fixed=[fixed 1 4 5 6]; values=[values M.referenceBaseline(j,:)];
    end
    free=setdiff(1:7,fixed); C(j,fixed)=values;
    rhs=XY(free); if ~isempty(fixed), rhs=rhs-XX(free,fixed)*values'; end
    if n>=8, C(j,free)=((XX(free,free)+pen(free,free))\rhs)'; end
end
M.C=C;
for j=1:P
    ss=0; n=0;
    for i=1:numel(train)
        U=train(i); D=fitting_trajectory(M,U,M.trainingEta(i),c); [~,K]=observed_kalman(M,U,D,c,true);
        pred=emission_features(D,K.mean,U.u)*C'; ok=isfinite(U.y(:,j));
        ss=ss+sum((pred(ok,j)-U.y(ok,j)).^2+C(j,3)^2*K.variance(ok)); n=n+sum(ok);
    end
    M.sensorSD(j)=max(c.sensorFloor,min(c.sensorCeiling,sqrt((ss+c.noiseShrinkageObservations*oldSD(j)^2)/(n+c.noiseShrinkageObservations))));
end
end

function M=fit_observed_one(train,val,Q,c,eid,useB)
if c.profileObserved, M=v17_fit_population_one(train,val,Q,c,eid,useB); return; end
M=initial_model(train,c); M.useB=useB;
if ~useB, M.C(:,3)=0; M.sigmaB=0; end
M.baselineFixed=false;
% Optional verified reference consists of measured healthy OPC-UA windows;
% no synthetic commissioning observations are silently added to a fleet.
if all(arrayfun(@(U)isfield(U,'reference') && ~isempty(U.reference),train))
    Y=[]; X=[];
    for i=1:numel(train)
        V=train(i).reference;
        assert(isfield(V,'healthyVerified') && V.healthyVerified,'pi17:baseline','Reference condition must be independently verified');
        X=[X;ones(numel(V.t),1) log(max(V.u(:,1:2),1e-8)) V.u(:,3)]; Y=[Y;V.y]; %#ok<AGROW>
    end
    M.referenceBaseline=zeros(size(M.C,1),4);
    for j=1:size(Y,2), ok=isfinite(Y(:,j)); M.referenceBaseline(j,:)=(X(ok,:)\Y(ok,j))'; end
    M.C(:,[1 4 5 6])=M.referenceBaseline; M.baselineFixed=true;
end
bestScore=Inf; best=M; rows=cell(0,10); stabilized=false; lastOpt=struct('exitflag',0);
for it=1:c.observedIterations
    before=[parameter_vector(M);M.C(:)];
    [M,opt]=observed_parameter_fit(M,train,c,c.observedFitSteps);
    if c.refineEmission, M=observed_emission_update(M,train,c); end
    % Approximate population frailty variance from centered unit MAPs. A floor
    % prevents zero spread; this is not a full hyperparameter Bayesian posterior.
    M.unitSD=max(.04,min(.6,sqrt(mean(M.trainingEta.^2))));
    opt=final_observed_gradient(opt,M,train,c);
    loss=observed_loss(M,train,c); score=forecast_score(M,val,Q,c,eid);
    change=norm([parameter_vector(M);M.C(:)]-before)/max(norm(before),1);
    rows(end+1,:)={it,loss,-loss,score,change,opt.exitflag,opt.gradientNorm,NaN,NaN,mean(M.sensorSD)}; %#ok<AGROW>
    fprintf('  observed fit B=%d cycle %d: NLL %.5g | causal VAL %.5g | change %.3g | flag %d/grad %.3g\n', ...
        useB,it,loss,score,change,opt.exitflag,opt.gradientNorm);
    if score<bestScore, bestScore=score; best=M; best.selectedIteration=it; best.selectedMStep=opt; end
    lastOpt=opt;
    if it>=2 && change<c.emTolerance && opt.exitflag>0, stabilized=true; break; end
end
M=best; M.validationScore=bestScore;
M.fitTrace=cell2table(rows,'VariableNames',{'iteration','expectedCompleteNLL','logEvidencePerUnit', ...
    'causalValidationLoss','relativeParameterChange','mStepExitflag','mStepGradientNorm','meanESS','etaAcceptance','meanSensorSD'});
M.optimization=struct('status','Observed B-marginal Gaussian likelihood plus centered frailty MAP', ...
    'stabilized',stabilized,'selectedIteration',M.selectedIteration,'selectedMStepExitflag',M.selectedMStep.exitflag, ...
    'lastMStepExitflag',lastOpt.exitflag,'gradientNorm',M.selectedMStep.gradientNorm);
end

function M=fit_observed_population(train,val,Q,c,eid)
fprintf('  v17: fit no-B control, then TRAIN-only covariance multistart.\n');
withoutB=v17_fit_population_one(train,val,Q,c,eid,false);
withB=v17_fit_B_multistart(withoutB,train,val,Q,c,eid);
geometry=v17_covariance_geometry(withB,train,c);withB.covarianceDiagnostic=geometry;
withB.BtauProfile=v17_tau_profile(withB,train,c);
v1=observed_validation(withB,val,c);v0=observed_validation(withoutB,val,c);gain=v0-v1;gg=gain(isfinite(gain));
se=std(gg)/sqrt(numel(gg));predictive=mean(gg)>c.observationSEMultiplier*se;
converged=v17_converged(withB.selectedMStep,c)&&v17_converged(withoutB.selectedMStep,c);
if strcmp(c.trainingLikelihood,'event_time') && c.requireResolvedPopulation && ~converged
 error('pi17:unresolvedPopulation','B/no-B comparison is unresolved after TRAIN recovery. The experiment is deferred; an unresolved control is never used as an operational fallback.');
end
if ~converged,fprintf('  ESTIMATION UNRESOLVED: B/no-B comparison; continuing collection with explicit eligibility flags.\n');end
retain=predictive && converged && geometry.localCovarianceSupported;
M=withoutB;if retain,M=withB;end
M.Bselection=table({val.id}',v1,v0,gain,'VariableNames',{'unit','BObservedNLL','noBObservedNLL','gainFromB'});
M.Bdecision=struct('retained',retain,'meanGain',mean(gg),'standardError',se, ...
 'covarianceMinimumSingularValue',geometry.minimumSingularValue,'comparisonConverged',converged, ...
 'observationPredictiveSupport',predictive,'localCovarianceSupported',geometry.localCovarianceSupported, ...
 'physicalStateIdentityEstablished',false,'criterion','Converged fits + paired VAL observation gain > configured SE multiple + interior supported covariance and correlation guard; no physical identity claim');
M.BfitCandidates=struct('withB',withB,'withoutB',withoutB);
M.Balternative=struct('withBValidation',mean(v1,'omitnan'),'noBValidation',mean(v0,'omitnan'));
M.label='Physics_SSM';
fprintf('  B retain=%d, observation support=%d, covariance support=%d, converged=%d; paired gain %.6g SE %.6g.\n',retain,predictive,geometry.localCovarianceSupported,converged,mean(gg),se);
fprintf('  B tau %.5g h, effective loading %s, measurement SD %s. B has unit stationary variance.\n',withB.tau,mat2str(withB.C(:,3)',4),mat2str(withB.sensorSD,4));
fprintf('  RUL VAL loss: B %.7g; no-B %.7g. Observation likelihood and RUL accuracy are distinct.\n',withB.validationScore,withoutB.validationScore);
end

function scores=observed_validation(M,units,c)
scores=zeros(numel(units),1);
for i=1:numel(units)
    U=units(i); [ks,~]=origin_nodes(U,c);
    if isempty(ks), scores(i)=NaN; continue; end
    k=ks(end); H=causal_prefix(U,k);
    eta=linspace(-c.unitEffectMax,c.unitEffectMax,c.etaGridPoints);
    D=observed_trajectory(M,H,eta,c); v=observed_kalman(M,H,D,c);
    lp=-.5*(eta/M.unitSD).^2; lp=lp-logsumexp_base(lp);
    live=all(D<c.Dcrit,1); v(~live)=Inf;
    scores(i)=-logsumexp_base(lp-v)/max(sum(isfinite(H.y(:))),1);
end
end

function y=logsumexp_base(x)
mx=max(x); if ~isfinite(mx), y=mx; else, y=mx+log(sum(exp(x-mx))); end
end

function P=observed_prefix(M,H,c,storePaths,N)
% Fixed eta quadrature, exact conditional Gaussian B, past-only summaries.
eta=linspace(-c.unitEffectMax,c.unitEffectMax,c.etaGridPoints)';
D=observed_trajectory(M,H,eta,c); [nll,KF]=observed_kalman(M,H,D,c,false);
lp=-.5*(eta'/M.unitSD).^2; lp=lp-logsumexp_base(lp); lw=lp-nll;
lw(~all(D<c.Dcrit,1))=-Inf;
assert(any(isfinite(lw)),'pi17:profile','No surviving unit-rate trajectory; inspect mapping/grid');
w=normalized_weights(lw'); ix=systematic_resample(w,N); K=numel(H.t);
filtered=zeros(K,3); ESS=zeros(K,1); eventMass=zeros(K,1); innovations=nan(size(H.y));
for k=1:K
    prior=lp;
    if k>1, prior=prior-KF.cumulativeNLL(k-1,:); prior(any(D(1:k-1,:)>=c.Dcrit,1))=-Inf; end
    wp0=normalized_weights(prior'); live=D(k,:)'<c.Dcrit;
    eventMass(k)=sum(wp0(live));
    prior(~live')=-Inf; wp=normalized_weights(prior');
    current=lp-KF.cumulativeNLL(k,:); current(~live')=-Inf; ww=normalized_weights(current');
    filtered(k,:)=[D(k,:)*ww KF.mean(k,:)*ww eta'*ww]; ESS(k)=1/sum(ww.^2);
    if storePaths
        mu=emission_features(D(k,:)',KF.predictedMean(k,:)',repmat(H.u(k,:),numel(eta),1))*M.C';
        avg=wp'*mu; variance=wp'*(mu-avg).^2+M.sensorSD.^2+KF.predictedVariance(k)*M.C(:,3)'.^2;
        ok=isfinite(H.y(k,:)); innovations(k,ok)=(H.y(k,ok)-avg(ok))./sqrt(variance(ok));
    end
end
pathD=[]; pathB=[];
if storePaths, pathD=D(:,ix)'; pathB=sample_B_smoother(M,H,KF,ix); end
B=KF.mean(end,ix)'+sqrt(max(KF.variance(end),0))*randn(N,1);
P=struct('D',D(end,ix)','B',B,'eta',eta(ix),'weights',ones(N,1)/N, ...
    'filteredMean',filtered,'ESS',ESS,'eventMass',eventMass,'logEvidence',logsumexp_base(lw), ...
    'resamples',1,'distinctRateParticles',numel(unique(eta(ix))),'etaAcceptance',NaN, ...
    'pathD',pathD,'pathB',pathB,'innovations',innovations,'cdfUnderflowParticles',0, ...
    'etaGrid',eta,'etaWeights',w,'BconditionalVariance',KF.variance, ...
    'status','Rao-Blackwellized deterministic-fatigue unit-effect grid; Gaussian B conditional on D');
end

function ref=observed_reference(M,train,c)
ref=struct('D',[],'B',[],'u',[],'unit',[]);
for i=1:numel(train)
 if isfield(M,'trainingDMean') && numel(M.trainingDMean)==numel(train) && numel(M.trainingDMean{i})==numel(train(i).t)
  D=M.trainingDMean{i}; % E[D|TRAIN], rather than D(E[eta|TRAIN]).
 else,D=observed_trajectory(M,train(i),M.trainingEta(i),c);end
 ref.D=[ref.D;D(1:end-1)];ref.B=[ref.B;zeros(numel(D)-1,1)]; %#ok<AGROW>
 ref.u=[ref.u;train(i).u(1:end-1,:)];ref.unit=[ref.unit;i*ones(numel(D)-1,1)]; %#ok<AGROW>
end
ref.G=physical_scores(M,ref.D,ref.u,c);ref.pinvG=pinv(ref.G,c.projectionTolerance);
ref.lo=min(ref.u,[],1);ref.hi=max(ref.u,[],1);pad=.1*(ref.hi-ref.lo)+[.025 .025 .05];
ref.lo=max([0 0 -Inf],ref.lo-pad);ref.hi=ref.hi+pad;ref.gmax=score_envelope(M,ref.lo,ref.hi,c);
end

function [loss,M]=observed_joint_objective(v,M,x,free,train,c)
nf=numel(free); x(free)=v(1:nf);
if isfield(M,'residualFamily') && strcmp(M.residualFamily,'fixed_basis'), M.nn.w=v(nf+1:end);
else, M.nn=unpack_network(v(nf+1:end),c.hidden1,c.hidden2,5); end
M.nn.w=project_l1(M.nn.w,M.bound); M=observed_decode(x,M,numel(train),c);
loss=observed_loss(M,train,c);
end

function [score,unit]=stable_score(M,val,Q,c,eid)
u=zeros(numel(val),c.selectionSeeds);
for s=1:c.selectionSeeds, [~,u(:,s)]=forecast_score(M,val,Q,c,eid+1000*(s-1)); end
unit=mean(u,2,'omitnan'); score=mean(unit,'omitnan');
end

function M=fit_observed_primary(train,val,Q,base,c,eid)
if c.profileObserved, M=v17_fit_primary(train,val,Q,base,c,eid); return; end
[best,baseUnits]=stable_score(base,val,Q,c,eid);
budget=c.jointSteps*c.residualCycles*sum(c.residualBounds>0);
control=base; controlOpt=base.selectedMStep;
for controlCycle=1:c.residualCycles
    [control,controlOpt]=observed_parameter_fit(control,train,c,max(1,ceil(budget/c.residualCycles)));
    if c.jointRefineEmission, control=observed_emission_update(control,train,c); end
    controlOpt=final_observed_gradient(controlOpt,control,train,c);
end
[controlScore,controlUnits]=stable_score(control,val,Q,c,eid);
takeControl=controlScore<best;
if takeControl, base=control; best=controlScore; baseUnits=controlUnits; end
base.extraPhysicsControlSelected=takeControl;
base.predictionOptimization=base.selectedMStep;
if takeControl, base.predictionOptimization=controlOpt; end
base.extraPhysicsControl=controlOpt; base.validationScore=best;
fprintf('  Physics-only refinement: %d BFGS steps, VAL %.5g, flag %d.\n',budget,controlScore,controlOpt.exitflag);
M=base; M.label='PI_DSSDM'; M.residualFamily=c.primaryFamily;
rows={0,0,best,0,0,NaN,0,0,0}; selected=table(); M.networkTrace=table();
for bound=c.residualBounds(c.residualBounds>0)
    candidate=base; candidate.bound=bound; candidate.residualFamily=c.primaryFamily; rng(c.seed+eid*100+47);
    candidate.nn=init_network(c.hidden1,c.hidden2,5);
    if strcmp(c.primaryFamily,'fixed_basis'), candidate.nn.W1(:)=0; candidate.nn.W2(:)=0; candidate.nn.b1(:)=0; candidate.nn.b2(:)=0; end
    candidate.reference=observed_reference(base,train,c); candidate=project_network(candidate,c);
    for cycle=1:c.residualCycles
        [x,free]=observed_encode(candidate,numel(train),c);
        nw=pack_network(candidate.nn); if strcmp(c.primaryFamily,'fixed_basis'), nw=candidate.nn.w; end
        initial=[x(free);nw];
        fun=@(v)observed_joint_objective(v,candidate,x,free,train,c);
        [v,loss,opt]=robust_bfgs(fun,initial,c.jointSteps,c);
        [~,candidate]=observed_joint_objective(v,candidate,x,free,train,c);
        if c.jointRefineEmission, candidate=observed_emission_update(candidate,train,c); end
        opt=final_joint_gradient(opt,candidate,train,c);
        [score,unit]=stable_score(candidate,val,Q,c,eid);
        gains=baseUnits-unit; gains=gains(isfinite(gains));
        assert(~isempty(gains),'pi17:selection','No common eligible validation units');
        improvement=mean(gains); se=std(gains)/sqrt(numel(gains));
        rho=discrepancy(candidate,candidate.reference.D,zeros(size(candidate.reference.D)),candidate.reference.u);
        rows(end+1,:)={bound,cycle,score,sqrt(mean(rho.^2)),max(abs(rho)),opt.gradientNorm,improvement,se,opt.exitflag}; %#ok<AGROW>
        fprintf('  JOINT residual %.2f cycle %d: observed NLL %.5g | stable VAL %.5g | paired gain %.4g/SE %.4g | flag %d\n', ...
            bound,cycle,loss,score,improvement,se,opt.exitflag);
        % A neural correction must improve over physics alone beyond paired unit
        % uncertainty. This conservative rule uses only independent VAL units.
        if score<best && improvement>max(c.minimumValidationGain,c.oneSEMultiplier*se)
            best=score; M=candidate; selected=table(cycle,loss,score,sqrt(mean(rho.^2)),max(abs(rho)),opt.gradientNorm, ...
                'VariableNames',{'cycle','expectedRateNLL','causalValidationLoss','rhoRMS','rhoMaxAbs','gradientNorm'});
            M.networkTrace=array2table([(1:size(opt.trace,1))' opt.trace(:,1:2)],'VariableNames',{'iteration','loss','gradientNorm'});
            M.jointOptimization=opt;
        end
    end
end
M.label='PI_DSSDM'; M.validationScore=best;
M.selection=cell2table(rows,'VariableNames',{'bound','cycle','causalValidationLoss','rhoRMS','rhoMaxAbs','gradientNorm','pairedUnitGain','pairedGainSE','exitflag','eligible','jointFeasibleGradientNorm'});
M.residualTrace=selected; M.optimization=struct('status','Joint constrained observed-likelihood fit and paired unit conservative selection', ...
    'physicsFrozen',false,'selectedBound',M.bound,'validationLogRULLoss',best);
M.physicsControl=base;
fprintf('  %s selected bound %.3g. Paired VAL one-SE rule; physics/emission refined with TRAIN only.\n',c.primaryFamily,M.bound);
end

function I=observed_identifiability(M,train,c,eid)
[x,free]=observed_encode(M,numel(train),c); names={'logRate','loadExponent','temperatureCoefficient','logAgingPlusFloor','logTau','logBsd'};
for j=1:numel(train)-1, names{end+1}=sprintf('centeredUnit_%d',j); end %#ok<AGROW>
[~,r]=observed_loss(M,train,c,false); J=zeros(numel(r),numel(free));
for j=1:numel(free)
    z=free(j); h=c.jacobianStep*max(1,abs(x(z))); p=x; q=x; p(z)=p(z)+h; q(z)=q(z)-h;
    [~,rp]=observed_loss(observed_decode(p,M,numel(train),c),train,c,false);
    [~,rq]=observed_loss(observed_decode(q,M,numel(train),c),train,c,false);
    J(:,j)=(rp-rq)/(2*h);
end
norms=sqrt(sum(J.^2,1)); active=norms>c.rankTolerance*max(norms); A=J(:,active)./max(norms(active),eps);
ss=svd(A,'econ'); rankA=sum(ss>c.rankTolerance*max(ss)); pc=nan(4);
phys=find(ismember(free,1:4)); nuisance=setdiff(1:numel(free),phys);
P=J(:,phys)-J(:,nuisance)*(pinv(J(:,nuisance))*J(:,phys)); sp=svd(P,'econ'); pr=sum(sp>c.rankTolerance*max(svd(J(:,phys),'econ')));
if pr==numel(phys)
    V=pinv(P'*P); sd=sqrt(max(diag(V),eps)); ci=V./(sd*sd'); pc(free(phys),free(phys))=ci;
end
cosine=J'*J./max(norms'*norms,eps); pairs=cell(0,3);
for i=1:numel(free), for j=i+1:numel(free)
    if abs(cosine(i,j))>.95, pairs(end+1,:)={names{free(i)},names{free(j)},cosine(i,j)}; end %#ok<AGROW>
end, end
S=observed_reference(M,train,c); S.D0=S.D; S.B0=S.B;
rho=discrepancy(M,S.D,zeros(size(S.D)),S.u); um=accumarray(S.unit,rho,[],@mean);
if c.profileObserved
    profiles=v17_profile_scan(M,train,c);
else
profiles=cell(0,7);
for z=intersect([1 2 4],free)*double(c.enableProfiles)
    if z==0, continue; end
    for value=x(z)+linspace(-.25,.25,c.profilePoints)
        xx=x; xx(z)=value; ff=setdiff(free,z); fun=@(v)observed_coordinates(v,xx,ff,M,train,c);
        [v,loss,out]=bfgs_fd(fun,xx(ff),c.profileIterations,c.gradientTolerance); xx(ff)=v;
        mm=observed_decode(xx,M,numel(train),c); vals=[mm.k mm.p mm.betaT mm.a];
        profiles(end+1,:)={z,value,vals(z),loss,out.exitflag,out.iterations,out.gradientNorm}; %#ok<AGROW>
    end
end
end
rankEmission=Inf; minE=Inf;
for d=linspace(0,c.Dcrit,20)
    E=[M.C(:,2)+2*d*M.C(:,7) M.C(:,3)]./M.sensorSD'; es=svd(E);
    rankEmission=min(rankEmission,sum(es>c.rankTolerance*max(es))); minE=min(minE,min(es));
end
I=struct('names',{names(free)},'activeParameters',sum(active),'activeRank',rankA, ...
    'singularValues',ss,'Jacobian',J,'informationSurrogate',J'*J,'physicsConditionalRank',pr, ...
    'physicsCorrelations',pc,'sensitivityCosines',cosine,'confoundedPairs',cell2table(pairs, ...
    'VariableNames',{'parameter1','parameter2','sensitivityCosine'}),'minimumEmissionRank',rankEmission, ...
    'minimumEmissionSingularValue',minE,'rhoRMS',sqrt(mean(rho.^2)),'rhoMaxAbs',max(abs(rho)), ...
    'physicalScoreOverlap',S.G'*rho/max(numel(rho),1),'unitMeanResidualRMS',sqrt(mean(um.^2)), ...
    'profiles',cell2table(profiles,'VariableNames',{'coordinate','transformedValue','physicalValue', ...
    'penalizedUnitMarginalNLLPerObservation','exitflag','iterations','gradientNorm'}),'smoothingSummary',S, ...
    'referencePhysicalOverlap',0,'rankAt1e5',sum(ss>1e-5*max(ss)), ...
    'note','Observed Kalman-whitened innovation sensitivities include propagated D and integrated B. Emission, noise, and NN coefficients conditioned on; covariance derivative omitted. J''J is not full Fisher information; v17 profiles reoptimize the penalized profiled objective; they are not confidence intervals.');
if M.bound>0, I.referencePhysicalOverlap=M.projection.referenceOrthogonality; end
fprintf('  Observed sensitivity rank %d/%d; at 1e-5 %d; physics %d/%d.\n',rankA,sum(active),I.rankAt1e5,pr,numel(phys));
if c.enableFullInformation, I.fullInformation=observed_full_information(M,train,c);
else, I.fullInformation=v17_skipped_information(); end
end

function print_observed_diagnostics(E,c)
M=E.models{1};P=E.models{4};I=E.identifiability;
fprintf('\nHIERARCHICAL PI-DSSDM v17:\n');
fprintf('D is irreversible conditional fatigue; B is an optional observation-residual state, subject to held-out checks. Exact TRAIN failure clocks use change of variables; forecast eta uses past-only survival-conditioned inference.\n');
fprintf('Population eta prior mean is zero. Posterior TRAIN means sum %.4g; these are not centered MAP coordinates.\n',sum(M.trainingEta));
fprintf('B retained=%d, VAL observation gain %.5g (SE %.5g).\n',M.useB,P.Bdecision.meanGain,P.Bdecision.standardError);
disp(table({'rate';'load exponent';'temperature';'aging';'B tau';'B SD (fixed reference)';'population eta SD'}, ...
 [M.k;M.p;M.betaT;M.a;M.tau;M.sigmaB;M.unitSD],[P.k;P.p;P.betaT;P.a;P.tau;P.sigmaB;P.unitSD], ...
 'VariableNames',{'parameter','PI_DSSDM','Physics_SSM'}));
fprintf('Final event/survival emission profile converged=%d; stationarity %.4g; %d nodes/unit.\n', ...
 M.marginalDiagnostic.emissionConverged,M.marginalDiagnostic.emissionStationarity,M.marginalDiagnostic.quadratureNodes);
fprintf('Observation C [1 D B logLoad logSpeed T D2]:\n');disp(M.C);
fprintf('UNIT-score rank %d/%d; conditional physical rank %d.\n%s\n',I.activeRank,I.activeParameters,I.physicsConditionalRank,I.note);
fprintf('Profile valid %d/%d.\n',sum(isfinite(I.profiles.penalizedUnitMarginalNLLPerObservation)),height(I.profiles));disp(I.profiles);
fprintf('%s\n',I.fullInformation.note);
if c.enableFullInformation,fprintf('Conditional marginal profile curvature rank %d/%d, condition %.4g, negative directions %d.\n',I.fullInformation.rank,I.fullInformation.activeParameters,I.fullInformation.scaledConditionNumber,I.fullInformation.negativeCurvatureDirections);end
fprintf('Unit-bootstrap parameter mixtures are used when configured and adequate; complete model uncertainty is not claimed.\n');
fprintf('Selection (converged marginal candidates, VAL-only one-SE):\n');disp(M.selection);
fprintf('Actual selected optimizer checkpoints:\n');disp(E.optimizerAudit);
fprintf('Observed TRAIN population unit SD %.5g; posterior unit SD mean %.5g.\n',M.unitSD,mean(M.trainingEtaSD));
fprintf('FORECAST METRICS, median first passage; positive bias is optimistic:\n');disp(E.metrics);
fprintf('ALPHA-LAMBDA accuracy alpha %.2f:\n',c.alpha);disp(E.alphaLambda);
fprintf('Calibration uses independent CAL units:\n');disp(E.calibration);
fprintf('State origin audit and all-method numerical resolution:\n');disp(E.stateOriginAudit);disp(E.methodNumerics);
end

function write_observed_report(R)
f=fopen(fullfile(R.outputDir,'Run_report.txt'),'w'); cl=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'PI-DSSDM v17.2.0\nSource SHA256: %s\n%s\n\n',R.provenance.newSHA256,R.config.label);
fprintf(f,['Fatigue D, operating-conditioned emission, zero-mean residual B selected on independent validation observations.\n' ...
    'B integrated analytically; proper exact-failure or right-censor likelihood for TRAIN units.\n' ...
    'Bounded deep residual jointly refines physics; conservative paired validation one-SE selection.\n' ...
    'Outcome-independent inspection/gap schedules and calendar origins; no inspections by default.\n' ...
    'PINN positive neural rate is propagated through first passage, with integrated-B eta inference.\n' ...
    'No physical fatigue RUL claim from uncalibrated OPC-UA torque/current/speed/position/temperature.\n' ...
    'Raw intervals include successful configured unit-bootstrap refits. Architecture/duty choices remain conditional; independent damage diffusion is absent.\n' ...
    'Empirical UNIT-score sensitivity profiles emission and conditions on the encoder; not complete population Fisher information.\n' ...
    'Conditional observed-likelihood profiles are penalized sensitivity checks, not confidence limits.\n' ...
    'Repeated independent fleets, not dependent forecast rows, quantify training variability. No superiority guarantee.\n\n']);
for e=1:numel(R.experiments)
    E=R.experiments{e}; M=E.models{1}; P=E.models{4}; I=E.identifiability;
    fprintf(f,'%s: B %d, bound %.4g, rank %d/%d, fit stable %d, selected flag %d, PINN flag %d.\n', ...
        E.evidence,M.useB,M.bound,I.activeRank,I.activeParameters,P.optimization.stabilized, ...
        P.optimization.selectedMStepExitflag,E.models{2}.optimization.exitflag);
end
end

function T=observed_selftests(c)
cc=c; cc.architecture='observed'; cc.trainUnits=3; cc.validationUnits=2; cc.calibrationUnits=12; cc.testUnits=2;
cc.etaGridPoints=81; U=generate_fleet(cc,'matched',29); M=initial_model(strip_truth(U(1:3)),cc);
H=causal_prefix(U(4),round(numel(U(4).t)*.6)); names={};
x=observed_encode(M,3,cc); x(7:8)=[.1;-.05]; M=observed_decode(x,M,3,cc);
assert(abs(sum(M.trainingEta))<1e-12 && all(M.gamma==0) && M.kappa==0);
names{end+1}='centered frailty and operating-emission separation enforced';
D=observed_trajectory(M,H,[0 .1],cc); assert(all(diff(D,1,1)>=0,'all'));
[nll,K]=observed_kalman(M,H,D,cc,true); assert(all(isfinite(nll)) && all(K.variance>=0));
names{end+1}='marginal reversible-state likelihood finite and positive variance';
% Rank-one likelihood equals direct multivariate Gaussian algebra.
HH=H; HH.t=0; HH.y=H.y(1,:); HH.u=H.u(1,:); HH.inspection=NaN;
DD=.2; v=observed_kalman(M,HH,DD,cc); mu=emission_features(DD,0,HH.u)*M.C';
V=diag(M.sensorSD.^2)+M.sigmaB^2*(M.C(:,3)*M.C(:,3)'); e=(HH.y-mu)';
direct=.5*(numel(e)*log(2*pi)+log(det(V))+e'*(V\e)); assert(abs(v-direct)<1e-8);
names{end+1}='integrated B likelihood matches direct Gaussian covariance';
N=M; N.useB=false; N.sigmaB=0; N.C(:,3)=0;
v=observed_kalman(N,HH,DD,cc); rr=(HH.y-emission_features(DD,0,HH.u)*N.C')./N.sensorSD;
assert(abs(v-(.5*sum(rr.^2)+sum(log(sqrt(2*pi)*N.sensorSD))))<1e-8);
names{end+1}='no-B model reduces exactly to independent measurement likelihood';
rng(72); P=observed_prefix(M,H,cc,true,60); assert(all(P.D<cc.Dcrit) && all(diff(P.pathD,1,2)>=0,'all'));
names{end+1}='Rao-Blackwellized fatigue posterior respects survival and monotonic paths';
V=U(4); k=numel(H.t); V.y(k+1:end,:)=1e6; V.u(k+1:end,:)=9; V.truth.D(:)=1e6;
H2=causal_prefix(V,k); rng(72); P2=observed_prefix(M,H2,cc,true,60); assert(isequaln(P,P2));
names{end+1}='new observed filter immune to future sensor and truth corruption';
mm=M; mm.p=3; mm.a=0; mm.betaT=0; idle=physics_rate(mm,[2 0 0;0 1 0]); assert(all(idle==0));
names{end+1}='zero cycles or zero load produce zero fatigue accumulation';
cc.fatigueLinearDamage=true; mm=observed_decode(x,M,3,cc); assert(mm.a==0);
names{end+1}='calibrated Miner mode structurally fixes aging to zero';
ref=observed_reference(M,strip_truth(U(1:3)),c); mm=M; mm.bound=.3; mm.reference=ref;
mm.nn.w=linspace(.1,-.05,numel(mm.nn.w))'; mm=project_network(mm,c); r1=discrepancy(mm,ref.D,zeros(size(ref.D)),ref.u);
r2=discrepancy(mm,ref.D,randn(size(ref.D))*10,ref.u);
assert(isequal(r1,r2) && max(abs(r1))<=.3 && norm(ref.G'*r1)/numel(r1)<1e-8);
names{end+1}='bounded projected fatigue discrepancy independent of nuisance B';
assert(size(ref.G,2)==numel(score_columns(c)));
names{end+1}='fixed Miner aging does not suppress learned damage-dependent discrepancy';
T=table(names',true(numel(names),1),'VariableNames',{'test','passed'});
end

function T=numerical_origin_audit(M,units,ids,Q,c,eid)
A=numerical_method_audit({M},{'PI_DSSDM'},units,ids,Q,c,eid);
T=table(A.unit,(1:height(A))',A.origin_h,A.baseRUL_h, ...
    A.baseRUL_h+A.halfStepChange_h,A.baseRUL_h+A.etaGridChange_h, ...
    A.halfStepChange_h,A.etaGridChange_h,nan(height(A),1), ...
    'VariableNames',{'unit','originIndex','origin_h','baseRUL_h','halfStepRUL_h', ...
    'doubleEtaGridRUL_h','halfStepChange_h','etaGridChange_h','fixedDutyMCsd_h'});
end

function T=state_origin_audit(P,units,ids)
rows=cell(0,6);
for i=ids
    U=units(i); if ~isfield(U,'truth') || isempty(U.truth), continue; end
    Q=P(strcmp(P.unit,U.id)&strcmp(P.method,'PI_DSSDM'),:); Q=Q(strcmp(Q.policy,Q.policy{1}),:);
    for j=1:height(Q)
        k=find(U.t<=Q.origin_h(j),1,'last'); truth=U.truth.D(k);
        rows(end+1,:)={U.id,Q.originIndex(j),Q.origin_h(j),truth,Q.estimatedD(j),Q.estimatedD(j)-truth}; %#ok<AGROW>
    end
end
T=cell2table(rows,'VariableNames',{'unit','originIndex','origin_h','trueD','estimatedD','errorD'});
end

function R=opc_operating_analysis(c)
% INIT is an operating reference, not automatically a verified undamaged unit.
% Torque/current are observations, not measured axial force. This analysis
% intentionally has no D calibration, fitted fatigue RUL, or accuracy score.
files={'Initial_data_20000.csv','Post_ALT_data_20000.csv','Before_failure_20000.csv','Failure_Mode_data_20000.csv'};
dir=fullfile(c.outputDir,['opc_audit_' datestr(now,'yyyymmdd_HHMMSS_FFF')]); mkdir(dir);
diary(fullfile(dir,'console.txt')); cl=onCleanup(@()diary('off')); %#ok<NASGU>
inventory=cell(0,6); records={}; labels={};
for i=1:numel(files)
    path=fullfile(c.telemetryDir,files{i}); if exist(path,'file')~=2, continue; end
    T=readtable(path,'VariableNamingRule','preserve'); vars=T.Properties.VariableNames;
    required={'position','speed','torque','voltage','current','temperature','times'};
    valid=all(ismember(required,vars));
    inventory(end+1,:)={files{i},height(T),width(T),valid,false,'No verified axial force, pitting damage, or fatigue failure labels'}; %#ok<AGROW>
    if ~valid, continue; end
    V=struct();
    for field={'position','speed','torque','voltage','current','temperature'}
        a=T.(field{1}); if ~isnumeric(a), a=str2double(string(a)); end
        V.(field{1})=double(a(:));
    end
    time=string(T.times); ss=seconds(duration(time,'InputFormat','hh:mm:ss.SSSSSS'));
    rollover=cumsum([0;diff(ss)<-12*3600]); ss=ss+rollover*86400; V.t=ss-ss(1);
    assert(all(diff(V.t)>=0),'pi17:opc','Nonmonotone within-record clocks require explicit timestamp repair');
    V.X=[V.speed abs(V.speed) V.position V.temperature V.voltage ...
        [0;diff(V.speed)./max(diff(V.t),1e-6)] sign(V.speed)];
    V.Y=[V.torque V.current]; records{end+1}=V; labels{end+1}=files{i}; %#ok<AGROW>
end
R=struct('inventory',cell2table(inventory,'VariableNames',{'record','rows','columns','OPCchannels', ...
    'physicalRUL_evaluable','evidence'}),'outputDir',dir);
disp(R.inventory); writetable(R.inventory,fullfile(dir,'Raw_telemetry_inventory.csv'));
assert(~isempty(records) && strcmp(labels{1},files{1}),'pi17:opc','INIT operating reference is required');
V=records{1}; n=size(V.X,1); split=max(10,floor(.7*n)); tr=1:split; va=split+1:n;
center=mean(V.X(tr,:),1); scale=max(std(V.X(tr,:),[],1),1e-6);
X=(V.X-center)./scale; A=[ones(n,1) X X(:,1).^2 X(:,2).^2 X(:,3).^2 X(:,4).^2];
pen=.1*eye(size(A,2)); pen(1,1)=0; C=(A(tr,:)'*A(tr,:)+pen)\(A(tr,:)'*V.Y(tr,:));
sd=max(sqrt(mean((V.Y(tr,:)-A(tr,:)*C).^2,1)),1e-6);
lo=min(V.X(tr,:),[],1); hi=max(V.X(tr,:),[],1); pad=.05*(hi-lo)+1e-6;
rows=cell(0,10); windows=cell(0,7); series=cell(size(records));
for i=1:numel(records)
    V=records{i}; x=(V.X-center)./scale;
    a=[ones(size(x,1),1) x x(:,1).^2 x(:,2).^2 x(:,3).^2 x(:,4).^2];
    residual=(V.Y-a*C)./sd;
    outside=any(V.X<lo-pad | V.X>hi+pad,2); use=~outside;
    if i==1, use(1:split)=false; end
    supported=sum(use); tau=NaN; corr1=NaN;
    z=residual(use,1);
    if numel(z)>10
        z=z-mean(z); corr1=sum(z(1:end-1).*z(2:end))/max(sum(z(1:end-1).^2),eps);
        if corr1>0 && corr1<1, tau=-median(diff(V.t))/log(corr1); end
    end
    med=[NaN NaN]; rmsValue=med;
    if supported>0, med=median(residual(use,:),1); rmsValue=sqrt(mean(residual(use,:).^2,1)); end
    rows(end+1,:)={labels{i},size(V.X,1),100*mean(outside),supported,med(1),med(2),rmsValue(1),rmsValue(2),corr1,tau}; %#ok<AGROW>
    for j=1:c.opcWindowRows:size(V.X,1)
        ix=j:min(j+c.opcWindowRows-1,size(V.X,1)); good=ix(~outside(ix));
        m=[NaN NaN]; if ~isempty(good), m=median(residual(good,:),1); end
        windows(end+1,:)={labels{i},V.t(ix(1)),V.t(ix(end)),numel(good),100*mean(outside(ix)),m(1),m(2)}; %#ok<AGROW>
    end
    series{i}=struct('t',V.t,'residual',residual,'outside',outside,'Y',V.Y,'prediction',a*C);
end
R.baselineCoefficients=C; R.scaling=struct('center',center,'scale',scale,'measurementSD',sd);
R.summary=cell2table(rows,'VariableNames',{'record','rows','outsideReferenceSupport_pct','supportedHeldoutRows', ...
    'medianTorqueResidual_SD','medianCurrentResidual_SD','RMSTorqueResidual_SD','RMSCurrentResidual_SD','lag1TorqueResidualCorrelation','roughResidualTau_seconds'});
R.windows=cell2table(windows,'VariableNames',{'record','start_s','end_s','supportedRows','outside_pct','torqueResidualMedian_SD','currentResidualMedian_SD'});
writetable(R.summary,fullfile(dir,'Operating_conditioned_summary.csv')); writetable(R.windows,fullfile(dir,'Operating_conditioned_windows.csv'));
writematrix(C,fullfile(dir,'OPC_baseline_coefficients.csv'));
fprintf('\nOPC-UA OPERATING REFERENCE AUDIT:\n'); disp(R.summary);
fprintf('INIT first 70%% fits the reference; last 30%% is a blocked observation check. No healthy condition is asserted.\n');
fprintf('Baseline predictors: signed/absolute speed, position, temperature, voltage, acceleration and direction.\n');
fprintf('Residual changes outside INIT operating support are withheld from supported-change interpretation.\n');
fprintf('Torque and current are coupled electromechanical observations, not two independently calibrated fatigue measurements.\n');
fprintf('Within-record clocks cannot reconstruct elapsed ALT-gap exposure or prove unit failure time.\n');
fprintf('Residual lag correlation may indicate dynamics or omitted operating effects; it does not establish physical B.\n');
fprintf('Fatigue RUL unavailable: calibrated axial load/cycle exposure and independent fatigue criterion absent.\n');
if c.makePlots
    f=new_figure(c,'OPC-UA reference and supported residual changes'); tiledlayout(numel(records),3,'TileSpacing','compact');
    for i=1:numel(records)
        S=series{i}; nexttile; plot(S.t,S.Y(:,1),'k'); hold on; plot(S.t,S.prediction(:,1),'b');
        title(labels{i},'Interpreter','none'); xlabel('Within-record seconds'); ylabel('Torque, recorded units'); grid on;
        nexttile; good=~S.outside; plot(S.t(good),S.residual(good,1),'.'); hold on;
        plot(S.t(~good),S.residual(~good,1),'.','Color',[.8 .8 .8]); xlabel('Seconds'); ylabel('Torque residual / INIT SD'); grid on;
        title('Supported color; outside-support gray');
        nexttile; plot(S.t(good),S.residual(good,2),'.'); hold on; plot(S.t(~good),S.residual(~good,2),'.','Color',[.8 .8 .8]);
        xlabel('Seconds'); ylabel('Current residual / INIT SD'); grid on;
    end
    sgtitle('Operating-conditioned OPC-UA changes; no fatigue damage or RUL labels'); save_plot(f,dir,'OPC_operating_reference',c);
end
R.instructions='Current data support operating-conditioned changes and conditional exposure scenarios. Add verified axial load mapping, continuous duty through gaps, and independent fatigue/pitting evidence before physical fatigue RUL validation.';
save(fullfile(dir,'OPC_audit.mat'),'R'); fprintf('Saved OPC-UA diagnostics to %s\n',dir);
end

function F=observed_full_information(M,train,c)
% Conditional predictive Gaussian Fisher geometry includes BOTH mean and
% covariance derivatives. Unit effects are nuisance coordinates, not integrated
% population effects. This is local information conditional on observed past.
[x,free]=observed_encode(M,numel(train),c); mask=true(size(M.C));
if M.useB, mask(2,3)=false; else, mask(:,3)=false; end
if M.baselineFixed, mask(:,[1 4 5 6])=false; end
if c.profileObserved && ~c.profileQuadraticEmission, mask(:,7)=false; end
idx=find(mask); nw=[]; if M.bound>0, nw=pack_network(M.nn); end
theta=[x(free);M.C(idx);log(M.sensorSD(:));nw];
names={'logRate','loadExponent','temperatureCoefficient','logAgingPlusFloor','logTau','logBsd'};
for i=1:numel(train)-1, names{end+1}=sprintf('centeredUnit_%d',i); end %#ok<AGROW>
names=names(free);
for i=idx', [j,k]=ind2sub(size(M.C),i); names{end+1}=sprintf('emission_%d_%d',j,k); end %#ok<AGROW>
for i=1:numel(M.sensorSD), names{end+1}=sprintf('logMeasurementSD_%d',i); end %#ok<AGROW>
for i=1:numel(nw), names{end+1}=sprintf('network_%d',i); end %#ok<AGROW>
base=predictive_moments(M,train,c); J=[];
for j=1:numel(theta)
    h=c.jacobianStep*max(1,abs(theta(j))); a=theta; b=theta; a(j)=a(j)+h; b(j)=b(j)-h;
    plus=predictive_moments(full_information_decode(a,x,free,idx,M,train,c),train,c);
    minus=predictive_moments(full_information_decode(b,x,free,idx,M,train,c),train,c);
    column=[];
    for k=1:numel(base)
        L=base{k}.L; dm=(plus{k}.mean-minus{k}.mean)/(2*h);
        dv=(plus{k}.covariance-minus{k}.covariance)/(2*h);
        wm=L\dm; wv=L\dv/L'; column=[column;wm;wv(:)/sqrt(2)]; %#ok<AGROW>
    end
    if isempty(J), J=zeros(numel(column),numel(theta)); end
    J(:,j)=column;
end
norms=sqrt(sum(J.^2,1)); active=norms>c.rankTolerance*max(norms);
A=J(:,active)./max(norms(active),eps); ss=svd(A,'econ'); rankA=sum(ss>c.rankTolerance*max(ss));
phy=find(ismember(free,1:4)); nuisance=setdiff(1:numel(theta),phy); N=J(:,nuisance);
P=J(:,phy)-N*(pinv(N,c.rankTolerance*max(norm(N,2),1))*J(:,phy)); sp=svd(P,'econ');
pr=sum(sp>c.rankTolerance*max(svd(J(:,phy),'econ'))); corr=nan(4);
if pr==numel(phy)
    V=pinv(P'*P); sd=sqrt(max(diag(V),eps)); corr(free(phy),free(phy))=V./(sd*sd');
end
F=struct('names',{names},'rank',rankA,'activeParameters',sum(active),'activeMask',active, ...
    'singularValues',ss,'information',J'*J,'physicsRank',pr,'physicsParameters',numel(phy), ...
    'physicsCorrelations',corr,'scaledConditionNumber',max(ss)/max(min(ss),eps),'note', ...
    'Local predictive Gaussian mean/covariance information, propagated D and integrated B, free emission/noise/active NN/centered frailty included. Conditional on observed history and fitted frailty hyperparameters, not full population-marginal Fisher or proof of physical damage identity.');
end

function M=full_information_decode(v,x,free,idx,M,train,c)
n=numel(free); x(free)=v(1:n); j=n;
M.C(idx)=v(j+1:j+numel(idx)); j=j+numel(idx);
M.sensorSD=exp(v(j+1:j+numel(M.sensorSD)))'; j=j+numel(M.sensorSD);
if j<numel(v), M.nn=unpack_network(v(j+1:end),c.hidden1,c.hidden2,5); M.nn.w=project_l1(M.nn.w,M.bound); end
M=observed_decode(x,M,numel(train),c);
end

function A=predictive_moments(M,train,c)
A={};
for i=1:numel(train)
    U=train(i); D=observed_trajectory(M,U,M.trainingEta(i),c); [~,K]=observed_kalman(M,U,D,c);
    mu=emission_features(D,K.predictedMean,U.u)*M.C';
    for k=1:numel(U.t)
        ok=isfinite(U.y(k,:));
        if any(ok)
            cb=M.C(ok,3); V=diag(M.sensorSD(ok).^2)+K.predictedVariance(k)*(cb*cb');
            A{end+1}=struct('mean',mu(k,ok)','covariance',V,'L',chol(V,'lower')); %#ok<AGROW>
        end
        if isfinite(U.inspection(k))
            A{end+1}=struct('mean',D(k),'covariance',c.inspectionSD^2,'L',c.inspectionSD); %#ok<AGROW>
        end
    end
    if U.failureObserved
        A{end+1}=struct('mean',D(end),'covariance',c.terminalDamageTolerance^2,'L',c.terminalDamageTolerance); %#ok<AGROW>
    end
end
end

function R=recheck_synthetic_results(path)
% Refit only the actual LSTM and re-evaluate saved physics models, permitting
% comparator/presentation checks without silently changing physical fits.
% Regeneration is allowed ONLY for known synthetic fleets and is identity-checked.
S=load(path,'R'); R=S.R; c=R.config;
assert(strcmp(R.version,'17.2.0'),'pi17:version','Recheck requires v17 results with the v17 sampling protocol');
assert(all(cellfun(@(E)startsWith(E.evidence,'SYNTHETIC:'),R.experiments)), ...
    'pi17:recheck','Recheck requires stored synthetic fleets; physical data cannot be reconstructed');
priorSHA=R.provenance.newSHA256; priorDir=R.outputDir;
R.outputDir=fullfile(fileparts(priorDir),['rechecked_' datestr(now,'yyyymmdd_HHMMSS_FFF')]); mkdir(R.outputDir);
diary(fullfile(R.outputDir,'console.txt')); cl=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('Rechecked synthetic validation. Physical/PINN fits preserved; LSTM left-padding training repeated if enabled.\n');
fprintf('Prior fit source SHA256 %s\n',priorSHA);
R.tests=selftest(configuration()); disp(R.tests);
R.metrics=table(); R.predictions=table(); R.alphaLambda=table();
for e=1:numel(R.experiments)
    E=R.experiments{e}; scenario=ceil(e/c.replicates); rep=mod(e-1,c.replicates)+1;
    units=generate_fleet(c,c.scenarios{scenario},c.seed+1000*scenario+rep); ids=E.ids;
    train=strip_truth(units(ids.train)); val=strip_truth(units(ids.validation));
    assert(isequaln(train,E.trainingUnits) && isequaln(val,E.validationUnits),'pi17:identity','Recreated synthetic observations differ');
    if c.enableLSTM, E.models{3}=fit_lstm(train,val,c,e); end
    [cal,~,~]=predict_group(units,ids.calibration,E.models,E.methodNames,E.dutyModel,c,e,E.evidence,false);
    [test,F,A]=predict_group(units,ids.test,E.models,E.methodNames,E.dutyModel,c,e,E.evidence,true);
    ix=~strcmp(test.method,'LSTM'); old=E.predictions;
    assert(isequaln(test.predictedRUL_h(ix),old.predictedRUL_h(ix)), ...
        'pi17:recheck','Non-LSTM forecasts changed; preserved-fit comparison refused');
    [test,C]=calibrate_bands(cal,test,c); [T,AL]=metrics(test,c);
    E.calibrationPredictions=cal; E.predictions=test; E.filterDiagnostics=F; E.ablation=A;
    E.calibration=C; E.metrics=T; E.alphaLambda=AL;
    print_diagnostics(E,c); export_experiment(E,e,R.outputDir);
    if c.makePlots, plot_experiment(E,c,e,R.outputDir); end
    R.experiments{e}=E; R.metrics=[R.metrics;T]; R.predictions=[R.predictions;test]; R.alphaLambda=[R.alphaLambda;AL]; %#ok<AGROW>
end
R.provenance=source_provenance(c); R.provenance.preservedFitSHA256=priorSHA; R.provenance.preservedFitDirectory=priorDir;
writetable(R.metrics,fullfile(R.outputDir,'Benchmark_metrics.csv'));
writetable(R.predictions,fullfile(R.outputDir,'RUL_predictions.csv'));
writetable(R.alphaLambda,fullfile(R.outputDir,'Alpha_lambda.csv'));
copyfile([mfilename('fullpath') '.m'],fullfile(R.outputDir,'Source_BSFD_PI_DSSDM_Hierarchical_v17.m'));
R.fleetComparisons=fleet_comparisons(R);
writetable(R.fleetComparisons,fullfile(R.outputDir,'Paired_fleet_comparisons.csv'));
write_report(R); if c.makePlots, plot_benchmark(R); end
save(fullfile(R.outputDir,'Results.mat'),'R','-v7.3');
disp(R.metrics); fprintf('Rechecked outputs: %s\n',R.outputDir);
end

% =====================================================================
% V9 EDGE EXPORT. Writes a distinct v17 schema and MATLAB golden forecasts.
% The existing v8 Python runtime requires an explicit v17 implementation and
% parity testing before accepting these bundles. This package does not update
% that external runtime. PINN exposure and protected-score indices are exported.
% Usage:
%   BSFD_PI_DSSDM_Hierarchical_v17('export_edge',struct( ...
%       'edgeResultsFile','C:\...\runs\run_YYYYMMDD_...\Results.mat','edgeExperiment',1))
% =====================================================================
function X=export_edge(c)
old=rng; restoreRng=onCleanup(@()rng(old)); %#ok<NASGU>
assert(~isempty(c.edgeResultsFile) && exist(c.edgeResultsFile,'file')==2,'pi17:edge', ...
    'Set edgeResultsFile to the Results.mat (or checkpoint.mat) of a finished v17 run.');
S=load(c.edgeResultsFile,'R'); assert(isfield(S,'R'),'pi17:edge','The file holds no R struct'); R=S.R;
assert(isfield(R,'version') && strcmp(R.version,'17.2.0'),'pi17:edge','Results were not produced by version 17.2.0');
assert(~isempty(R.experiments),'pi17:edge','Results hold no finished experiment');
e=c.edgeExperiment;
assert(e>=1 && e<=numel(R.experiments) && e==fix(e),'pi17:edge','No experiment %d in the results',e);
E=R.experiments{e}; cr=R.config;
assert(strcmp(cr.architecture,'observed'),'pi17:edge','The edge runtime implements the observed architecture only');
out=c.edgeExportFile;
if isempty(out), out=fullfile(fileparts(c.edgeResultsFile),sprintf('BSFD_v17_edge_export_e%d.mat',e)); end
if exist('OCTAVE_VERSION','builtin')~=0, platform='Octave'; else, platform='MATLAB'; end
names=E.methodNames; models=E.models;
X=struct('format','bsfd-edge-v17-export-1','version',R.version,'experiment',e,'evidence',E.evidence, ...
    'resultsFile',c.edgeResultsFile,'resultsSHA256',edge_hash(c.edgeResultsFile),'platform',platform, ...
    'created',datestr(now,'yyyy-mm-ddTHH:MM:SS'));
X.config=cr; X.methods=names; X.models=cell(1,numel(models));
for m=1:numel(models), X.models{m}=edge_model(models{m},names{m}); end
Q=E.dutyModel; X.duty=struct('current',Q.current,'next',Q.next,'mean',Q.mean,'sd',Q.sd);
X.calibration=edge_columns(E.calibration); X.metrics=edge_columns(E.metrics);
U=vertcat(E.trainingUnits.u); Y=vertcat(E.trainingUnits.y); sp=zeros(numel(E.trainingUnits),1);
for i=1:numel(E.trainingUnits), sp(i)=median(diff(E.trainingUnits(i).t)); end
ym=zeros(1,size(Y,2)); for j=1:size(Y,2), v=Y(isfinite(Y(:,j)),j); if isempty(v), ym(j)=NaN; else, ym(j)=mean(v); end, end
X.trainingSupport=struct('uMin',min(U,[],1),'uMax',max(U,[],1),'uMean',mean(U,1),'yMin',min(Y,[],1), ...
    'yMax',max(Y,[],1),'yMean',ym,'nodeSpacingHours',median(sp),'units',numel(E.trainingUnits), ...
    'failureTimes',[E.trainingUnits.failureTime]);
X.goldens=edge_goldens(models,names,Q,E.example.prefix,cr);
save(out,'-struct','X','-v7');
fprintf('Edge export written: %s\n  experiment %d (%s), methods %s, platform %s\n',out,e,E.evidence,strjoin(names,', '),platform);
X.file=out;
end

function h=edge_hash(path)
% SHA-256 in 16 MB chunks: a benchmark Results.mat can exceed the Java heap in one read.
if exist('OCTAVE_VERSION','builtin')~=0, h=hash('sha256',fileread(path)); return; end
if ~usejava('jvm'), h='unavailable: JVM disabled'; return; end
f=fopen(path,'rb'); assert(f>=0,'pi17:edge','Cannot read %s',path); cl=onCleanup(@()fclose(f)); %#ok<NASGU>
md=java.security.MessageDigest.getInstance('SHA-256');
while true
    b=fread(f,2^24,'*uint8');
    if isempty(b), break; end
    md.update(b);
end
h=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2)',1,[]));
end

function S=edge_model(M,name)
S=struct('method',name,'kind',M.kind,'available',logical(M.available),'label',M.label);
if isfield(M,'status'), S.status=M.status; end
if ~S.available, return; end
if strcmp(M.kind,'lstm')
    L=M.net.Layers; cls=cell(1,numel(L));
    for j=1:numel(L), cls{j}=class(L(j)); end
    pat={'SequenceInputLayer$','LSTMLayer$','FullyConnectedLayer$','ReLULayer$','FullyConnectedLayer$','RegressionOutputLayer$'};
    ok=numel(L)==numel(pat);
    for j=1:min(numel(L),numel(pat)), ok=ok && ~isempty(regexp(cls{j},pat{j},'once')); end
    assert(ok,'pi17:edge','Unexpected LSTM layer stack: %s',strjoin(cls,', '));
    assert(strcmp(L(2).OutputMode,'last') && strcmp(L(2).StateActivationFunction,'tanh') && ...
        strcmp(L(2).GateActivationFunction,'sigmoid'),'pi17:edge','LSTM activations differ from the edge implementation');
    assert(strcmp(char(L(1).Normalization),'none'),'pi17:edge','LSTM input normalisation must be none');
    hs=L(2).HiddenState; cs=L(2).CellState; H=L(2).NumHiddenUnits;
    if isempty(hs), hs=zeros(H,1); end
    if isempty(cs), cs=zeros(H,1); end
    S.lstm=struct('InputWeights',double(L(2).InputWeights),'RecurrentWeights',double(L(2).RecurrentWeights), ...
        'Bias',double(L(2).Bias),'HiddenState',double(hs),'CellState',double(cs), ...
        'FC1Weights',double(L(3).Weights),'FC1Bias',double(L(3).Bias), ...
        'FC2Weights',double(L(5).Weights),'FC2Bias',double(L(5).Bias));
    S.scale=M.scale; S.hidden=H;
    if isfield(M,'optimization') && isfield(M.optimization,'validationLogRULLoss')
        S.validationLogRULLoss=M.optimization.validationLogRULLoss;
    end
    return
end
assert(M.kappa==0 && all(M.gamma(:)==0),'pi17:edge','Observed models have deterministic fatigue: kappa and gamma must be zero');
assert(isfield(M,'Bdefinition'),'pi17:edge','Observed models must carry Bdefinition (B never enters the discrepancy)');
f={'k','p','betaT','a','tau','sigmaB','unitSD','sensorSD','C','bound','trainingEta'};
for j=1:numel(f), S.(f{j})=double(M.(f{j})); end
S.useB=logical(M.useB); S.nn=M.nn;
if isempty(M.projection) || M.bound==0, S.projection=[];
else, S.projection=struct('A',M.projection.A,'sup',M.projection.sup,'lo',M.projection.lo,'hi',M.projection.hi); end
if isfield(M,'pinnNN'), S.pinnNN=M.pinnNN; end
if isfield(M,'residualFamily'), S.residualFamily=M.residualFamily; end
S.physicalScoreColumns=score_columns(M.config);
if isfield(M,'validationScore'), S.validationScore=M.validationScore; end
end

function S=edge_columns(T)
% Tables become structs of columns; text columns become cellstr.
if ~isa(T,'table'), S=T; return; end
S=struct(); v=T.Properties.VariableNames;
for j=1:numel(v)
    col=T.(v{j});
    if isnumeric(col) || islogical(col), S.(v{j})=double(col); else, S.(v{j})=cellstr(string(col)); end
end
end

function G=edge_goldens(models,names,Q,H,c)
% Deterministic quantities plus the exact random offsets each stage drew, so the
% a future v17 edge implementation can replay the forecast pipeline.
assert(~isempty(H.plan),'pi17:edge','The example prefix carries no plan; the planned policy cannot be checked');
seed=c.seed+77; G=struct('prefix',H,'seed',seed); G.policies=c.policies; post=cell(1,numel(models));
for m=1:numel(models)
    M=models{m}; if ~M.available || strcmp(M.kind,'lstm'), continue; end
    if strcmp(M.kind,'pinn'), g=edge_pinn_golden(M,H,c); lanes=(1:20:c.etaGridPoints)';
        rng(seed,'twister'); g.posteriorOffset=rand;
    else
        g=edge_grid_golden(M,H,c); lanes=(1:20:c.etaGridPoints)';
        % first rand of observed_prefix = offset of its systematic resample (grid methods only;
        % inverse_prefix resamples after randn, so the PINN lanes are exported instead)
        rng(seed,'twister'); g.posteriorOffset=rand;
    end
    rng(seed,'twister'); post{m}=model_posterior(M,H,c);
    g.postD=post{m}.D; g.postEta=post{m}.eta;
    rng(seed+50,'twister'); bp=future_bank(H,'planned',Q,c,numel(lanes));
    if strcmp(M.kind,'pinn'), e0=g.grid(lanes);
    else, e0=linspace(-c.unitEffectMax,c.unitEffectMax,c.etaGridPoints)'; e0=e0(lanes); end
    D0=g.Dend(lanes);
    % Uniform weights over the lanes: systematic resampling is the identity for any offset.
    P=struct('D',D0(:),'B',zeros(numel(lanes),1),'eta',e0(:),'weights',ones(numel(lanes),1)/numel(lanes));
    if strcmp(M.kind,'pinn'), P.exposure=g.Eend(lanes); end
    g.laneIndex=lanes; g.laneSamples=model_samples(M,H,P,bp,c);
    G.(names{m})=g;
end
for p=1:numel(c.policies)
    pol=c.policies{p};
    rng(seed+p,'twister'); bank=future_bank(H,pol,Q,c,c.forecastPaths);
    b=struct('dt',bank.dt,'origin',bank.origin,'policy',pol);
    if strcmp(pol,'planned'), b.u=reshape(bank.u(:,1,:),numel(bank.dt),3); else, b.u=bank.u; end
    G.(['bank_' pol])=b;
    for m=1:numel(models)
        M=models{m}; if ~M.available, continue; end
        rng(seed+p+100,'twister'); r2=rand;
        rng(seed+p+100,'twister'); samples=model_samples(M,H,post{m},bank,c);
        G.(sprintf('%s_%s',names{m},pol))=struct('forecastOffset',r2,'samples',samples, ...
            'median',quantile_base(samples,.5),'lower',quantile_base(samples,c.intervalAlpha/2), ...
            'upper',quantile_base(samples,1-c.intervalAlpha/2));
    end
end
end

function g=edge_grid_golden(M,H,c)
eta=linspace(-c.unitEffectMax,c.unitEffectMax,c.etaGridPoints)';
D=observed_trajectory(M,H,eta,c); [nll,KF]=observed_kalman(M,H,D,c,false);
lp=-.5*(eta'/M.unitSD).^2; lp=lp-logsumexp_base(lp); lw=lp-nll; lw(~all(D<c.Dcrit,1))=-Inf;
w=normalized_weights(lw');
g=struct('Dend',D(end,:)','nll',nll(:),'w',w,'KFmeanEnd',KF.mean(end,:)','KFvarEnd',KF.variance(end), ...
    'filteredD',D*w,'filteredB',KF.mean*w);
end

function g=edge_pinn_golden(M,H,c)
grid=linspace(-c.unitEffectMax,c.unitEffectMax,c.etaGridPoints)';
[D,~,E]=pinn_trajectory(M,H,grid,c); [nll,KF]=observed_kalman(M,H,D,c);
lp=-.5*(grid'/M.unitSD).^2; lp=lp-logsumexp_base(lp); lw=lp-nll;
lw(~all(D<c.Dcrit,1))=-Inf;
g=struct('grid',grid,'Dend',D(end,:)','Eend',E(end,:)','nll',nll(:), ...
    'w',normalized_weights(lw'),'KFmeanEnd',KF.mean(end,:)','KFvarEnd',KF.variance(end));
end

function [H,A]=residual_features(M,D,B,u,c)
if isfield(M,'residualFamily') && strcmp(M.residualFamily,'fixed_basis') && isfield(c,'basisFamily') && strcmp(c.basisFamily,'rbf')
    H=v17_rbf_basis(D,u,c,numel(M.nn.w)); A=struct();
elseif isfield(M,'residualFamily') && strcmp(M.residualFamily,'fixed_basis')
    d=max(0,min(1,D(:)/c.Dcrit));
    V=[sin(pi*d) tanh(u(:,3)/c.temperatureFeatureScale) ...
        d.*tanh(log(max(u(:,1),1e-8))/c.loadFeatureScale) ...
        d.*tanh(log(max(u(:,2),1e-8))/c.speedFeatureScale) 2*d-1];
    H=zeros(numel(d),numel(M.nn.w));
    for j=1:size(H,2)
        if j<=size(V,2), H(:,j)=V(:,j); else, H(:,j)=sin(j*pi*d); end
    end
    A=struct();
else, [H,A]=hidden_features(M.nn,D,B,u,c);
end
end

function [H,F]=v17_rbf_basis(D,u,c,n)
% Smooth (C-infinity) fixed discrepancy basis: Gaussian radial functions of
% normalized damage plus operating main effects and damage interactions.
% Unlike the old clamped sine basis it has no derivative kink at D=Dcrit,
% and every function is bounded by 1 for all D (keeps the log-rate bound).
d=D(:)/c.Dcrit;centers=linspace(0,1,c.basisDamageCenters);s=c.basisWidthFactor/max(1,c.basisDamageCenters-1);
R=exp(-.5*((d-centers)/s).^2);dR=-((d-centers)/s^2).*R/c.Dcrit;
tl=tanh(log(max(u(:,1),1e-8))/c.loadFeatureScale);ts=tanh(log(max(u(:,2),1e-8))/c.speedFeatureScale);tt=tanh(u(:,3)/c.temperatureFeatureScale);
z=zeros(size(d));g=tanh(2*d);dg=2*(1-g.^2)/c.Dcrit;
H=[R tl ts tt g.*tl g.*tt];F=[dR z z z dg.*tl dg.*tt];
assert(n<=size(H,2),'pi17:basis','Requested %d basis functions; the radial basis provides %d.',n,size(H,2));
H=H(:,1:n);F=F(:,1:n);
end

function n=v17_basis_size(c)
n=c.basisDamageCenters+5;
end

function [x,f,out]=robust_bfgs(fun,x,steps,c)
[x,f,out]=v17_bfgs(fun,x,max(1,steps*c.optimizerPasses),c,''); out.passes=c.optimizerPasses;
end

function [ks,zs]=origin_nodes(U,c)
if strcmp(c.originMode,'calendar'), targets=c.originHours;
else, targets=c.originFractions*U.t(end); end
ks=[]; zs=[];
for z=1:numel(targets)
    target=targets(z);
    % Survival at a scheduled time is admissible information. No extrapolated
    % pre-failure fraction or endpoint enters a calendar origin selection.
    if target>U.t(end) || (U.failureObserved && target>=U.failureTime), continue; end
    k=find(U.t<=target,1,'last');
    if ~isempty(k) && (isempty(ks) || k~=ks(end)), ks(end+1)=k; zs(end+1)=z; end %#ok<AGROW>
end
end

function [samples,info]=pinn_first_passage(M,P,bank,c)
n=size(bank.u,2);if c.forceGridPassage,ix=(1:n)';else,ix=systematic_resample(P.weights,n);end
D=P.D(ix);E=P.exposure(ix);eta=P.eta(ix);samples=inf(n,1);samples(D>=c.Dcrit)=0;elapsed=0;
for k=1:numel(bank.dt)
 ns=max(1,ceil(bank.dt(k)/c.integrationStepHours));h=bank.dt(k)/ns;u=reshape(bank.u(k,:,:),n,3);
 for j=1:ns
  live=isinf(samples);if ~any(live),break;end
  [~,er]=pinn_rate(M,E,bank.origin+elapsed,u,eta,c);
  [r,~]=pinn_rate(M,E+.5*h*er,bank.origin+elapsed+.5*h,u,eta,c);
  dx=h*r;cap=c.Dcrit-D;hit=live & dx>=cap & dx>0;
  samples(hit)=elapsed+h*max(0,cap(hit))./dx(hit);D=D+dx;E=E+h*er;elapsed=elapsed+h;
 end
 if ~any(isinf(samples)),break;end
end
info=struct('rhoRMS',NaN,'rhoMaxAbs',NaN,'outOfSupportFraction',NaN,'censoredFraction',mean(isinf(samples)));
end

function paths=sample_B_smoother(M,H,KF,ix)
% Scalar Gaussian forward-filter backward sampling, conditional on sampled eta.
K=numel(H.t); n=numel(ix); paths=zeros(n,K);
paths(:,K)=KF.mean(K,ix)'+sqrt(max(KF.variance(K),0))*randn(n,1);
for k=K-1:-1:1
    phi=exp(-(H.t(k+1)-H.t(k))/M.tau);
    den=max(KF.predictedVariance(k+1),eps);
    gain=KF.variance(k)*phi/den;
    mu=KF.mean(k,ix)'+gain*(paths(:,k+1)-KF.predictedMean(k+1,ix)');
    variance=max(0,KF.variance(k)-gain^2*KF.predictedVariance(k+1));
    paths(:,k)=mu+sqrt(variance)*randn(n,1);
end
end

function T=schedule_audit(units,ids,c)
rows=cell(0,8);
for i=ids
    U=units(i); [ks,zs]=origin_nodes(U,c);
    for j=1:numel(ks)
        H=causal_prefix(U,ks(j)); due=find(isfinite(H.inspection) & H.t>0,1);
        first=NaN; if ~isempty(due), first=H.t(due); end
        oracle=7*first-H.t(end); truth=U.failureTime-H.t(end);
        rows(end+1,:)={U.id,zs(j),H.t(end),sum(isfinite(H.inspection)),first, ...
            oracle,truth,oracle-truth}; %#ok<AGROW>
    end
end
T=cell2table(rows,'VariableNames',{'unit','originIndex','origin_h','availableInspections', ...
    'firstInspection_h','legacyTimestampHeuristicRUL_h','trueRUL_h','legacyHeuristicError_h'});
% In the default OPC-like benchmark no inspection time exists. In calendar
% mode first time is constant across units, independent of their lifetime.
if strcmp(c.inspectionMode,'none'), assert(all(T.availableInspections==0)); end
end

function T=innovation_summary(V)
rows=cell(0,6);
for j=1:size(V,2)
    v=V(:,j); good=isfinite(v); a=v(good); lag=NaN;
    ix=find(good(1:end-1)&good(2:end));
    if numel(ix)>3
        q=corrcoef(v(ix),v(ix+1)); lag=q(1,2);
    end
    if isempty(a), rows(end+1,:)={j,0,NaN,NaN,NaN,lag};
    else, rows(end+1,:)={j,numel(a),mean(a),sqrt(mean(a.^2)),max(abs(a)),lag}; end %#ok<AGROW>
end
T=cell2table(rows,'VariableNames',{'channel','observations','mean','RMS','maxAbs','lag1Correlation'});
end

function T=numerical_method_audit(models,names,units,ids,Q,c,eid)
% Explicitly distinguish integration, eta grid, PF particles and future-duty
% Monte Carlo. NaN means not applicable, never a fabricated zero change.
rows=cell(0,13);old=rng;cl=onCleanup(@()rng(old)); %#ok<NASGU>
for i=ids(1:min(numel(ids),c.maxDiagnosticUnits))
 U=units(i);[ks,zs]=origin_nodes(U,c);if isempty(ks),continue;end
 for iz=unique([1 numel(ks)])
  H=causal_prefix(U,ks(iz));seed=c.seed+eid*1000+i*10+zs(iz);truth=U.failureTime-H.t(end);
  for pol=1:numel(c.numericalAuditPolicies)
   policy=c.numericalAuditPolicies{pol};R=c.forecastReplicates;if strcmp(policy,'planned'),R=1;end
   banks=cell(1,R);bigBanks=cell(1,R);
   for r=1:R
    rng(seed+1+10000*(r-1));banks{r}=future_bank(H,policy,Q,c,c.forecastPaths);
    rng(seed+1+10000*(r-1));bigBanks{r}=future_bank(H,policy,Q,c,2*c.forecastPaths);
   end
   first=numel(rows(:,1))+1;baseline=nan(1,numel(models));refined=baseline;
   for m=1:numel(models)
    active=v17_for_policy(models{m},policy);if ~active.available,continue;end
    rng(seed);P=model_posterior(active,H,c);
    [ss,ii]=v17_forecast_distribution(active,H,P,banks,c,seed+2);base=v17_quantile(ss,ii,.5);baseline(m)=base;
    step=NaN;grid=NaN;particles=NaN;mc=NaN;paths=NaN;
    cc=c;cc.integrationStepHours=c.integrationStepHours/2;cc.transitionStepHours=c.transitionStepHours/2;
    if ~strcmp(active.kind,'lstm')
     rng(seed);PP=model_posterior(active,H,cc);[ss,ii]=v17_forecast_distribution(active,H,PP,banks,cc,seed+2);step=v17_quantile(ss,ii,.5);
     cg=cc;
     if strcmp(active.kind,'smc')
      cg.particles=2*c.particles;rng(seed);PP=model_posterior(active,H,cg);
      [ss,ii]=v17_forecast_distribution(active,H,PP,banks,cg,seed+2);particles=v17_quantile(ss,ii,.5);refined(m)=particles;
     else
      cg.etaGridPoints=2*c.etaGridPoints-1;rng(seed);PP=model_posterior(active,H,cg);
      [ss,ii]=v17_forecast_distribution(active,H,PP,banks,cg,seed+2);grid=v17_quantile(ss,ii,.5);refined(m)=grid;
     end
    else,refined(m)=base;end
    if strcmp(policy,'probabilistic')
     vals=zeros(c.numericalReplicates,1);
     for r=1:c.numericalReplicates
      rng(seed+20000+r);bank=future_bank(H,policy,Q,c,c.forecastPaths);
      [aa,ff]=model_samples(active,H,P,bank,c);vals(r)=v17_quantile(aa,ff,.5);
     end
     mc=std(vals);[ss,ii]=v17_forecast_distribution(active,H,P,bigBanks,c,seed+2);paths=v17_quantile(ss,ii,.5)-base;
    end
    changes=[step-base grid-step particles-step paths];valid=changes(isfinite(changes));
    resolved=isfinite(base) && all(abs(valid)<=c.numericalToleranceHours);
    if isfinite(mc),resolved=resolved && mc/sqrt(R)<=c.numericalToleranceHours;end
    rows(end+1,:)={U.id,names{m},policy,H.t(end),base,step-base,grid-step,particles-step,paths,mc,NaN,resolved,truth}; %#ok<AGROW>
   end
   % Same original/refined information and draws for paired method gains.
   for rr=first:size(rows,1)
    m=find(strcmp(names,rows{rr,2}));
    rows{rr,11}=(abs(refined(m)-truth)-abs(refined(1)-truth))-(abs(baseline(m)-truth)-abs(baseline(1)-truth));
   end
  end
 end
end
T=cell2table(rows,'VariableNames',{'unit','method','policy','origin_h','baseRUL_h','halfStepChange_h','etaGridChange_h', ...
 'doubleParticlesChange_h','doubleDutyPathsChange_h','replicateMedianSD_h','pairedMAEGainRefinementChange_h','resolvedAtDeclaredTolerance','trueRUL_h'});
end

function T=fleet_comparisons(R)
rows=cell(0,9); methods=setdiff(unique(R.metrics.method),{'PI_DSSDM'});
for ss=1:numel(R.config.scenarios)
    scenario=R.config.scenarios{ss};
    for p=1:numel(R.config.policies)
        policy=R.config.policies{p};
        for j=1:numel(methods)
            a=[]; b=[];
            for e=1:numel(R.experiments)
                E=R.experiments{e};
                if ~startsWith(E.evidence,['SYNTHETIC:' scenario ':']), continue; end
                Q=E.metrics(strcmp(E.metrics.policy,policy),:);
                x=Q.MAE_h(strcmp(Q.method,'PI_DSSDM')); y=Q.MAE_h(strcmp(Q.method,methods{j}));
                if ~isempty(x) && ~isempty(y) && isfinite(x) && isfinite(y), a(end+1)=x; b(end+1)=y; end %#ok<AGROW>
            end
            if isempty(a), continue; end
            gain=b-a; se=NaN;
            if numel(gain)>1, se=std(gain)/sqrt(numel(gain)); end
            rows(end+1,:)={scenario,policy,methods{j},numel(gain),mean(a),mean(b), ...
                mean(gain),se,sum(gain>0)}; %#ok<AGROW>
        end
    end
end
T=cell2table(rows,'VariableNames',{'scenario','policy','comparator','independentFleets', ...
    'primaryMAE_h','comparatorMAE_h','pairedMAEGain_h','pairedGainSE_h','fleetsPrimaryWins'});
fprintf('\nPAIRED INDEPENDENT-FLEET MAE COMPARISONS (descriptive, no row-wise significance):\n'); disp(T);
end

function T=revision_selftests(c)
cc=c; cc.trainUnits=3; cc.validationUnits=2; cc.calibrationUnits=12; cc.testUnits=2;
cc.etaGridPoints=81; cc.originMode='calendar'; names={};
U=generate_fleet(cc,'fatigue_matched',811);
assert(all(arrayfun(@(V)all(isnan(V.inspection)),U)) || strcmp(cc.inspectionMode,'calendar'));
if strcmp(cc.inspectionMode,'none'), names{end+1}='default synthetic benchmark contains no oracle damage inspections'; end
ca=cc; ca.inspectionMode='calendar'; A=generate_fleet(ca,'fatigue_matched',811);
for i=1:numel(A)
    t=A(i).t(isfinite(A(i).inspection));
    assert(all(abs(t/ca.inspectionEveryHours-round(t/ca.inspectionEveryHours))<1e-8));
    assert(all(t<A(i).failureTime));
end
names{end+1}='inspection calendar independent of eventual lifetime, no terminal inspection';
W=generate_fleet(cc,'fatigue_weak_gap',812);
for i=1:numel(W)
    missing=all(isnan(W(i).y),2);
    assert(isequal(missing,W(i).t>=cc.sensorGapHours(1)&W(i).t<cc.sensorGapHours(2)));
end
names{end+1}='telemetry gap follows fixed calendar, not eventual failure fraction';
V=U(1); [k,z]=origin_nodes(V,cc); V.failureTime=V.failureTime+1000; V.t(end)=V.t(end)+1000;
[kk,zz]=origin_nodes(V,cc); keep=zz<=max(z); assert(isequal(k,kk(keep)));
names{end+1}='calendar origins invariant to future endpoint changes';
M=initial_model(strip_truth(U(1:3)),cc); M.k=cc.truthRate; M.p=cc.truthLoadExponent;
M.betaT=cc.truthTemperatureCoefficient; M.a=0;
D=observed_trajectory(M,U(1),U(1).truth.eta,cc);
assert(max(abs(D-U(1).truth.D))<1e-8);
names{end+1}='matched simulator reproduces the fitted transition exactly at true parameters';
assert(~ismember(4,score_columns(cc)) || cc.fitTemperatureCoefficient || cc.protectFixedTemperature);
names{end+1}='unverified fixed-zero temperature direction remains available to discrepancy';
M.kind='pinn'; M.pinnNN=init_network(cc.pinnHidden1,cc.pinnHidden2,5); M.pinnNN.w(:)=0;
H=causal_prefix(U(4),10); [D,~,E]=pinn_trajectory(M,H,0,cc);
P=struct('D',D(end),'B',0,'eta',0,'exposure',E(end),'weights',1);
bank=struct('dt',1000,'u',reshape([1 1 0],1,1,3),'origin',H.t(end));
[f,~]=pinn_first_passage(M,P,bank,cc); expected=(cc.Dcrit-D(end))/cc.nominalRate;
assert(abs(f-expected)<1e-8);
M.pinnNN.w(:)=.7; f2=pinn_first_passage(M,P,bank,cc); assert(abs(f2-f)>1e-3);
names{end+1}='PINN neural derivative actively changes future first-passage RUL';
H2=H; H2.t=[H.t;H.t(end)+cc.transitionStepHours]; H2.u=[H.u;H.u(end,:)];
H2.y=[H.y;nan(1,size(H.y,2))]; H2.inspection=[H.inspection;NaN];
[D2,~,E2]=pinn_trajectory(M,H2,0,cc);
[r,er]=pinn_rate(M,E(end),H.t(end),H.u(end,:),0,cc);
% Recompute the origin using the same changed network before consistency check.
[D0,~,E0]=pinn_trajectory(M,H,0,cc); [r,er]=pinn_rate(M,E0(end),H.t(end),H.u(end,:),0,cc);
[r,~]=pinn_rate(M,E0(end)+.5*cc.transitionStepHours*er,H.t(end)+.5*cc.transitionStepHours,H.u(end,:),0,cc);
assert(abs(D2(end)-D0(end)-r*cc.transitionStepHours)<1e-10);
assert(abs(E2(end)-E0(end)-er*cc.transitionStepHours)<1e-10);
names{end+1}='PINN historical continuation uses the same forecast derivative';
G=initial_model(strip_truth(U(1:3)),cc); G.bound=.3; G.residualFamily='fixed_basis'; G.config=cc;
G.reference=observed_reference(G,strip_truth(U(1:3)),cc); G.nn.w(:)=.05; G=project_network(G,cc);
rho=discrepancy(G,G.reference.D,zeros(size(G.reference.D)),G.reference.u);
assert(max(abs(rho))<=G.bound && norm(G.reference.G'*rho)/numel(rho)<1e-8);
names{end+1}='fixed-basis comparator obeys the same bound and physical-score projection';
H=causal_prefix(U(4),15); rng(83); P=observed_prefix(G,H,cc,true,100);
assert(all(isfinite(P.innovations(:))) && all(isfinite(P.pathB(:))));
assert(mean(var(P.pathB,0,1))>0);
names{end+1}='causal mixture innovations finite and B bands include conditional variance';
G.bound=0;
[nll,K]=observed_kalman(G,H,observed_trajectory(G,H,[-.1 0 .1],cc),cc);
assert(isequal(nll,K.cumulativeNLL(end,:)));
names{end+1}='cached cumulative Kalman likelihood equals original terminal likelihood';
rng(90); PP=observed_prefix(G,H,cc,false,60); HH=H; HH.y(end,:)=HH.y(end,:)+1000;
rng(90); PQ=observed_prefix(G,HH,cc,false,60);
assert(isequal(PP.filteredMean(1:end-1,:),PQ.filteredMean(1:end-1,:)));
assert(all(PP.eventMass>=0 & PP.eventMass<=1+1e-12));
names{end+1}='sequential filtered summaries cannot use later observations and report survival probability';
Q=fit_duty_model(strip_truth(U(1:3)));
H.plan=struct('issuedAt',0,'t',[0;10000],'u',zeros(2,3));
bank=future_bank(H,'planned',Q,cc,10); rng(12); P=observed_prefix(G,H,cc,false,30);
v=first_passage(G,P,bank,cc); assert(all(isinf(v)));
names{end+1}='idle planned duty preserves zero fatigue increments and censored RUL';
T=table(names',true(numel(names),1),'VariableNames',{'test','passed'});
end

function D=fitting_trajectory(M,U,eta,c)
if strcmp(M.kind,'pinn'), D=pinn_trajectory(M,U,eta,c);
else, D=observed_trajectory(M,U,eta,c); end
end

function plot_revision_diagnostics(E,c,e,dir)
f=new_figure(c,sprintf('E%d corrected-model diagnostics',e));
tiledlayout(2,3,'TileSpacing','compact'); I=E.identifiability.fullInformation;
nexttile; semilogy(max(I.singularValues,eps),'o-'); grid on;
xlabel('Scaled active coordinate'); ylabel('Singular value');
title(sprintf('Joint local rank %d/%d; condition %.3g',I.rank,I.activeParameters,I.scaledConditionNumber));
nexttile; correlation_image(I.physicsCorrelations); colorbar; axis square;
xticks(1:4); yticks(1:4); xticklabels({'k','p','T','a'}); yticklabels({'k','p','T','a'});
title('Physics after nuisance; NaN if fixed/deficient');
nexttile; B=E.models{4}.Bselection; bar(B.gainFromB); yline(0,'k:'); grid on;
xlabel('Independent validation unit'); ylabel('No-B NLL minus B NLL');
title(sprintf('B retained %d; conditional covariance singular %.3g',E.models{4}.useB,E.models{4}.Bdecision.covarianceMinimumSingularValue));
nexttile; A=E.methodNumerics;
if isempty(A), text(.05,.5,'Numerical subset deferred to FULL'); axis off;
else, bar([A.halfStepChange_h A.etaGridChange_h]); grid on;
xlabel('Audited method / origin'); ylabel('RUL change h');
legend({'Half crossing step','Double eta grid'},'Location','best'); end
title('Numerical audit, explicit subset');
nexttile; A=E.innovationAudit; bar([A.mean A.RMS A.lag1Correlation]); grid on;
xlabel('Observation channel'); legend({'Mean','RMS','Lag-1'},'Location','best');
title('Causal predictive mixture innovations, example');
nexttile; A=E.scheduleAudit; scatter(A.origin_h,A.availableInspections,25,'filled'); grid on;
xlabel('Scheduled forecast origin h'); ylabel('Available damage inspections');
title({sprintf('Inspection protocol: %s',c.inspectionMode),'Declared independently of failure'});
sgtitle(E.evidence,'Interpreter','none'); save_plot(f,dir,sprintf('E%02d_Corrected_model_audits',e),c);

f=new_figure(c,sprintf('E%d method accuracy and optimisation',e)); tiledlayout(2,3,'TileSpacing','compact');
names=E.methodNames; nm=numel(names);
for pp=1:numel(c.policies)
    nexttile; Q=E.metrics(strcmp(E.metrics.policy,c.policies{pp}),:); V=nan(nm,3);
    for j=1:nm, q=Q(strcmp(Q.method,names{j}),:); if ~isempty(q), V(j,:)=[q.MAE_h q.RMSE_h q.bias_h]; end; end
    bar(V); xticks(1:nm); xticklabels(names); xtickangle(20); ylabel('Hours'); grid on;
    legend({'MAE','RMSE','Signed bias'},'Location','best'); title(c.policies{pp});
end
nexttile; S=E.models{1}.selection; plot(S.bound,S.causalValidationLoss,'o'); hold on;
if numel(E.models)>4 && strcmp(E.methodNames{5},'Basis_hybrid'), S=E.models{5}.selection; plot(S.bound,S.causalValidationLoss,'x'); legend({'Deep','Fixed basis'}); end
xlabel('Log-rate residual bound'); ylabel('VAL log-RUL loss'); grid on; xlim([-.02*max(.01,max(c.residualBounds)) 1.02*max(.01,max(c.residualBounds))]); title('Depth control uses TRAIN/VAL only');
nexttile; S=E.models{1}.selection; plot(S.gradientNorm,'o-'); yline(c.gradientTolerance,'k:');
xlabel('Candidate checkpoint'); ylabel('TRAIN joint gradient'); grid on; title('Final gradients of distinct candidates');
nexttile; S=E.models{2}.selection; bar(S.relativeODEResidualRMS); xlabel('PINN candidate checkpoint'); ylabel('Log-rate ODE RMS'); grid on;
title('PINN collocation residual');
nexttile; A=E.stateOriginAudit;
if ~isempty(A), scatter(A.trueD,A.estimatedD,22,A.originIndex,'filled'); hold on; plot([0 c.Dcrit],[0 c.Dcrit],'k:'); colorbar; grid on;
    xlabel('Synthetic true D'); ylabel('Estimated D at origin'); title(sprintf('D RMSE %.3g',sqrt(mean(A.errorD.^2))));
else, text(.1,.5,'No independent D truth for state accuracy'); axis off; end
sgtitle(E.evidence,'Interpreter','none'); save_plot(f,dir,sprintf('E%02d_Method_accuracy_and_optimisation',e),c);
end

function opt=final_observed_gradient(opt,M,train,c)
opt.phaseGradientNorm=opt.gradientNorm; opt.phaseExitflag=opt.exitflag;
[x,free]=observed_encode(M,numel(train),c);
fun=@(v)observed_coordinates(v,x,free,M,train,c);
opt.gradientNorm=norm(fd_gradient(fun,x(free)),Inf);
if opt.gradientNorm>=c.gradientTolerance && opt.exitflag>0, opt.exitflag=0; end
end

function opt=final_joint_gradient(opt,M,train,c)
opt.phaseGradientNorm=opt.gradientNorm; opt.phaseExitflag=opt.exitflag;
[x,free]=observed_encode(M,numel(train),c);
nw=pack_network(M.nn); if strcmp(M.residualFamily,'fixed_basis'), nw=M.nn.w; end
v=[x(free);nw]; fun=@(z)observed_joint_objective(z,M,x,free,train,c);
opt.gradientNorm=norm(fd_gradient(fun,v),Inf);
if opt.gradientNorm>=c.gradientTolerance && opt.exitflag>0, opt.exitflag=0; end
end

function T=optimizer_summary(models,names)
rows=cell(0,7);
for j=1:numel(models)
    M=models{j}; flag=NaN; grad=NaN; steps=NaN; evaluations=NaN; seconds=NaN;
    label='not available';
    if strcmp(M.kind,'lstm'), label='LSTM validation-selected training';
    elseif isfield(M,'jointOptimization') && M.bound>0, opt=M.jointOptimization; label='selected joint correction';
    elseif strcmp(M.kind,'pinn'), opt=M.optimization; label='selected PINN trajectory';
    elseif isfield(M,'predictionOptimization'), opt=M.predictionOptimization; label='selected physics checkpoint';
    else, opt=M.selectedMStep; label='selected population checkpoint'; end
    if ~strcmp(M.kind,'lstm')
        flag=opt.exitflag; grad=opt.gradientNorm; steps=opt.iterations;
        if isfield(opt,'functionEvaluations'), evaluations=opt.functionEvaluations; end
        if isfield(opt,'elapsedSeconds'), seconds=opt.elapsedSeconds; end
    end
    rows(end+1,:)={names{j},label,flag,grad,steps,evaluations,seconds}; %#ok<AGROW>
end
T=cell2table(rows,'VariableNames',{'method','selectedCheckpoint','exitflag', ...
    'postEmissionGradientNorm','lastSelectedPhaseSteps','lastSelectedPhaseFunctionEvaluations','lastSelectedPhaseSeconds'});
end

function correlation_image(A)
h=imagesc(A,[-1 1]); set(h,'AlphaData',isfinite(A)); set(gca,'Color',[.95 .95 .95]);
for i=1:size(A,1), for j=1:size(A,2)
    if ~isfinite(A(i,j)), text(j,i,'-','Color',[.4 .4 .4],'HorizontalAlignment','center'); end
end, end
end

function R=refresh_reports(path)
% Presentation-only update after an integrated run. Stored fit-source hash,
% forecasts and model parameters remain intact. New reporting source is saved.
S=load(path,'R'); R=S.R; assert(strcmp(R.version,'17.2.0'),'pi17:version','Requires v17 results');
old=rng; cl=onCleanup(@()rng(old)); %#ok<NASGU>
R.provenance.fitSourceSHA256=R.provenance.newSHA256;
R.provenance.reportingSourceSHA256=hash_file([mfilename('fullpath') '.m']);
R.provenance.reportingRefresh='Sequential filter diagnostics, single-fleet SE, correlation masking and profile labels; fits and all predictions verified unchanged';
before=R.predictions;
diary(fullfile(R.outputDir,'Reporting_refresh_console.txt')); dc=onCleanup(@()diary('off')); %#ok<NASGU>
R.tests=selftest(R.config); disp(R.tests);
R.fleetComparisons=fleet_comparisons(R);
writetable(R.fleetComparisons,fullfile(R.outputDir,'Paired_fleet_comparisons.csv'));
for e=1:numel(R.experiments)
    E=R.experiments{e};
    scenario=ceil(e/R.config.replicates); rep=mod(e-1,R.config.replicates)+1;
    units=generate_fleet(R.config,R.config.scenarios{scenario},R.config.seed+1000*scenario+rep);
    assert(isequaln(strip_truth(units(E.ids.train)),E.trainingUnits),'pi17:identity','Regenerated TRAIN differs');
    [cal,~,~]=predict_group(units,E.ids.calibration,E.models,E.methodNames,E.dutyModel,R.config,e,E.evidence,false);
    [test,F,A]=predict_group(units,E.ids.test,E.models,E.methodNames,E.dutyModel,R.config,e,E.evidence,true);
    [test,C]=calibrate_bands(cal,test,R.config);
    assert(isequaln(test,E.predictions),'pi17:identity','Any forecast/interval/status changed during diagnostic refresh');
    E.filterDiagnostics=F; E.ablation=A; E.calibration=C;
    rng(R.config.seed+e*101); E.example.posterior=particle_filter(E.models{1},E.example.prefix,R.config,true,R.config.particles);
    E.innovationAudit=innovation_summary(E.example.posterior.innovations);
    R.experiments{e}=E; print_diagnostics(E,R.config); export_experiment(E,e,R.outputDir);
    if R.config.makePlots, plot_experiment(E,R.config,e,R.outputDir); plot_revision_diagnostics(E,R.config,e,R.outputDir); end
end
if R.config.makePlots, plot_benchmark(R); end
assert(isequaln(before,R.predictions),'pi17:refresh','Reporting changed predictions');
copyfile([mfilename('fullpath') '.m'],fullfile(R.outputDir,'Reporting_source_BSFD_PI_DSSDM_Hierarchical_v17.m'));
save(fullfile(R.outputDir,'Results.mat'),'R','-v7.3');
fprintf('Reporting refreshed. Original fitting source and hash retained; forecasts unchanged.\n');
end

function c=v17_configuration(mode,c)
% Prespecified budgets, scenario order and seeds. No search for favorable TEST.
% ASSESS inherits the confirmatory sample sizes, then applies its own frozen
% reduced-budget layer (v17_assess_configuration) and seed family.
assess=strcmp(mode,'assess');if assess,mode='confirm';end
exhaustive=strcmp(mode,'full_exhaustive');if exhaustive,mode='full';end
c=v17_configuration_layers(mode,c);
if assess,c=v17_assess_configuration(c);
elseif ismember(mode,{'full','benchmark','confirm'}) && ~exhaustive,c=v17_full_configuration(c,mode);end
c.fullProfile='fast';if exhaustive,c.fullProfile='exhaustive';end
end

function c=v17_full_configuration(c,mode)
% Frozen FAST FULL/CONFIRM profile (17.2), fixed before any FULL-seed fleet
% was generated. It keeps the confirmatory design: 6 scenarios x 5
% independent fleets, 24/10/24/16 unit splits, all six methods, both duty
% protocols, 5e-5 tolerance and the FULL seed family. The estimator is the
% one ASSESS 17.0 evaluated (encoder learned on TRAIN, then held fixed for
% the output-coordinate fit, without joint encoder recovery), so FULL and
% ASSESS test the same method. Evidence used for each change (no TEST
% metric of any FULL fleet):
%  - Joint encoder recovery ran 12-15 min per call and almost never reached
%    joint stationarity (SCREEN 17.1.1), so it is removed. Joint
%    stationarity is still computed and reported.
%  - Bound 0.15 was never selected in SCREEN and stalled most often. The
%    grid is {0, .30, .50}.
%  - The stall fixes (17.1.2) end non-improving fits early.
%  - Unit-bootstrap refits are run on replicate 1 of every scenario (6
%    fleets), conditional on the TRAIN encoder. Primary bands remain
%    split-conformal on independent CAL units, which is the coverage
%    guarantee. The bootstrap is a reported sensitivity analysis.
%  - Monte Carlo precision is raised where SCREEN showed unresolved
%    contrasts (forecast paths, duty paths, VAL paths); integration steps
%    stay at the audited 2 h.
% Measured (load_exponent, 12 workers, timing seed): 71 min with bootstrap
% (bootstrap + mixture forecasts ~23 min), so ~47 min without; 30 experiments
% ~= 6 x 71 + 24 x 47 min ~= 26 h.
% The previous multi-day profile is still available as mode 'full_exhaustive'.
c.residualBounds=[0 .30 .50];c.residualStarts=2;c.encoderSteps=15;c.functionalSteps=150;c.marginalCycles=2;
c.jointRecoverySteps=0;c.requireJointEncoderStationarity=false;c.curvatureEscapeCycles=1;
c.marginalSteps=80;c.populationRecoverySteps=100;c.BstartScreenSteps=8;c.BrefineSteps=60;c.BrefineCycles=2;
c.lstmHidden=[16 32];c.lstmStarts=1;c.lstmEpochs=100;c.lstmLearningRates=[.001 .003];
c.transitionStepHours=2;c.integrationStepHours=2;
c.selectionSeeds=1;c.validationPaths=96;c.stackWeights=[0 .25 .5 .75 1];c.processKappaGrid=[0 1 4];
c.processEtaNodes=41;c.processParticles=48;c.processOutputParticles=768;
c.etaGridPoints=401;c.coarseEtaPoints=101;c.gridRefinementLevels=0;c.forecastPaths=384;c.forecastReplicates=4;
c.populationBootstrapMembers=8;c.bootstrapMinimumMembers=5;c.bootstrapMaximumAttempts=12;
c.bootstrapReplicates=1;c.bootstrapRefitEncoder=false;c.bootstrapFitSteps=45;
c.enableProfiles=false;c.enableFullInformation=false;c.enableRateHypothesisAudit=false;
c.maxDiagnosticUnits=1;c.marginalDiagnosticUnits=4;c.numericalGainRepeats=2;c.numericalReplicates=2;
c.dutyValidationPaths=48;c.maxGradientWorkers=12;c.parallelForecasts=true;c.retryFailedExperiment=true;
c.label=sprintf('v17.2 FAST %s: 6 scenarios x 5 fleets, frozen ASSESS-validated estimator, all results retained',upper(mode));
c=v17_equal_pinn_budget(c);
end

function c=v17_assess_configuration(c)
% Frozen reduced-cost ASSESSMENT profile: 4 scenarios x 3 independent fleets
% with the full 24/10/24/16 unit splits, so fleet-level paired comparisons
% remain possible. Savings come from (1) no joint encoder recovery runs, the
% dominant v16 cost (the encoder is TRAIN-learned then held fixed, and
% eligibility is output-coordinate stationarity), (2) no population
% bootstrap (bands remain CAL-conformal), (3) one discrepancy bound with two
% starts, (4) coarser but audited numerics, (5) more parallel workers and
% parallel unit forecasting, (6) optional diagnostics off. Not FULL evidence.
c.scenarios={'fatigue_matched','fatigue_discrepancy','fatigue_load_exponent','fatigue_weak_gap'};c.replicates=3;
c.seed=2030102201;c.label='v17.1 ASSESS: 4 scenarios x 3 fleets, reduced budgets, all results retained';
c.residualBounds=[0 .30];c.residualStarts=2;c.encoderSteps=15;c.functionalSteps=120;c.marginalCycles=1;
c.jointRecoverySteps=0;c.requireJointEncoderStationarity=false;c.curvatureEscapeCycles=1;
c.marginalSteps=80;c.populationRecoverySteps=100;c.BstartScreenSteps=8;c.BrefineSteps=60;c.BrefineCycles=2;
c.lstmHidden=32;c.lstmStarts=1;c.lstmEpochs=60;c.lstmLearningRates=[.001 .003];
c.transitionStepHours=2;c.integrationStepHours=2;
c.selectionSeeds=1;c.validationPaths=64;c.stackWeights=[0 .5 1];c.processKappaGrid=[0 1 4];
c.processEtaNodes=41;c.processParticles=48;c.processOutputParticles=768;
c.etaGridPoints=401;c.coarseEtaPoints=101;c.gridRefinementLevels=0;c.forecastPaths=256;c.forecastReplicates=3;
c.populationBootstrapMembers=0;c.bootstrapMaximumAttempts=0;
c.enableProfiles=false;c.enableFullInformation=false;c.enableRateHypothesisAudit=false;
c.maxDiagnosticUnits=1;c.marginalDiagnosticUnits=4;c.numericalGainRepeats=2;c.numericalReplicates=2;
c.numericalAuditPolicies={'planned'};c.dutyValidationPaths=32;
c.maxGradientWorkers=12;c.parallelForecasts=true;
c=v17_equal_pinn_budget(c);
end

function c=v17_configuration_layers(mode,c)
c.profileObserved=true; c.profileQuadraticEmission=false; c.measurementLogPriorSD=1.2; c.unitHyperLogSD=.6;
c.enableProfiles=false; c.enableFullInformation=false; c.exactPlanned=true; c.forceGridPassage=false;
c.coarseEtaPoints=81; c.adaptiveEta=true; c.calibrationScales=table(); c.bandScaleFloor=.025;
c.includeSMC=true; c.requireLSTM=true; c.workflowMode=mode; c.confirmationFile='';
c.gateMinimumGain=.05; c.gateMinimumFleets=5; c.gateMatchedTolerance=.05;
c.gateMaximumLateBias_h=6; c.gateMinimumUnitCoverage=.85; c.gateMaximumWidthToRUL=2; c.gateConfidence=.95;
c.gateComparators={'Physics_SSM','Inverse_PINN','LSTM','Bayesian_PF'};
c.seed=20261017; c.optimizerPasses=1; c.refineEmission=false; c.jointRefineEmission=false;
c.observedIterations=3; c.observedFitSteps=35; c.jointSteps=35; c.residualCycles=2; c.residualBounds=[0 .15];
c.pinnStarts=1; c.pinnIterations=70; c.hidden1=3; c.hidden2=2; c.selectionSeeds=1;
c.validationPaths=40; c.validationParticles=100; c.forecastPaths=100; c.particles=180; c.etaGridPoints=201;
c.lstmHidden=24; c.lstmEpochs=30; c.lstmTrainingHours=40:40:400;
c.trainUnits=12; c.validationUnits=8; c.calibrationUnits=12; c.testUnits=8; c.replicates=1;
c.maxDiagnosticUnits=0; c.showFigures=false; c.maxRunSeconds=1800;
c.outputDir=fullfile(fileparts(mfilename('fullpath')),'runs');
c.originalSource=fullfile(fileparts(mfilename('fullpath')),'Reference','BSFD_PI_DSSDM_TwoState_v9.m');
c.label='Balanced development screen; all outcomes retained';
c.requireConvergedSelection=true; c.fastProfile=true; c.fastDenseMaxObs=1200; c.profileCacheMB=96;
c.profileDataSignature=''; c.runtimeCandidateDir=''; c.runtimeFitLabel='fit';
c.parallelMode='auto'; c.startParallelPool=false; c.maxGradientWorkers=4; c.activeGradientWorkers=0;
c.parallelMinimumParameters=12; c.checkpointEveryIterations=5; c.checkpointEverySeconds=20; c.progressEveryIterations=10;
c.intervalScaleMinimumUnits=4; c.intervalPredictedRULBreaks=[0 48 160 Inf]; c.lateRULThresholds=[24 48];
if ismember(mode,{'smoke','quick'})
    c.seed=20261018; c.trainUnits=4; c.validationUnits=3; c.calibrationUnits=10; c.testUnits=3;
    c.replicates=1; c.scenarios={'fatigue_discrepancy'}; c.observedIterations=1; c.observedFitSteps=6;
    c.jointSteps=6; c.residualCycles=1; c.pinnIterations=7; c.lstmEpochs=3; c.lstmHidden=8;
    c.particles=80; c.forecastPaths=30; c.validationPaths=20; c.etaGridPoints=81; c.coarseEtaPoints=41;
    c.originHours=[80 240 320]; c.lstmTrainingHours=80:80:400; c.maxRunSeconds=600;
    c.parallelMode='off'; c.label='Software smoke check; fitting deliberately insufficient for performance claims';
elseif ismember(mode,{'confirm','full','benchmark','data'})
    c.seed=20271017; if ismember(mode,{'full','benchmark'}), c.seed=20281017; end
    c.trainUnits=24; c.validationUnits=10; c.calibrationUnits=24; c.testUnits=16; c.replicates=5;
    c.observedIterations=4; c.observedFitSteps=100; c.jointSteps=120; c.residualCycles=3; c.residualBounds=[0 .15 .30];
    c.pinnIterations=240; c.pinnStarts=2; c.etaGridPoints=401; c.coarseEtaPoints=101; c.particles=600;
    c.forecastPaths=300; c.validationPaths=80; c.selectionSeeds=2; c.lstmHidden=[24 48]; c.lstmEpochs=100;
    c.lstmTrainingHours=40:20:400; c.maxRunSeconds=14400; c.label='Fresh-fleet confirmatory synthetic benchmark';
    if ismember(mode,{'full','benchmark','data'})
        c.enableProfiles=true; c.enableFullInformation=true; c.maxDiagnosticUnits=3;
        c.maxRunSeconds=28800; c.showFigures=true; c.label='Full synthetic benchmark, results independent of superiority gate';
    end
end
c=v17_revision_configuration(c,mode);c=v17_hierarchical_configuration(c,mode);
end

function E=experiment(units,c,eid,evidence,runDir)
rng(c.seed+floor((eid-1)/numel(c.scenarios))*19001,'twister'); ids=split_units(numel(units),c);
train=strip_truth(units(ids.train)); val=strip_truth(units(ids.validation));
d=fullfile(runDir,'stages'); if ~exist(d,'dir'), mkdir(d); end
c.runtimeCandidateDir=fullfile(runDir,'candidates',sprintf('E%03d',eid));
[ok,S]=v17_stage(d,eid,'physics');
if ok, physics=S.physics; Q=S.Q;dutyValidation=S.dutyValidation;
else
    v17_deadline('check'); fprintf('Stage 1: coherent profiled physics/emission/frailty fit.\n');
    [Q,dutyValidation]=v17_select_duty_model(train,val,c,eid); physics=fit_population(train,val,Q,c,eid);
    v17_stage(d,eid,'physics',struct('physics',physics,'Q',Q,'ids',ids,'dutyValidation',dutyValidation));
end
v17_stage_reporting('physics',eid,c,runDir);
populationStart=physics;
[ok,S]=v17_stage(d,eid,'primary');
if ok, primary=S.primary; physics=S.physics;
else
    v17_deadline('check'); fprintf('Stage 2: bounded TRAIN discrepancy, conservative VAL selection.\n');
    primary=fit_primary(train,val,Q,physics,c,eid); physics=primary.physicsControl;
    v17_stage(d,eid,'primary',struct('primary',primary,'physics',physics));
end
v17_stage_reporting('primary',eid,c,runDir);
[ok,S]=v17_stage(d,eid,'pinn');
if ok, pinn=S.pinn;
else, v17_deadline('check'); fprintf('Stage 3: inverse PINN.\n'); pinn=fit_pinn(train,val,Q,physics,c,eid); v17_stage(d,eid,'pinn',struct('pinn',pinn)); end
[ok,S]=v17_stage(d,eid,'lstm');
if ok, lstm=S.lstm;
else, v17_deadline('check'); v17_rng_stage(c,eid,'lstm'); fprintf('Stage 4: actual LSTM.\n'); clstm=c;clstm.runtimeDutyModel=Q;lstm=fit_lstm(train,val,clstm,eid); v17_stage(d,eid,'lstm',struct('lstm',lstm)); end
models={primary,pinn,lstm,physics}; methods={'PI_DSSDM','Inverse_PINN','LSTM','Physics_SSM'};
if c.includeBasisComparator
    [ok,S]=v17_stage(d,eid,'basis');
    if ok, basis=S.basis;
    else
        v17_deadline('check'); fprintf('Stage 5: small-basis discrepancy comparator.\n');
        cb=c; cb.primaryFamily='fixed_basis'; basis=fit_observed_primary(train,val,Q,populationStart,cb,eid);
        basis.label='Basis_hybrid'; v17_stage(d,eid,'basis',struct('basis',basis));
    end
    models{end+1}=basis; methods{end+1}='Basis_hybrid';
end
if c.includeSMC
    pf=physics; pf.kind='smc'; pf.label='Bayesian_PF'; models{end+1}=pf; methods{end+1}='Bayesian_PF';
end
policyRouting=table();bootstrapAudit=table();
if c.policySpecificSelection
 [ok,S]=v17_stage(d,eid,'policy_models');
 if ok,models=S.models;policyRouting=S.policyRouting;
 else,[models,policyRouting]=v17_select_policy_models(models,methods,val,Q,c,eid);v17_stage(d,eid,'policy_models',struct('models',{models},'policyRouting',policyRouting));end
end
point=struct();
if c.savePointForecastsFirst
 [ok,point]=v17_stage(d,eid,'point_forecasts');
 if ~ok
  fprintf('Stage 6a: save conditional point forecasts BEFORE expensive uncertainty refits.\n');
  [pc,pt,pf,pa,pb,pcc]=v17_forecast_bundle(units,ids,models,methods,Q,c,eid,evidence,'POINT');
  point=struct('cal',pc,'test',pt,'filters',pf,'ablation',pa,'bands',pb,'cc',pcc);
  v17_stage(d,eid,'point_forecasts',point);
 end
 v17_export_point_results(point,models,methods,c,eid,runDir);
end
if v17_bootstrap_required(c,evidence)
 [ok,S]=v17_stage(d,eid,'bootstrap');
 if ok,models=S.models;bootstrapAudit=S.bootstrapAudit;
 else,[models,bootstrapAudit]=v17_bootstrap_models(models,methods,train,c,eid);v17_stage(d,eid,'bootstrap',struct('models',{models},'bootstrapAudit',bootstrapAudit));end
end
models=v17_link_stack_partners(models,c);
primary=models{1};physics=models{4};pinn=models{2};lstm=models{3};
[ok,S]=v17_stage(d,eid,'forecasts');
if ok, cal=S.cal; test=S.test; filters=S.filters; ablation=S.ablation; bands=S.bands; cc=S.cc;
else
    v17_deadline('check'); fprintf('Stage 6b: final uncertainty-qualified CAL/TEST outputs.\n');
    if c.savePointForecastsFirst && ~v17_has_population_members(models,c)
     cal=point.cal;test=point.test;filters=point.filters;ablation=point.ablation;bands=point.bands;cc=point.cc;
     fprintf('  No accepted parameter mixture: reusing IDENTICAL conditional point forecasts.\n');
    else
     [cal,test,filters,ablation,bands,cc]=v17_forecast_bundle(units,ids,models,methods,Q,c,eid,evidence,'FINAL');
    end
    v17_stage(d,eid,'forecasts',struct('cal',cal,'test',test,'filters',filters,'ablation',ablation,'bands',bands,'cc',cc));
end
v17_deadline('check'); [ok,S]=v17_stage(d,eid,'information');
if ok, I=S.I; else, I=identifiability(primary,train,c,eid); v17_stage(d,eid,'information',struct('I',I)); end
[met,al]=metrics(test,c);met=v17_tag_metrics(met,models,methods,c);
E=struct('ids',ids,'evidence',evidence,'models',{models},'methodNames',{methods}, ...
    'dutyModel',Q,'trainingUnits',{train},'validationUnits',{val},'identifiability',I, ...
    'calibrationPredictions',cal,'predictions',test,'metrics',met,'alphaLambda',al, ...
    'calibration',bands,'calibrationScales',cc.calibrationScales,'filterDiagnostics',filters,'ablation',ablation);
U=units(ids.test(1)); [ks,~]=origin_nodes(U,c); H=causal_prefix(U,ks(end));
rng(c.seed+eid*101); post=observed_prefix(primary,H,c,true,c.particles);
E.example=struct('unit',U,'prefix',H,'posterior',post);
E.numericalAudit=numerical_origin_audit(primary,units,ids.test,Q,c,eid);
E.stateOriginAudit=state_origin_audit(test,units,ids.test);
E.scheduleAudit=schedule_audit(units,ids.test,c); E.innovationAudit=innovation_summary(post.innovations);
E.methodNumerics=numerical_method_audit(models,methods,units,ids.test,Q,c,eid);
if c.policySpecificSelection,E.optimizerAudit=v17_policy_optimizer_summary(models,methods,c);else,E.optimizerAudit=optimizer_summary(models,methods);end
E.policyRouting=policyRouting;E.dutyValidation=dutyValidation;E.bootstrapAudit=bootstrapAudit;
E.lateMetrics=v17_late_metrics(test,c);
E.intervalNestingViolations=sum(test.lower_h>test.rawLower_h+1e-9 | test.upper_h<test.rawUpper_h-1e-9);
[auditOK,AS]=v17_stage(d,eid,'hierarchical_audits');
if ~auditOK
 [HA,PA,RA]=v17_hierarchical_audits(primary,models,methods,train,val,units,ids,Q,c,eid);
 AS=struct('hierarchyAudit',HA,'pairedDutyAudit',PA,'rateStateHypothesis',RA);v17_stage(d,eid,'hierarchical_audits',AS);
end
E.hierarchyAudit=AS.hierarchyAudit;E.pairedDutyAudit=AS.pairedDutyAudit;E.rateStateHypothesis=AS.rateStateHypothesis;
print_diagnostics(E,c); export_experiment(E,eid,runDir); v17_extra_reporting(E,c,eid,runDir); v17_revision_reporting(E,units,ids,c,eid,runDir); v17_hierarchical_reporting(E,c,eid,runDir);v17_policy_reporting(E,c,eid,runDir);v17_consolidated_reporting(E,c,eid,runDir);
writetable(E.calibrationScales,fullfile(runDir,sprintf('VAL_band_scales_%02d.csv',eid)));
if c.makePlots, plot_experiment(E,c,eid,runDir); plot_revision_diagnostics(E,c,eid,runDir); end
end

function M=v17_map_population_initializer(train,val,Q,c,eid,useB)
v17_rng_stage(c,eid,sprintf('population_B%d',useB)); M=initial_model(train,c); M.useB=useB; M.baselineFixed=false;
if ~useB, M.C(:,3)=0; M.sigmaB=0; end
if ~c.profileQuadraticEmission, M.C(:,7)=0; end
if all(arrayfun(@(U)isfield(U,'reference') && ~isempty(U.reference),train))
    Y=[]; X=[];
    for i=1:numel(train)
        V=train(i).reference; assert(isfield(V,'healthyVerified') && V.healthyVerified,'pi17:baseline','Healthy reference must be independently verified.');
        X=[X;ones(numel(V.t),1) log(max(V.u(:,1:2),1e-8)) V.u(:,3)]; Y=[Y;V.y]; %#ok<AGROW>
    end
    M.referenceBaseline=zeros(size(M.C,1),4);
    for j=1:size(Y,2), good=isfinite(Y(:,j)); M.referenceBaseline(j,:)=(X(good,:)\Y(good,j))'; end
    M.C(:,[1 4 5 6])=M.referenceBaseline; M.baselineFixed=true;
end
best=Inf; bestConverged=Inf; predictive=M; converged=[]; rows=cell(0,10); archive={}; bestIteration=0;
for it=1:c.observedIterations
    tag=sprintf('physics_B%d_cycle%02d',useB,it); [M,opt,loss]=v17_profile_fit(M,train,c,c.observedFitSteps,tag);
    [score,~]=stable_score(M,val,Q,c,eid); ok=v17_converged(opt,c);
    archive{end+1}=struct('model',M,'optimizer',opt,'validationLoss',score); %#ok<AGROW>
    rows(end+1,:)={it,loss,-loss,score,NaN,opt.exitflag,opt.gradientNorm,NaN,NaN,mean(M.sensorSD)}; %#ok<AGROW>
    fprintf('  PROFILE B=%d cycle %d TRAIN %.7g VAL %.6g gradient %.4g converged=%d\n',useB,it,loss,score,opt.gradientNorm,ok);
    if score<best, best=score; predictive=M; predictive.selectedIteration=it; predictive.selectedMStep=opt; bestIteration=it; end
    if ok && score<bestConverged, bestConverged=score; converged=M; converged.selectedIteration=it; converged.selectedMStep=opt; end
    if ok, break; end
end
scores=cellfun(@(A)A.validationLoss,archive); optimizers=cellfun(@(A)A.optimizer,archive,'UniformOutput',false);
[chosen,hasConverged]=v17_select_checkpoint(scores,optimizers,c); A=archive{chosen}; M=A.model;
M.selectedIteration=chosen; M.selectedMStep=A.optimizer; selectedScore=A.validationLoss;
policy='No converged candidate, explicitly unresolved'; if hasConverged, policy='Best validation among converged candidates'; end
M.validationBestIteration=bestIteration; M.validationBestLoss=best; M.validationScore=selectedScore; M.fitCandidates=archive;
M.fitTrace=cell2table(rows,'VariableNames',{'iteration','expectedCompleteNLL','logEvidencePerUnit','causalValidationLoss','relativeParameterChange','mStepExitflag','mStepGradientNorm','meanESS','etaAcceptance','meanSensorSD'});
M.optimization=struct('status',policy,'stabilized',v17_converged(M.selectedMStep,c),'selectedIteration',M.selectedIteration, ...
    'selectedMStepExitflag',M.selectedMStep.exitflag,'lastMStepExitflag',opt.exitflag,'gradientNorm',M.selectedMStep.gradientNorm);
end

function [M,opt,loss]=v17_profile_fit(M,train,c,steps,tag)
if nargin<5,tag='';end
c.profileDataSignature=v17_hash_text(jsonencode(train));
[v,L]=v17_profile_encode(M,train,c);fun=@(z)v17_profile_objective(z,M,L,train,c);
continued=isfield(M,'optimizerContinuation') && isfield(M.optimizerContinuation,'signature') && ...
 strcmp(M.optimizerContinuation.signature,L.signature) && isequaln(M.optimizerContinuation.x,v);
if continued,c.initialBFGS=M.optimizerContinuation;end
c.runtimeFitLabel=tag; path='';if ~isempty(tag),path=v17_candidate_path(c,tag);end
fprintf('  Coordinate-consistent continuation %s: %d.\n',tag,continued);
[v,~,opt]=v17_bfgs(fun,v,max(1,steps*c.optimizerPasses),c,path);
[loss,M]=v17_profile_objective(v,M,L,train,c);
opt.converged=v17_converged(opt,c);opt.phaseGradientNorm=opt.gradientNorm;opt.phaseExitflag=opt.exitflag;
opt.curvatureContinued=continued;M.profileObjective=loss;
M.optimizerContinuation=struct('x',opt.finalVector,'g',opt.finalGradient,'H',opt.inverseHessian,'signature',L.signature);
end

function [v,L]=v17_profile_encode(M,train,c)
[x,free]=observed_encode(M,numel(train),c);
L=struct('x',x,'free',free,'nx',numel(free),'nn',0,'kind',M.kind,'outputOnly',false);
v=x(free);
if strcmp(M.kind,'pinn'),nw=pack_network(M.pinnNN);
elseif M.bound>0
 if isfield(M,'outputCoordinates'),q=M.outputCoordinates;
 else,q=M.nn.w/max(M.bound-sum(abs(M.nn.w)),1e-5);end
 L.outputOnly=strcmp(M.residualFamily,'fixed_basis') || c.freezeResidualHidden;
 if L.outputOnly,nw=q;else,N=M.nn;N.w=q;nw=pack_network(N);end
else,nw=[];end
L.nn=numel(nw);v=[v;nw];L.loading=[];
if M.useB,L.loading=setdiff(1:size(M.C,1),2);v=[v;M.C(L.loading,3)];end
v=[v;v17_bounded_encode(log(M.sensorSD(:)),log(c.sensorFloor),log(c.sensorCeiling)); ...
 v17_bounded_encode(log(M.unitSD),log(.04),log(.6))];
sig=struct('kind',M.kind,'bound',M.bound,'useB',M.useB,'nn',L.nn,'outputOnly',L.outputOnly, ...
 'free',free,'quadratic',c.profileQuadraticEmission,'data',v17_data_signature(train,c));
sig.objective=[c.emissionRidge c.quadraticEmissionRidgeMultiplier c.networkPenalty c.residualPenalty c.unitResidualPenalty ...
 c.measurementLogPriorSD c.unitHyperLogSD c.terminalDamageTolerance c.inspectionSD c.rateLogPriorSD c.exponentPriorSD ...
 c.tempPriorSD c.nominalRate c.nominalLoadExponent c.nominalTempCoefficient c.unitSD c.sensorSD c.outputSmoothEpsilon ...
 c.projectionSmoothEpsilon c.sensorFloor c.sensorCeiling c.protectFixedLoadSpeed c.protectFixedTemperature];
if M.bound>0,sig.reference=[M.reference.D;M.reference.u(:)];end
L.signature=v17_hash_text(jsonencode(sig));
if isfield(M,'optimizerContinuation') && isfield(M.optimizerContinuation,'signature') && ...
 strcmp(M.optimizerContinuation.signature,L.signature) && numel(M.optimizerContinuation.x)==numel(v)
 % Reuse the actual optimizer vector, never a rounded physical round trip.
 v=M.optimizerContinuation.x;
end
end

function [loss,M]=v17_profile_objective(v,M,L,train,c)
x=L.x;x(L.free)=v(1:L.nx);j=L.nx;
if L.nn>0
 nw=v(j+1:j+L.nn);j=j+L.nn;
 if strcmp(L.kind,'pinn'),M.pinnNN=unpack_network(nw,c.pinnHidden1,c.pinnHidden2,5);
 else
  if L.outputOnly,q=nw;else,M.nn=unpack_network(nw,c.hidden1,c.hidden2,5);q=M.nn.w;end
  M.outputCoordinates=q;M.nn.w=v17_smooth_output(q,M.bound,c);
 end
end
if M.useB,M.C(L.loading,3)=v(j+1:j+numel(L.loading));M.C(2,3)=1;j=j+numel(L.loading);end
p=size(M.C,1);
M.sensorSD=exp(v17_bounded_decode(v(j+1:j+p),log(c.sensorFloor),log(c.sensorCeiling)))';j=j+p;
M.unitSD=exp(v17_bounded_decode(v(j+1),log(.04),log(.6)));
M=observed_decode(x,M,numel(train),c);M.config=c;
[loss,M]=v17_profile_emission(M,train,c);
% A negligible raw-coordinate ridge prevents artificial stationarity at an
% infinitely saturated output map. It does not replace physical shrinkage.
if L.nn>0 && ~strcmp(L.kind,'pinn'),loss=loss+1e-7*sum(M.outputCoordinates.^2);end
if ~isfinite(loss),loss=1e30;end
end

function [loss,M,diagnostic]=v17_profile_emission_reference(M,train,c)
% Exact GLS variable projection of the linear mean in a Gaussian OU model.
% Kalman gains depend on covariance, never on these mean coefficients.
% Filtering Y and its design with identical gains produces whitened GLS.
p=size(M.C,1); mask=true(p,7); mask(:,3)=false;
if ~c.profileQuadraticEmission, mask(:,7)=false; M.C(:,7)=0; end
if M.baselineFixed, mask(:,[1 4 5 6])=false; end
idx=find(mask); fixed=M.C; fixed(idx)=0; nf=numel(idx);
G=zeros(nf); rhs=zeros(nf,1); yy=0; logdet=0; count=0; event=0; ode=[];
R=M.sensorSD.^2; cb=M.C(:,3);
for i=1:numel(train)
    U=train(i);
    if strcmp(M.kind,'pinn'), [D,q]=pinn_trajectory(M,U,M.trainingEta(i),c);
        target=physics_rate(M,U.u).*exp(M.trainingEta(i)).*(1+M.a*D);
        ode=[ode;log(max(q,realmin)./max(target,realmin))]; %#ok<AGROW>
    else, D=observed_trajectory(M,U,M.trainingEta(i),c); end
    X=emission_features(D,zeros(size(D)),U.u); my=0; mx=zeros(1,nf); variance=M.sigmaB^2;
    for k=1:numel(U.t)
        if k>1
            phi=exp(-(U.t(k)-U.t(k-1))/M.tau); my=phi*my; mx=phi*mx;
            variance=phi^2*variance+M.sigmaB^2*(1-phi^2);
        end
        good=isfinite(U.y(k,:)); m=sum(good);
        if m>0
            design=kron(X(k,:),eye(p)); design=design(good,idx);
            b=cb(good); rr=R(good)'; vb=b./rr; den=1+variance*(b'*vb);
            W=diag(1./rr)-variance*(vb*vb')/den;
            design=design-b*mx; y=U.y(k,good)'-(X(k,:)*fixed(good,:)')'-b*my;
            G=G+design'*W*design; rhs=rhs+design'*W*y; yy=yy+y'*W*y;
            logdet=logdet+sum(log(rr))+log(den); count=count+m;
            gain=variance*b'*W; my=my+gain*y; mx=mx+gain*design;
            variance=max(0,variance-gain*b*variance);
        end
        if isfinite(U.inspection(k))
            event=event+.5*((D(k)-U.inspection(k))/c.inspectionSD)^2; count=count+1;
        end
    end
    if U.failureObserved
        event=event+.5*((D(end)-c.Dcrit)/c.terminalDamageTolerance)^2+ ...
            5*sum((max(D(1:end-1)-c.Dcrit,0)/c.terminalDamageTolerance).^2); count=count+1;
    end
end
weights=ones(p,7); weights(:,1)=1e-6; weights(:,7)=c.quadraticEmissionRidgeMultiplier; penalty=c.emissionRidge*diag(weights(idx));
coef=(G+penalty+1e-12*eye(nf))\rhs; M.C(idx)=coef;
data=.5*(yy-2*coef'*rhs+coef'*(G+penalty)*coef+logdet+count*log(2*pi))+event;
n=numel(train); eta=M.trainingEta;
prior=.5*(log(M.k/c.nominalRate)/c.rateLogPriorSD)^2+ ...
    .5*((M.p-c.nominalLoadExponent)/c.exponentPriorSD)^2+.5*((M.betaT-c.nominalTempCoefficient)/c.tempPriorSD)^2+ ...
    .5*sum((eta/M.unitSD).^2)+(n-1)*log(M.unitSD/c.unitSD)+ ...
    .5*(log(M.unitSD/c.unitSD)/c.unitHyperLogSD)^2+ ...
    .5*sum((log(M.sensorSD/c.sensorSD)/c.measurementLogPriorSD).^2);
barrier=100*sum(max(abs(eta)-c.unitEffectMax,0).^2);
loss=(data+prior)/max(count,1)+barrier;
if strcmp(M.kind,'pinn')
    loss=loss+c.pinnPhysicsWeight*mean(ode.^2)+c.networkPenalty*sum(pack_network(M.pinnNN).^2);
elseif M.bound>0
    ref=M.reference; rho=discrepancy(M,ref.D,zeros(size(ref.D)),ref.u); um=accumarray(ref.unit,rho,[],@mean);
    loss=loss+c.residualPenalty*mean(rho.^2)+c.unitResidualPenalty*mean(um.^2)+c.networkPenalty*sum(pack_network(M.nn).^2);
end
diagnostic=struct('normalEquationResidual',norm((G+penalty)*coef-rhs,Inf),'observations',count,'GLSdataObjective',data);
end

function M=v17_fit_primary(train,val,Q,base,c,eid)
[best,baseUnits]=stable_score(base,val,Q,c,eid);base.predictionOptimization=base.selectedMStep;
M=base;M.label='PI_DSSDM';M.residualFamily=c.primaryFamily;rows={0,0,best,0,0,base.selectedMStep.gradientNorm,0,0,base.selectedMStep.exitflag,v17_converged(base.selectedMStep,c),base.selectedMStep.gradientNorm,0};
candidates={};M.networkTrace=table();M.residualTrace=table();
starts=1;if isfield(c,'residualStarts') && ~strcmp(c.primaryFamily,'fixed_basis'),starts=max(1,c.residualStarts);end
for bound=c.residualBounds(c.residualBounds>0)
 for start=1:starts
 % Every start begins at the physics solution (zero output weights); starts
 % differ only in the TRAIN-learned encoder initialisation.
 candidate=base;candidate.bound=bound;candidate.residualFamily=c.primaryFamily;
 rng(c.seed+eid*100+47+1009*(start-1));candidate.nn=init_network(c.hidden1,c.hidden2,5);
 if strcmp(c.primaryFamily,'fixed_basis')
  candidate.nn.W1(:)=0;candidate.nn.W2(:)=0;candidate.nn.b1(:)=0;candidate.nn.b2(:)=0;
  if isfield(c,'basisFamily') && strcmp(c.basisFamily,'rbf'),candidate.nn.w=zeros(v17_basis_size(c),1);end
 elseif c.neuralSkipFeatures,candidate.nn.w=[candidate.nn.w;zeros(3,1)];end
 candidate.outputCoordinates=zeros(size(candidate.nn.w));candidate.reference=observed_reference(base,train,c);candidate=project_network(candidate,c);
 startTag='';if start>1,startTag=sprintf('_s%02d',start);end
 if c.encoderSteps>0 && ~strcmp(c.primaryFamily,'fixed_basis')
  [candidate,~,~]=v17_marginal_fit(candidate,train,c,c.encoderSteps,sprintf('%s_b%03d%s_encoder',c.primaryFamily,round(100*bound),startTag),true);
 end
 candidate=v17_select_function_coordinates(candidate,c);
 for cycle=1:c.marginalCycles
  tag=sprintf('%s_b%03d%s_function_cycle%02d',c.primaryFamily,round(100*bound),startTag,cycle);
  [candidate,opt,loss]=v17_marginal_fit(candidate,train,c,c.functionalSteps,tag,false);
  if strcmp(c.trainingLikelihood,'event_time') && v17_converged(opt,c)
   [candidate,opt,loss]=v17_curvature_polish(candidate,train,c,tag);
  end
  candidate.validationScore=NaN;
  if ~strcmp(c.primaryFamily,'fixed_basis')
   candidate=v17_joint_stationarity(candidate,train,c,tag);
   if c.jointRecoverySteps>0 && v17_converged(opt,c) && ~candidate.encoderStationarity.jointStationary
    if isfield(candidate,'marginalContinuation'),candidate=rmfield(candidate,'marginalContinuation');end
    [candidate,opt,loss]=v17_marginal_fit(candidate,train,c,c.jointRecoverySteps,[tag '_joint_TRAIN_recovery'],true);
    if v17_converged(opt,c),[candidate,opt,loss]=v17_curvature_polish(candidate,train,c,[tag '_joint']);end
    candidate=v17_joint_stationarity(candidate,train,c,[tag '_joint']);
   end
  end
  [score,us]=stable_score(candidate,val,Q,c,eid);candidate.validationScore=score;gain=baseUnits-us;gain=gain(isfinite(gain));se=std(gain)/sqrt(numel(gain));gg=mean(gain);
  rho=discrepancy(candidate,candidate.reference.D,zeros(size(candidate.reference.D)),candidate.reference.u);
  eligible=v17_converged(opt,c) && v17_converged(base.selectedMStep,c);
  if c.requireJointEncoderStationarity && isfield(candidate,'encoderStationarity'),eligible=eligible && candidate.encoderStationarity.jointStationary;end
  jointGrad=opt.gradientNorm;if isfield(candidate,'encoderStationarity'),jointGrad=candidate.encoderStationarity.jointFeasibleGradientNorm;end
  rows(end+1,:)={bound,cycle,score,sqrt(mean(rho.^2)),max(abs(rho)),opt.gradientNorm,gg,se,opt.exitflag,eligible,jointGrad,start}; %#ok<AGROW>
  candidates{end+1}=struct('model',candidate,'optimizer',opt,'validationLoss',score,'eligible',eligible); %#ok<AGROW>
  fprintf('  FUNCTION %s bound %.2f start %d VAL %.6g gain %.4g SE %.4g exitflag %d eligible=%d.\n',c.primaryFamily,bound,start,score,gg,se,opt.exitflag,eligible);
  % v17: the binding selection is made once, in v17_select_policy_models,
  % over every eligible candidate. Here only the archive representative is chosen.
  gate=true;if ~isfield(c,'primaryOneSEGate') || c.primaryOneSEGate,gate=gg>max(c.minimumValidationGain,c.oneSEMultiplier*se);end
  if eligible && score<best && gate
   M=candidate;best=score;M.jointOptimization=opt;
   M.residualTrace=table(cycle,loss,score,sqrt(mean(rho.^2)),max(abs(rho)),opt.gradientNorm, ...
    'VariableNames',{'cycle','expectedRateNLL','causalValidationLoss','rhoRMS','rhoMaxAbs','gradientNorm'});
   M.networkTrace=array2table([(1:size(opt.trace,1))' opt.trace(:,1:2)],'VariableNames',{'iteration','loss','gradientNorm'});
  end
  if v17_converged(opt,c),break;end
 end
 end
end
M.label='PI_DSSDM';M.validationScore=best;M.residualFamily=c.primaryFamily;M.physicsControl=base;
M.discrepancyCandidates=candidates;M.selection=cell2table(rows,'VariableNames',{'bound','cycle','causalValidationLoss','rhoRMS','rhoMaxAbs','gradientNorm','pairedUnitGain','pairedGainSE','exitflag','eligible','jointFeasibleGradientNorm','start'});
M.optimization=struct('status','Marginal TRAIN fit; binding VAL selection deferred to the policy stage','selectedBound',M.bound, ...
 'physicsFrozen',false,'validationLogRULLoss',best);
if ~isfield(M,'networkTrace'),M.networkTrace=table();end
if ~isfield(M,'residualTrace'),M.residualTrace=table();end
end

function M=v17_fit_pinn(train,val,Q,base,c,eid)
rows=cell(0,7);archive={};opts={};scores=[];
for start=1:c.pinnStarts
 rng(c.seed+eid*10000+400+start);candidate=base;candidate.kind='pinn';candidate.bound=0;
 candidate.pinnNN=init_network(c.pinnHidden1,c.pinnHidden2,5);candidate.pinnNN.w(:)=0;
 for cycle=1:c.pinnCycles
  [candidate,opt,loss]=v17_marginal_fit(candidate,train,c,c.pinnIterations,sprintf('marginal_pinn_s%02d_cycle%02d',start,cycle),true);
  if cycle==c.pinnCycles && c.recoverComparators && ~v17_converged(opt,c)
   if isfield(candidate,'marginalContinuation'),candidate=rmfield(candidate,'marginalContinuation');end
   [candidate,opt,loss]=v17_marginal_fit(candidate,train,c,c.populationRecoverySteps,sprintf('pinn_s%02d_TRAIN_recovery',start),true);
  end
  score=forecast_score(candidate,val,Q,c,eid);ode=[];
  for i=1:numel(train)
   [D,q]=pinn_trajectory(candidate,train(i),candidate.trainingEta(i),c);
   target=physics_rate(candidate,train(i).u).*exp(candidate.trainingEta(i)).*(1+candidate.a*D);
   ode=[ode;log(max(q,realmin)./max(target,realmin))]; %#ok<AGROW>
  end
  rmsODE=sqrt(mean(ode.^2));candidate.validationScore=score;candidate.selectedMStep=opt;candidate.optimization=opt;candidate.optimization.relativeODEResidualRMS=rmsODE;candidate.pinnTrace=opt.trace;
  candidate=v17_joint_stationarity(candidate,train,c,'PINN_joint_KKT');archive{end+1}=candidate;opts{end+1}=opt;scores(end+1)=score; %#ok<AGROW>
  rows(end+1,:)={start,loss,score,opt.exitflag,rmsODE,opt.gradientNorm,cycle}; %#ok<AGROW>
  if v17_converged(opt,c),break;end
 end
end
[chosen,~]=v17_select_checkpoint(scores,opts,c);M=archive{chosen};M.label='Inverse_PINN';M.validationScore=scores(chosen);
M.policyArchive=archive;
M.selection=cell2table(rows,'VariableNames',{'start','objective','causalValidationLoss','exitflag','relativeODEResidualRMS','gradientNorm','cycle'});
end

function bank=v17_score_bank(H,policy,Q,c,n,eid)
persistent cache
if ischar(H) && strcmp(H,'reset'), cache=containers.Map('KeyType','char','ValueType','any'); bank=[]; return; end
if isempty(cache), cache=containers.Map('KeyType','char','ValueType','any'); end
key=sprintf('%d/%d/%s/%.12g/%s/%d/%.12g/%.12g',c.seed,eid,H.id,H.t(end),policy,n,c.forecastHorizonHours,c.dutyStepHours);
if isKey(cache,key), bank=cache(key); else, bank=future_bank(H,policy,Q,c,n); cache(key)=bank; end
end

function q=v17_quantile(samples,info,p)
if isfield(info,'sampleWeights'), q=v17_weighted_quantile(samples,info.sampleWeights,p);
else, q=quantile_base(samples,p); end
end

function q=v17_weighted_quantile(x,w,p)
% Mid-mass interpolation removes artificial jumps caused by reporting a grid
% node as a continuous eta/RUL quantile. Infinite right-censored mass stays Inf.
[x,ix]=sort(x(:));w=w(ix);keep=w>0 & ~isnan(x);x=x(keep);w=w(keep);w=w/sum(w);
[x,~,group]=unique(x);w=accumarray(group,w);
finite=isfinite(x);finiteMass=sum(w(finite));
if p>finiteMass+1e-14,q=Inf;return;end
if isempty(x),q=NaN;return;end
if ~any(finite),q=Inf;return;end
xx=x(finite);ww=w(finite);centers=cumsum(ww)-.5*ww;
[centers,keep]=unique(centers,'stable');xx=xx(keep);
if numel(centers)==1,q=xx(1);return;end
if p<=centers(1),q=xx(1);elseif p>=centers(end),q=xx(end);
else,q=interp1(centers,xx,p,'linear');end
end

function P=v17_grid_prefix_once(M,H,c)
eta=linspace(-c.unitEffectMax,c.unitEffectMax,c.coarseEtaPoints)';
[D,E,K,nll,w]=evaluate(eta);
% Sequential diagnostic summaries use the fixed, full-support coarse grid.
% The origin-adaptive grid must not be reused to smooth earlier summaries.
nc=numel(H.t); filtered=zeros(nc,3); ess=zeros(nc,1); mass=zeros(nc,1);
lp=-.5*(eta'/M.unitSD).^2;
for k=1:nc
    previous=lp; if k>1, previous=previous-K.cumulativeNLL(k-1,:); previous(any(D(1:k-1,:)>=c.Dcrit,1))=-Inf; end
    before=normalized_weights(previous'); live=D(k,:)'<c.Dcrit; mass(k)=sum(before(live));
    current=lp-K.cumulativeNLL(k,:); current(~live')=-Inf; wk=normalized_weights(current');
    filtered(k,:)=[D(k,:)*wk K.mean(k,:)*wk eta'*wk]; ess(k)=1/sum(wk.^2);
end
if c.adaptiveEta
    lo=v17_weighted_quantile(eta,w,.0001); hi=v17_weighted_quantile(eta,w,.9999);
    % Cover at least one full coarse cell; otherwise a sharp posterior between
    % coarse nodes could be wrongly truncated around the winning coarse node.
    pad=max([.02,.15*(hi-lo),2*c.unitEffectMax/(c.coarseEtaPoints-1)]);
    lo=max(-c.unitEffectMax,lo-pad); hi=min(c.unitEffectMax,hi+pad);
else, lo=-c.unitEffectMax; hi=c.unitEffectMax; end
eta=linspace(lo,hi,c.etaGridPoints)'; [D,E,K,nll,w]=evaluate(eta);
filtered(end,:)=[D(end,:)*w K.mean(end,:)*w eta'*w];
P=struct('D',D(end,:)','B',K.mean(end,:)','eta',eta,'weights',w, ...
    'filteredMean',filtered,'ESS',ess,'eventMass',mass, ...
    'distinctRateParticles',numel(eta),'etaAcceptance',NaN,'cdfUnderflowParticles',0, ...
    'etaGrid',eta,'etaWeights',w,'status','Adaptive conditional eta quadrature; B integrated; global parameters plug-in');
if strcmp(M.kind,'pinn'), P.exposure=E(end,:)'; end
    function [DD,EE,KK,ll,ww]=evaluate(ee)
        EE=[];
        if strcmp(M.kind,'pinn'), [DD,~,EE]=pinn_trajectory(M,H,ee,c);
        else, DD=observed_trajectory(M,H,ee,c); end
        [ll,KK]=observed_kalman(M,H,DD,c,false);
        lw=-.5*(ee'/M.unitSD).^2-ll;
        if numel(ee)>1, lw([1 end])=lw([1 end])+log(.5); end % trapezoidal endpoint weights
        lw(~all(DD<c.Dcrit,1))=-Inf;
        assert(any(isfinite(lw)),'pi17:quadrature','No surviving trajectory in quadrature support');
        ww=normalized_weights(lw');
    end
end

function P=v17_noisy_prefix(M,H,c)
% Causal posterior for the v17 gamma damage-increment model,
%   dD ~ Gamma(shape=h/kappa, scale=kappa*r(D,u,eta)), mean r*h (midpoint law).
% Eta is integrated on a node grid; within each node a survival-conditioned
% particle filter carries D, and B is Rao-Blackwellised (exact Kalman given
% D). Node evidence is the unbiased particle-filter likelihood estimate.
% Support comes from the deterministic posterior, widened by its own width
% on each side; prior mass outside that window is neglected (recorded).
kp=M.processKappa;P0=v17_grid_prefix(rmfield(M,'processKappa'),H,c);
lo=v17_weighted_quantile(P0.eta,P0.weights,.0005);hi=v17_weighted_quantile(P0.eta,P0.weights,.9995);
span=max(hi-lo,.05);lo=max(-c.unitEffectMax,lo-span);hi=min(c.unitEffectMax,hi+span);
G=c.processEtaNodes;Np=c.processParticles;N=G*Np;nodes=linspace(lo,hi,G);
etaAll=reshape(repmat(nodes,Np,1),[],1);lp=-.5*(nodes/M.unitSD).^2;
D=zeros(N,1)+H.initialD;bm=zeros(N,1);bv=M.sigmaB^2;w=ones(Np,G)/Np;logZ=zeros(1,G);
K=numel(H.t);filtered=zeros(K,3);ess=zeros(K,1);mass=ones(K,1);zero=zeros(N,1);
for k=1:K
 if k>1
  dt=H.t(k)-H.t(k-1);u=repmat(H.u(k-1,:),N,1);ns=max(1,ceil(dt/c.transitionStepHours));h=dt/ns;
  base=physics_rate(M,u).*exp(etaAll);
  for j=1:ns
   r=base.*exp(discrepancy(M,D,zero,u)).*(1+M.a*D);mid=D+.5*h*r;
   dx=h*base.*exp(discrepancy(M,mid,zero,u)).*(1+M.a*mid);
   D=D+kp*(dx/h).*randg(h/kp,N,1);
  end
  phi=exp(-dt/M.tau);bm=phi*bm;bv=phi^2*bv+M.sigmaB^2*(1-phi^2);
 end
 live=D<c.Dcrit;incr=zeros(N,1);incr(~live)=Inf;
 nodePrior=normalized_weights((lp+logZ)');mass(k)=sum(nodePrior'.*sum(w.*reshape(live,Np,G),1));
 good=isfinite(H.y(k,:));
 if any(good)
  mu=emission_features(D,bm,repmat(H.u(k,:),N,1))*M.C';
  residual=H.y(k,good)-mu(:,good);cb=M.C(good,3);rr=M.sensorSD(good)'.^2;
  vb=cb./rr;den=1+bv*(cb'*vb);W=diag(1./rr)-bv*(vb*vb')/den;
  incr=incr+.5*(sum((residual*W).*residual,2)+sum(log(rr))+log(den)+sum(good)*log(2*pi));
  gain=bv*cb'*W;bm=bm+residual*gain';bv=max(0,bv-gain*cb*bv);
 end
 if isfinite(H.inspection(k)),incr=incr+.5*((D-H.inspection(k))/c.inspectionSD).^2+log(sqrt(2*pi)*c.inspectionSD);end
 lw=log(max(w,realmin))-reshape(incr,Np,G);top=max(lw,[],1);alive=isfinite(top);
 total=zeros(1,G);total(alive)=sum(exp(lw(:,alive)-top(alive)),1);
 logZ(alive)=logZ(alive)+top(alive)+log(total(alive));logZ(~alive)=-Inf;
 w(:,alive)=exp(lw(:,alive)-top(alive))./total(alive);
 assert(any(alive),'pi17:noisyFilter','No surviving damage-increment particle in any eta node.');
 nodeWeight=normalized_weights((lp+logZ)');Wall=reshape(w.*nodeWeight',[],1);
 filtered(k,:)=[Wall'*D Wall'*bm Wall'*etaAll];ess(k)=1/sum(Wall.^2);
 for g=find(alive)
  if 1/sum(w(:,g).^2)<c.essFraction*Np || k==K
   ix=(g-1)*Np+systematic_resample(w(:,g),Np);range=(g-1)*Np+(1:Np);
   D(range)=D(ix);bm(range)=bm(ix);w(:,g)=1/Np;
  end
 end
end
nodeWeight=normalized_weights((lp+logZ)');Wall=reshape(w.*nodeWeight',[],1);
B=bm+sqrt(max(bv,0))*randn(N,1);eta=etaAll;weights=Wall;
if N>c.processOutputParticles
 ix=systematic_resample(Wall,c.processOutputParticles);D=D(ix);B=B(ix);eta=eta(ix);weights=ones(numel(ix),1)/numel(ix);
end
P=struct('D',D,'B',B,'eta',eta,'weights',weights,'filteredMean',filtered,'ESS',ess,'eventMass',mass, ...
 'distinctRateParticles',numel(unique(eta)),'etaAcceptance',NaN,'cdfUnderflowParticles',0, ...
 'etaGrid',nodes(:),'etaWeights',nodeWeight,'processKappa',kp,'etaWindow',[lo hi], ...
 'status',sprintf('Eta-node x particle filter, gamma damage increments kappa=%.3g h; B integrated',kp));
end

function P=v17_smc_prefix(M,H,c)
% Genuine sequential importance/resampling with full-prefix MH moves for eta.
% Scalar B is Rao-Blackwellized; global parameters remain plug-in estimates.
n=c.particles; eta=sqrt(2)*M.unitSD*erfinv((2*rand(n,1)-1)*erf(c.unitEffectMax/(sqrt(2)*M.unitSD)));
D=zeros(n,1)+H.initialD; bm=zeros(1,n); bv=M.sigmaB^2; w=ones(n,1)/n; logLike=zeros(n,1);
K=numel(H.t); filtered=zeros(K,3); ess=zeros(K,1); mass=ones(K,1); accept=0; proposed=0;
for k=1:K
    if k>1
        dt=H.t(k)-H.t(k-1); D=advance_D(D,physics_rate(M,repmat(H.u(k-1,:),n,1)).*exp(eta),M.a,dt);
        phi=exp(-dt/M.tau); bm=phi*bm; bv=phi^2*bv+M.sigmaB^2*(1-phi^2);
    end
    live=D<c.Dcrit; mass(k)=sum(w(live)); incr=zeros(n,1); incr(~live)=Inf;
    good=isfinite(H.y(k,:));
    if any(good)
        mu=emission_features(D,bm',repmat(H.u(k,:),n,1))*M.C';
        residual=H.y(k,good)-mu(:,good); cb=M.C(good,3); rr=M.sensorSD(good)'.^2;
        vb=cb./rr; den=1+bv*(cb'*vb); W=diag(1./rr)-bv*(vb*vb')/den;
        incr=incr+.5*(sum((residual*W).*residual,2)+sum(log(rr))+log(den)+sum(good)*log(2*pi));
        gain=bv*cb'*W; bm=bm+(residual*gain')'; bv=max(0,bv-gain*cb*bv);
    end
    if isfinite(H.inspection(k)), incr=incr+.5*((D-H.inspection(k))/c.inspectionSD).^2; end
    w=normalized_weights(log(max(w,realmin))-incr); logLike=logLike-incr;
    filtered(k,:)=[w'*D bm*w w'*eta]; ess(k)=1/sum(w.^2);
    if ess(k)<c.essFraction*n && k<K
        ix=systematic_resample(w,n); D=D(ix); eta=eta(ix); bm=bm(ix); logLike=logLike(ix); w(:)=1/n;
        HH=causal_prefix(H,k);
        for sweep=1:c.rejuvenationSteps
            proposal=eta+c.etaProposalSD*randn(n,1); DT=observed_trajectory(M,HH,proposal,c);
            [ll,KF]=observed_kalman(M,HH,DT,c,false); pl=-ll'; pl(any(DT>=c.Dcrit,1)' | abs(proposal)>c.unitEffectMax)=-Inf;
            ratio=pl-logLike-.5*(proposal.^2-eta.^2)/M.unitSD^2;
            take=log(rand(n,1))<ratio; eta(take)=proposal(take); D(take)=DT(end,take)'; bm(take)=KF.mean(end,take);
            logLike(take)=pl(take); accept=accept+sum(take); proposed=proposed+n;
        end
    end
end
P=struct('D',D,'B',bm','eta',eta,'weights',w,'filteredMean',filtered,'ESS',ess,'eventMass',mass, ...
    'etaAcceptance',accept/max(proposed,1),'distinctRateParticles',numel(unique(eta)), ...
    'cdfUnderflowParticles',0,'status','Rao-Blackwellized sequential Monte Carlo PF with full-prefix Metropolis eta moves');
end

function T=v17_fit_band_scales(P,c)
% Fixed predicted-RUL bins, fitted using independent VAL units only. Sparse
% bins revert to global scale. True life fractions never enter the mapping.
rows=cell(0,8);
for method=unique(P.method)'
    for policy=unique(P.policy)'
        Q=P(strcmp(P.method,method{1}) & strcmp(P.policy,policy{1}) & P.available & isfinite(P.predictedRUL_h),:);
        err=abs(log1p(Q.trueRUL_h)-log1p(Q.predictedRUL_h));
        globalScale=v17_unit_mean(err,Q.unit); if ~isfinite(globalScale), globalScale=c.bandScaleFloor; end
        for b=1:numel(c.intervalPredictedRULBreaks)-1
            lo=c.intervalPredictedRULBreaks(b); hi=c.intervalPredictedRULBreaks(b+1); ix=Q.predictedRUL_h>=lo & Q.predictedRUL_h<hi;
            units=numel(unique(Q.unit(ix))); fallback=units<c.intervalScaleMinimumUnits;
            scale=globalScale; if ~fallback, scale=v17_unit_mean(err(ix),Q.unit(ix)); end
            rows(end+1,:)={method{1},policy{1},lo,hi,max(c.bandScaleFloor,scale),units,fallback,height(Q)}; %#ok<AGROW>
        end
    end
end
T=cell2table(rows,'VariableNames',{'method','policy','lowerPredictedRUL_h','upperPredictedRUL_h','scale','independentValidationUnits','globalFallback','validationForecasts'});
end

function scale=v17_band_scale(P,c)
scale=ones(height(P),1); if isempty(c.calibrationScales), return; end
T=c.calibrationScales;
for j=1:height(T)
    r=T(j,:); ix=strcmp(P.method,r.method{1}) & strcmp(P.policy,r.policy{1});
    if ismember('scale',T.Properties.VariableNames)
        ix=ix & P.predictedRUL_h>=r.lowerPredictedRUL_h & P.predictedRUL_h<r.upperPredictedRUL_h; scale(ix)=r.scale;
    else
        % Compatibility with the inherited numerical regression test schema.
        scale(ix)=r.intercept+r.inverseSqrtRUL./sqrt(P.predictedRUL_h(ix)+1);
    end
end
scale=max(c.bandScaleFloor,scale);
end

function F=v17_skipped_information()
F=struct('names',{{}},'rank',NaN,'activeParameters',NaN,'activeMask',false(1,0), ...
    'singularValues',NaN,'information',NaN,'physicsRank',NaN,'physicsParameters',NaN, ...
    'physicsCorrelations',nan(4),'scaledConditionNumber',NaN,'negativeCurvatureDirections',NaN, ...
    'note','NOT COMPUTED: enableFullInformation=false in this configuration (v16 wrongly said it was reserved for FULL; FULL also leaves it off unless overridden).');
end

function rows=v17_profile_scan(M,train,c)
% Scan outwards from the fitted center, warm-starting only from converged
% neighboring points. An unconverged value is exported as NaN, not as an
% apparently valid likelihood curve or confidence interval.
rows=cell(0,7);if ~c.enableProfiles,return;end
c.profileDataSignature=v17_hash_text(jsonencode(train));[v,L]=v17_profile_encode(M,train,c);
for z=intersect([1 2 4],L.free)
 iz=find(L.free==z);other=setdiff(1:numel(v),iz);values=v(iz)+linspace(-c.profileSpan,c.profileSpan,c.profilePoints);
 [~,order]=sort(abs(values-v(iz)));anchors={};locations=[];
 for j=order
  anchor=v;if ~isempty(locations),[~,near]=min(abs(locations-values(j)));anchor=anchors{near};end
  anchor(iz)=values(j);previous=[];good=false;
  for cycle=1:c.profileCycles
   fun=@(u)v17_profile_free(u,anchor,other,M,L,train,c);cc=c;
   tag=sprintf('profile_coordinate%d_point%02d_cycle%02d',z,j,cycle);cc.runtimeFitLabel=tag;
   if ~isempty(previous),cc.initialBFGS=previous;end
   [u,loss,opt]=v17_bfgs(fun,anchor(other),c.profileIterations,cc,v17_candidate_path(c,tag));anchor(other)=u;
   previous=struct('x',u,'g',opt.finalGradient,'H',opt.inverseHessian);
   good=v17_converged(opt,c);if good,break;end
  end
  [~,mm]=v17_profile_objective(anchor,M,L,train,c);phys=[mm.k mm.p mm.betaT mm.a];
  if good,anchors{end+1}=anchor;locations(end+1)=values(j);else,loss=NaN;end %#ok<AGROW>
  rows(end+1,:)={z,values(j),phys(z),loss,opt.exitflag,opt.iterations,opt.gradientNorm}; %#ok<AGROW>
  fprintf('  Profile coordinate %d point %d: valid=%d, gradient %.4g.\n',z,j,good,opt.gradientNorm);
 end
end
end

function f=v17_profile_free(u,v,index,M,L,train,c)
v(index)=u; f=v17_profile_objective(v,M,L,train,c);
end

function [ok,S]=v17_stage(dir,e,tag,varargin)
persistent timers
if isempty(timers), timers=containers.Map('KeyType','char','ValueType','any'); end
f=fullfile(dir,sprintf('E%03d_%s.mat',e,tag));
if isempty(varargin)
    ok=exist(f,'file')==2; S=struct();
    if ok
        S=load(f); ok=isfield(S,'stageComplete') && S.stageComplete;
        if ok, fprintf('  Reusing completed stage: %s\n',tag); end
    end
    if ~ok, timers(f)=tic; end
else
    v17_deadline('check'); S=varargin{1}; S.stageComplete=true;
    if isKey(timers,f), S.stageElapsedSeconds=toc(timers(f)); else, S.stageElapsedSeconds=NaN; end
    v17_save(f,S); ok=true; fprintf('  Saved completed stage %s, %.1f invocation seconds.\n',tag,S.stageElapsedSeconds);
end
end

function v17_save(path,payload)
tmp=[path '.pending.mat']; save(tmp,'-struct','payload','-v7.3');
[ok,msg]=movefile(tmp,path,'f'); assert(ok,'pi17:checkpoint','Atomic checkpoint replacement failed: %s',msg);
end

function answer=v17_deadline(action,seconds)
persistent started limit
if isempty(started), started=tic; limit=Inf; end
if strcmp(action,'start'), started=tic; limit=seconds; answer=false; return; end
answer=toc(started)>=limit;
if strcmp(action,'check') && answer, error('pi17:budget','Invocation time budget reached. Resume the checkpoint to reuse completed stages.'); end
end

function v17_export_current(R)
writetable(R.metrics,fullfile(R.outputDir,'Benchmark_metrics.csv'));
writetable(R.predictions,fullfile(R.outputDir,'RUL_predictions.csv'));
writetable(R.alphaLambda,fullfile(R.outputDir,'Alpha_lambda.csv'));
try
    v17_assessment_summary(R);
catch err
    fprintf('Assessment summary skipped: %s\n',err.message);
end
end

function S=v17_assessment_summary(R)
% Running fleet-level assessment, rewritten after every completed experiment.
% The unit of inference is the independent fleet (experiment), never the
% repeated forecast row. Gain = comparator MAE - PI-DSSDM MAE (positive means
% PI-DSSDM is better). Unadjusted t intervals and exact sign tests are
% descriptive; multiplicity across comparators/policies is not corrected.
S=table(); T=R.metrics; if isempty(T), return; end
methods=setdiff(unique(T.method),{'PI_DSSDM'}); policies=unique(T.policy); rows=cell(0,15);
scenario=regexprep(T.evidence,'^SYNTHETIC:([^:]+):.*$','$1');
groups=[{'ALL'};unique(scenario)];
for g=1:numel(groups)
 for p=1:numel(policies)
  for m=1:numel(methods)
   a=[];b=[];eligible=[];
   for e=unique(T.experiment)'
    if ~strcmp(groups{g},'ALL') && ~any(strcmp(scenario(T.experiment==e),groups{g})), continue; end
    x=T(T.experiment==e & strcmp(T.policy,policies{p}) & strcmp(T.method,'PI_DSSDM'),:);
    y=T(T.experiment==e & strcmp(T.policy,policies{p}) & strcmp(T.method,methods{m}),:);
    if isempty(x) || isempty(y) || ~isfinite(x.MAE_h(1)) || ~isfinite(y.MAE_h(1)), continue; end
    a(end+1)=x.MAE_h(1); b(end+1)=y.MAE_h(1); %#ok<AGROW>
    ok=true; if ismember('estimationEligible',T.Properties.VariableNames), ok=y.estimationEligible(1); end
    eligible(end+1)=ok; %#ok<AGROW>
   end
   n=numel(a); if n==0, continue; end
   gain=b-a; lo=NaN; hi=NaN;
   if n>1
    nu=n-1; critical=sqrt(nu*(1/betaincinv(.05,nu/2,.5)-1)); half=critical*std(gain)/sqrt(n);
    lo=mean(gain)-half; hi=mean(gain)+half;
   end
   wins=sum(gain>1e-9); losses=sum(gain<-1e-9); k=min(wins,losses); trials=wins+losses; signP=1;
   if trials>0, signP=min(1,2*sum(arrayfun(@(j)nchoosek(trials,j),0:k))/2^trials); end
   if n>1 && lo>0, verdict='PI better (CI>0)'; elseif n>1 && hi<0, verdict='PI worse (CI<0)'; else, verdict='no clear difference'; end
   rows(end+1,:)={groups{g},policies{p},methods{m},n,mean(a),mean(b),mean(gain),lo,hi,wins,losses,signP, ...
    100*mean(gain./max(b,eps)),mean(eligible),verdict}; %#ok<AGROW>
  end
 end
end
S=cell2table(rows,'VariableNames',{'scenario','policy','comparator','fleets','PI_MAE_h','comparator_MAE_h', ...
 'meanGain_h','gain95Low_h','gain95High_h','PIwins','PIlosses','signTestP','meanGainPercent','comparatorEligibleFraction','verdict'});
writetable(S,fullfile(R.outputDir,'Assessment_summary.csv'));
% Plain-text digest for quick reading during the run.
f=fopen(fullfile(R.outputDir,'Assessment_summary.txt'),'w'); cleanup=onCleanup(@()fclose(f));
fprintf(f,'PI-DSSDM v17 running assessment | %s | %d/%d experiments complete\n',R.config.workflowMode,numel(R.experiments),R.plannedExperiments);
fprintf(f,'Gain = comparator MAE - PI-DSSDM MAE (h); positive favours PI-DSSDM. Fleet is the unit of inference.\n');
fprintf(f,'Intervals are unadjusted 95%% t intervals across fleets; descriptive, not confirmatory.\n\n');
A=S(strcmp(S.scenario,'ALL'),:);
for j=1:height(A)
 fprintf(f,'%-13s %-12s fleets %2d | PI %.2f vs %.2f h | gain %+6.2f h [%+.2f, %+.2f] | W/L %d/%d | sign p %.3f | %s\n', ...
  A.policy{j},A.comparator{j},A.fleets(j),A.PI_MAE_h(j),A.comparator_MAE_h(j),A.meanGain_h(j),A.gain95Low_h(j),A.gain95High_h(j), ...
  A.PIwins(j),A.PIlosses(j),A.signTestP(j),A.verdict{j});
end
if ismember('selectedFamily',R.predictions.Properties.VariableNames)
 P=R.predictions(strcmp(R.predictions.method,'PI_DSSDM'),:);
 if ~isempty(P)
  [fam,~,ix]=unique(strcat(P.policy,':',P.selectedFamily)); counts=accumarray(ix,1);
  fprintf(f,'\nPI-DSSDM applied family (forecast rows): ');
  for j=1:numel(fam), fprintf(f,'%s=%d  ',fam{j},counts(j)); end
  if ismember('processKappa_h',P.Properties.VariableNames), fprintf(f,'\nRows with kappa>0: %d/%d',sum(P.processKappa_h>0),height(P)); end
  fprintf(f,'\n');
 end
end
fprintf(f,'\nPer-scenario rows are in Assessment_summary.csv.\n');
end

function d=v17_scientific_config(c)
% FULL may change runtime/diagnostic settings, never a confirmed estimator.
omit={'seed','outputDir','dataFile','confirmationFile','workflowMode','label','maxRunSeconds', ...
    'makePlots','showFigures','figureResolution','enableProfiles','enableFullInformation', ...
    'maxDiagnosticUnits','profilePoints','profileIterations','numericalAuditPolicies','runtimeCandidateDir','runtimeFitLabel','activeGradientWorkers','parallelMode','startParallelPool','maxGradientWorkers'};
d=rmfield(c,intersect(omit,fieldnames(c)));
end

function G=v17_original_evidence_gate(R)
% Prespecified practical and uncertainty criteria, never a forced success.
c=R.config; rows=cell(0,4); confirming=ismember(c.workflowMode,{'confirm','full'});
rows(end+1,:)={'all_planned_fleets_completed',numel(R.experiments)==R.plannedExperiments,'Required','Incomplete fleets cannot establish the configured result.'};
rows(end+1,:)={'fresh_confirmation_profile',confirming,'Required','SCREEN and SMOKE are developmental, never GO for a full claim.'};
P=R.predictions; allAvailable=~isempty(P) && all(P.available);
rows(end+1,:)={'all_comparators_available',allAvailable,'Required','Actual LSTM and declared PF/physics/PINN comparators must be available.'};
for ss=1:numel(c.scenarios)
    scenario=c.scenarios{ss};
    for pp=1:numel(c.policies)
        policy=c.policies{pp}; z=startsWith(P.evidence,['SYNTHETIC:' scenario ':']) & strcmp(P.policy,policy); Q=P(z,:);
        if isempty(Q), continue; end
        for j=1:numel(c.gateComparators)
            name=c.gateComparators{j}; gains=[]; ratios=[];
            for e=unique(Q.experiment)'
                F=Q(Q.experiment==e,:); un=unique(F.unit); aa=[]; bb=[];
                for u=1:numel(un)
                    A=F(strcmp(F.unit,un{u}) & strcmp(F.method,'PI_DSSDM'),:);
                    B=F(strcmp(F.unit,un{u}) & strcmp(F.method,name),:);
                    if ~isempty(A) && ~isempty(B) && all(A.available) && all(B.available)
                        aa(end+1)=mean(abs(A.predictedRUL_h-A.trueRUL_h)); bb(end+1)=mean(abs(B.predictedRUL_h-B.trueRUL_h)); %#ok<AGROW>
                    end
                end
                if ~isempty(aa), gains(end+1)=mean(bb)-mean(aa); ratios(end+1)=mean(aa)/max(mean(bb),eps); end %#ok<AGROW>
            end
            enough=numel(gains)>=c.gateMinimumFleets; passed=false; lower=NaN;
            if numel(gains)>1
                multiplicity=numel(c.gateComparators)*numel(c.policies); alpha=(1-c.gateConfidence)/multiplicity; nu=numel(gains)-1;
                critical=sqrt(nu*(1/betaincinv(alpha,nu/2,.5)-1)); lower=mean(gains)-critical*std(gains)/sqrt(numel(gains));
            end
            if ismember(scenario,{'fatigue_discrepancy','fatigue_load_exponent'}), passed=enough && mean(ratios)<=1-c.gateMinimumGain && lower>0;
            else, passed=enough && mean(ratios)<=1+c.gateMatchedTolerance; end
            rows(end+1,:)={sprintf('%s_%s_vs_%s',scenario,policy,name),passed,'Predictive', ...
                sprintf('%d fleets, mean PI/base ratio %.4g, multiplicity-adjusted paired lower gain %.4g h',numel(gains),mean(ratios),lower)}; %#ok<AGROW>
        end
        A=Q(strcmp(Q.method,'PI_DSSDM'),:); late=A.lifeFraction>=.75;
        bias=mean(A.predictedRUL_h(late)-A.trueRUL_h(late));
        rows(end+1,:)={sprintf('%s_%s_late_bias',scenario,policy),any(late) && bias<=c.gateMaximumLateBias_h,'Bias',sprintf('Late-quarter mean optimistic bias %.4g h; limit %.4g h',bias,c.gateMaximumLateBias_h)};
        % Unit-simultaneous criterion uses the unit-max band when the primary
        % band is the origin-stratified (marginal) band.
        if ismember('lowerUnitMax_h',A.Properties.VariableNames), cover=A.trueRUL_h>=A.lowerUnitMax_h & A.trueRUL_h<=A.upperUnitMax_h;
        else, cover=A.trueRUL_h>=A.lower_h & A.trueRUL_h<=A.upper_h; end
        ids=strcat(string(A.experiment),'/',string(A.unit));
        uq=unique(ids); unitCover=false(numel(uq),1); for u=1:numel(uq), unitCover(u)=all(cover(ids==uq(u))); end
        ratio=mean(A.upper_h-A.lower_h)/mean(A.trueRUL_h);
        rows(end+1,:)={sprintf('%s_%s_band_precision',scenario,policy),mean(unitCover)>=c.gateMinimumUnitCoverage && ratio<=c.gateMaximumWidthToRUL,'Uncertainty',sprintf('Unit coverage %.4g; mean width / mean RUL %.4g',mean(unitCover),ratio)};
    end
end
converged=true;
for e=1:numel(R.experiments)
    O=R.experiments{e}.optimizerAudit; ix=ismember(O.method,{'PI_DSSDM','Inverse_PINN','Physics_SSM','Basis_hybrid'});
    strict=O.exitflag(ix)==1 & O.postEmissionGradientNorm(ix)<c.gradientTolerance;
    limited=O.exitflag(ix)==2 & O.postEmissionGradientNorm(ix)<v17_stationarity_tolerance(c);
    converged=converged && all(strict | limited);
end
rows(end+1,:)={'final_saved_objective_convergence',converged,'Estimation','All fitted mechanistic checkpoints meet the stated criterion: exitflag 1 at gradientTolerance, or declared resolution-limited exitflag 2.'};
T=cell2table(rows,'VariableNames',{'criterion','passed','category','detail'});
decision='HOLD'; if all(T.passed), decision='GO'; elseif ~confirming, decision='DEVELOPMENT_ONLY'; end
G=struct('decision',decision,'table',T,'note','No physical validity or journal acceptance is implied by GO. Full uses fresh seed family again.');
end

function T=v17_selftests(c)
names={}; cc=c; cc.profileObserved=true; cc.profileQuadraticEmission=false;
cc.trainUnits=3; cc.validationUnits=2; cc.calibrationUnits=10; cc.testUnits=2;
cc.coarseEtaPoints=41; cc.etaGridPoints=81; cc.exactPlanned=true;
U=generate_fleet(cc,'fatigue_matched',91831); train=strip_truth(U(1:3));
M=initial_model(train,cc); M.useB=true; M.baselineFixed=false; M.C(:,7)=0;
[loss,MM,d]=v17_profile_emission(M,train,cc); assert(isfinite(loss) && d.normalEquationResidual<1e-7);
names{end+1}='profiled GLS solves its conditional normal equations';
% Compare the OU innovation likelihood against a dense Gaussian calculation.
H=causal_prefix(U(4),8); D=observed_trajectory(M,H,0,cc); [nll,~]=observed_kalman(M,H,D,cc);
X=emission_features(D,zeros(size(D)),H.u); residual=H.y-X*M.C';
K=numel(H.t); covariance=kron(M.sigmaB^2*exp(-abs(H.t-H.t')/M.tau),M.C(:,3)*M.C(:,3)')+kron(eye(K),diag(M.sensorSD.^2));
v=reshape(residual',[],1); L=chol(covariance,'lower'); dense=.5*(sum((L\v).^2)+2*sum(log(diag(L)))+numel(v)*log(2*pi));
assert(abs(nll-dense)<1e-7); names{end+1}='conditional Gaussian OU likelihood agrees with dense covariance';
% The profiled C is a minimizer of that likelihood plus the declared ridge.
epsC=MM; epsC.C(1,2)=epsC.C(1,2)+.02;
assert(v17_fixed_profile_objective(MM,train,cc)<=v17_fixed_profile_objective(epsC,train,cc)+1e-8);
names{end+1}='profiled emission improves the same penalized observation objective';
for index=[1 4 10 16]
    if index>numel(MM.C), continue; end
    if mod(index-1,size(MM.C,1))+1==0, continue; end
    plus=MM; minus=MM; plus.C(index)=plus.C(index)+1e-6; minus.C(index)=minus.C(index)-1e-6;
    if ismember(index,[7 8 9 19 20 21]), continue; end
    derivative=(v17_fixed_profile_objective(plus,train,cc)-v17_fixed_profile_objective(minus,train,cc))/2e-6;
    assert(abs(derivative)<1e-4);
end
names{end+1}='GLS profile is stationary in the original Kalman observation objective';
Q=fit_duty_model(train); H=causal_prefix(U(4),10); rng(12); bank=future_bank(H,'probabilistic',Q,cc,20);
assert(all(reshape(bank.u(1,:,:),20,3)==repmat(H.u(end,:),20,1),'all'));
names{end+1}='probabilistic duty retains known current input in first held interval';
v17_score_bank('reset'); rng(14); a=v17_score_bank(H,'probabilistic',Q,cc,20,1); rng(99); b=v17_score_bank(H,'probabilistic',Q,cc,20,1);
assert(isequal(a,b)); names{end+1}='validation duty bank cache returns identical declared paths';
P=v17_grid_prefix(M,H,cc); assert(abs(sum(P.weights)-1)<1e-12 && all(diff(P.eta)>0));
names{end+1}='adaptive quadrature normalizes surviving posterior mass';
fake=M; fake.useB=false; fake.sigmaB=0; fake.C(:,3)=0; fake.sensorSD(:)=.001;
FH=H; FD=observed_trajectory(fake,FH,.075,cc); FH.y=emission_features(FD,zeros(size(FD)),FH.u)*fake.C';
cs=cc; cs.coarseEtaPoints=21; cs.etaGridPoints=401; FP=v17_grid_prefix(fake,FH,cs);
assert(abs(FP.weights'*FP.eta-.075)<.005);
names{end+1}='adaptive support retains a sharp posterior between coarse grid nodes';
HH=H; HH.y(end,:)=HH.y(end,:)+10; PP=v17_grid_prefix(M,HH,cc);
assert(isequal(P.filteredMean(1:end-1,:),PP.filteredMean(1:end-1,:)));
names{end+1}='origin-adaptive posterior does not revise earlier filtered summaries';
bank=future_bank(H,'planned',Q,cc,20); [a,ia]=model_samples(M,H,P,bank,cc); rng(1234); [b,ib]=model_samples(M,H,P,bank,cc);
assert(isequal(a,b) && v17_quantile(a,ia,.5)==v17_quantile(b,ib,.5));
names{end+1}='planned weighted first-passage distribution has no resampling noise';
PF=M; PF.kind='smc'; cc.particles=250; rng(42); S=v17_smc_prefix(PF,H,cc);
assert(abs(sum(S.weights)-1)<1e-10 && all(S.eventMass>=0 & S.eventMass<=1+1e-10));
assert(abs(S.weights'*S.eta-P.weights'*P.eta)<.08);
names{end+1}='genuine sequential PF normalizes mass and approximates grid eta inference';
% Vector-valued forecast scale must preserve independent unit-max calibration.
qtab=table({'A';'B'},{'planned';'planned'},[0;0],[.1;.2],[2;2], ...
    'VariableNames',{'method','policy','intercept','inverseSqrtRUL','validationForecasts'});
cc.calibrationScales=qtab;
cal=table(repmat({'A'},10,1),repmat({'planned'},10,1),arrayfun(@(k)sprintf('u%d',k),(1:10)','UniformOutput',false), ...
    (10:19)',(11:20)',ones(10,1),'VariableNames',{'method','policy','unit','trueRUL_h','predictedRUL_h','available'});
tt=cal(1:2,:); [tt,ct]=calibrate_bands(cal,tt,cc);
assert(all(tt.lower_h<=tt.upper_h) && ct.independentCalibrationUnits==10 && all(isfinite(tt.upper_h)));
names{end+1}='VAL-scaled CAL bands support vector scales and independent unit ranks';
T=table(names',true(numel(names),1),'VariableNames',{'test','passed'});
end

function f=v17_fixed_profile_objective(M,train,c)
f=0;
for i=1:numel(train), D=observed_trajectory(M,train(i),M.trainingEta(i),c); f=f+observed_kalman(M,train(i),D,c); end
W=ones(size(M.C)); W(:,1)=1e-6; W(:,3)=0; W(:,7)=c.quadraticEmissionRidgeMultiplier;
f=f+.5*c.emissionRidge*sum(W.*M.C.^2,'all');
end

function value=v17_unit_mean(x,ids)
names=unique(ids); averages=nan(numel(names),1);
for i=1:numel(names), averages(i)=mean(x(strcmp(ids,names{i})),'omitnan'); end
value=mean(averages,'omitnan');
end

function [lo,hi]=v17_initial_log_band(P,c)
pred=P.predictedRUL_h; lo=pred; hi=pred;
if ismember('rawLower_h',P.Properties.VariableNames)
    valid=~isnan(P.rawLower_h)&~isnan(P.rawUpper_h); lo(valid)=min(P.rawLower_h(valid),pred(valid)); hi(valid)=max(P.rawUpper_h(valid),pred(valid));
end
lo=log(max(0,lo)+c.relativeFloorHours); hi=log(max(0,hi)+c.relativeFloorHours);
censored=isinf(pred); lo(censored)=log(c.relativeFloorHours); hi(censored)=Inf;
end

function [loss,M,diagnostic]=v17_profile_emission(M,train,c)
% Exact Gaussian variable projection, not a surrogate training objective.
% Covariance is independent of D and mean coefficients. Reuse its Cholesky
% whitening for finite differences that change only damage or NN parameters.
if ~c.fastProfile || any(arrayfun(@(U)sum(isfinite(U.y(:)))>c.fastDenseMaxObs,train))
    [loss,M,diagnostic]=v17_profile_emission_reference(M,train,c); return;
end
p=size(M.C,1); mask=true(p,7); mask(:,3)=false;
if ~c.profileQuadraticEmission, mask(:,7)=false; M.C(:,7)=0; end
if M.baselineFixed, mask(:,[1 4 5 6])=false; end
idx=find(mask); fixed=M.C; fixed(idx)=0; nf=numel(idx);
context=v17_data_signature(train,c); key=[M.tau M.sigmaB M.sensorSD M.C(:,3)' fixed(:)' double(mask(:)')];
cache=v17_fast_cache('get',context,key);
if isempty(cache)
    cache=cell(numel(train),1);
    for i=1:numel(train)
        U=train(i); K=numel(U.t); yy=reshape(U.y',[],1); ok=isfinite(yy);
        timeIndex=repelem((1:K)',p); channel=repmat((1:p)',K,1);
        timeIndex=timeIndex(ok); channel=channel(ok); t=U.t(timeIndex);
        b=M.C(channel,3); variance=M.sigmaB^2*exp(-abs(t-t')/M.tau).*(b*b');
        variance=variance+diag(M.sensorSD(channel).^2);
        if isempty(t), W=zeros(0); logdet=0;
        else, LL=chol(variance,'lower'); W=LL\eye(numel(t)); logdet=2*sum(log(diag(LL))); end
        X=emission_features(zeros(K,1),zeros(K,1),U.u);
        design=kron(X,eye(p)); design=design(ok,idx);
        mu=reshape((X*fixed')',[],1); y=W*(yy(ok)-mu(ok));
        cache{i}=struct('W',W,'A0',W*design,'y',y,'logdet',logdet, ...
            'timeIndex',timeIndex,'channel',channel,'n',sum(ok));
    end
    v17_fast_cache('put',context,key,cache,c.profileCacheMB);
end
[Dall,Qall]=v17_training_trajectories(M,train,c);
G=zeros(nf); rhs=zeros(nf,1); yy=0; logdet=0; count=0; event=0; ode=[];
for i=1:numel(train)
    U=train(i); D=Dall{i}; C=cache{i}; A=C.A0;
    for channel=1:p
        rr=find(C.channel==channel); d=D(C.timeIndex(rr));
        col=find(idx==sub2ind([p 7],channel,2));
        if ~isempty(col), A(:,col)=C.W(:,rr)*d; end
        col=find(idx==sub2ind([p 7],channel,7));
        if ~isempty(col), A(:,col)=C.W(:,rr)*(d.^2); end
    end
    G=G+A'*A; rhs=rhs+A'*C.y; yy=yy+C.y'*C.y; logdet=logdet+C.logdet; count=count+C.n;
    ins=isfinite(U.inspection); event=event+.5*sum(((D(ins)-U.inspection(ins))/c.inspectionSD).^2); count=count+sum(ins);
    if U.failureObserved
        event=event+.5*((D(end)-c.Dcrit)/c.terminalDamageTolerance)^2+ ...
            5*sum((max(D(1:end-1)-c.Dcrit,0)/c.terminalDamageTolerance).^2); count=count+1;
    end
    if strcmp(M.kind,'pinn')
        q=Qall{i};
        target=physics_rate(M,U.u).*exp(M.trainingEta(i)).*(1+M.a*D);
        ode=[ode;log(max(q,realmin)./max(target,realmin))]; %#ok<AGROW>
    end
end
weights=ones(p,7); weights(:,1)=1e-6; weights(:,7)=c.quadraticEmissionRidgeMultiplier; penalty=c.emissionRidge*diag(weights(idx));
coef=(G+penalty+1e-12*eye(nf))\rhs; M.C(idx)=coef;
data=.5*(yy-2*coef'*rhs+coef'*(G+penalty)*coef+logdet+count*log(2*pi))+event;
n=numel(train); eta=M.trainingEta;
prior=.5*(log(M.k/c.nominalRate)/c.rateLogPriorSD)^2+ ...
    .5*((M.p-c.nominalLoadExponent)/c.exponentPriorSD)^2+.5*((M.betaT-c.nominalTempCoefficient)/c.tempPriorSD)^2+ ...
    .5*sum((eta/M.unitSD).^2)+(n-1)*log(M.unitSD/c.unitSD)+ ...
    .5*(log(M.unitSD/c.unitSD)/c.unitHyperLogSD)^2+ ...
    .5*sum((log(M.sensorSD/c.sensorSD)/c.measurementLogPriorSD).^2);
barrier=100*sum(max(abs(eta)-c.unitEffectMax,0).^2);
loss=(data+prior)/max(count,1)+barrier;
if strcmp(M.kind,'pinn')
    loss=loss+c.pinnPhysicsWeight*mean(ode.^2)+c.networkPenalty*sum(pack_network(M.pinnNN).^2);
elseif M.bound>0
    ref=M.reference; rho=discrepancy(M,ref.D,zeros(size(ref.D)),ref.u); um=accumarray(ref.unit,rho,[],@mean);
    loss=loss+c.residualPenalty*mean(rho.^2)+c.unitResidualPenalty*mean(um.^2)+c.networkPenalty*sum(pack_network(M.nn).^2);
end
diagnostic=struct('normalEquationResidual',norm((G+penalty)*coef-rhs,Inf),'observations',count,'GLSdataObjective',data);
end

function key=v17_data_signature(train,c)
% A fit receives a hash once. Tests and independent calls hash their data.
if isfield(c,'profileDataSignature') && ~isempty(c.profileDataSignature), key=c.profileDataSignature; return; end
key=v17_hash_text(jsonencode(train));
end

function value=v17_fast_cache(action,varargin)
persistent entries totalBytes
if isempty(entries), entries={}; totalBytes=0; end
value=[];
if strcmp(action,'reset'), entries={}; totalBytes=0; return; end
context=varargin{1}; key=varargin{2};
if strcmp(action,'get')
    for i=numel(entries):-1:1
        if strcmp(entries{i}.context,context) && isequal(entries{i}.key,key)
            value=entries{i}.value; item=entries{i}; entries(i)=[]; entries{end+1}=item; return;
        end
    end
else
    value=varargin{3}; info=whos('value'); bytes=info.bytes; budget=varargin{4}*1024^2;
    while ~isempty(entries) && totalBytes+bytes>budget
        totalBytes=totalBytes-entries{1}.bytes; entries(1)=[];
    end
    if bytes<=budget
        entries{end+1}=struct('context',context,'key',key,'value',{value},'bytes',bytes); totalBytes=totalBytes+bytes;
    end
end
end

function [Dall,Qall]=v17_training_trajectories(M,train,c)
% Cache by physical/neural dynamics, then update only units whose centered
% frailty changes. Covariance-only finite differences reuse all trajectories.
persistent entries
if isempty(entries),entries={};end
if strcmp(M.kind,'pinn'),nn=pack_network(M.pinnNN);else,nn=pack_network(M.nn);end
key=[double(M.kind) M.k M.p M.betaT M.a M.bound nn' c.transitionStepHours c.nominalRate c.nominalLoadExponent c.nominalTempCoefficient];
if M.bound>0,key=[key M.projection.A(:)' M.projection.sup];end
context=v17_data_signature(train,c);found=0;
if c.cacheTrajectories
 for j=1:numel(entries)
  if strcmp(entries{j}.context,context) && isequaln(entries{j}.key,key),found=j;break;end
 end
end
n=numel(train);
if found>0
 item=entries{found};Dall=item.Dall;Eall=item.Eall;Qall=item.Qall;oldEta=item.eta;entries(found)=[];
else,Dall=cell(n,1);Eall=cell(n,1);Qall=cell(n,1);oldEta=nan(n,1);end
changed=find(oldEta~=M.trainingEta);K=arrayfun(@(U)numel(U.t),train);
for i=changed'
 Dall{i}=zeros(K(i),1)+train(i).initialD;Eall{i}=zeros(K(i),1);Qall{i}=zeros(K(i),1);
end
% All independent units at a given observation index share matrix operations,
% while retaining their own timestamps, operating inputs and substep counts.
for k=1:max(K(changed),[],'omitnan')
 ids=changed(K(changed)>=k);if isempty(ids),continue;end
 if k>1
  h=zeros(numel(ids),1);ns=h;d=h;ex=h;tt=h;u=zeros(numel(ids),3);
  for j=1:numel(ids)
   i=ids(j);dt=train(i).t(k)-train(i).t(k-1);ns(j)=max(1,ceil(dt/c.transitionStepHours));h(j)=dt/ns(j);
   d(j)=Dall{i}(k-1);ex(j)=Eall{i}(k-1);tt(j)=train(i).t(k-1);u(j,:)=train(i).u(k-1,:);
  end
  eta=M.trainingEta(ids);base=physics_rate(M,u).*exp(eta);
  for step=1:max(ns)
   a=find(step<=ns);ha=h(a);ua=u(a,:);ea=eta(a);
   if strcmp(M.kind,'pinn')
    time=tt(a)+(step-1)*ha;[~,er]=pinn_rate(M,ex(a),time,ua,ea,c);
    rate=pinn_rate(M,ex(a)+.5*ha.*er,time+.5*ha,ua,ea,c);
    d(a)=d(a)+ha.*rate;ex(a)=ex(a)+ha.*er;
   else
    rate=base(a).*exp(discrepancy(M,d(a),zeros(size(a)),ua)).*(1+M.a*d(a));
    mid=d(a)+.5*ha.*rate;
    rate=base(a).*exp(discrepancy(M,mid,zeros(size(a)),ua)).*(1+M.a*mid);
    d(a)=d(a)+ha.*rate;
   end
  end
  for j=1:numel(ids),i=ids(j);Dall{i}(k)=d(j);Eall{i}(k)=ex(j);end
 end
 if strcmp(M.kind,'pinn')
  e=zeros(numel(ids),1);time=e;u=zeros(numel(ids),3);
  for j=1:numel(ids),i=ids(j);e(j)=Eall{i}(k);time(j)=train(i).t(k);u(j,:)=train(i).u(k,:);end
  q=pinn_rate(M,e,time,u,M.trainingEta(ids),c);
  for j=1:numel(ids),Qall{ids(j)}(k)=q(j);end
 end
end
if c.cacheTrajectories
 entries{end+1}=struct('context',context,'key',key,'eta',M.trainingEta,'Dall',{Dall},'Eall',{Eall},'Qall',{Qall});
 while numel(entries)>c.trajectoryCacheEntries,entries(1)=[];end
end
end

function hash=v17_hash_text(text)
md=java.security.MessageDigest.getInstance('SHA-256'); md.update(unicode2native(text,'UTF-8'));
hash=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2)',1,[]));
end

function c=v17_parallel_setup(c)
% Explicit gradient parallelism, optional. Base MATLAB remains supported.
c.activeGradientWorkers=0;
if strcmp(c.parallelMode,'off') || ~license('test','Distrib_Computing_Toolbox'), return; end
pool=gcp('nocreate');
if isempty(pool) && c.startParallelPool
    try
        % 17.2: no idle shutdown during long serial stages of a day-long run.
        try, pool=parpool('Processes',c.maxGradientWorkers,'IdleTimeout',Inf);
        catch, pool=parpool('Processes',c.maxGradientWorkers); end
    catch err, fprintf('Parallel startup unavailable: %s. Continuing serially.\n',err.message); return; end
end
if ~isempty(pool), c.activeGradientWorkers=min(pool.NumWorkers,c.maxGradientWorkers); end
end

function c=v17_restart_pool(c)
try,delete(gcp('nocreate'));catch,end
c.startParallelPool=true;c=v17_parallel_setup(c);
end

function v17_log_experiment_error(runDir,e,label,err)
path=fullfile(runDir,'Experiment_errors.csv');
row=table(e,{label},{datestr(now,'yyyy-mm-dd HH:MM:SS')},{err.identifier},{err.message}, ...
 'VariableNames',{'experiment','evidence','time','identifier','message'});
if isfile(path),row=[readtable(path,'TextType','char','Delimiter',',');row];end %#ok<AGROW>
writetable(row,path);
end

function [g,evaluations]=v17_fd_gradient(fun,x,c)
% Central interior and SECOND-ORDER one-sided boundary differences. Objective
% calls remain feasible. No smooth map can suppress a physical log-gradient.
n=numel(x);[lo,hi]=v17_optimizer_bounds(c,n);g=zeros(n,1);counts=zeros(n,1);
scale=1;if isfield(c,'fdStepScale') && ~isempty(c.fdStepScale),scale=c.fdStepScale;end
if c.activeGradientWorkers>0 && n>=c.parallelMinimumParameters
 if isempty(gcp('nocreate')),parpool('Processes',c.activeGradientWorkers);end
 parfor (j=1:n,c.activeGradientWorkers),[g(j),counts(j)]=v17_coordinate_gradient(fun,x,j,lo(j),hi(j),scale);end
else
 for j=1:n,[g(j),counts(j)]=v17_coordinate_gradient(fun,x,j,lo(j),hi(j),scale);end
end
evaluations=sum(counts);
end

function [x,f,out]=v17_bfgs(fun,x,steps,c,path)
% Projected BFGS in explicit meaningful coordinates. Armijo uses the ACTUAL
% feasible displacement. At a box optimum only outward gradients may remain.
if nargin<5,path='';end
[lo,hi]=v17_optimizer_bounds(c,numel(x));assert(all(x>=lo & x<=hi),'pi17:bounds','Infeasible starting point');
initial=x;started=tic;previousSeconds=0;lastSaved=tic;stallRescues=0;stallMark=0;
if ~isempty(path) && exist(path,'file')==2
 S=load(path,'state');state=S.state;
 assert(isequaln(state.initial,initial) && state.steps==steps,'pi17:checkpoint','Candidate context changed');
 if state.finished,x=state.x;f=state.f;out=state.output;return;end
 x=state.x;f=state.f;g=state.g;H=state.H;trace=state.trace;it=state.iteration;evaluations=state.evaluations;previousSeconds=state.elapsedSeconds;
 if isfield(state,'stallRescues'),stallRescues=state.stallRescues;stallMark=state.stallMark;end
 fprintf('  Continue optimizer %s at accepted iteration %d.\n',state.label,it);
else
 v17_deadline('check');f=fun(x);
 if isfield(c,'initialBFGS') && isequaln(c.initialBFGS.x,x)
  g=c.initialBFGS.g;H=c.initialBFGS.H;evaluations=1;
 else
  [g,ne]=v17_fd_gradient(fun,x,c);evaluations=1+ne;H=eye(numel(x));
  if c.optimizerInitialScale,H=diag(min(c.maximumInitialInverseScale,max(1,1./sqrt(abs(g)+1e-4))));end
 end
 trace=zeros(0,3);it=0;state=struct('initial',initial,'steps',steps,'label',c.runtimeFitLabel);
end
flag=0;refreshed=false;refreshes=0;
while it<steps
 pg=x-v17_project_parameters(x-g,c);
 state.stallRescues=stallRescues;state.stallMark=stallMark;
 if v17_deadline('expired')
  v17_write_optimizer(path,state,x,f,g,H,trace,it,evaluations,previousSeconds+toc(started),false,struct());
  error('pi17:budget','Invocation time budget reached. Current candidate optimizer state saved.');
 end
 if norm(pg,Inf)<c.gradientTolerance,flag=1;break;end
 active=(x<=lo+1e-12 & g>0)|(x>=hi-1e-12 & g<0);
 direction=-H*g;direction(active)=0;onFace=false;
 if v17_flag(c,'l1FaceDirection')
  % 17.1.2: on an active L1 face the quasi-Newton step mostly points out of
  % the ball, the projection cancels it and Armijo accepts a negligible
  % tangential move (the SCREEN 17.1.1 stalls). Restrict it to the face.
  [direction,onFace]=v17_l1_face_direction(direction,x,c);direction(active)=0;
 end
 if g'*direction>=0 || any(~isfinite(direction)),H=eye(numel(x));direction=-pg;
 elseif onFace && norm(direction,Inf)<c.faceDirectionFraction*norm(pg,Inf),direction=-pg;end
 accepted=false;
 for retry=0:1
  if retry==1,H=eye(numel(x));direction=-pg;end
  if norm(direction)>2,direction=direction*2/norm(direction);end
  alpha=1;
  for ls=1:24
   candidate=v17_project_parameters(x+alpha*direction,c);dx=candidate-x;
   if norm(dx,Inf)<1e-14,alpha=alpha/2;continue;end
   nf=fun(candidate);evaluations=evaluations+1;
   if isfinite(nf) && g'*dx<0 && nf<=f+1e-4*(g'*dx),accepted=true;break;end
   alpha=alpha/2;
  end
  if accepted,break;end
 end
 if ~accepted && v17_flag(c,'lineSearchGradientRefresh') && ~refreshed
  % v17: a failed Armijo search is first treated as a possibly inaccurate
  % gradient. Recompute it once with a smaller difference step and retry
  % steepest descent before declaring a line-search stop.
  cr=c;cr.fdStepScale=c.refreshGradientStepFactor;[g,ne]=v17_fd_gradient(fun,x,cr);evaluations=evaluations+ne;
  H=eye(numel(x));refreshed=true;refreshes=refreshes+1;continue;
 end
 if ~accepted,flag=-2;break;end
 refreshed=false;
 [ng,ne]=v17_fd_gradient(fun,candidate,c);evaluations=evaluations+ne;dx=candidate-x;dg=ng-g;curvature=dx'*dg;
 if curvature>1e-10*norm(dx)*max(norm(dg),eps)
  V=eye(numel(x))-dx*dg'/curvature;H=V*H*V'+dx*dx'/curvature;
 else,H=eye(numel(x));end
 x=candidate;f=nf;g=ng;it=it+1;pg=x-v17_project_parameters(x-g,c);trace(end+1,:)=[f norm(pg,Inf) alpha]; %#ok<AGROW>
 if mod(it,c.progressEveryIterations)==0 || it==1
  fprintf('  %-32s iter %4d/%d TRAIN %.7g feasible-grad %.4g elapsed %.1f s\n',c.runtimeFitLabel,it,steps,f,norm(pg,Inf),previousSeconds+toc(started));
 end
 if v17_flag(c,'earlyStallStop') && norm(pg,Inf)>=c.gradientTolerance && size(trace,1)-stallMark>c.stallStopWindow && ...
   trace(end-c.stallStopWindow,1)-f<=c.stallStopRelativeTolerance*max(1,abs(f))
  % 17.1.2: the objective has stopped moving although the gradient test is
  % unmet. Reset the curvature once; if it stalls again, stop instead of
  % spending the rest of the budget (exitflag -3, never converged by itself).
  if stallRescues<c.stallRescueLimit
   H=eye(numel(x));stallRescues=stallRescues+1;stallMark=size(trace,1);
   fprintf('  %-32s objective stalled at iter %d; curvature reset %d/%d.\n',c.runtimeFitLabel,it,stallRescues,c.stallRescueLimit);
  else,flag=-3;break;end
 end
 state.stallRescues=stallRescues;state.stallMark=stallMark;
 if mod(it,c.checkpointEveryIterations)==0 || toc(lastSaved)>=c.checkpointEverySeconds
  v17_write_optimizer(path,state,x,f,g,H,trace,it,evaluations,previousSeconds+toc(started),false,struct());lastSaved=tic;
 end
end
state.stallRescues=stallRescues;state.stallMark=stallMark;
pg=x-v17_project_parameters(x-g,c);if norm(pg,Inf)<c.gradientTolerance,flag=1;end
rawFlag=flag;
if flag<=0 && v17_flag(c,'acceptResolutionLimited') && norm(pg,Inf)<c.resolutionGradientTolerance
 % Resolution-limited stationarity (exitflag 2), reported separately from
 % exitflag 1. Line-search stop: no descent even after the refreshed
 % gradient. Budget stop: the last stallWindow accepted iterations reduced
 % the objective by less than stallRelativeTolerance*max(1,|f|).
 stalled=false;
 if flag==-2 || flag==-3,stalled=true;
 elseif size(trace,1)>=c.stallWindow,stalled=trace(end-c.stallWindow+1,1)-f<=c.stallRelativeTolerance*max(1,abs(f));end
 if stalled,flag=2;end
end
out=struct('exitflag',flag,'iterations',it,'gradientNorm',norm(pg,Inf),'rawGradientNorm',norm(g,Inf), ...
 'trace',trace,'functionEvaluations',evaluations,'elapsedSeconds',previousSeconds+toc(started), ...
 'converged',flag==1 || flag==2,'gradientWorkers',c.activeGradientWorkers, ...
 'finalVector',x,'finalGradient',g,'projectedGradient',pg,'inverseHessian',H,'lowerBounds',lo,'upperBounds',hi);
out.status='iteration_budget_exhausted';if flag==1,out.status='feasible_gradient_tolerance_met';elseif flag==2,out.status='stationary_within_numerical_resolution';elseif flag==-3,out.status='objective_stalled';elseif flag<0,out.status='line_search_stopped';end
out.rawExitflag=rawFlag;out.gradientRefreshes=refreshes;out.stallRescues=stallRescues;
out.boundaryCoordinates=find(abs(x-lo)<1e-8 | abs(x-hi)<1e-8);
if isfield(c,'optimizerL1Indices') && ~isempty(c.optimizerL1Indices)
 % The L1 face is a constraint boundary too; v16 omitted it from this list.
 out.l1ConstraintActive=abs(sum(abs(x(c.optimizerL1Indices)))-c.optimizerL1Radius)<1e-8;
else,out.l1ConstraintActive=false;end
v17_write_optimizer(path,state,x,f,g,H,trace,it,evaluations,out.elapsedSeconds,true,out);
end

function [index,hasConverged]=v17_select_checkpoint(scores,optimizers,c)
ok=cellfun(@(O)v17_converged(O,c),optimizers); hasConverged=any(ok); eligible=isfinite(scores);
if c.requireConvergedSelection && hasConverged, eligible=eligible & ok; end
values=scores; values(~eligible)=Inf; [~,index]=min(values);
end

function v17_write_optimizer(path,state,x,f,g,H,trace,it,evaluations,seconds,finished,output)
if isempty(path), return; end
state.x=x; state.f=f; state.g=g; state.H=H; state.trace=trace; state.iteration=it;
state.evaluations=evaluations; state.elapsedSeconds=seconds; state.finished=finished; state.output=output;
v17_save(path,struct('state',state));
end

function path=v17_candidate_path(c,tag)
path=''; if isfield(c,'runtimeCandidateDir') && ~isempty(c.runtimeCandidateDir)
    if ~exist(c.runtimeCandidateDir,'dir'), mkdir(c.runtimeCandidateDir); end
    path=fullfile(c.runtimeCandidateDir,[tag '.mat']);
end
end

function code=v17_scenario_code(name)
known={'fatigue_matched','fatigue_discrepancy','fatigue_weak_gap','fatigue_emission_mismatch','fatigue_combined_mismatch'};
code=find(strcmp(name,known));if isempty(code),code=100+sum(double(name).*(1:numel(name)));end
end

function v17_rng_stage(c,e,tag)
rng(mod(c.seed+e*19001+sum(double(tag).*(1:numel(tag)))*37,2^32-1),'twister');
end

function yes=v17_converged(opt,c)
yes=isfield(opt,'exitflag') && opt.exitflag>0 && isfield(opt,'gradientNorm') && opt.gradientNorm<c.gradientTolerance;
if ~yes && v17_flag(c,'acceptResolutionLimited') && isfield(opt,'exitflag') && opt.exitflag==2
 yes=isfield(opt,'gradientNorm') && opt.gradientNorm<c.resolutionGradientTolerance;
end
end

function tol=v17_stationarity_tolerance(c)
tol=c.gradientTolerance;if v17_flag(c,'acceptResolutionLimited'),tol=c.resolutionGradientTolerance;end
end

function T=v17_late_metrics(P,c)
rows=cell(0,11);
for method=unique(P.method)'
    for policy=unique(P.policy)'
        for horizon=c.lateRULThresholds
            Q=P(strcmp(P.method,method{1}) & strcmp(P.policy,policy{1}) & P.trueRUL_h<=horizon & P.available,:);
            n=height(Q); units=numel(unique(Q.unit)); err=Q.predictedRUL_h-Q.trueRUL_h;
            cover=Q.trueRUL_h>=Q.lower_h & Q.trueRUL_h<=Q.upper_h;
            rows(end+1,:)={method{1},policy{1},horizon,n,units,mean(abs(err)),sqrt(mean(err.^2)),mean(err), ...
                mean(abs(err)./max(Q.trueRUL_h,c.relativeFloorHours)),mean(cover),mean(Q.upper_h-Q.lower_h)}; %#ok<AGROW>
        end
    end
end
T=cell2table(rows,'VariableNames',{'method','policy','trueRULAtMost_h','forecasts','independentUnits','MAE_h','RMSE_h','bias_h','MARE','coverage','meanWidth_h'});
end

function v17_extra_reporting(E,c,e,outDir)
fprintf('\nLATE-LIFE DIAGNOSTICS, group by true RUL for evaluation only:\n'); disp(E.lateMetrics);
fprintf('Raw-to-calibrated interval nesting violations: %d.\n',E.intervalNestingViolations);
files=dir(fullfile(c.runtimeCandidateDir,'*.mat')); work=cell(0,5);
for i=1:numel(files)
    candidateFile=fullfile(files(i).folder,files(i).name);
    savedVariables=whos('-file',candidateFile);
    if ~any(strcmp({savedVariables.name},'state')), continue; end
    S=load(candidateFile,'state');
    if ~isfield(S,'state'), continue; end
    flag=NaN; if S.state.finished, flag=S.state.output.exitflag; end
    work(end+1,:)={files(i).name,S.state.elapsedSeconds,S.state.iteration,S.state.finished,flag}; %#ok<AGROW>
end
work=cell2table(work,'VariableNames',{'candidate','cumulativeOptimizationSeconds','acceptedIterations','finishedDeclaredBudget','exitflag'});
writetable(work,fullfile(outDir,sprintf('Candidate_optimization_work_%02d.csv',e)));
writetable(E.lateMetrics,fullfile(outDir,sprintf('Late_RUL_metrics_%02d.csv',e)));
P=E.models{4}; writetable(P.fitTrace,fullfile(outDir,sprintf('Population_checkpoint_selection_%02d.csv',e)));
fprintf('Population selected iteration %d; validation-best iteration %d; selected converged=%d.\n', ...
    P.selectedIteration,P.validationBestIteration,v17_converged(P.selectedMStep,c));
if ~c.makePlots, return; end
f=new_figure(c,sprintf('E%d RUL sensitivity and interval precision',e)); tiledlayout(2,2,'TileSpacing','compact');
Q=E.predictions(strcmp(E.predictions.method,'PI_DSSDM'),:); palette=lines(numel(c.policies));
nexttile; hold on;
for j=1:numel(c.policies), A=Q(strcmp(Q.policy,c.policies{j}),:); scatter(A.trueRUL_h,A.predictedRUL_h-A.trueRUL_h,25,palette(j,:),'filled'); end
yline(0,'k:'); xline(24,'k--'); xlabel('True RUL h, evaluation only'); ylabel('Signed RUL error h'); grid on; legend(c.policies,'Location','best');
nexttile; hold on;
for j=1:numel(c.policies), A=Q(strcmp(Q.policy,c.policies{j}),:); scatter(A.predictedRUL_h,A.upper_h-A.lower_h,25,palette(j,:),'filled'); end
xlabel('Predicted RUL h'); ylabel('Calibrated width h'); grid on;
nexttile; O=E.optimizerAudit; good=isfinite(O.postEmissionGradientNorm); semilogy(find(good),max(O.postEmissionGradientNorm(good),eps),'o'); hold on;
yline(c.gradientTolerance,'r:'); xticks(1:height(O)); xticklabels(O.method); xtickangle(25); ylabel('Selected objective gradient'); grid on;
nexttile; S=E.stateOriginAudit;
if isempty(S), text(.1,.5,'No independent synthetic D truth'); axis off;
else, scatter(max(c.Dcrit-S.trueD,eps),abs(S.errorD),25,'filled'); hold on;
    lim=max(c.Dcrit-S.trueD); plot([0 lim],[0 lim],'k:'); xlabel('True remaining damage margin'); ylabel('Absolute D error'); grid on; end
sgtitle([E.evidence ' | evaluation diagnostics'],'Interpreter','none'); save_plot(f,outDir,sprintf('E%02d_Late_RUL_and_precision',e),c);
end

function [predictions,filters,ablation]=v17_predict_cached(units,ids,models,methods,Q,c,e,evidence,diagnose,tag)
% Unit-level forecast persistence. Reusing a CAL/TEST forecast never changes
% its prefix seed, future-duty bank, model, or information setting.
predictions=table(); filters=table(); ablation=table();
dir=fullfile(c.runtimeCandidateDir,'forecasts'); if ~exist(dir,'dir'), mkdir(dir); end
paths=arrayfun(@(id)fullfile(dir,sprintf('%s_unit%04d.mat',tag,id)),ids,'UniformOutput',false);
missing=find(~cellfun(@(p)exist(p,'file')==2,paths));
if v17_flag(c,'parallelForecasts') && c.activeGradientWorkers>0 && numel(missing)>1
    % v17: independent units are forecast in parallel. Each origin sets its
    % own RNG seed, so results are identical to the serial loop.
    cw=c; cw.activeGradientWorkers=0; v17_deadline('check');
    fprintf('  %s: forecasting %d units on %d workers.\n',tag,numel(missing),c.activeGradientWorkers);
    parfor (jj=1:numel(missing),c.activeGradientWorkers)
        j=missing(jj); [P,F,A]=predict_group(units,ids(j),models,methods,Q,cw,e,evidence,diagnose);
        v17_save(paths{j},struct('predictions',P,'filters',F,'ablation',A));
    end
end
for j=1:numel(ids)
    v17_deadline('check'); path=fullfile(dir,sprintf('%s_unit%04d.mat',tag,ids(j)));
    if exist(path,'file')==2, S=load(path);
    else
        [P,F,A]=predict_group(units,ids(j),models,methods,Q,c,e,evidence,diagnose);
        S=struct('predictions',P,'filters',F,'ablation',A); v17_save(path,S);
    end
    predictions=[predictions;S.predictions]; filters=[filters;S.filters]; ablation=[ablation;S.ablation]; %#ok<AGROW>
    fprintf('  %s forecast checkpoint %d/%d units.\n',tag,j,numel(ids));
end
end

function T=v17_regression_tests(c)
names={}; cc=c; cc.trainUnits=3; cc.validationUnits=2; cc.calibrationUnits=10; cc.testUnits=2;
cc.activeGradientWorkers=0; cc.parallelMode='off'; cc.profileDataSignature='';
U=generate_fleet(cc,'fatigue_discrepancy',91377); train=strip_truth(U(1:3)); M=initial_model(train,cc);
M.useB=true; M.baselineFixed=false; M.C(:,7)=0;
% Missing values, unequal trajectories and irregular intervals remain allowed.
train(1).y(2:5:end,1)=NaN;
for family={'zero','deep','fixed_basis','pinn'}
    A=M;
    if strcmp(family{1},'pinn'), A.kind='pinn'; A.pinnNN=init_network(cc.pinnHidden1,cc.pinnHidden2,5); A.pinnNN.w(:)=.04;
    elseif ~strcmp(family{1},'zero')
        A.bound=.15; A.residualFamily=family{1}; A.reference=observed_reference(A,train,cc); A.nn.w(:)=.03; A=project_network(A,cc);
    end
    [fa,AA]=v17_profile_emission(A,train,cc); [fb,BB]=v17_profile_emission_reference(A,train,cc);
    assert(abs(fa-fb)<1e-7 && max(abs(AA.C(:)-BB.C(:)))<1e-6,'pi17:test','Fast/reference likelihood mismatch');
    names{end+1}=['fast exact GLS agrees with Kalman profile: ' family{1}]; %#ok<AGROW>
    if A.bound>0
        d=v17_training_trajectories(A,train,cc);
        for i=1:numel(train), ref=observed_trajectory(A,train(i),A.trainingEta(i),cc); assert(max(abs(d{i}-ref))<1e-10); end
    end
end
names{end+1}='batched damage integrator matches scalar trajectory at every observation';
A=M; A.useB=false; A.sigmaB=0; A.C(:,3)=0; A.baselineFixed=true;
cc.profileQuadraticEmission=true; [fa,AA]=v17_profile_emission(A,train,cc); [fb,BB]=v17_profile_emission_reference(A,train,cc);
assert(abs(fa-fb)<1e-7 && max(abs(AA.C(:)-BB.C(:)))<1e-6);
names{end+1}='fast profile handles fixed baseline, quadratic emission and absent B';
cc.profileQuadraticEmission=false;
[v,L]=v17_profile_encode(M,train,cc); ca=cc; cb=cc; cb.fastProfile=false;
ga=v17_fd_gradient(@(z)v17_profile_objective(z,M,L,train,ca),v,ca);
gb=v17_fd_gradient(@(z)v17_profile_objective(z,M,L,train,cb),v,cb);
assert(norm(ga-gb,Inf)<5e-5); names{end+1}='fast and serial profile gradients agree for joint parameter estimation';
ops={struct('exitflag',0,'gradientNorm',.16),struct('exitflag',1,'gradientNorm',.00016)};
[chosen,ok]=v17_select_checkpoint([.02678 .03015],ops,cc); assert(chosen==2 && ok);
names{end+1}='converged later physics checkpoint outranks unfinished validation winner';
ops{2}.exitflag=0; [chosen,ok]=v17_select_checkpoint([.02678 .03015],ops,cc); assert(chosen==1 && ~ok);
names{end+1}='absence of convergence is retained explicitly, not disguised as successful fitting';
cal=table(repmat({'A'},10,1),repmat({'planned'},10,1),arrayfun(@(k)sprintf('u%d',k),(1:10)','UniformOutput',false), ...
    (10:19)',(11:20)',(8:17)',(12:21)',ones(10,1), ...
    'VariableNames',{'method','policy','unit','trueRUL_h','predictedRUL_h','rawLower_h','rawUpper_h','available'});
test=cal; test.trueRUL_h(:)=20; cc.calibrationScales=table(); [B,~]=calibrate_bands(cal,test,cc);
assert(all(B.lower_h<=B.rawLower_h+1e-10 & B.upper_h>=B.rawUpper_h-1e-10));
names{end+1}='unit conformal calibration never shrinks the raw interval';
scales=v17_fit_band_scales(cal,cc); cc.calibrationScales=scales; modified=test; modified.trueRUL_h(:)=1e5;
assert(isequal(v17_band_scale(test,cc),v17_band_scale(modified,cc)));
names{end+1}='interval scaling is independent of TEST labels and lifetime fractions';
cc.runtimeFitLabel='checkpoint_regression'; cc.checkpointEveryIterations=1; cc.progressEveryIterations=100;
dir=tempname; mkdir(dir); path=fullfile(dir,'optimizer.mat'); x=[2;-1;3];
fun=@(z)v17_test_quadratic(z,0); v17_deadline('start',Inf); paused=false;
% Inject the deadline during objective evaluation, avoiding a flaky race
% between a millisecond timer and MATLAB's first-call compilation.
try, v17_bfgs(@v17_test_force_deadline,x,100,cc,path); catch err, paused=strcmp(err.identifier,'pi17:budget'); end
assert(paused && exist(path,'file')==2); saved=load(path,'state'); assert(~saved.state.finished);
v17_deadline('start',Inf); [xr,~,o]=v17_bfgs(fun,x,100,cc,path); [xu,~,oo]=v17_bfgs(fun,x,100,cc,'');
assert(o.converged && norm(xr-xu)<1e-10 && isequal(o.trace,oo.trace));
names{end+1}='deadline checkpoint is unfinished and resumes identical BFGS trajectory';
delete(path); rmdir(dir);
dir=tempname; mkdir(dir); payload=struct('sentinel',17); v17_stage(dir,1,'test',payload); [ok,S]=v17_stage(dir,1,'test');
assert(ok && S.stageComplete && S.sentinel==17); delete(fullfile(dir,'E001_test.mat')); rmdir(dir);
names{end+1}='only explicitly completed stages are reused';
T=table(names',true(numel(names),1),'VariableNames',{'test','passed'});
end

function f=v17_test_force_deadline(x)
f=v17_test_quadratic(x,0); v17_deadline('start',0);
end

function f=v17_test_quadratic(x,seconds)
if seconds>0, pause(seconds); end
f=sum(([1;2;3].*x).^2)/2;
end

function T=v17_engine_check(c)
% Timings use distinct nearby neural vectors so trajectory-cache hits cannot
% masquerade as the speed of a changing optimizer objective.
cc=c;cc.trainUnits=8;cc.validationUnits=2;cc.calibrationUnits=10;cc.testUnits=2;
cc.profileDataSignature='';U=generate_fleet(cc,'fatigue_discrepancy',129073);train=strip_truth(U(1:8));
cc.profileDataSignature=v17_hash_text(jsonencode(train));rows=cell(0,6);
for family={'deep','pinn'}
 M=initial_model(train,cc);M.baselineFixed=false;
 if strcmp(family{1},'pinn'),M.kind='pinn';M.pinnNN=init_network(cc.pinnHidden1,cc.pinnHidden2,5);M.pinnNN.w(:)=.04;
 else,M.bound=.3;M.residualFamily='deep';M.nn.w=[M.nn.w;zeros(3,1)]+.01;M.reference=observed_reference(M,train,cc);M=project_network(M,cc);end
 [a,A]=v17_profile_emission(M,train,cc);[b,B]=v17_profile_emission_reference(M,train,cc);
 assert(abs(a-b)<1e-7 && max(abs(A.C(:)-B.C(:)))<1e-6);
 variants=cell(1,3);
 for j=1:3
  N=M;if strcmp(family{1},'pinn'),N.pinnNN.w(1)=N.pinnNN.w(1)+j*.001;
  else,N.nn.w(1)=N.nn.w(1)+j*.001;N=project_network(N,cc);end
  variants{j}=N;
 end
 timer=tic;for j=1:3,v17_profile_emission(variants{j},train,cc);end;fast=toc(timer)/3;
 timer=tic;for j=1:3,v17_profile_emission_reference(variants{j},train,cc);end;slow=toc(timer)/3;
 rows(end+1,:)={family{1},fast,slow,slow/fast,abs(a-b),max(abs(A.C(:)-B.C(:)))}; %#ok<AGROW>
end
T=cell2table(rows,'VariableNames',{'family','batchedObjectiveSeconds','scalarReferenceSeconds','evaluationSpeedRatio','absoluteObjectiveDifference','maximumEmissionDifference'});
fprintf('Changing-parameter objective timing; not an end-to-end speed guarantee.\n');
end

function T=v17_parallel_check(c)
c=v17_parallel_setup(c); assert(c.activeGradientWorkers>0,'pi17:parallel','Start a pool or set startParallelPool=true.');
serial=c; serial.activeGradientWorkers=0; parallel=c; parallel.parallelMinimumParameters=1;
fun=@(x)sum((x-(1:numel(x))').^2); x=linspace(-1,1,16)';
a=v17_fd_gradient(fun,x,serial); b=v17_fd_gradient(fun,x,parallel);
assert(norm(a-b,Inf)<1e-10);
T=table(c.activeGradientWorkers,norm(a-b,Inf),'VariableNames',{'actualGradientWorkers','maximumGradientDifference'});
end

function c=v17_revision_configuration(c,mode)
% Freeze these choices before looking at the new TEST fleets. They address
% diagnosed defects; none is selected using the inspected v11 TEST units.
c.profileQuadraticEmission=true; c.quadraticEmissionRidgeMultiplier=10;
c.originalSource=fullfile(fileparts(mfilename('fullpath')),'Reference','BSFD_PI_DSSDM_TwoState_v11.m');
c.neuralSkipFeatures=true; c.outputSmoothEpsilon=1e-6;
c.projectionSmoothEpsilon=1e-8; c.freezeResidualHidden=false;
c.neuralWarmSteps=20; c.unitResidualPenalty=.005;
c.pinnCycles=2; c.pinnWarmSteps=0;
c.lstmLearningRates=[.001 .003]; c.lstmStarts=1; c.lstmValidationPatience=8;
c.forecastReplicates=2; c.conservativeQuantile=.10;
c.gridRefinementLevels=1; c.gridDamageTolerance=2e-4;
c.numericalToleranceHours=.25; c.numericalReplicates=3;
c.profileCycles=2; c.profileSpan=.25;
c.cacheTrajectories=true; c.trajectoryCacheEntries=5;
c.optimizerInitialScale=true; c.maximumInitialInverseScale=100;
c.posteriorInformationWarningRatio=.5;
c.seed=20261116; c.label='v17 fixed development protocol; results may include ties and losses';
c.observedFitSteps=70; c.observedIterations=3; c.jointSteps=90; c.residualCycles=2;
c.pinnIterations=120; c.residualBounds=[0 .15 .30];
c.lstmHidden=[16 32]; c.lstmEpochs=40; c.maxRunSeconds=3600;
c.etaGridPoints=401; c.coarseEtaPoints=101; c.forecastPaths=120;
c.trainUnits=12; c.validationUnits=8; c.calibrationUnits=12; c.testUnits=8;
c.maxDiagnosticUnits=1; c.numericalAuditPolicies={'planned','probabilistic'};
c.scenarios={'fatigue_matched','fatigue_discrepancy','fatigue_weak_gap'};
if strcmp(mode,'controls')
 c.scenarios={'fatigue_matched','fatigue_discrepancy','fatigue_emission_mismatch','fatigue_combined_mismatch'};
 c.label='Factorial transition/observation mismatch controls, development evidence';
end
if ismember(mode,{'confirm','full','benchmark','data'})
 c.seed=20271116; if ismember(mode,{'full','benchmark'}),c.seed=20281116;end
 c.trainUnits=24;c.validationUnits=10;c.calibrationUnits=24;c.testUnits=16;
 c.scenarios={'fatigue_matched','fatigue_discrepancy','fatigue_emission_mismatch','fatigue_combined_mismatch','fatigue_weak_gap'};
 c.observedFitSteps=140; c.observedIterations=4; c.jointSteps=160; c.residualCycles=3;
 c.pinnIterations=240; c.pinnCycles=4; c.pinnStarts=2;
 c.neuralWarmSteps=35; c.lstmHidden=[24 48]; c.lstmEpochs=100; c.lstmStarts=2;
 c.forecastReplicates=3; c.etaGridPoints=801; c.coarseEtaPoints=161;
 c.gridRefinementLevels=1; c.forecastPaths=384; c.particles=1200;
 c.integrationStepHours=1; c.transitionStepHours=1; c.profileIterations=140;
 c.profileCycles=3; c.maxRunSeconds=28800;
 c.maxDiagnosticUnits=2;
 if ismember(mode,{'full','benchmark','data'}),c.maxDiagnosticUnits=3;end
 c.numericalAuditPolicies={'planned','probabilistic'};
 c.label='Fresh v17 fleets; five scenarios; 25 experiments; no forced superiority';
end
if ismember(mode,{'smoke','quick'})
 c.seed=20261117; c.scenarios={'fatigue_discrepancy'};
 c.trainUnits=4;c.validationUnits=3;c.calibrationUnits=10;c.testUnits=3;
 c.maxDiagnosticUnits=0;c.forecastPaths=30;
 c.observedFitSteps=6; c.observedIterations=1; c.jointSteps=6;
 c.residualCycles=1; c.neuralWarmSteps=2; c.pinnIterations=7; c.pinnCycles=1;
 c.residualBounds=[0 .15]; c.lstmLearningRates=.002; c.lstmStarts=1;
 c.lstmHidden=8; c.lstmEpochs=3; c.forecastReplicates=1;
 c.etaGridPoints=81; c.coarseEtaPoints=41; c.gridRefinementLevels=0;
 c.maxRunSeconds=600; c.profileCycles=1; c.numericalReplicates=2;
end
end

function z=v17_bounded_encode(x,lo,hi)
% A smooth bijection to the open feasible interval; no hidden clipping in
% the optimizer objective. Values at a declared boundary get an interior seed.
t=max(-1+1e-10,min(1-1e-10,(2*x-lo-hi)/(hi-lo)));
z=(lo+hi)/2+(hi-lo)/2*atanh(t);
end

function x=v17_bounded_decode(z,lo,hi)
x=(lo+hi)/2+(hi-lo)/2*tanh((2*z-lo-hi)/(hi-lo));
end

function w=v17_smooth_output(q,bound,c)
% ||w||_1 < bound for every finite q. Unlike project_l1, this map retains
% unique optimizer coordinates and has no projection kink at the boundary.
q=q(:); w=bound*q/(1+sum(sqrt(q.^2+c.outputSmoothEpsilon^2)));
end

function P=v17_grid_prefix(M,H,c)
cc=c;cc.gridRefinementLevels=0;P=v17_grid_prefix_once(M,H,cc);change=NaN;converged=c.gridRefinementLevels==0;
for level=1:c.gridRefinementLevels
 cc.etaGridPoints=2*cc.etaGridPoints-1;PP=v17_grid_prefix_once(M,H,cc);
 before=arrayfun(@(a)v17_weighted_quantile(P.D,P.weights,a),[.1 .5 .9]);
 after=arrayfun(@(a)v17_weighted_quantile(PP.D,PP.weights,a),[.1 .5 .9]);
 change=max(abs(before-after));P=PP;
 if change<=c.gridDamageTolerance,converged=true;break;end
end
P.gridConverged=converged;P.gridDamageChange=change;P.gridPointsUsed=numel(P.eta);
end

function [samples,info]=v17_forecast_distribution(M,H,P,banks,c,seed)
% Pool common independent duty banks before taking the median. All methods
% receive identical banks. Planned duty needs only one bank and weighted eta.
samples=[];weights=[];medians=zeros(numel(banks),1);rms=[];maximum=[];outside=[];
for r=1:numel(banks)
 rng(seed+100*(r-1),'twister');[ss,fi]=model_samples(M,H,P,banks{r},c);
 if isfield(fi,'sampleWeights'),ww=fi.sampleWeights(:);else,ww=ones(numel(ss),1)/numel(ss);end
 ww=ww/sum(ww);samples=[samples;ss(:)];weights=[weights;ww/numel(banks)]; %#ok<AGROW>
 medians(r)=v17_weighted_quantile(ss,ww,.5);
 if isfield(fi,'rhoRMS'),rms(end+1)=fi.rhoRMS;maximum(end+1)=fi.rhoMaxAbs;outside(end+1)=fi.outOfSupportFraction;end %#ok<AGROW>
end
info=struct('sampleWeights',weights,'rhoRMS',sqrt(mean(rms.^2)),'rhoMaxAbs',max([NaN maximum],[],'omitnan'), ...
 'outOfSupportFraction',mean(outside),'replicateMedianSD_h',std(medians),'replicates',numel(banks));
end

function v17_revision_reporting(E,units,ids,c,e,outDir)
P=E.predictions;M=E.models{1};I=E.identifiability;
fprintf('\nv17 MODELLING AND FAIRNESS AUDIT:\n');
fprintf('Quadratic emission=%d, ridge multiplier %.3g.\n',c.profileQuadraticEmission,c.quadraticEmissionRidgeMultiplier);
for p=1:numel(c.policies)
 N=v17_for_policy(M,c.policies{p});kappa=0;if isfield(N,'processKappa'),kappa=N.processKappa;end
 fprintf('PI-DSSDM %s: gamma damage-increment intensity kappa=%.3g h (VAL-selected; 0 means deterministic clock).\n',c.policies{p},kappa);
end
fprintf('Mean origin damage SD %.4g; %d/%d primary forecasts have SD/margin >= %.3g.\n', ...
 mean(P.estimatedDSD(strcmp(P.method,'PI_DSSDM')),'omitnan'),sum(P.originDamageUncertain & strcmp(P.method,'PI_DSSDM')),sum(strcmp(P.method,'PI_DSSDM')),c.posteriorInformationWarningRatio);
fprintf('Conservative RUL is quantile %.2f, reported separately. Primary MAE uses posterior median.\n',c.conservativeQuantile);
fprintf('Event probabilities are raw conditional model outputs, not calibrated physical failure probabilities.\n');
fprintf('Profile valid points %d/%d. Invalid points are NaN; no profile confidence intervals are claimed.\n',sum(isfinite(I.profiles.penalizedUnitMarginalNLLPerObservation)),height(I.profiles));
disp(E.methodNumerics);
O=E.optimizerAudit;O.comparableInformation=true(height(O),1);
O.mechanisticStationarityApplicable=~strcmp(O.method,'LSTM');
O.converged=double((O.exitflag==1 & O.postEmissionGradientNorm<c.gradientTolerance) | ...
 (O.exitflag==2 & O.postEmissionGradientNorm<v17_stationarity_tolerance(c)));
O.resolutionLimited=double(O.exitflag==2);
O.converged(~O.mechanisticStationarityApplicable)=NaN;
writetable(O,fullfile(outDir,sprintf('Comparator_fairness_%02d.csv',e)));
uq=P(strcmp(P.method,'PI_DSSDM'),{'unit','policy','origin_h','estimatedD','estimatedDSD','damageUncertaintyToMargin','originDamageUncertain','conservativeRUL_h','rawFailureProbability24h','rawFailureProbability48h','posteriorGridConverged','posteriorGridPoints','replicateMedianSD_h'});
writetable(uq,fullfile(outDir,sprintf('Origin_uncertainty_and_risk_%02d.csv',e)));
if M.bound>0
 ref=M.reference;[~,F]=project_network(M,c);ss=svd(F,'econ');
 normF=sqrt(sum(F.^2,1));active=normF>c.rankTolerance*max(normF);
 scaled=F(:,active)./max(normF(active),eps);sv=svd(scaled,'econ');
 rankF=sum(sv>c.rankTolerance*max(sv));condition=max(sv)/max(min(sv),eps);
 fprintf('Residual OUTPUT feature rank %d/%d, scaled condition %.5g; deep-weight uniqueness is not implied.\n',rankF,sum(active),condition);
 feature=table((1:numel(ss))',ss,'VariableNames',{'index','singularValue'});
 writetable(feature,fullfile(outDir,sprintf('Residual_function_features_%02d.csv',e)));
 % Synthetic TRAIN-only oracle projection diagnostic. Never passed to fitting,
 % validation, calibration, TEST prediction, or method selection.
 T=v17_capacity_diagnostic(M,units,ids.train,c);
 if ~isempty(T),writetable(T,fullfile(outDir,sprintf('TRAIN_oracle_capacity_DIAGNOSTIC_ONLY_%02d.csv',e)));disp(T);end
end

if ~c.makePlots,return;end
f=new_figure(c,sprintf('E%d v17 numerical and uncertainty audit',e));tiledlayout(2,2,'TileSpacing','compact');
Q=P(strcmp(P.method,'PI_DSSDM'),:);
nexttile;scatter(Q.predictedRUL_h,Q.estimatedDSD,24,'filled');xlabel('Median RUL, h');ylabel('Origin posterior SD(D)');grid on;
nexttile;scatter(Q.trueRUL_h,Q.conservativeRUL_h,24,'filled');hold on;lim=max(Q.trueRUL_h);plot([0 lim],[0 lim],'k:');xlabel('True RUL, evaluation only');ylabel('Conservative quantile RUL, h');grid on;
nexttile;N=E.methodNumerics;if isempty(N),text(.1,.5,'Numerical audit disabled in this profile');axis off;
else,plot(abs(N.halfStepChange_h),'o');hold on;plot(abs(N.etaGridChange_h),'x');plot(abs(N.doubleParticlesChange_h),'+');yline(c.numericalToleranceHours,'r:');ylabel('Absolute numerical change, h');xlabel('Explicit audit case');legend('Integration','Eta grid','PF particles','Tolerance');grid on;end
nexttile;scatter(Q.trueRUL_h,100*Q.rawFailureProbability24h,24,'filled');xline(24,'k:');xlabel('True RUL, evaluation only');ylabel('Raw Pr(RUL <=24h), %');grid on;
sgtitle([E.evidence ' | v17 audits'],'Interpreter','none');save_plot(f,outDir,sprintf('E%02d_v17_Uncertainty_and_numerics',e),c);
end

function T=v17_revision_tests(c)
% Focused scientific regressions for the actual v17 public path. They check
% invariants and independent formulations, not a favorable synthetic ranking.
names={};cc=c;cc.parallelMode='off';cc.activeGradientWorkers=0;cc.profileDataSignature='';
cc.trainUnits=3;cc.validationUnits=2;cc.calibrationUnits=10;cc.testUnits=2;
cc.runtimeCandidateDir='';cc.gridRefinementLevels=0;cc.forecastReplicates=1;
cc.coarseEtaPoints=41;cc.etaGridPoints=81;cc.profileQuadraticEmission=true;
U=generate_fleet(cc,'fatigue_matched',129071);train=strip_truth(U(1:3));M=initial_model(train,cc);
M.useB=true;M.baselineFixed=false;M.config=cc;
[x,free]=observed_encode(M,3,cc);N=observed_decode(x,M,3,cc);
assert(abs(log(N.k/M.k))<1e-12 && abs(N.tau-M.tau)<1e-11 && abs(N.sigmaB-M.sigmaB)<1e-12);
names{end+1}='smooth physical-coordinate encode/decode preserves interior parameters';
q=[-100;0;.4;12;-3];w=v17_smooth_output(q,.3,cc);
assert(sum(abs(w))<.3 && all(isfinite(w)));
hh=1e-6;left=v17_smooth_output(q+[0;hh;0;0;0],.3,cc);right=v17_smooth_output(q-[0;hh;0;0;0],.3,cc);
assert(all(isfinite((left-right)/(2*hh))));names{end+1}='smooth residual map is feasible and finite at zero coordinates';
M.bound=.3;M.residualFamily='deep';M.nn.w=[M.nn.w;zeros(3,1)];M.outputCoordinates=linspace(-.2,.3,numel(M.nn.w))';
M.nn.w=v17_smooth_output(M.outputCoordinates,M.bound,cc);M.reference=observed_reference(N,train,cc);M=project_network(M,cc);
[~,F]=project_network(M,cc);rho=F*M.nn.w;
assert(size(F,2)==cc.hidden2+3 && max(abs(rho))<=M.bound && norm(M.reference.G'*rho)/numel(rho)<1e-8);
names{end+1}='deep and damage-shape skip paths obey one bound and physical orthogonality';
[v,L]=v17_profile_encode(M,train,cc);[loss,MM]=v17_profile_objective(v,M,L,train,cc);
assert(isfinite(loss));MM.optimizerContinuation=struct('x',v,'g',zeros(size(v)),'H',eye(numel(v)),'signature',L.signature);
[vv,LL]=v17_profile_encode(MM,train,cc);assert(isequaln(v,vv) && strcmp(L.signature,LL.signature));
names{end+1}='full optimizer vector survives physical/projection round trips exactly';
% A completed fit cycle genuinely reuses H and g under the same objective.
test=cc;test.gradientTolerance=1e9;test.optimizerPasses=1;
[NN,opt]=v17_profile_fit(MM,train,test,1,'');assert(opt.curvatureContinued && opt.exitflag==1);
names{end+1}='between-cycle curvature continuation guard succeeds with smooth coordinates';
fast=cc;fast.fastProfile=true;slow=cc;slow.fastProfile=false;
[a,A]=v17_profile_emission(M,train,fast);[b,B]=v17_profile_emission(M,train,slow);
assert(abs(a-b)<1e-8 && max(abs(A.C(:)-B.C(:)))<1e-7);
names{end+1}='quadratic profiled likelihood matches independent Kalman GLS reference';
base=N;base.bound=0;
cached=v17_training_trajectories(base,train,cc);base.trainingEta(1)=.1;base.trainingEta(3)=-.1;
changed=v17_training_trajectories(base,train,cc);
for i=1:3,assert(max(abs(changed{i}-observed_trajectory(base,train(i),base.trainingEta(i),cc)))<1e-12);end
assert(isequal(cached{2},changed{2}));names{end+1}='trajectory cache updates coupled centered frailty units without stale paths';
assert(abs(v17_weighted_quantile([1;2;3],[1;1;1],.5)-2)<1e-12);
assert(isinf(v17_weighted_quantile([1;2;Inf],[.1;.1;.8],.5)));
assert(v17_weighted_quantile([1;2;3],[.2;.6;.2],.55)>2);
names{end+1}='interpolated weighted quantiles preserve medians and censored mass';
H=causal_prefix(U(4),12);Q=fit_duty_model(train);bank=future_bank(H,'planned',Q,cc,20);
N.kind='ssm';P=v17_grid_prefix(N,H,cc);[r,fi]=model_samples(N,H,P,bank,cc);
assert(all(r>=0) && abs(sum(fi.sampleWeights)-1)<1e-12);
names{end+1}='weighted planned first passage remains positive with no eta-resampling noise';
% Same-prefix future corruption cannot influence any origin distribution.
V=U(4);V.y(13:end,:)=1e9;V.u(13:end,:)=999;V.truth.D(:)=999;
P2=v17_grid_prefix(N,causal_prefix(V,12),cc);assert(isequaln(P,P2));
names{end+1}='new quadrature and state-uncertainty fields remain causal';
N.kind='pinn';N.pinnNN=init_network(cc.pinnHidden1,cc.pinnHidden2,5);N.pinnNN.w(:)=.2;
[D,~,E]=pinn_trajectory(N,H,0,cc);P=struct('D',D(end),'B',0,'eta',0,'exposure',E(end),'weights',1);
bank=struct('dt',cc.transitionStepHours,'u',reshape(H.u(end,:),1,1,3),'origin',H.t(end),'policy','planned');
H2=H;H2.t=[H.t;H.t(end)+cc.transitionStepHours];H2.u=[H.u;H.u(end,:)];H2.y=[H.y;nan(1,3)];H2.inspection=[H.inspection;NaN];
[DD,~,EE]=pinn_trajectory(N,H2,0,cc);[~,er]=pinn_rate(N,E(end),H.t(end),H.u(end,:),0,cc);
rr=pinn_rate(N,E(end)+.5*cc.transitionStepHours*er,H.t(end)+.5*cc.transitionStepHours,H.u(end,:),0,cc);
assert(abs(DD(end)-D(end)-cc.transitionStepHours*rr)<1e-12 && abs(EE(end)-E(end)-cc.transitionStepHours*er)<1e-12);
names{end+1}='PINN historical and forecast midpoint laws agree';
% The four factorial scenarios have distinct, explicit simulator mechanisms.
matched=generate_fleet(cc,'fatigue_matched',129072);em=generate_fleet(cc,'fatigue_emission_mismatch',129072);
assert(isequal(matched(1).truth.D,em(1).truth.D) && isequal(matched(1).u,em(1).u));
delta=em(1).y(:,1)-matched(1).y(:,1);assert(max(abs(delta-.15*matched(1).truth.D.^3))<1e-12);
names{end+1}='observation-only control changes emission without altering damage or duty';
CAP=v17_capacity_diagnostic(M,U,1:3,cc);assert(height(CAP)==1 && all(isfinite(table2array(CAP))));
EMPTY=v17_capacity_diagnostic(M,rmfield(U,'truth'),1:3,cc);assert(isempty(EMPTY));
names{end+1}='capacity audit is finite on TRAIN support and safely absent without synthetic truth';
if isfield(N,'optimizerContinuation'),N=rmfield(N,'optimizerContinuation');end
test=cc;test.enableProfiles=true;test.profilePoints=3;test.profileIterations=1;test.profileCycles=1;test.gradientTolerance=1e-30;
rows=v17_profile_scan(M,train,test);flags=cell2mat(rows(:,5));values=cell2mat(rows(:,4));
assert(all(isnan(values(flags<=0))));names{end+1}='unconverged profiles cannot appear as valid curvature evidence';
T=table(names',true(numel(names),1),'VariableNames',{'test','passed'});
end

function G=v17_evidence_gate(R)
G=v17_original_evidence_gate(R);c=R.config;audits=0;unresolved=0;grid=0;gridBad=0;quadOK=true;emOK=true;paired=0;pairedBad=0;
for e=1:numel(R.experiments)
 E=R.experiments{e};N=E.methodNumerics;audits=audits+height(N);unresolved=unresolved+sum(~N.resolvedAtDeclaredTolerance);
 ix=isfinite(E.predictions.posteriorGridConverged);grid=grid+sum(ix);gridBad=gridBad+sum(E.predictions.posteriorGridConverged(ix)==0);
 quadOK=quadOK && isfield(E,'hierarchyAudit') && E.hierarchyAudit.marginalQuadratureResolved;
 for m=[1 2 4 5]
  if m<=numel(E.models) && E.models{m}.available
   emOK=emOK && isfield(E.models{m},'marginalDiagnostic') && E.models{m}.marginalDiagnostic.emissionConverged;
  end
 end
 if isfield(E,'pairedDutyAudit'),paired=paired+height(E.pairedDutyAudit);pairedBad=pairedBad+sum(~E.pairedDutyAudit.resolvedAtDeclaredTolerance);end
end
rows={'explicit_numerical_resolution',audits>0 && unresolved==0,'Numerical',sprintf('%d/%d subset rows unresolved at %.4g h.',unresolved,audits,c.numericalToleranceHours); ...
 'posterior_grid_stability',c.gridRefinementLevels>0 && grid>0 && gridBad==0,'Numerical',sprintf('%d/%d origin posterior grids unresolved.',gridBad,grid); ...
 'unit_marginal_training_quadrature',quadOK && ~isempty(R.experiments),'Inference','Refine TRAIN likelihood quadrature with fixed fitted C; a subset diagnostic.'; ...
 'marginal_emission_profile_stationarity',emOK && ~isempty(R.experiments),'Inference','All selected mechanistic emission profiles must solve the same marginal objective.'; ...
 'covariance_support_for_retained_B',v17_retained_B_supported(R),'Inference','Retained B requires converged direct fits and conditional covariance support; physical identity remains unestablished.'; ...
 'paired_future_duty_gain_precision',paired>0 && pairedBad==0,'Numerical',sprintf('%d/%d late-origin paired duty contrasts unresolved; not an all-origin precision proof.',pairedBad,paired)};
G.table=[G.table;cell2table(rows,'VariableNames',G.table.Properties.VariableNames)];G.decision='HOLD';
if all(G.table.passed),G.decision='GO';elseif ~ismember(c.workflowMode,{'confirm','full'}),G.decision='DEVELOPMENT_ONLY';end
G=v17_release_gate(R,G);
G.note='Predictive, marginal-inference and numerical evidence remain separate. Physical damage identity and journal acceptance are not established by GO.';
end

function T=v17_old_capacity_diagnostic(M,units,trainIds,c)
% Diagnostic ONLY. No returned value enters fitting, selection or forecasting.
T=table();truth=[];D=[];U=[];
for i=trainIds(:)'
 V=units(i);
 if ~isfield(V,'truth') || ~isstruct(V.truth) || ~all(isfield(V.truth,{'D','scenario'})),continue;end
 dd=V.truth.D(1:end-1);uu=V.u(1:end-1,:);rho=zeros(size(dd));
 if ismember(V.truth.scenario,{'fatigue_discrepancy','fatigue_weak_gap','fatigue_combined_mismatch'}),rho=.28*sin(3*dd)+.10*dd.*tanh(uu(:,3));end
 if strcmp(V.truth.scenario,'fatigue_load_exponent'),rho=(V.truth.loadExponent-c.nominalLoadExponent)*log(max(uu(:,1),1e-8));end
 truth=[truth;rho];D=[D;dd];U=[U;uu]; %#ok<AGROW>
end
if isempty(truth),return;end
G=physical_scores(M,D,U,c);protected=G*(pinv(G)*truth);target=truth-protected;
M=project_network(M,c);H=residual_features(M,D,zeros(size(D)),U,c);
F=(H-G*M.projection.A)./M.projection.sup;
w=project_l1(pinv(F)*target,M.bound);unconstrained=F*(pinv(F)*target);bounded=F*w;
T=table(sqrt(mean(truth.^2)),sqrt(mean(protected.^2)),sqrt(mean(target.^2)), ...
 sqrt(mean((target-unconstrained).^2)),sqrt(mean((target-bounded).^2)), ...
 'VariableNames',{'trueRhoRMS','protectedComponentRMS','permittedTargetRMS','unconstrainedFeatureErrorRMS','boundedProjectedLSerrorRMS'});
end

function c=v17_hierarchical_configuration(c,mode)
% Decisions informed by v12 development outcomes. New fleet seeds are frozen.
c.originalSource=fullfile(fileparts(mfilename('fullpath')),'Reference','BSFD_PI_DSSDM_TwoState_v12.m');
c.pairedFactorial=true;c.marginalTraining=true;c.marginalQuadrature=17;
c.marginalEMiterations=80;c.marginalEMtolerance=1e-7;
c.marginalSteps=50;c.marginalCycles=2;c.encoderSteps=12;c.functionalSteps=55;
c.initializerSteps=25;c.initializerCycles=1;c.functionConditionLimit=1e4;
c.quadratureProposalInflation=1.6;c.marginalRootIterations=3;
c.seed=20261217;c.rateHypothesisSigma=[0 .08 .16 .30];
c.rateHypothesisTau=[8 24 72];c.rateHypothesisParticles=256;
c.enableRateHypothesisAudit=true;
c.earlyRelativeDamageWarning=.25;c.earlyEtaSDWarning=.10;
c.numericalGainRepeats=4;c.numericalAuditPairedDuty=true;
c.enableFullInformation=false;c.profileIterations=35;c.profileCycles=1;
c.maxDiagnosticUnits=1;c.marginalDiagnosticUnits=4;
c.observedFitSteps=25;c.observedIterations=1;c.neuralWarmSteps=0;
c.jointSteps=12;c.residualCycles=1;c.pinnIterations=45;c.pinnCycles=2;
c.forecastReplicates=4;c.forecastPaths=192;
c.trainUnits=10;c.validationUnits=8;c.calibrationUnits=12;c.testUnits=8;
c.maxRunSeconds=3600;c.showFigures=false;
c.label='v17 unit-marginal development; no superiority is presumed';
if ismember(mode,{'confirm','full','benchmark','data'})
 c.seed=20271217;if ismember(mode,{'full','benchmark'}),c.seed=20281217;end
 c.trainUnits=24;c.validationUnits=10;c.calibrationUnits=24;c.testUnits=16;
 c.marginalQuadrature=25;c.marginalSteps=100;c.functionalSteps=120;
 c.encoderSteps=30;c.initializerSteps=45;c.initializerCycles=2;
 c.marginalCycles=3;c.pinnIterations=90;c.pinnCycles=3;
 c.forecastPaths=512;c.forecastReplicates=6;c.maxDiagnosticUnits=3;
 c.marginalDiagnosticUnits=8;c.numericalGainRepeats=6;
 c.maxRunSeconds=28800;c.enableFullInformation=true;
 c.label='v17 frozen paired synthetic benchmark; all results retained';
end

if ismember(mode,{'smoke','quick'})
 c.seed=20261218;c.trainUnits=4;c.validationUnits=3;c.calibrationUnits=10;c.testUnits=3;
 c.initializerSteps=8;c.initializerCycles=1;c.marginalSteps=3;c.marginalCycles=1;
 c.encoderSteps=1;c.functionalSteps=3;c.marginalQuadrature=9;
 c.pinnIterations=3;c.pinnStarts=1;c.pinnCycles=1;
 c.forecastPaths=30;c.forecastReplicates=2;c.maxDiagnosticUnits=0;
 c.marginalDiagnosticUnits=1;c.numericalGainRepeats=2;
 c.enableRateHypothesisAudit=false;c.maxRunSeconds=1200;
end
c=v17_covariance_configuration(c,mode);
end

function [v,L]=v17_marginal_encode(M,train,c,learnEncoder)
M=v17_standardize_B(M);M=v17_marginal_context(M);
% DIRECT meaningful coordinates, with explicit box constraints. The marginal
% estimator does not use the old saturating tanh physical-parameter map.
x=[log(M.k/c.nominalRate);M.p;M.betaT;log(M.a+.01);log(M.tau);0];
free=[1 2 3 4];if c.fatigueLinearDamage,free(free==4)=[];end
if ~c.fitLoadExponent,free(free==2)=[];end
if ~c.fitTemperatureCoefficient,free(free==3)=[];end
if M.useB,free=[free 5];end
lower=[-5;1;-.6;log(.01);log(c.BtauBounds(1));-Inf];
upper=[5;5;.8;log(3.01);log(c.BtauBounds(2));Inf];
L=struct('x',x,'free',free,'nx',numel(free),'nn',0,'learnEncoder',learnEncoder,'pinn',strcmp(M.kind,'pinn'));
v=x(free);L.lower=lower(free);L.upper=upper(free);L.outputIndices=[];
if L.pinn
 if learnEncoder,nw=pack_network(M.pinnNN);else,nw=M.pinnNN.w;end
elseif M.bound>0
 if c.directNeuralCoordinates,q=M.nn.w/M.bound;elseif isfield(M,'outputCoordinates'),q=M.outputCoordinates;else,q=zeros(size(M.nn.w));end
 if learnEncoder,N=M.nn;N.w=q;nw=pack_network(N);
 else
  if isfield(M,'activeOutputIndices'),L.outputIndices=M.activeOutputIndices;else,L.outputIndices=1:numel(q);end
  nw=q(L.outputIndices);
 end
else,nw=[];end
L.nn=numel(nw);v=[v;nw];L.lower=[L.lower;-Inf(size(nw))];L.upper=[L.upper;Inf(size(nw))];
L.l1Indices=[];L.l1Radius=Inf;
if c.directNeuralCoordinates && L.nn>0
 L.lower(L.nx+1:L.nx+L.nn)=-c.encoderWeightBound;L.upper(L.nx+1:L.nx+L.nn)=c.encoderWeightBound;
 if M.bound>0 && ~L.pinn
  if learnEncoder,L.l1Indices=(L.nx+L.nn-numel(M.nn.w)+1:L.nx+L.nn)';else,L.l1Indices=(L.nx+1:L.nx+L.nn)';end
  L.lower(L.l1Indices)=-1;L.upper(L.l1Indices)=1;L.l1Radius=1;
 end
end
L.loading=[];p=size(M.C,1);
if M.useB
 L.loading=1:p;v=[v;M.C(:,3)/c.BloadingCoordinateScale];
 L.lower=[L.lower;-c.BloadingMaximum/c.BloadingCoordinateScale*ones(p,1)];
 L.upper=[L.upper;c.BloadingMaximum/c.BloadingCoordinateScale*ones(p,1)];
end
v=[v;log(M.sensorSD(:));log(M.unitSD)];
L.lower=[L.lower;repmat(log(c.sensorFloor),p,1);log(.04)];
L.upper=[L.upper;repmat(log(c.sensorCeiling),p,1);log(.6)];
sig=struct('kind',M.kind,'bound',M.bound,'useB',M.useB,'learnEncoder',learnEncoder, ...
 'activeOutputIndices',L.outputIndices,'data',v17_hash_text(jsonencode(train)), ...
 'quadrature',c.marginalQuadrature,'EM',[c.marginalEMiterations c.marginalEMtolerance], ...
 'proposalEta',M.quadratureProposalEta,'initialEmission',M.emissionInitializer, ...
 'lower',L.lower,'upper',L.upper,'config',v17_scientific_config(c));
if ~learnEncoder
 if L.pinn,NN=M.pinnNN;else,NN=M.nn;end
 NN.w(:)=0;sig.frozenEncoder=pack_network(NN);
end
if M.bound>0,sig.reference=[M.reference.D;M.reference.u(:)];end
names={'logRateRatio','loadExponent','temperatureCoefficient','logAgingPlusFloor','logTau','unused'};
L.names=names(free);
for j=1:L.nn,L.names{end+1}=sprintf('conditionalNeuralCoordinate_%d',j);end
for j=L.loading,L.names{end+1}=sprintf('effectiveBLoading_scaled_sensor%d',j);end
for j=1:p,L.names{end+1}=sprintf('logSensorSD_%d',j);end
L.names{end+1}='logPopulationFrailtySD';L.signature=v17_hash_text(jsonencode(sig));
if isfield(M,'marginalContinuation') && strcmp(M.marginalContinuation.signature,L.signature),v=M.marginalContinuation.x;end
v=min(L.upper,max(L.lower,v));
if ~isempty(L.l1Indices),v(L.l1Indices)=project_l1(v(L.l1Indices),L.l1Radius);end
end

function [loss,M]=v17_marginal_objective(v,M,L,train,c)
if any(v<L.lower-1e-10 | v>L.upper+1e-10),loss=1e30;return;end
M=v17_standardize_B(M);M=v17_marginal_context(M);
cols=setdiff(1:7,3);M.C(:,cols)=M.emissionInitializer(:,cols);
x=L.x;x(L.free)=v(1:L.nx);j=L.nx;
M.k=c.nominalRate*exp(x(1));M.p=x(2);M.betaT=x(3);M.a=exp(x(4))-.01;M.tau=exp(x(5));
if c.fatigueLinearDamage,M.a=0;end
if ~c.fitLoadExponent,M.p=c.nominalLoadExponent;end
if ~c.fitTemperatureCoefficient,M.betaT=c.nominalTempCoefficient;end
if L.nn>0
 nw=v(j+1:j+L.nn);j=j+L.nn;
 if L.pinn
  if L.learnEncoder,M.pinnNN=unpack_network(nw,c.pinnHidden1,c.pinnHidden2,5);else,M.pinnNN.w=nw;end
 elseif M.bound>0
  if L.learnEncoder,M.nn=unpack_network(nw,c.hidden1,c.hidden2,5);q=M.nn.w;
  else,q=zeros(size(M.nn.w));q(L.outputIndices)=nw;end
  M.outputCoordinates=q;if c.directNeuralCoordinates,M.nn.w=M.bound*q;else,M.nn.w=v17_smooth_output(q,M.bound,c);end
 end
end
p=size(M.C,1);
if M.useB,M.C(:,3)=c.BloadingCoordinateScale*v(j+1:j+p);j=j+p;M.sigmaB=1;else,M.C(:,3)=0;M.sigmaB=0;end
M.sensorSD=exp(v(j+1:j+p))';j=j+p;M.unitSD=exp(v(j+1));M.config=c;
if M.bound>0
 M.reference.G=physical_scores(M,M.reference.D,M.reference.u,c);
 M.reference.pinvG=pinv(M.reference.G,c.projectionTolerance);
 M.reference.gmax=score_envelope(M,M.reference.lo,M.reference.hi,c);M=project_network(M,c);
end
[loss,M]=v17_marginal_profile(M,train,c);
if L.nn>0 && ~L.pinn,loss=loss+1e-7*sum(M.nn.w.^2);end
if ~isfinite(loss),loss=1e30;end
end

function [M,opt,loss]=v17_marginal_fit(M,train,c,steps,tag,learnEncoder)
if nargin<6,learnEncoder=false;end
M=v17_standardize_B(M);M=v17_marginal_context(M);
c.profileDataSignature=v17_hash_text(jsonencode(train));
[v,L]=v17_marginal_encode(M,train,c,learnEncoder);fun=@(z)v17_marginal_objective(z,M,L,train,c);
c.optimizerLowerBound=L.lower;c.optimizerUpperBound=L.upper;c.optimizerL1Indices=L.l1Indices;c.optimizerL1Radius=L.l1Radius;
continued=isfield(M,'marginalContinuation') && strcmp(M.marginalContinuation.signature,L.signature) && isequaln(M.marginalContinuation.x,v);
if continued,c.initialBFGS=M.marginalContinuation;elseif isfield(c,'initialBFGS'),c=rmfield(c,'initialBFGS');end
c.runtimeFitLabel=tag;path=v17_candidate_path(c,tag);
fprintf('  PROFILE %s: %d coordinates, training %s, encoder learned=%d.\n',tag,numel(v),c.trainingLikelihood,learnEncoder);
[v,~,opt]=v17_bfgs(fun,v,steps,c,path);[loss,M]=v17_marginal_objective(v,M,L,train,c);
opt.curvatureContinued=continued;opt.emissionProfileConverged=M.marginalDiagnostic.emissionConverged;
opt.marginalObjective=true;opt.encoderConditionedOn=~learnEncoder;opt.coordinateNames=L.names;
opt.coordinateNote='Direct log-physical/effective-loading coordinates; feasible projected gradient, no tanh attenuation.';
if ~opt.emissionProfileConverged,opt.exitflag=0;opt.converged=false;opt.status='marginal_emission_EM_unresolved';end
M.marginalContinuation=struct('x',v,'g',opt.finalGradient,'H',opt.inverseHessian,'signature',L.signature);
M.marginalOptimization=opt;M.selectedMStep=opt;M.profileObjective=loss;
end

function M=v17_fit_population_one(train,val,Q,c,eid,useB)
M=v17_population_initializer(train,c,useB);archive={};rows=cell(0,10);
limit=c.marginalCycles;
if strcmp(c.trainingLikelihood,'event_time'),limit=limit+1;end
for cycle=1:limit
 steps=c.marginalSteps;tag=sprintf('population_B%d_cycle%02d',useB,cycle);
 if cycle>c.marginalCycles
  steps=c.populationRecoverySteps;tag=sprintf('population_B%d_TRAIN_recovery',useB);
  if isfield(M,'marginalContinuation'),M=rmfield(M,'marginalContinuation');end
 end
 [M,opt,loss]=v17_marginal_fit(M,train,c,steps,tag,false);
 rows(end+1,:)={cycle,loss,-loss,NaN,NaN,opt.exitflag,opt.gradientNorm,NaN,NaN,mean(M.sensorSD)}; %#ok<AGROW>
 archive{end+1}=struct('model',M,'optimizer',opt,'validationLoss',NaN); %#ok<AGROW>
 if v17_converged(opt,c),break;end
end
M.selectedMStep=opt;M.selectedIteration=cycle;M.fitCandidates=archive;
M.validationScore=forecast_score(M,val,Q,c,eid);M.validationBestIteration=cycle;M.validationBestLoss=M.validationScore;
M.fitCandidates{end}.validationLoss=M.validationScore;M.fitCandidates{end}.model.validationScore=M.validationScore;
rows{end,4}=M.validationScore;
M.fitTrace=cell2table(rows,'VariableNames',{'iteration','unitMarginalNLLPerObservation','negativePenalizedMarginalNLLPerObservation', ...
 'causalValidationLoss','relativeParameterChange','mStepExitflag','mStepGradientNorm','meanESS','etaAcceptance','meanSensorSD'});
M.optimization=struct('status','TRAIN event/survival profile; final checkpoint and deterministic recovery, no VAL iteration search', ...
 'stabilized',v17_converged(opt,c),'selectedIteration',cycle,'selectedMStepExitflag',opt.exitflag, ...
 'lastMStepExitflag',opt.exitflag,'gradientNorm',opt.gradientNorm);
end

function M=v17_select_function_coordinates(M,c)
% Select independent OUTPUT directions on TRAIN support. Hidden weights were
% learned in a separate TRAIN phase and are conditioned on in final fitting.
[M,F]=project_network(M,c);scale=sqrt(sum(F.^2,1));F=F./max(scale,eps);
[~,R,pivot]=qr(F,'vector');diagonal=abs(diag(R));rankF=sum(diagonal>c.rankTolerance*max(diagonal));
rankF=max(1,rankF);
while rankF>1 && cond(F(:,pivot(1:rankF)))>c.functionConditionLimit,rankF=rankF-1;end
M.activeOutputIndices=sort(pivot(1:rankF));
q=M.outputCoordinates;q(setdiff(1:numel(q),M.activeOutputIndices))=0;
M.outputCoordinates=q;if c.directNeuralCoordinates,M.nn.w=M.bound*q;else,M.nn.w=v17_smooth_output(q,M.bound,c);end
M.functionCoordinateNote='Final output coefficients identified conditional on a TRAIN-learned, frozen encoder; encoder uncertainty remains.';
end

function [z,w]=v17_normal_nodes(n)
% Golub-Welsch quadrature for a STANDARD normal density, not exp(-x^2).
persistent counts nodes weights
if isempty(counts),counts=[];nodes={};weights={};end
ix=find(counts==n,1);if ~isempty(ix),z=nodes{ix};w=weights{ix};return;end
J=diag(sqrt(1:n-1),1)+diag(sqrt(1:n-1),-1);[V,L]=eig(J);
[z,ix]=sort(diag(L));w=V(1,ix)'.^2;w=w/sum(w);
counts(end+1)=n;nodes{end+1}=z;weights{end+1}=w;
end

function [z,w]=v17_legendre_nodes(n)
persistent counts nodes weights
if isempty(counts),counts=[];nodes={};weights={};end
ix=find(counts==n,1);if ~isempty(ix),z=nodes{ix};w=weights{ix};return;end
j=(1:n-1)';a=j./sqrt(4*j.^2-1);[V,L]=eig(diag(a,1)+diag(a,-1));
[z,ix]=sort(diag(L));w=2*V(1,ix)'.^2;
counts(end+1)=n;nodes{end+1}=z;weights{end+1}=w;
end

function y=v17_log_normal(x,mu,sd)
y=-.5*((x-mu)./sd).^2-log(sd)-.5*log(2*pi);
end

function T=v17_hierarchy_parallel_check(c)
c.parallelMode='off';c.activeGradientWorkers=0;c.trainUnits=3;c.validationUnits=2;c.calibrationUnits=10;c.testUnits=2;
c.marginalQuadrature=9;c.runtimeCandidateDir='';c.profileDataSignature='';
U=generate_fleet(c,'fatigue_matched',190127);train=strip_truth(U(1:3));M=initial_model(train,c);
M.kind='observed';M.useB=true;M.baselineFixed=false;M.config=c;M.trainingEta=zeros(3,1);
[v,L]=v17_marginal_encode(M,train,c,false);fun=@(z)v17_marginal_objective(z,M,L,train,c);
serial=v17_fd_gradient(fun,v,c);cp=c;cp.parallelMode='auto';cp.startParallelPool=true;cp.maxGradientWorkers=2;
cp.parallelMinimumParameters=1; % Exercise parfor even when the fixture has fewer than 12 coordinates.
cp=v17_parallel_setup(cp);parallel=v17_fd_gradient(fun,v,cp);
difference=max(abs(serial-parallel));tolerance=1e-8*max(1,norm(serial,Inf));
% Finite differences amplify floating-point reduction differences. This is
% far below the 2e-4 fitting criterion and does not require bitwise equality.
assert(difference<=tolerance,'pi17:parallel','Gradient difference %.6g exceeds %.6g.',difference,tolerance);
T=table(cp.activeGradientWorkers,numel(v),difference,tolerance, ...
 'VariableNames',{'actualGradientWorkers','marginalCoordinates','maximumGradientDifference','declaredGradientTolerance'});disp(T);
end

function nll=v17_static_prefix_nll(M,H,c)
% Deterministic static-state comparator for the exploratory R-state probe.
% Do not manufacture a rate-state gain from static particle impoverishment.
P=v17_grid_prefix(M,H,c);eta=P.eta;D=observed_trajectory(M,H,eta,c);ll=observed_kalman(M,H,D,c);
lw=v17_log_normal(eta,0,M.unitSD)-log(erf(c.unitEffectMax/(sqrt(2)*M.unitSD)))-ll';
lw(any(D>=c.Dcrit,1)')=-Inf;
if numel(eta)>1,lw([1 end])=lw([1 end])+log(.5);width=eta(2)-eta(1);else,width=1;end
mx=max(lw);nll=-mx-log(sum(exp(lw-mx))*width);
end

function M=v17_marginal_context(M)
% These seeds define a deterministic profiled objective across iterations,
% continuation and resume. They are initialization, never additional data.
if ~isfield(M,'emissionInitializer')
 M.emissionInitializer=M.C;M.quadratureProposalEta=M.trainingEta;M.quadratureProposalRate=M.k;
end
end

function [A,paired,rate]=v17_hierarchical_audits(M,models,names,train,val,units,ids,Q,c,eid)
count=min(numel(train),c.marginalDiagnosticUnits);subset=train(1:count);N=M;
N.trainingEta=M.trainingEta(1:count);coarse=c;coarse.marginalEMiterations=0;
[~,B,db]=v17_marginal_profile(N,subset,coarse);fine=coarse;fine.marginalQuadrature=2*c.marginalQuadrature-1;fine.failureRootTolerance=c.failureRootTolerance/4;
[~,F,df]=v17_marginal_profile(N,subset,fine);
change=max(abs(db.marginalUnitNLL-df.marginalUnitNLL));etaChange=max(abs(B.trainingEta-F.trainingEta));
A=struct('marginalQuadratureNLLChange',change,'marginalQuadratureEtaMeanChange',etaChange, ...
 'marginalQuadratureResolved',change<.01 && etaChange<.002,'auditedTRAINunits',count, ...
 'scope','Failure-clock/root and right-censor quadrature refinement with fixed C on a TRAIN subset; not complete global uncertainty.');
auditConfig=c;if ~c.numericalAuditPairedDuty,auditConfig.maxDiagnosticUnits=0;end
paired=v17_paired_duty_audit(models,names,units,ids.test,Q,auditConfig,eid);
rate=struct('additionalStateRetainedInPrimary',false,'predictiveSupport',false,'conclusion','Rate-state hypothesis audit disabled by configuration.');
if c.enableRateHypothesisAudit,rate=v17_rate_state_audit(M,train,val,c,c.seed+eid*70001);end
end

function T=v17_paired_duty_audit(models,names,units,ids,Q,c,eid)
% Repeat the ACTUAL pooled-bank median functional and paired absolute-error
% contrast on a declared late-origin subset. Population/fleet uncertainty is
% separate. SD describes regeneration of the statistic, not SE of its mean.
rows=cell(0,10);
for i=ids(1:min(numel(ids),c.maxDiagnosticUnits))
 U=units(i);[ks,zs]=origin_nodes(U,c);if isempty(ks),continue;end
 k=ks(end);z=zs(end);H=causal_prefix(U,k);truth=U.failureTime-H.t(end);
 gain=nan(c.numericalGainRepeats,numel(models));big=gain;
 for repeat=1:c.numericalGainRepeats
  seed=c.seed+eid*19000+i*137+z+repeat*19711;
  banks=cell(1,c.forecastReplicates);large=banks;
  for bank=1:c.forecastReplicates
   rng(seed+bank*771);banks{bank}=future_bank(H,'probabilistic',Q,c,c.forecastPaths);
   rng(seed+bank*771);large{bank}=future_bank(H,'probabilistic',Q,c,2*c.forecastPaths);
  end
  baseline=nan(1,numel(models));refined=baseline;
  for m=1:numel(models)
   active=v17_for_policy(models{m},'probabilistic');v17_deadline('check');if ~active.available,continue;end
   rng(seed+13);P=model_posterior(active,H,c);
   [a,aa]=v17_forecast_distribution(active,H,P,banks,c,seed+17);baseline(m)=v17_quantile(a,aa,.5);
   [b,bb]=v17_forecast_distribution(active,H,P,large,c,seed+17);refined(m)=v17_quantile(b,bb,.5);
  end
  gain(repeat,:)=abs(baseline-truth)-abs(baseline(1)-truth);
  big(repeat,:)=abs(refined-truth)-abs(refined(1)-truth);
 end
 for m=2:numel(models)
  ok=isfinite(gain(:,m))&isfinite(big(:,m));g=gain(ok,m);b=big(ok,m);
  mu=mean(g);sd=std(g);change=mean(b-g);resolved=numel(g)>=2 && sd<=c.numericalToleranceHours && abs(change)<=c.numericalToleranceHours;
  rows(end+1,:)={U.id,H.t(end),names{m},numel(g),mu,sd,sd/sqrt(max(1,numel(g))),change,resolved,truth}; %#ok<AGROW>
 end
end
T=cell2table(rows,'VariableNames',{'unit','origin_h','comparator','independentMCregenerations','meanPairedAbsoluteErrorGain_h', ...
 'MCsdOfRegeneratedGain_h','SEofDiagnosticMean_h','doublingPathsPairedGainChange_h','resolvedAtDeclaredTolerance','trueRUL_h'});
end

function v17_hierarchical_reporting(E,c,e,outDir)
M=E.models{1};A=E.hierarchyAudit;
fprintf('\nV15 INFERENCE AUDIT: integrated frailty, same observation likelihood, failure-time/survival likelihood.\n');
fprintf('TRAIN quadrature max unit-NLL change %.4g, eta-mean change %.4g, resolved=%d.\n', ...
 A.marginalQuadratureNLLChange,A.marginalQuadratureEtaMeanChange,A.marginalQuadratureResolved);
Q=E.predictions(strcmp(E.predictions.method,'PI_DSSDM'),:);
Q.relativeDamageSD=Q.estimatedDSD./max(Q.estimatedD,.01);
Q.earlyRateUncertain=Q.relativeDamageSD>c.earlyRelativeDamageWarning | Q.estimatedEtaSD>c.earlyEtaSDWarning;
fprintf('Early-state/rate warnings %d/%d primary forecasts. A small SD/failure-margin ratio does not guarantee precise early rate.\n',sum(Q.earlyRateUncertain),height(Q));
writetable(Q(:,{'unit','policy','origin_h','estimatedD','estimatedDSD','relativeDamageSD','estimatedEtaSD','earlyRateUncertain'}), ...
 fullfile(outDir,sprintf('Early_damage_and_rate_uncertainty_%02d.csv',e)));
writetable(table(M.trainingEta,M.trainingEtaSD,'VariableNames',{'posteriorEtaMean','posteriorEtaSD'}),fullfile(outDir,sprintf('TRAIN_posterior_frailty_%02d.csv',e)));
writetable(E.pairedDutyAudit,fullfile(outDir,sprintf('Paired_future_duty_gain_precision_%02d.csv',e)));disp(E.pairedDutyAudit);
fid=fopen(fullfile(outDir,sprintf('Hierarchical_inference_audit_%02d.json',e)),'w');fwrite(fid,jsonencode(A),'char');fclose(fid);
R=E.rateStateHypothesis;fprintf('Additional rate state retained in primary=%d.\n%s\n',R.additionalStateRetainedInPrimary,R.conclusion);
if isfield(R,'candidates')
 writetable(R.candidates,fullfile(outDir,sprintf('Rate_state_TRAIN_candidates_%02d.csv',e)));
 fprintf('Rate hypothesis VAL gain %.4g SE %.4g; particle refinement change %.4g; predictive support=%d.\n',R.validationGain,R.validationGainSE,R.pairedParticleRefinementChange,R.predictiveSupport);
end
fid=fopen(fullfile(outDir,sprintf('Rate_state_hypothesis_%02d.json',e)),'w');fwrite(fid,jsonencode(R),'char');fclose(fid);
if ~c.makePlots,return;end
f=new_figure(c,sprintf('E%d v17 hierarchical diagnostics',e));tiledlayout(2,2,'TileSpacing','compact');
nexttile;errorbar(1:numel(M.trainingEta),M.trainingEta,2*M.trainingEtaSD,'o');xlabel('TRAIN unit');ylabel('Posterior eta mean +/- 2 SD');grid on;
nexttile;scatter(Q.estimatedD,Q.relativeDamageSD,24,'filled');yline(c.earlyRelativeDamageWarning,'r:');xlabel('Estimated D');ylabel('SD(D)/max(D,0.01)');grid on;
nexttile;scatter(Q.estimatedD,Q.estimatedEtaSD,24,'filled');yline(c.earlyEtaSDWarning,'r:');xlabel('Estimated D');ylabel('Posterior rate-frailty SD');grid on;
nexttile;if isempty(E.pairedDutyAudit),text(.1,.5,'Paired duty audit disabled in this profile');axis off;
else,T=E.pairedDutyAudit;errorbar(1:height(T),T.meanPairedAbsoluteErrorGain_h,T.MCsdOfRegeneratedGain_h,'o');yline(0,'k:');ylabel('Paired gain +/- MC SD, h');xlabel('Declared audit contrast');grid on;end
sgtitle([E.evidence ' | unit-marginal inference'],'Interpreter','none');save_plot(f,outDir,sprintf('E%02d_Hierarchical_inference',e),c);
end

function [nll,diagnostic]=v17_rate_probe_filter(M,H,sigma,tau,c,N,seed)
% Hypothesis tool ONLY: [D,R] with an OU log-rate modifier R, static eta,
% and analytically integrated B. It is not silently installed in PI-DSSDM.
% This bootstrap filter has no exact path rejuvenation; particle precision
% and static-frailty impoverishment therefore remain explicit diagnostics.
old=rng;cl=onCleanup(@()rng(old));rng(seed,'twister'); %#ok<NASGU>
u=((1:N)'-.5)/N;u=u(randperm(N));
eta=sqrt(2)*M.unitSD*erfinv((2*u-1)*erf(c.unitEffectMax/(sqrt(2)*M.unitSD)));
D=zeros(N,1)+H.initialD;R=sigma*randn(N,1);bm=zeros(N,1);bv=M.sigmaB^2;w=ones(N,1)/N;
nll=0;ess=zeros(numel(H.t),1);distinct=ess;meanD=ess;meanR=ess;
for k=1:numel(H.t)
 if k>1
  dt=H.t(k)-H.t(k-1);steps=max(1,ceil(dt/c.transitionStepHours));h=dt/steps;u=repmat(H.u(k-1,:),N,1);
  for s=1:steps
   phi=exp(-h/tau);next=phi*R+sigma*sqrt(max(0,1-phi^2))*randn(N,1);
   multiplier=exp(.5*(R+next)-.5*sigma^2);base=physics_rate(M,u).*exp(eta).*multiplier;
   rate=base.*exp(discrepancy(M,D,zeros(N,1),u)).*(1+M.a*D);mid=D+.5*h.*rate;
   D=D+h*base.*exp(discrepancy(M,mid,zeros(N,1),u)).*(1+M.a*mid);R=next;
  end
  phi=exp(-dt/M.tau);bm=phi*bm;bv=phi^2*bv+M.sigmaB^2*(1-phi^2);
 end
 good=isfinite(H.y(k,:));logl=zeros(N,1);logl(D>=c.Dcrit)=-Inf;
 if any(good)
  mu=emission_features(D,bm,repmat(H.u(k,:),N,1))*M.C';res=H.y(k,good)-mu(:,good);
  load=M.C(good,3);rv=M.sensorSD(good)'.^2;v=load./rv;den=1+bv*(load'*v);
  W=diag(1./rv)-bv*(v*v')/den;
  logl=logl-.5*(sum((res*W).*res,2)+sum(log(rv))+log(den)+sum(good)*log(2*pi));
  gain=bv*load'*W;bm=bm+res*gain';bv=max(0,bv-gain*load*bv);
 end
 if isfinite(H.inspection(k)),logl=logl-.5*((D-H.inspection(k))/c.inspectionSD).^2-log(c.inspectionSD*sqrt(2*pi));end
 logs=log(max(w,realmin))+logl;mx=max(logs);
 if ~isfinite(mx),nll=Inf;break;end
 z=sum(exp(logs-mx));nll=nll-mx-log(z);w=exp(logs-mx)/z;
 ess(k)=1/sum(w.^2);distinct(k)=numel(unique(eta));meanD(k)=w'*D;meanR(k)=w'*R;
 if ess(k)<.5*N && k<numel(H.t),ix=systematic_resample(w,N);D=D(ix);R=R(ix);eta=eta(ix);bm=bm(ix);w(:)=1/N;end
end
diagnostic=struct('minimumESS',min(ess),'finalDistinctFrailty',numel(unique(eta)), ...
 'filteredD',meanD,'filteredRateModifier',meanR,'time',H.t, ...
 'scope','Exploratory bootstrap rate-state filter; no joint refit or exact static-eta rejuvenation.');
end

function A=v17_rate_state_audit(M,train,val,c,seed)
% Candidate parameters are chosen using TRAIN observations only. Independent
% VAL observations test predictive evidence. TEST sensors/truth are absent.
train=train(1:min(numel(train),c.marginalDiagnosticUnits));val=val(1:min(numel(val),c.marginalDiagnosticUnits));
parameters=[0 24];
for sigma=c.rateHypothesisSigma(c.rateHypothesisSigma>0),for tau=c.rateHypothesisTau,parameters(end+1,:)=[sigma tau];end,end %#ok<AGROW>
scores=zeros(size(parameters,1),numel(train));
for j=1:size(parameters,1)
 for i=1:numel(train)
  H=causal_prefix(train(i),max(2,numel(train(i).t)-1));
  if parameters(j,1)==0,ll=v17_static_prefix_nll(M,H,c);else,[ll,~]=v17_rate_probe_filter(M,H,parameters(j,1),parameters(j,2),c,c.rateHypothesisParticles,seed+i*13);end
  scores(j,i)=ll/max(1,sum(isfinite(H.y(:))));
 end
end
[~,chosen]=min(mean(scores,2));sigma=parameters(chosen,1);tau=parameters(chosen,2);
gain=zeros(numel(val),1);fine=gain;distinct=gain;
for i=1:numel(val)
 H=causal_prefix(val(i),max(2,numel(val(i).t)-1));count=max(1,sum(isfinite(H.y(:))));
 a=v17_static_prefix_nll(M,H,c);aa=a;
 if sigma==0,b=a;bb=a;dd=struct('finalDistinctFrailty',Inf);
 else
  [b,~]=v17_rate_probe_filter(M,H,sigma,tau,c,c.rateHypothesisParticles,seed+1000+i);
  [bb,dd]=v17_rate_probe_filter(M,H,sigma,tau,c,2*c.rateHypothesisParticles,seed+1000+i);
 end
 gain(i)=(a-b)/count;fine(i)=(aa-bb)/count;distinct(i)=dd.finalDistinctFrailty;
end
se=std(gain)/sqrt(numel(gain));precision=abs(mean(gain)-mean(fine));
support=numel(gain)>=3 && sigma>0 && mean(gain)>se && mean(fine)>0 && precision<max(.5*mean(gain),1e-4) && min(distinct)>=4;
rows=table(parameters(:,1),parameters(:,2),mean(scores,2),'VariableNames',{'candidateRateSD','candidateTau_h','TRAINobservedNLLPerObservation'});
A=struct('candidates',rows,'selectedSigma',sigma,'selectedTau_h',tau,'validationGain',mean(gain),'validationGainSE',se, ...
 'doubledParticleGain',mean(fine),'pairedParticleRefinementChange',precision,'predictiveSupport',support, ...
 'additionalStateRetainedInPrimary',false,'minimumDistinctFrailty',min(distinct), ...
 'conclusion','Additional R is a hypothesis. Predictive support requires a subsequent jointly fitted, identifiable state model; no physical R interpretation is asserted.');
end

function R=v17_state_hypothesis_check(c)
% Separate software challenge. Known simulation parameters are used here,
% rather than presenting an oracle-parameter exercise as a model benchmark.
c.marginalDiagnosticUnits=3;c.transitionStepHours=2;old=rng;cl=onCleanup(@()rng(old)); %#ok<NASGU>
rows=cell(0,7);details=cell(2,1);
for scenario=1:2
 rng(c.seed+39173+scenario);sigma=[0 .30];sigma=sigma(scenario);
 M=struct('kind','observed','k',.002,'p',3,'betaT',0,'a',0,'tau',18,'sigmaB',.04,'unitSD',.16, ...
  'sensorSD',[.025 .025 .025],'bound',0,'projection',[],'config',c, ...
  'C',[.02 1 .2 0 0 0 .1;0 .1 1 0 0 0 0;.01 .7 -.2 0 0 0 .05]);
 units=cell(1,6);
 for i=1:6
  t=(0:8:240)';u=[ones(numel(t),2) zeros(numel(t),1)];D=zeros(size(t));B=D;V=D;V(1)=sigma*randn;eta=.16*randn;
  B(1)=.04*randn;y=zeros(numel(t),3);
  for k=1:numel(t)
   if k>1
    d=D(k-1);v=V(k-1);
    for s=1:4,next=exp(-2/24)*v+sigma*sqrt(1-exp(-4/24))*randn;d=d+2*.002*exp(eta+.5*(v+next)-.5*sigma^2);v=next;end
    D(k)=d;V(k)=v;B(k)=exp(-8/18)*B(k-1)+.04*sqrt(1-exp(-16/18))*randn;
   end
   y(k,:)=emission_features(D(k),B(k),u(k,:))*M.C'+M.sensorSD.*randn(1,3);
  end
  units{i}=struct('id',sprintf('rateProbe_%d_%d',scenario,i),'t',t,'u',u,'y',y,'inspection',nan(size(t)), ...
   'failureObserved',false,'failureTime',Inf,'initialD',0,'plan',[]);
 end
 units=[units{:}];A=v17_rate_state_audit(M,units(1:3),units(4:6),c,c.seed+scenario*100);details{scenario}=A;
 rows(end+1,:)={sigma,A.selectedSigma,A.selectedTau_h,A.validationGain,A.validationGainSE,A.pairedParticleRefinementChange,A.predictiveSupport}; %#ok<AGROW>
end
R=struct('results',cell2table(rows,'VariableNames',{'simulatedRateSD','selectedRateSD','selectedTau_h','VALgain','VALgainSE','particleRefinementChange','predictiveSupport'}), ...
 'details',{details},'scope','Separate rate-state software challenge with known generator parameters. Not PI-DSSDM comparative performance.');disp(R.results);
end

function I=identifiability(M,train,c,eid) %#ok<INUSD>
% Scores of integrated UNIT likelihoods. Emission coefficients are profiled;
% the learned encoder is conditioned on. This is not full Bayesian Fisher.
[v,L]=v17_marginal_encode(M,train,c,false);p=numel(v);n=numel(train);
[center,MM]=v17_marginal_objective(v,M,L,train,c);J=zeros(n,p);steps=c.jacobianStep*max(1,abs(v));
names=L.names;
for j=1:p
 vp=v;vm=v;vp(j)=min(L.upper(j),vp(j)+steps(j));vm(j)=max(L.lower(j),vm(j)-steps(j));
 [~,A]=v17_marginal_objective(vp,M,L,train,c);[~,B]=v17_marginal_objective(vm,M,L,train,c);
 J(:,j)=(A.marginalDiagnostic.marginalUnitNLL-B.marginalDiagnostic.marginalUnitNLL)/(vp(j)-vm(j));
end
norms=sqrt(sum(J.^2,1));active=norms>c.rankTolerance*max(norms);scaled=J(:,active)./max(norms(active),eps);
ss=svd(scaled,'econ');rankJ=sum(ss>c.rankTolerance*max(ss));
physical=find(ismember(L.free,1:4));nuisance=setdiff(1:p,physical);pr=0;pc=nan(4);
if ~isempty(physical)
 R=J(:,physical)-J(:,nuisance)*(pinv(J(:,nuisance))*J(:,physical));s=svd(R,'econ');
 pr=sum(s>c.rankTolerance*max(svd(J(:,physical),'econ')));
 if pr==numel(physical),V=pinv(R'*R);sd=sqrt(max(diag(V),eps));pc(L.free(physical),L.free(physical))=V./(sd*sd');end
end
cosine=J'*J./max(norms'*norms,eps);pairs=cell(0,3);
for i=1:p,for j=i+1:p,if abs(cosine(i,j))>.95,pairs(end+1,:)={names{i},names{j},cosine(i,j)};end,end,end %#ok<AGROW>
ref=observed_reference(M,train,c);ref.D0=ref.D;ref.B0=ref.B;
rho=discrepancy(M,ref.D,zeros(size(ref.D)),ref.u);um=accumarray(ref.unit,rho,[],@mean);
erank=Inf;emin=Inf;
for d=linspace(0,c.Dcrit,20)
 E=[M.C(:,2)+2*d*M.C(:,7) M.C(:,3)]./M.sensorSD';s=svd(E);erank=min(erank,sum(s>c.rankTolerance*max(s)));emin=min(emin,min(s));
end
profiles=cell(0,7);
if c.enableProfiles
 for jj=physical
  values=min(L.upper(jj),max(L.lower(jj),v(jj)+linspace(-c.profileSpan,c.profileSpan,c.profilePoints)));[~,order]=sort(abs(values-v(jj)));
  for index=order
   anchor=v;anchor(jj)=values(index);other=setdiff(1:p,jj);
   if abs(values(index)-v(jj))<1e-12 && isfield(M,'marginalOptimization')
    opt=M.marginalOptimization;loss=center;trial=v;
   else
    fun=@(z)v17_marginal_fixed(z,anchor,other,M,L,train,c);cc=c;cc.runtimeFitLabel='marginal_profile';cc.optimizerLowerBound=L.lower(other);cc.optimizerUpperBound=L.upper(other);cc.optimizerL1Indices=find(ismember(other,L.l1Indices));cc.optimizerL1Radius=L.l1Radius;
    [z,loss,opt]=v17_bfgs(fun,anchor(other),c.profileIterations,cc,v17_candidate_path(c,sprintf('marginal_profile_%d_%d',jj,index)));
    trial=anchor;trial(other)=z;
   end
   [~,A]=v17_marginal_objective(trial,M,L,train,c);phys=[A.k A.p A.betaT A.a];
   if ~v17_converged(opt,c),loss=NaN;end
   profiles(end+1,:)={L.free(jj),values(index),phys(L.free(jj)),loss,opt.exitflag,opt.iterations,opt.gradientNorm}; %#ok<AGROW>
  end
 end
end
F=v17_skipped_information();
interior=all(v-steps>L.lower & v+steps<L.upper) && (isempty(L.l1Indices) || sum(abs(v(L.l1Indices)))+sum(steps(L.l1Indices))<L.l1Radius);
if c.enableFullInformation && interior
 H=zeros(p);
 for j=1:p
  vp=v;vm=v;vp(j)=min(L.upper(j),vp(j)+steps(j));vm(j)=max(L.lower(j),vm(j)-steps(j));
  H(j,j)=(v17_marginal_objective(vp,M,L,train,c)-2*center+v17_marginal_objective(vm,M,L,train,c))/steps(j)^2;
  for k=1:j-1
   pp=v;pm=v;mp=v;mm=v;pp([j k])=pp([j k])+steps([j k]);mm([j k])=mm([j k])-steps([j k]);
   pm(j)=pm(j)+steps(j);pm(k)=pm(k)-steps(k);mp(j)=mp(j)-steps(j);mp(k)=mp(k)+steps(k);
   H(j,k)=(v17_marginal_objective(pp,M,L,train,c)-v17_marginal_objective(pm,M,L,train,c)- ...
    v17_marginal_objective(mp,M,L,train,c)+v17_marginal_objective(mm,M,L,train,c))/(4*steps(j)*steps(k));H(k,j)=H(j,k);
  end
 end
 diagScale=sqrt(max(abs(diag(H)),eps));HS=H./(diagScale*diagScale');eigvals=eig((HS+HS')/2);sv=svd(HS);
 F=struct('names',{names},'rank',sum(sv>c.rankTolerance*max(sv)),'activeParameters',p,'activeMask',true(1,p), ...
  'singularValues',sv,'information',H,'physicsRank',pr,'physicsParameters',numel(physical), ...
  'physicsCorrelations',pc,'scaledConditionNumber',max(sv)/max(min(sv),eps), ...
  'negativeCurvatureDirections',sum(eigvals < -c.rankTolerance*max(abs(eigvals))), ...
  'note','Penalized unit-marginal PROFILE curvature, learned encoder conditioned on; not population Fisher or physical identifiability proof.');
end
I=struct('names',{names},'activeParameters',sum(active),'activeRank',rankJ,'singularValues',ss,'Jacobian',J, ...
 'informationSurrogate',J'*J,'physicsConditionalRank',pr,'physicsCorrelations',pc,'sensitivityCosines',cosine, ...
 'confoundedPairs',cell2table(pairs,'VariableNames',{'parameter1','parameter2','sensitivityCosine'}), ...
 'minimumEmissionRank',erank,'minimumEmissionSingularValue',emin,'rhoRMS',sqrt(mean(rho.^2)),'rhoMaxAbs',max(abs(rho)), ...
 'physicalScoreOverlap',ref.G'*rho/max(numel(rho),1),'unitMeanResidualRMS',sqrt(mean(um.^2)), ...
 'profiles',cell2table(profiles,'VariableNames',{'coordinate','transformedValue','physicalValue','penalizedUnitMarginalNLLPerObservation','exitflag','iterations','gradientNorm'}), ...
 'smoothingSummary',ref,'referencePhysicalOverlap',0,'rankAt1e5',sum(ss>1e-5*max(ss)),'fullInformation',F, ...
 'note','Empirical UNIT-score sensitivity of the failure-time/survival likelihood after emission profiling. Rank is limited by TRAIN unit count; selected encoder conditioned on. Not full Fisher information.');
if M.bound>0,I.referencePhysicalOverlap=M.projection.referenceOrthogonality;end
I.covarianceCoordinates='Standardized B, effective loadings; direct constrained physical log-coordinates';
I.fullCurvatureInterior=interior;
I.marginalProfileConverged=MM.marginalDiagnostic.emissionConverged;
end

function f=v17_marginal_fixed(z,v,other,M,L,train,c)
v(other)=z;f=v17_marginal_objective(v,M,L,train,c);
end

function [w,diagnostic]=v17_l1_least_squares(F,target,bound)
% Convex constrained least squares. Projecting an unconstrained coefficient
% vector ONCE is not this solution when F'F is not proportional to identity.
n=max(1,size(F,1));A=F'*F/n;b=F'*target/n;L=max(norm(A,2),eps);
w=zeros(size(F,2),1);z=w;t=1;gap=Inf;
for it=1:20000
 next=project_l1(z-(A*z-b)/L,bound);g=A*next-b;
 gap=g'*next+bound*norm(g,Inf);
 if gap<1e-11*(1+mean(target.^2)),w=next;break;end
 tt=(1+sqrt(1+4*t^2))/2;z=next+(t-1)/tt*(next-w);w=next;t=tt;
end
diagnostic=struct('iterations',it,'convexDualGap',max(0,gap),'converged',gap<1e-9,'outputL1',sum(abs(w)));
end

function T=v17_capacity_diagnostic(M,units,trainIds,c)
% Synthetic TRAIN diagnostic only; the oracle target never enters learning.
T=table();D=[];U=[];truth=[];
for i=trainIds(:)'
 V=units(i);if ~isfield(V,'truth')||~all(isfield(V.truth,{'D','scenario'})),continue;end
 d=V.truth.D(1:end-1);u=V.u(1:end-1,:);rho=zeros(size(d));
 if ismember(V.truth.scenario,{'fatigue_discrepancy','fatigue_weak_gap','fatigue_combined_mismatch'}),rho=.28*sin(3*d)+.10*d.*tanh(u(:,3));end
 if strcmp(V.truth.scenario,'fatigue_load_exponent'),rho=(V.truth.loadExponent-c.nominalLoadExponent)*log(max(u(:,1),1e-8));end
 D=[D;d];U=[U;u];truth=[truth;rho]; %#ok<AGROW>
end
if isempty(truth),return;end
G=physical_scores(M,D,U,c);protected=G*(pinv(G)*truth);target=truth-protected;
M=project_network(M,c);H=residual_features(M,D,zeros(size(D)),U,c);F=(H-G*M.projection.A)./M.projection.sup;
un=pinv(F)*target;[w,report]=v17_l1_least_squares(F,target,M.bound);
T=table(sqrt(mean(truth.^2)),sqrt(mean(protected.^2)),sqrt(mean(target.^2)),sqrt(mean((F*un-target).^2)), ...
 sqrt(mean((F*w-target).^2)),report.convexDualGap,report.iterations, ...
 'VariableNames',{'trueRhoRMS','protectedComponentRMS','permittedTargetRMS','unconstrainedFeatureErrorRMS', ...
 'boundedConstrainedOptimumErrorRMS','convexDualGap','iterations'});
end

function T=v17_hierarchy_tests(c)
names={};cc=c;cc.parallelMode='off';cc.activeGradientWorkers=0;cc.profileDataSignature='';cc.runtimeCandidateDir='';
cc.trainUnits=3;cc.validationUnits=2;cc.calibrationUnits=10;cc.testUnits=2;
cc.marginalQuadrature=21;cc.marginalEMiterations=100;
[z,w]=v17_normal_nodes(21);assert(abs(sum(w)-1)<1e-14 && abs(w'*z)<1e-13 && abs(w'*(z.^2)-1)<1e-12);
names{end+1}='standard-normal quadrature reproduces normalization, mean and variance';
[gl,gw]=v17_legendre_nodes(17);assert(abs(sum(gw)-2)<1e-13 && abs(gw'*gl)<1e-13 && abs(gw'*(gl.^2)-2/3)<1e-13);
names{end+1}='composite integration rule reproduces constant, linear and quadratic integrals';
U=generate_fleet(cc,'fatigue_matched',918277);train=strip_truth(U(1:3));M=initial_model(train,cc);
M.kind='observed';M.useB=true;M.baselineFixed=false;M.config=cc;M.trainingEta=[-.1;.05;.05];
et=[M.trainingEta-.12 M.trainingEta M.trainingEta+.12];D=v17_eta_trajectories(M,train,et,cc);
for i=1:3,ref=observed_trajectory(M,train(i),et(i,:),cc);assert(max(abs(D{i}-ref),[],'all')<1e-11);end
names{end+1}='unit-by-quadrature batched dynamics agree with independent scalar engine';
% A marginal normal random-intercept model has a known analytic likelihood.
obs=[.2;-.1;.4];sd=.17;noise=.09;ee=sd*z;
conditional=.5*sum(((obs-ee')/noise).^2,1)+numel(obs)*log(noise*sqrt(2*pi));
ll=-log(sum(w'.*exp(-conditional)));C=noise^2*eye(3)+sd^2*ones(3);L=chol(C,'lower');
exact=.5*(norm(L\obs)^2+2*sum(log(diag(L)))+3*log(2*pi));
[zz,ww]=v17_normal_nodes(121);qq=.5*sum(((obs-sd*zz')/noise).^2,1)+3*log(noise*sqrt(2*pi));
fine=-log(sum(ww'.*exp(-qq)));assert(abs(fine-exact)<1e-7 && abs(ll-exact)<.1);
names{end+1}='unit random-effect integration agrees with an analytic Gaussian marginal model';
[x,L]=v17_marginal_encode(M,train,cc,false);assert(all(L.free<7));
names{end+1}='training unit frailties are integrated, absent from optimizer coordinates';
[loss,N,diagnostic]=v17_marginal_profile(M,train,cc);
assert(isfinite(loss) && all(isfinite(diagnostic.marginalUnitNLL)) && all(N.trainingEtaSD>0));
names{end+1}='actual unit-marginal emission profile returns finite likelihood and posterior frailty variance';
assert(all(diff(diagnostic.EMtrace(:,1))<=1e-7));
names{end+1}='emission EM updates do not increase the same marginal penalized objective';
N.config=cc;[v,L]=v17_marginal_encode(N,train,cc,false);[a,A]=v17_marginal_objective(v,N,L,train,cc);[b,B]=v17_marginal_objective(v,N,L,train,cc);
assert(isequaln(a,b) && isequaln(A.C,B.C));names{end+1}='adaptive marginal objective is deterministic for fixed coordinates';
F=[1 0;1 .01;0 1];target=[1;1;-.5];[coef,report]=v17_l1_least_squares(F,target,.4);
old=project_l1(pinv(F)*target,.4);assert(sum(abs(coef))<=.4+1e-12 && norm(F*coef-target)<=norm(F*old-target)+1e-8 && report.convexDualGap<1e-9);
names{end+1}='constrained capacity optimization is feasible and improves over single coefficient projection';
V=U(1);H=causal_prefix(V,8);P=v17_grid_prefix(N,H,cc);V.y(9:end,:)=1e8;V.truth.D(:)=99;
PP=v17_grid_prefix(N,causal_prefix(V,8),cc);assert(isequaln(P,PP));
names{end+1}='hierarchical fit retains fixed-origin future-sensor and truth immunity';
W=generate_fleet(cc,'fatigue_emission_mismatch',918277);assert(isequal(U(2).u,W(2).u) && isequal(U(2).truth.D,W(2).truth.D));
names{end+1}='paired factorial generator preserves later unit identities and operating histories';

% Compare the actual nonlinear hierarchical kernel with an independent dense
% trapezoidal integral, keeping fitted emission coefficients fixed.
quad=cc;quad.marginalQuadrature=41;quad.marginalEMiterations=0;
[~,~,testD]=v17_marginal_profile(N,train(1),quad);
ee=linspace(-cc.unitEffectMax,cc.unitEffectMax,6001)';dd=observed_trajectory(N,train(1),ee,cc);
ll=observed_kalman(N,train(1),dd,cc);
anchor=.5*((dd(end,:)-cc.Dcrit)/cc.terminalDamageTolerance).^2+5*sum((max(dd(1:end-1,:)-cc.Dcrit,0)/cc.terminalDamageTolerance).^2,1);
lp=v17_log_normal(ee,0,N.unitSD)-log(erf(cc.unitEffectMax/(sqrt(2)*N.unitSD)));step=ee(2)-ee(1);lw=lp'-ll-anchor;lw([1 end])=lw([1 end])+log(.5);
mx=max(lw);dense=-mx-log(sum(exp(lw-mx))*step);
assert(abs(dense-testD.marginalUnitNLL)<2e-3,'pi17:quadrature','Nonlinear marginal check difference %.6g',dense-testD.marginalUnitNLL);
names{end+1}='nonlinear marginal observation/anchor kernel agrees with independent dense integration';
% Posterior second moments, rather than squared unit MAPs, enter a population
% variance update. The known Gaussian model supplies an independent identity.
tau=.18;noise=.10;populationVariance=tau^2+noise^2;shrink=tau^2/populationVariance;
posteriorSecondMoment=shrink^2*populationVariance+tau^2*noise^2/populationVariance;
assert(abs(posteriorSecondMoment-tau^2)<1e-14 && shrink^2*populationVariance<tau^2);
names{end+1}='integrating posterior frailty variance avoids the Gaussian plug-in second-moment loss';
context=cc;context.gradientTolerance=1e9;
[CONT,~]=v17_marginal_fit(N,train,context,1,'',false);
[~,continued]=v17_marginal_fit(CONT,train,context,1,'',false);assert(continued.curvatureContinued);
names{end+1}='hierarchical optimizer preserves exact coordinates and curvature across the same objective';
idle=H;idle.u(:,1:2)=0;[~,probe]=v17_rate_probe_filter(N,idle,.2,24,cc,64,9001);
assert(all(abs(probe.filteredD-idle.initialD)<1e-12));
names{end+1}='candidate dynamic log-rate state preserves zero fatigue under idle exposure';

T=table(names',true(numel(names),1),'VariableNames',{'test','passed'});
end

function [Dall,Qall]=v17_eta_trajectories(M,train,eta,c)
% Batched trajectories for all units AND all frailty quadrature nodes.
n=numel(train);q=size(eta,2);K=arrayfun(@(U)numel(U.t),train);
Dall=cell(n,1);Qall=cell(n,1);E=zeros(n,q);d=zeros(n,q);
for i=1:n,Dall{i}=zeros(K(i),q)+train(i).initialD;Qall{i}=zeros(K(i),q);d(i,:)=train(i).initialD;end
for k=1:max(K)
 ids=find(K>=k);N=numel(ids);u=zeros(N,3);t=zeros(N,1);h=t;steps=ones(N,1);
 for j=1:N
  i=ids(j);u(j,:)=train(i).u(max(1,k-1),:);t(j)=train(i).t(max(1,k-1));
  if k>1,dt=train(i).t(k)-train(i).t(k-1);steps(j)=max(1,ceil(dt/c.transitionStepHours));h(j)=dt/steps(j);end
 end
 if k>1
  for step=1:max(steps)
   jj=find(step<=steps);ii=ids(jj);uc=repelem(u(jj,:),q,1);hh=reshape(repelem(h(jj),q),[],1);
   dd=reshape(d(ii,:)',[],1);ee=reshape(E(ii,:)',[],1);et=reshape(eta(ii,:)',[],1);
   if strcmp(M.kind,'pinn')
    time=reshape(repelem(t(jj)+(step-1)*h(jj),q),[],1);[~,ex]=pinn_rate(M,ee,time,uc,et,c);
    rate=pinn_rate(M,ee+.5*hh.*ex,time+.5*hh,uc,et,c);ee=ee+hh.*ex;
   else
    base=physics_rate(M,uc).*exp(et);rate=base.*exp(discrepancy(M,dd,zeros(size(dd)),uc)).*(1+M.a*dd);
    mid=dd+.5*hh.*rate;rate=base.*exp(discrepancy(M,mid,zeros(size(mid)),uc)).*(1+M.a*mid);
   end
   dd=dd+hh.*rate;d(ii,:)=reshape(dd,q,[])';E(ii,:)=reshape(ee,q,[])';
  end
 end
 if strcmp(M.kind,'pinn')
  uu=zeros(N,3);tt=zeros(N,1);for j=1:N,i=ids(j);uu(j,:)=train(i).u(k,:);tt(j)=train(i).t(k);end
  rate=pinn_rate(M,reshape(E(ids,:)',[],1),repelem(tt,q),repelem(uu,q,1),reshape(eta(ids,:)',[],1),c);
  rate=reshape(rate,q,[])';
 else,rate=zeros(N,q);end
 for j=1:N,i=ids(j);Dall{i}(k,:)=d(i,:);Qall{i}(k,:)=rate(j,:);end
end
end

function cache=v17_marginal_covariance(M,train,c,idx,fixed)
context=v17_data_signature(train,c);key=[-13 M.tau M.sigmaB M.sensorSD M.C(:,3)' fixed(:)' idx'];
cache=v17_fast_cache('get',context,key);if ~isempty(cache),return;end
p=size(M.C,1);cache=cell(numel(train),1);
for i=1:numel(train)
 U=train(i);K=numel(U.t);yy=reshape(U.y',[],1);ok=isfinite(yy);
 timeIndex=repelem((1:K)',p);channel=repmat((1:p)',K,1);timeIndex=timeIndex(ok);channel=channel(ok);
 tt=U.t(timeIndex);b=M.C(channel,3);
 C=M.sigmaB^2*exp(-abs(tt-tt')/M.tau).*(b*b')+diag(M.sensorSD(channel).^2);
 if isempty(tt),W=zeros(0);logdet=0;else,L=chol(C,'lower');W=L\eye(numel(tt));logdet=2*sum(log(diag(L)));end
 X=emission_features(zeros(K,1),zeros(K,1),U.u);A=kron(X,eye(p));A=W*A(ok,idx);
 mu=reshape((X*fixed')',[],1);y=W*(yy(ok)-mu(ok));
 cache{i}=struct('W',W,'A0',A,'y',y,'yy',y'*y,'logdet',logdet,'timeIndex',timeIndex,'channel',channel,'n',sum(ok));
end
v17_fast_cache('put',context,key,cache,c.profileCacheMB);
end

function [eta,logWeight,proposal]=v17_marginal_nodes(M,train,c,cache)
% Adaptive composite quadrature integrates the population frailty prior over
% its full bounded support, rather than optimizing unit MAP coordinates.
n=numel(train);mu=M.trainingEta(:);delta=.01;
if isfield(M,'quadratureProposalEta') && numel(M.quadratureProposalEta)==n,mu=M.quadratureProposalEta(:);end
if numel(mu)~=n,mu=zeros(n,1);end
if isfield(M,'quadratureProposalRate') && ~strcmp(M.kind,'pinn')
 mu=mu-log(M.k/M.quadratureProposalRate);
end
for iteration=1:c.marginalRootIterations
 et=[mu-delta mu mu+delta];DD=v17_eta_trajectories(M,train,et,c);
 for i=1:n
  if train(i).failureObserved
   derivative=(DD{i}(end,3)-DD{i}(end,1))/(2*delta);
   correction=(c.Dcrit-DD{i}(end,2))/max(derivative,1e-8);
   mu(i)=max(-c.unitEffectMax+.02,min(c.unitEffectMax-.02,mu(i)+max(-.35,min(.35,correction))));
  end
 end
end
DD=v17_eta_trajectories(M,train,[mu-delta mu mu+delta],c);sd=zeros(n,1);
for i=1:n
 d=DD{i}(:,2);derivative=(DD{i}(:,3)-DD{i}(:,1))/(2*delta);C=cache{i};
 dm=derivative.*(M.C(:,2)'+2*d*M.C(:,7)');dm=reshape(dm',[],1);dy=C.W*dm(sub2ind(size(train(i).y'),C.channel,C.timeIndex));
 pred=emission_features(d,zeros(size(d)),train(i).u)*M.C';pred=reshape(pred',[],1);
 yy=reshape(train(i).y',[],1);ix=sub2ind(size(train(i).y'),C.channel,C.timeIndex);
 residual=C.W*(yy(ix)-pred(ix));score=dy'*residual-mu(i)/M.unitSD^2;
 curvature=dy'*dy+1/M.unitSD^2;
 if train(i).failureObserved
  score=score+(c.Dcrit-d(end))*derivative(end)/c.terminalDamageTolerance^2;
  curvature=curvature+(derivative(end)/c.terminalDamageTolerance)^2;
 end
 mu(i)=max(-c.unitEffectMax+.01,min(c.unitEffectMax-.01,mu(i)+max(-.15,min(.15,score/max(curvature,eps)))));
 sd(i)=max(.003,min(.25,c.quadratureProposalInflation/sqrt(max(curvature,eps))));
end
[z,w]=v17_legendre_nodes(c.marginalQuadrature);Q=numel(z);
eta=zeros(n,3*Q);logWeight=-Inf(n,3*Q);
priorNormalizer=erf(c.unitEffectMax/(sqrt(2)*M.unitSD));
for i=1:n
 % Composite integration covers the ENTIRE bounded frailty support. A dense
 % central interval resolves narrow anchored posteriors, while both tails
 % remain explicit. There is no mixture-proposal under-integration term.
 lo=max(-c.unitEffectMax,mu(i)-4*sd(i));hi=min(c.unitEffectMax,mu(i)+4*sd(i));
 bounds=[-c.unitEffectMax lo hi c.unitEffectMax];
 for interval=1:3
  a=bounds(interval);b=bounds(interval+1);ix=(interval-1)*Q+(1:Q);
  if b-a>eps
   ee=(a+b)/2+(b-a)/2*z;
   eta(i,ix)=ee';logWeight(i,ix)=(log((b-a)/2*w)+v17_log_normal(ee,0,M.unitSD)-log(priorNormalizer))';
  else,eta(i,ix)=mu(i);end
 end
end
proposal=struct('mean',mu,'sd',sd,'nodesPerUnit',3*Q,'family','Adaptive composite Gauss-Legendre, full frailty support');
end

function [loss,M,diagnostic]=v17_marginal_profile(M,train,c)
if isfield(c,'trainingLikelihood') && strcmp(c.trainingLikelihood,'event_time')
 [loss,M,diagnostic]=v17_event_profile(M,train,c);
else
 [loss,M,diagnostic]=v17_anchor_reference_profile(M,train,c);
end
end

function c=v17_covariance_configuration(c,mode)
% Changes address the audited v13 fit, not a search for favorable TEST scores.
c.originalSource=fullfile(fileparts(mfilename('fullpath')),'Reference','BSFD_PI_DSSDM_Hierarchical_v13.m');
c.BtauBounds=[2 200];c.BloadingCoordinateScale=.1;c.BloadingMaximum=5;
c.BstartTauHours=[4 20 100];c.BstartScreenSteps=6;c.BrefineFinalists=2;
c.BrefineSteps=50;c.BrefineCycles=2;c.BboundaryFraction=.005;
c.BgeometryConditionLimit=1e8;c.minimumBSignalToNoise=.02;
c.BgeometryUnits=2;c.BtauProfileFactors=[.5 .8 1 1.25 2];
c.requireJointEncoderStationarity=true;c.encoderSteps=6;
c.optimizerLowerBound=[];c.optimizerUpperBound=[];
c.seed=2026101801;c.startParallelPool=true;c.showFigures=false;
c.parallelMinimumParameters=6;
c.exactTerminalBInterval=true;
c.label='v17 covariance-coordinate development; no superiority presumed';
if ismember(mode,{'confirm','full','benchmark','data'})
 c.seed=2027101801;if ismember(mode,{'full','benchmark'}),c.seed=2028101801;end
 c.BstartScreenSteps=10;c.BrefineSteps=100;c.BrefineCycles=3;
 c.encoderSteps=30;c.BgeometryUnits=3;
 c.label='v17 frozen independent comparative study';
end
if ismember(mode,{'smoke','quick'})
 c.BstartScreenSteps=2;c.BrefineFinalists=1;c.BrefineSteps=4;c.BrefineCycles=1;
 c.encoderSteps=1;c.BgeometryUnits=1;c.startParallelPool=false;
end
c=v17_consolidated_configuration(c,mode);
end

function M=v17_standardize_B(M)
% B is now a UNIT-STATIONARY-VARIANCE OU residual. Its emission loading a
% carries all sensor-scale amplitude. Cov[y(t),y(s)|D,u,eta] is
% exp(-|t-s|/tau)*a*a' + independent measurement covariance.
% This removes the small-sigma/huge-loading representation exposed in v13.
if M.useB
 if ~isfield(M,'standardizedB') || ~M.standardizedB
  M.C(:,3)=M.sigmaB*M.C(:,3);M.sigmaB=1;
 end
else,M.sigmaB=0;M.C(:,3)=0;end
M.standardizedB=true;
M.Bdefinition='Unit-variance zero-mean OU observation residual; a is the effective sensor loading. No unmeasured physical identity asserted.';
end

function [g,n]=v17_coordinate_gradient(fun,x,j,lo,hi,scale)
if nargin<6,scale=1;end
h=scale*2e-5*max(1,abs(x(j)));a=x;b=x;
if x(j)-h>=lo && x(j)+h<=hi
 a(j)=x(j)+h;b(j)=x(j)-h;g=(fun(a)-fun(b))/(2*h);n=2;
elseif hi-x(j)>=x(j)-lo
 h=min(h,(hi-x(j))/2);assert(h>eps,'pi17:bounds','No finite derivative interval');
 a(j)=x(j)+h;b(j)=x(j)+2*h;g=(-3*fun(x)+4*fun(a)-fun(b))/(2*h);n=3;
else
 h=min(h,(x(j)-lo)/2);assert(h>eps,'pi17:bounds','No finite derivative interval');
 a(j)=x(j)-h;b(j)=x(j)-2*h;g=(3*fun(x)-4*fun(a)+fun(b))/(2*h);n=3;
end
end

function [lo,hi]=v17_optimizer_bounds(c,n)
lo=-Inf(n,1);hi=Inf(n,1);
if isfield(c,'optimizerLowerBound') && ~isempty(c.optimizerLowerBound),lo=c.optimizerLowerBound(:);hi=c.optimizerUpperBound(:);end
assert(numel(lo)==n && numel(hi)==n && all(lo<hi),'pi17:bounds','Invalid optimizer bounds');
end

function M=v17_population_initializer(train,c,useB)
% Exact-failure information initializes the TRAIN clock scale only. No
% simulator D/B, no future validation sensor and no validation label enters.
M=initial_model(train,c);M.useB=useB;M.baselineFixed=false;M.config=c;
M.C(:,3)=0;M.sigmaB=0;M.standardizedB=true;M.trainingEta=zeros(numel(train),1);
et=zeros(numel(train),1);
if c.fatigueLinearDamage
 for i=1:numel(train)
  if train(i).failureObserved
   D=observed_trajectory(M,train(i),0,c);et(i)=log(max(c.Dcrit-train(i).initialD,eps)/max(D(end)-train(i).initialD,eps));
  end
 end
 shift=mean(et);M.k=min(c.nominalRate*exp(5),max(c.nominalRate*exp(-5),M.k*exp(shift)));
 M.trainingEta=max(-c.unitEffectMax+.02,min(c.unitEffectMax-.02,et-shift));
 M.unitSD=max(.04,min(.6,sqrt(mean(M.trainingEta.^2))));
end
if ~c.profileQuadraticEmission,M.C(:,7)=0;end
% Honor independently verified operating-reference calibration if supplied.
if all(arrayfun(@(U)isfield(U,'reference') && ~isempty(U.reference),train))
 X=[];Y=[];
 for i=1:numel(train)
  V=train(i).reference;assert(V.healthyVerified,'pi17:baseline','Reference needs independent verification');
  X=[X;ones(numel(V.t),1) log(max(V.u(:,1:2),1e-8)) V.u(:,3)];Y=[Y;V.y]; %#ok<AGROW>
 end
 for j=1:size(Y,2),good=isfinite(Y(:,j));M.C(j,[1 4 5 6])=(X(good,:)\Y(good,j))';end
 M.baselineFixed=true;
end
if useB,M.sigmaB=1;M.C(:,3)=c.BloadingCoordinateScale*ones(size(M.C,1),1);end
end

function M=v17_fit_B_multistart(base,train,val,Q,c,eid)
% All starts and finalist decisions use TRAIN likelihood only. VAL is used
% once for the B/no-B comparison after the population model has been fitted.
seed=base;drop={'fitCandidates','BfitCandidates','marginalContinuation','emissionInitializer','quadratureProposalEta','quadratureProposalRate','marginalOptimization', ...
 'validationScore','validationBestLoss','validationBestIteration','selectedMStep','selectedIteration'};
for j=1:numel(drop),if isfield(seed,drop{j}),seed=rmfield(seed,drop{j});end,end
residuals={};lag=zeros(size(seed.C,1));pairs=0;dt=[];
for i=1:numel(train)
 D=observed_trajectory(seed,train(i),seed.trainingEta(i),c);
 r=train(i).y-emission_features(D,zeros(size(D)),train(i).u)*seed.C';
 for j=1:size(r,2),good=isfinite(r(:,j));r(good,j)=r(good,j)-mean(r(good,j));end
 residuals{i}=r;good=all(isfinite(r(1:end-1,:)),2)&all(isfinite(r(2:end,:)),2); %#ok<AGROW>
 a=r(1:end-1,:);b=r(2:end,:);lag=lag+.5*(a(good,:)'*b(good,:)+b(good,:)'*a(good,:));pairs=pairs+sum(good);
 delta=diff(train(i).t);dt=[dt;delta(good)]; %#ok<AGROW>
end
lag=lag/max(pairs,1);[V,E]=eig((lag+lag')/2);[lambda,ix]=max(diag(E));direction=V(:,ix);
[~,anchor]=max(abs(direction));if direction(anchor)<0,direction=-direction;end
scale=sqrt(max(lambda,c.sensorFloor^2));if isempty(dt),spacing=1;else,spacing=median(dt);end
archive={};rows=cell(0,8);
for start=1:numel(c.BstartTauHours)
 candidate=seed;candidate.useB=true;candidate.standardizedB=true;candidate.sigmaB=1;
 candidate.tau=max(c.BtauBounds(1),min(c.BtauBounds(2),c.BstartTauHours(start)));
 candidate.C(:,3)=direction*scale*exp(min(1,spacing/(2*candidate.tau)));
 r=vertcat(residuals{:});varR=var(r,0,1,'omitnan');
 candidate.sensorSD=sqrt(max(c.sensorFloor^2,min(c.sensorCeiling^2,varR-candidate.C(:,3)'.^2)));
 [candidate,opt,loss]=v17_marginal_fit(candidate,train,c,c.BstartScreenSteps,sprintf('B_start%02d_screen',start),false);
 candidate.validationScore=NaN;archive{start}=struct('model',candidate,'optimizer',opt,'trainLoss',loss); %#ok<AGROW>
 rows(end+1,:)={start,0,loss,opt.gradientNorm,opt.exitflag,candidate.tau,norm(candidate.C(:,3)),false}; %#ok<AGROW>
end
losses=cellfun(@(A)A.trainLoss,archive);[~,order]=sort(losses);finalists=order(1:min(c.BrefineFinalists,numel(order)));
for start=finalists
 candidate=archive{start}.model;
 for cycle=1:c.BrefineCycles
  [candidate,opt,loss]=v17_marginal_fit(candidate,train,c,c.BrefineSteps,sprintf('B_start%02d_refine%02d',start,cycle),false);
  rows(end+1,:)={start,cycle,loss,opt.gradientNorm,opt.exitflag,candidate.tau,norm(candidate.C(:,3)),true}; %#ok<AGROW>
  if v17_converged(opt,c),break;end
 end
 if ~v17_converged(opt,c) && c.populationRecoverySteps>0
  if isfield(candidate,'marginalContinuation'),candidate=rmfield(candidate,'marginalContinuation');end
  [candidate,opt,loss]=v17_marginal_fit(candidate,train,c,c.populationRecoverySteps,sprintf('B_start%02d_TRAIN_recovery',start),false);
  rows(end+1,:)={start,c.BrefineCycles+1,loss,opt.gradientNorm,opt.exitflag,candidate.tau,norm(candidate.C(:,3)),true}; %#ok<AGROW>
 end
 candidate.validationScore=NaN;archive{start}=struct('model',candidate,'optimizer',opt,'trainLoss',loss);
end
scores=cellfun(@(A)A.trainLoss,archive);opts=cellfun(@(A)A.optimizer,archive,'UniformOutput',false);
[chosen,has]=v17_select_checkpoint(scores,opts,c);M=archive{chosen}.model;
M.selectedMStep=archive{chosen}.optimizer;M.selectedIteration=chosen;
M.validationScore=forecast_score(M,val,Q,c,eid);M.validationBestIteration=chosen;M.validationBestLoss=M.validationScore;
M.BstartSelection=cell2table(rows,'VariableNames',{'start','refineCycle','TRAINmarginalLoss','feasibleGradientNorm','exitflag','tau_h','effectiveLoadingNorm','finalistRefinement'});
M.BstartChosen=chosen;M.BstartCriterion='Lowest TRAIN objective among converged starts if any; all starts retained; no VAL/TEST start selection';
archive{chosen}.model.validationScore=M.validationScore;
M.fitCandidates=archive;M.fitTrace=table(chosen,M.profileObjective,-M.profileObjective,M.validationScore,NaN,M.selectedMStep.exitflag,M.selectedMStep.gradientNorm,NaN,NaN,mean(M.sensorSD), ...
 'VariableNames',{'iteration','unitMarginalNLLPerObservation','negativePenalizedMarginalNLLPerObservation','causalValidationLoss','relativeParameterChange','mStepExitflag','mStepGradientNorm','meanESS','etaAcceptance','meanSensorSD'});
M.optimization=struct('status',M.BstartCriterion,'stabilized',has,'selectedIteration',chosen, ...
 'selectedMStepExitflag',M.selectedMStep.exitflag,'lastMStepExitflag',M.selectedMStep.exitflag,'gradientNorm',M.selectedMStep.gradientNorm);
end

function G=v17_covariance_geometry(M,train,c)
% Conditional covariance Fisher geometry, given D/eta/mean. This does NOT
% profile mean, frailty or encoder uncertainty and is not a physical proof.
p=size(M.C,1);J=[];a=M.C(:,3);count=min(numel(train),c.BgeometryUnits);
for i=1:count
 U=train(i);K=numel(U.t);mask=isfinite(reshape(U.y',[],1));channel=repmat((1:p)',K,1);t=repelem(U.t,p);
 channel=channel(mask);t=t(mask);distance=abs(t-t');E=exp(-distance/M.tau);aa=a(channel);
 C=E.*(aa*aa')+diag(M.sensorSD(channel).^2);L=chol(C,'lower');A=zeros(numel(C),1+2*p);
 deriv=E.*(aa*aa').*(distance/M.tau);W=L\deriv/L';A(:,1)=W(:)/sqrt(2);
 for j=1:p
  indicator=double(channel==j);deriv=c.BloadingCoordinateScale*E.*(indicator*aa'+aa*indicator');W=L\deriv/L';A(:,1+j)=W(:)/sqrt(2);
  deriv=diag(2*M.sensorSD(j)^2*indicator);W=L\deriv/L';A(:,1+p+j)=W(:)/sqrt(2);
 end
 J=[J;A]; %#ok<AGROW>
end
norms=sqrt(sum(J.^2,1));scaled=J./max(norms,eps);s=svd(scaled,'econ');rankJ=sum(s>c.rankTolerance*max(s));
condition=max(s)/max(min(s),eps);raw=svd(J,'econ');info=J'*J;
correlations=nan(size(info));if rankJ==size(J,2),V=pinv(info);sd=sqrt(max(diag(V),eps));correlations=V./(sd*sd');end
fraction=min(log(M.tau/c.BtauBounds(1)),log(c.BtauBounds(2)/M.tau))/log(c.BtauBounds(2)/c.BtauBounds(1));
signal=sqrt(mean((a./M.sensorSD').^2));interior=fraction>c.BboundaryFraction;
 off=abs(correlations);off(1:size(off,1)+1:end)=0;maxCorrelation=max(off,[],'all');
 practical=all(isfinite(off),'all') && maxCorrelation<c.maximumBParameterCorrelation;
G=struct('rank',rankJ,'parameters',size(J,2),'scaledConditionNumber',condition, ...
 'minimumSingularValue',min(raw),'singularValues',s,'information',info,'correlations',correlations, ...
 'maximumAbsoluteParameterCorrelation',maxCorrelation,'practicalCovarianceSupport',practical,'tauInterior',interior,'tauLogBoundaryFraction',fraction,'signalToNoiseRMS',signal,'auditedTRAINunits',count, ...
 'localCovarianceSupported',rankJ==size(J,2) && condition<c.BgeometryConditionLimit && interior && signal>c.minimumBSignalToNoise && practical, ...
 'scope','Conditional covariance-only Gaussian Fisher geometry; mean, D/eta and encoder treated as known. Not full population identifiability or B physical identity.');
G.parameterNames=[{'logTau'} arrayfun(@(j)sprintf('effectiveLoading_scaled_%d',j),1:p,'UniformOutput',false) ...
 arrayfun(@(j)sprintf('logMeasurementSD_%d',j),1:p,'UniformOutput',false)];
end

function T=v17_tau_profile(M,train,c)
% Conditional diagnostic: reprofile emission/eta integration, hold all other
% nonlinear parameters fixed. It is not a nuisance-reoptimized confidence set.
tau=unique(min(c.BtauBounds(2),max(c.BtauBounds(1),M.tau*c.BtauProfileFactors)));rows=cell(0,5);
for value=tau
 v17_deadline('check');N=M;N.tau=value;[loss,~,diagnostic]=v17_marginal_profile(N,train,c);
 rows(end+1,:)={value,loss,diagnostic.emissionConverged,diagnostic.emissionStationarity,diagnostic.rawMarginalNLL}; %#ok<AGROW>
end
T=cell2table(rows,'VariableNames',{'tau_h','conditionalPenalizedMarginalLoss','emissionConverged','emissionStationarity','rawMarginalNLL'});
end

function M=v17_joint_stationarity(M,train,c,tag)
if ~strcmp(M.kind,'pinn') && (M.bound<=0 || strcmp(M.residualFamily,'fixed_basis')),return;end
[v,L]=v17_marginal_encode(M,train,c,true);cc=c;cc.optimizerLowerBound=L.lower;cc.optimizerUpperBound=L.upper;cc.optimizerL1Indices=L.l1Indices;cc.optimizerL1Radius=L.l1Radius;
fun=@(z)v17_marginal_objective(z,M,L,train,c);g=v17_fd_gradient(fun,v,cc);pg=v-v17_project_parameters(v-g,cc);
% v17 applies the same declared resolution tolerance as the marginal fit;
% strict stationarity at gradientTolerance is still recorded separately.
M.encoderStationarity=struct('jointFeasibleGradientNorm',norm(pg,Inf),'jointStationary',norm(pg,Inf)<v17_stationarity_tolerance(c), ...
 'strictlyStationary',norm(pg,Inf)<c.gradientTolerance, ...
 'scope','Joint direct-coordinate stationarity at final candidate, including encoder; global optimum and encoder uncertainty not established');
fprintf('  %s final JOINT feasible gradient %.5g, stationary=%d.\n',tag,norm(pg,Inf),M.encoderStationarity.jointStationary);
end

function v17_stage_reporting(stage,e,c,runDir)
% Scientific diagnostics are available immediately after physics/primary,
% even if a later expensive comparator reaches the invocation budget.
file=fullfile(runDir,'stages',sprintf('E%03d_%s.mat',e,stage));S=load(file);
if strcmp(stage,'physics')
 M=S.physics;B=M.BfitCandidates.withB;G=B.covarianceDiagnostic;
 writetable(M.Bselection,fullfile(runDir,sprintf('B_retention_%02d.csv',e)));
 writetable(B.BstartSelection,fullfile(runDir,sprintf('B_TRAIN_start_selection_%02d.csv',e)));
 writetable(B.BtauProfile,fullfile(runDir,sprintf('B_tau_CONDITIONAL_profile_%02d.csv',e)));
 writematrix(G.information,fullfile(runDir,sprintf('B_conditional_covariance_information_%02d.csv',e)));
 writematrix(G.correlations,fullfile(runDir,sprintf('B_conditional_covariance_correlations_%02d.csv',e)));
 fid=fopen(fullfile(runDir,sprintf('B_covariance_diagnostics_%02d.json',e)),'w');fwrite(fid,jsonencode(G),'char');fclose(fid);
 fprintf('\nEARLY B COVARIANCE DIAGNOSTIC: rank %d/%d, scaled condition %.5g, tau interior=%d, signal/noise %.4g.\n',G.rank,G.parameters,G.scaledConditionNumber,G.tauInterior,G.signalToNoiseRMS);
 disp(B.BstartSelection);disp(B.BtauProfile);
 if c.makePlots
  f=new_figure(c,sprintf('E%d B covariance estimation',e));tiledlayout(2,2,'TileSpacing','compact');
  nexttile;plot(B.BtauProfile.tau_h,B.BtauProfile.conditionalPenalizedMarginalLoss,'o-');xline(B.tau,':');xlabel('tau, h');ylabel('Conditional marginal loss');title('Other nonlinear parameters fixed');grid on;
  nexttile;bar([B.C(:,3) B.sensorSD']);xlabel('Observation');ylabel('Sensor-scale amplitude');legend('Effective B loading','Independent noise SD');grid on;
  nexttile;imagesc(G.correlations,[-1 1]);colorbar;title('Conditional covariance parameter correlations');
  nexttile;bar(M.Bselection.gainFromB);yline(0,':');xlabel('Independent VAL unit');ylabel('Paired observation NLL gain');grid on;
  sgtitle(sprintf('B retained %d; predictive support %d; physical identity unestablished',M.Bdecision.retained,M.Bdecision.observationPredictiveSupport));save_plot(f,runDir,sprintf('E%02d_B_covariance_early',e),c);
 end
elseif strcmp(stage,'primary')
 M=S.primary;writetable(M.selection,fullfile(runDir,sprintf('Primary_selection_%02d.csv',e)));disp(M.selection);
 if c.makePlots
  f=new_figure(c,sprintf('E%d primary selection',e));tiledlayout(1,2);
  nexttile;plot(M.selection.bound,M.selection.causalValidationLoss,'o-');xlabel('Allowed log-rate discrepancy');ylabel('VAL squared log-RUL loss');grid on;
  nexttile;errorbar(M.selection.bound,M.selection.pairedUnitGain,M.selection.pairedGainSE,'o');yline(0,':');xlabel('Allowed log-rate discrepancy');ylabel('Paired gain +/- one unit SE');grid on;
  sgtitle(sprintf('Selected bound %.2f; no automatic neural advantage',M.bound));save_plot(f,runDir,sprintf('E%02d_Primary_selection_early',e),c);
 end
end
end

function T=v17_covariance_tests(c)
names={};cc=c;cc.activeGradientWorkers=0;cc.parallelMode='off';cc.runtimeCandidateDir='';cc.runtimeFitLabel='boundary_regression';
cc.optimizerLowerBound=log(2);cc.optimizerUpperBound=log(200);cc.gradientTolerance=2e-6;
% The v13 near-bound tau had an inward log-gradient of 0.0036. Direct
% coordinates must see it, and leave the upper-bound neighborhood.
target=log(18);x=log(198.779);fun=@(z).5*(z-target).^2;
g=v17_fd_gradient(fun,x,cc);assert(abs(g-(x-target))<1e-8 && abs(g)>1);
[z,~,opt]=v17_bfgs(fun,x,40,cc,'');assert(opt.converged && abs(exp(z)-18)<1e-3);
names{end+1}='direct log-coordinate optimizer escapes the v13 near-upper-bound regime';
cc.optimizerLowerBound=0;cc.optimizerUpperBound=1;
f=@(z)v17_feasible_test_objective(z);[z,~,opt]=v17_bfgs(f,.95,30,cc,'');
assert(opt.converged && z==0 && opt.rawGradientNorm>1 && opt.gradientNorm==0);
names{end+1}='boundary finite differences remain feasible and constrained stationarity permits only outward gradient';
M=struct('useB',true,'sigmaB',.09,'C',zeros(3,7));M.C(:,3)=[.25;1;-.25];N=v17_standardize_B(M);
assert(N.sigmaB==1 && norm(N.C(:,3)*N.C(:,3)'-M.sigmaB^2*(M.C(:,3)*M.C(:,3)'),Inf)<1e-14);
names{end+1}='standardized B preserves effective sensor covariance without a loading anchor';
scaled=M;scaled.sigmaB=.0009;scaled.C(:,3)=100*M.C(:,3);S=v17_standardize_B(scaled);
assert(norm(N.C(:,3)-S.C(:,3))<1e-14);
names{end+1}='small-sigma huge-loading representations collapse to identical effective coordinates';
cc.optimizerLowerBound=[];cc.optimizerUpperBound=[];cc.trainUnits=3;cc.validationUnits=2;cc.calibrationUnits=10;cc.testUnits=2;
U=generate_fleet(cc,'fatigue_matched',918288);train=strip_truth(U(1:3));N=v17_population_initializer(train,cc,true);
[v,L]=v17_marginal_encode(N,train,cc,false);assert(numel(L.loading)==3 && ~any(strcmp(L.names,'logBsd')));
[~,P]=v17_marginal_objective(v,N,L,train,cc);assert(P.sigmaB==1 && all(isfinite(P.C(:))));
names{end+1}='actual marginal estimator uses all effective loadings and no B-scale coordinate';
for j=1:numel(v)
 h=1e-6;a=v;b=v;a(j)=min(L.upper(j),v(j)+h);b(j)=max(L.lower(j),v(j)-h);
 assert(all(a>=L.lower & a<=L.upper & b>=L.lower & b<=L.upper));
end
names{end+1}='all direct marginal coordinates carry explicit feasible bounds';
G=v17_covariance_geometry(P,train,cc);assert(isfinite(G.scaledConditionNumber) && G.rank<=G.parameters);
zero=P;zero.C(:,3)=0;G0=v17_covariance_geometry(zero,train,cc);assert(~G0.localCovarianceSupported && G0.rank<G0.parameters);
names{end+1}='zero-amplitude B cannot pass conditional covariance identification';
cc.exactTerminalBInterval=true;dt=v17_B_elapsed_interval(8,100,103.4,cc);
assert(abs(dt-3.4)<1e-12 && v17_B_elapsed_interval(8,100,Inf,cc)==8);
cc.exactTerminalBInterval=false;assert(v17_B_elapsed_interval(8,100,103.4,cc)==8);
names{end+1}='terminal OU evolution uses actual elapsed time; explicit legacy mode preserves v13 data';
T=table(names',true(numel(names),1),'VariableNames',{'test','passed'});
end

function f=v17_feasible_test_objective(z)
assert(z>=0 && z<=1,'pi17:testFeasibility','Objective evaluated outside its bounds');f=(z+1)^2;
end

function elapsed=v17_B_elapsed_interval(nominal,intervalStart,failure,c)
elapsed=nominal;
if c.exactTerminalBInterval && isfinite(failure)
 elapsed=max(0,min(nominal,failure-intervalStart));
end
end

function R=v17_covariance_fit_diagnostic(c,overriddenFields)
% Short mechanistic-estimation diagnostic. No neural/PINN/LSTM training and
% no TEST performance claim. The same production B/no-B estimator is used.
runDir=fullfile(c.outputDir,['run_' datestr(now,'yyyymmdd_HHMMSS_FFF') '_covariance_diagnostic']);
old=rng;restore=onCleanup(@()rng(old)); %#ok<NASGU>
if ~isempty(c.dataFile)
 allow={'dataFile','maxRunSeconds','parallelMode','startParallelPool','maxGradientWorkers','showFigures'};
 assert(all(ismember(overriddenFields,allow)),'pi17:diagnosticResume','Diagnostic resume permits runtime settings only; a changed scientific design needs a new run');
 S=load(c.dataFile,'R');R=S.R;
 assert(strcmp(R.version,'17.2.0') && strcmp(R.sourceSHA256,hash_file([mfilename('fullpath') '.m'])),'pi17:diagnosticResume','Use this exact v17 diagnostic source');
 budget=c.maxRunSeconds;parallel=c.parallelMode;pool=c.startParallelPool;workers=c.maxGradientWorkers;visible=c.showFigures;
 c=R.config;c.maxRunSeconds=budget;c.parallelMode=parallel;c.startParallelPool=pool;c.maxGradientWorkers=workers;c.showFigures=visible;runDir=R.outputDir;
end
if ~isfolder(runDir),mkdir(runDir);end
c.runtimeCandidateDir=fullfile(runDir,'candidates','E001');
diary(fullfile(runDir,'console.txt'));cl=onCleanup(@()diary('off')); %#ok<NASGU>
c=v17_parallel_setup(c);v17_deadline('start',c.maxRunSeconds);v17_fast_cache('reset');v17_score_bank('reset');
R=struct('version','17.2.0','config',c,'sourceSHA256',hash_file([mfilename('fullpath') '.m']), ...
 'outputDir',runDir,'status','running','scope','Synthetic matched covariance estimation only; no comparative TEST RUL evidence');
copyfile([mfilename('fullpath') '.m'],fullfile(runDir,'Source_BSFD_PI_DSSDM_Hierarchical_v17.m'));
v17_save(fullfile(runDir,'CovarianceCheck.mat'),struct('R',R));
try
 units=generate_fleet(c,'fatigue_matched',c.seed+100000);rng(c.seed,'twister');ids=split_units(numel(units),c);
 train=strip_truth(units(ids.train));val=strip_truth(units(ids.validation));Q=fit_duty_model(train);
 stages=fullfile(runDir,'stages');if ~isfolder(stages),mkdir(stages);end
 [ok,S]=v17_stage(stages,1,'physics');
 if ok,M=S.physics;
 else
  fprintf('\nV15 COVARIANCE DIAGNOSTIC: %d TRAIN, %d VAL; TRAIN-only start selection.\n',numel(train),numel(val));
  M=fit_population(train,val,Q,c,1);v17_stage(stages,1,'physics',struct('physics',M,'Q',Q,'ids',ids));
 end
 v17_stage_reporting('physics',1,c,runDir);R.physics=M;B=M.BfitCandidates.withB;
 trueA=c.truthBsd*[.25;1;-.25];
 R.recovery=struct('trueTau_h',c.truthBtau,'estimatedTau_h',B.tau,'trueEffectiveLoading',trueA, ...
  'estimatedEffectiveLoading',B.C(:,3),'effectiveCovarianceRelativeFrobeniusError', ...
  norm(B.C(:,3)*B.C(:,3)'-trueA*trueA','fro')/norm(trueA*trueA','fro'), ...
  'estimatedMeasurementSD',B.sensorSD,'trueMeasurementSD',.045*ones(1,3), ...
  'scope','Post-fit generator diagnostic only; no truth used for fitting/start selection');
 R.status='complete';disp(R.recovery);
catch err
 R.status='error';if strcmp(err.identifier,'pi17:budget'),R.status='paused_budget';end
 R.lastError=struct('identifier',err.identifier,'message',err.message);
 v17_save(fullfile(runDir,'CovarianceCheck.mat'),struct('R',R));
 if ~strcmp(err.identifier,'pi17:budget'),rethrow(err);end
 fprintf('Diagnostic paused. Use RUN_COVARIANCE_DIAGNOSTIC_v17 with dataFile pointing to %s.\n',fullfile(runDir,'CovarianceCheck.mat'));
end
v17_save(fullfile(runDir,'CovarianceCheck.mat'),struct('R',R));
fprintf('Covariance diagnostic status: %s\n%s\n',R.status,runDir);
end

function yes=v17_retained_B_supported(R)
yes=~isempty(R.experiments);
for e=1:numel(R.experiments)
 M=R.experiments{e}.models{4};
 if M.useB,yes=yes && M.Bdecision.comparisonConverged && M.Bdecision.localCovarianceSupported;end
end
end

function [loss,M,diagnostic]=v17_anchor_reference_profile(M,train,c)
% Observations integrate B analytically and eta numerically. Linear emission
% coefficients are fitted by deterministic EM within this SAME marginal
% objective. TRAIN terminal D anchors remain a declared working anchor model,
% not an exact density of continuously observed failure times.
p=size(M.C,1);mask=true(p,7);mask(:,3)=false;
if ~c.profileQuadraticEmission,mask(:,7)=false;M.C(:,7)=0;end
if M.baselineFixed,mask(:,[1 4 5 6])=false;end
idx=find(mask);fixed=M.C;fixed(idx)=0;nf=numel(idx);n=numel(train);
cache=v17_marginal_covariance(M,train,c,idx,fixed);
[eta,lw,proposal]=v17_marginal_nodes(M,train,c,cache);
[DD,QQ]=v17_eta_trajectories(M,train,eta,c);nq=size(eta,2);
G=cell(n,1);rhs=cell(n,1);constant=zeros(n,1);event=zeros(n,nq);count=0;
for i=1:n
 U=train(i);C=cache{i};D=DD{i};A=repmat(C.A0,1,1,nq);
 for channel=1:p
  rr=find(C.channel==channel);d=D(C.timeIndex(rr),:);
  col=find(idx==sub2ind([p 7],channel,2));if ~isempty(col),A(:,col,:)=reshape(C.W(:,rr)*d,C.n,1,nq);end
  col=find(idx==sub2ind([p 7],channel,7));if ~isempty(col),A(:,col,:)=reshape(C.W(:,rr)*(d.^2),C.n,1,nq);end
 end
 G{i}=pagemtimes(pagetranspose(A),A);rhs{i}=reshape(pagemtimes(pagetranspose(A),C.y),nf,nq);
 constant(i)=.5*(C.yy+C.logdet+C.n*log(2*pi));count=count+C.n;
 good=isfinite(U.inspection);
 if any(good),event(i,:)=event(i,:)+.5*sum(((D(good,:)-U.inspection(good))/c.inspectionSD).^2,1);count=count+sum(good);end
 if U.failureObserved
  event(i,:)=event(i,:)+.5*((D(end,:)-c.Dcrit)/c.terminalDamageTolerance).^2+ ...
   5*sum((max(D(1:end-1,:)-c.Dcrit,0)/c.terminalDamageTolerance).^2,1);count=count+1;
 end
end
weights=ones(p,7);weights(:,1)=1e-6;weights(:,7)=c.quadraticEmissionRidgeMultiplier;
penalty=c.emissionRidge*diag(weights(idx));coef=M.C(idx);trace=[];converged=false;it=0;
for it=1:c.marginalEMiterations
 [unitNLL,posterior]=e_step(coef);normal=penalty;right=zeros(nf,1);
 for i=1:n
  normal=normal+sum(G{i}.*reshape(posterior(i,:),1,1,nq),3);right=right+rhs{i}*posterior(i,:)';
 end
 next=(normal+1e-12*eye(nf))\right;
 before=sum(unitNLL)+.5*coef'*penalty*coef;
 change=norm(next-coef,Inf);coef=next;trace(end+1,:)=[before change]; %#ok<AGROW>
 if change<c.marginalEMtolerance*(1+norm(coef,Inf)),converged=true;break;end
end
[unitNLL,posterior]=e_step(coef);M.C(idx)=coef;
M.trainingEta=sum(eta.*posterior,2);M.trainingEtaSD=sqrt(sum((eta-M.trainingEta).^2.*posterior,2));
M.quadratureReferenceRate=M.k;
M.trainingDMean=cell(n,1);M.trainingDVariance=cell(n,1);
for i=1:n,M.trainingDMean{i}=DD{i}*posterior(i,:)';M.trainingDVariance{i}=sum((DD{i}-M.trainingDMean{i}).^2.*posterior(i,:),2);end
normal=penalty;right=zeros(nf,1);
for i=1:n,normal=normal+sum(G{i}.*reshape(posterior(i,:),1,1,nq),3);right=right+rhs{i}*posterior(i,:)';end
stationarity=norm(normal*coef-right,Inf)/max(count,1);
converged=converged || stationarity<10*c.marginalEMtolerance;
prior=.5*(log(M.k/c.nominalRate)/c.rateLogPriorSD)^2+ ...
 .5*((M.p-c.nominalLoadExponent)/c.exponentPriorSD)^2+.5*((M.betaT-c.nominalTempCoefficient)/c.tempPriorSD)^2+ ...
 .5*(log(M.unitSD/c.unitSD)/c.unitHyperLogSD)^2+.5*sum((log(M.sensorSD/c.sensorSD)/c.measurementLogPriorSD).^2);
raw=sum(unitNLL);loss=(raw+.5*coef'*penalty*coef+prior)/max(count,1);
if strcmp(M.kind,'pinn')
 ode=[];
 for i=1:n
  target=physics_rate(M,train(i).u).*exp(eta(i,:)).*(1+M.a*DD{i});
  rr=log(max(QQ{i},realmin)./max(target,realmin));ode=[ode;sum(rr.^2.*posterior(i,:),2)]; %#ok<AGROW>
 end
 loss=loss+c.pinnPhysicsWeight*mean(ode)+c.networkPenalty*sum(pack_network(M.pinnNN).^2);
elseif M.bound>0
 r=discrepancy(M,M.reference.D,zeros(size(M.reference.D)),M.reference.u);um=accumarray(M.reference.unit,r,[],@mean);
 loss=loss+c.residualPenalty*mean(r.^2)+c.unitResidualPenalty*mean(um.^2)+c.networkPenalty*sum(pack_network(M.nn).^2);
end
diagnostic=struct('marginalUnitNLL',unitNLL,'etaMean',M.trainingEta,'etaSD',M.trainingEtaSD, ...
 'observationCount',count,'emissionConverged',converged,'emissionStationarity',stationarity, ...
 'EMiterations',size(trace,1),'EMtrace',trace,'rawMarginalNLL',raw,'proposal',proposal,'quadratureNodes',nq);
M.marginalDiagnostic=diagnostic;M.marginalTraining=true;
 function [nll,post]=e_step(b)
  post=zeros(n,nq);nll=zeros(n,1);
  for unit=1:n
   quad=reshape(pagemtimes(reshape(b,1,nf),pagemtimes(G{unit},b)),1,nq);
   conditional=constant(unit)-b'*rhs{unit}+.5*quad+event(unit,:);
   logp=lw(unit,:)-conditional;mx=max(logp);assert(isfinite(mx),'pi17:quadrature','No finite marginal mass');
   ww=exp(logp-mx);zz=sum(ww);post(unit,:)=ww/zz;nll(unit)=-mx-log(zz);
  end
 end
end


function [T,F,A]=v17_predict_policy_group(units,ids,models,names,Q,c,eid,evidence,diagnose)
old=rng;cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
rows=cell(0,38);fr=cell(0,12);ar=cell(0,9);
for j=1:numel(ids)
 U=units(ids(j));[ks,zs]=origin_nodes(U,c);
 for iz=1:numel(ks)
  z=zs(iz);H=causal_prefix(U,ks(iz));seed=c.seed+eid*1000000+ids(j)*1000+z*10;post=cell(1,numel(models));
  for pol=1:numel(c.policies)
   R=c.forecastReplicates;if strcmp(c.policies{pol},'planned'),R=1;end
   banks=cell(1,R);
   for r=1:R,rng(seed+pol+10000*(r-1),'twister');banks{r}=future_bank(H,c.policies{pol},Q,c,c.forecastPaths);end
   for m=1:numel(models)
    active=v17_for_policy(models{m},c.policies{pol});rng(seed,'twister');
    post{m}=model_posterior(active,H,c);
    if diagnose && ~strcmp(active.kind,'lstm')
     P=post{m};fr(end+1,:)={eid,U.id,names{m},z,H.t(end),min(P.ESS),mean(P.ESS),P.etaAcceptance,P.distinctRateParticles,min(P.eventMass),sum(P.D>=c.Dcrit),P.cdfUnderflowParticles}; %#ok<AGROW>
    end
    pred=NaN;lo=NaN;hi=NaN;cp=NaN;d=NaN;b=NaN;rr=NaN;rm=NaN;os=NaN;safe=NaN;p24=NaN;p48=NaN;dsd=NaN;esd=NaN;ratio=NaN;warn=false;gc=NaN;gp=NaN;mc=NaN;
    status='unavailable';
    if active.available
     [samples,fi]=v17_forecast_distribution(active,H,post{m},banks,c,seed+pol+100);
     pred=v17_quantile(samples,fi,.5);lo=v17_quantile(samples,fi,c.intervalAlpha/2);hi=v17_quantile(samples,fi,1-c.intervalAlpha/2);
     safe=v17_quantile(samples,fi,c.conservativeQuantile);p24=sum(fi.sampleWeights(samples<=24));p48=sum(fi.sampleWeights(samples<=48));
     cp=sum(fi.sampleWeights(isinf(samples)));mc=fi.replicateMedianSD_h;
     if strcmp(active.kind,'lstm'),status='LSTM conditional duty spread; raw event probabilities not calibrated';
     else
      P=post{m};d=P.weights'*P.D;b=P.weights'*P.B;
      dsd=sqrt(max(0,P.weights'*(P.D-d).^2));em=P.weights'*P.eta;esd=sqrt(max(0,P.weights'*(P.eta-em).^2));
      ratio=dsd/max(c.Dcrit-d,eps);warn=ratio>=c.posteriorInformationWarningRatio;
      if isfield(P,'gridConverged'),gc=P.gridConverged;gp=P.gridPointsUsed;end
      rr=fi.rhoRMS;rm=fi.rhoMaxAbs;os=fi.outOfSupportFraction;status='median first passage; conditional population parameters';
      if isfield(active,'populationMembers'),status='median first passage; unit-bootstrap parameter mixture';end
      if isinf(pred),status='right_censored_median';end
     end
     if m==1 && diagnose
      off=v17_disable_future_residual(active);[ss,ii]=v17_forecast_distribution(off,H,post{1},banks,c,seed+pol+100);
      offPred=v17_quantile(ss,ii,.5);truth=NaN;if U.failureObserved,truth=U.failureTime-H.t(end);end
      ar(end+1,:)={eid,U.id,c.policies{pol},z,H.t(end),truth,pred,offPred,pred-offPred}; %#ok<AGROW>
     end
    end
    truth=NaN;fraction=NaN;if U.failureObserved,truth=U.failureTime-H.t(end);fraction=H.t(end)/U.failureTime;end
    kappa=0;if isfield(active,'processKappa'),kappa=active.processKappa;end
    stackWeight=NaN;if isfield(active,'stackWeight'),stackWeight=active.stackWeight;end
    if isfield(active,'stackWeight') && active.available && ~isinf(pred),status=[status sprintf('; linear pool %.2f discrepancy/%.2f physics',stackWeight,1-stackWeight)];end
    rows(end+1,:)={eid,evidence,U.id,names{m},c.policies{pol},z,H.t(end),fraction,truth,pred,lo,hi,NaN,NaN,cp,d,b,status,active.available,rr,rm,os, ...
     safe,p24,p48,dsd,esd,ratio,warn,gc,gp,R,mc,v17_model_family(active),v17_model_bound(active),v17_population_count(active),kappa,stackWeight}; %#ok<AGROW>
   end
  end
 end
 fprintf('  Forecasted %d/%d units, %d prefixes, %d duty policies; uncertainty warnings retained.\n',j,numel(ids),numel(ks),numel(c.policies));
end

T=cell2table(rows,'VariableNames',{'experiment','evidence','unit','method','policy','originIndex','origin_h','lifeFraction','trueRUL_h','predictedRUL_h', ...
 'rawLower_h','rawUpper_h','lower_h','upper_h','censoredPathFraction','estimatedD','estimatedB','status','available','forecastRhoRMS','forecastRhoMaxAbs','residualOutOfSupportFraction', ...
 'conservativeRUL_h','rawFailureProbability24h','rawFailureProbability48h','estimatedDSD','estimatedEtaSD','damageUncertaintyToMargin','originDamageUncertain','posteriorGridConverged','posteriorGridPoints','dutyReplicates','replicateMedianSD_h','selectedFamily','selectedResidualBound','populationMembers','processKappa_h','stackDiscrepancyWeight'});
F=cell2table(fr,'VariableNames',{'experiment','unit','method','originIndex','origin_h','minimumESS','meanESS','etaAcceptance','distinctEtaParticles','minimumEventMass','liveFailedParticles','CDFunderflowParticles'});
A=cell2table(ar,'VariableNames',{'experiment','unit','policy','originIndex','origin_h','trueRUL_h','residualOnRUL_h','residualOffRUL_h','difference_h'});
end

function [loss,M,diagnostic]=v17_event_profile(M,train,c)
% Proper joint p(y, exact failure time) or p(y, survival to censoring).
% For exact failures the monotone clock identifies eta(Tf); its density is
% p_eta(eta*) * Ddot(Tf,eta*) / dD(Tf,eta*)/deta. No terminal-D penalty.
% D and eta are still inferred from PAST observations alone at forecast time.
p=size(M.C,1);mask=true(p,7);mask(:,3)=false;
if ~c.profileQuadraticEmission,mask(:,7)=false;M.C(:,7)=0;end
if M.baselineFixed,mask(:,[1 4 5 6])=false;end
idx=find(mask);fixed=M.C;fixed(idx)=0;nf=numel(idx);n=numel(train);
cache=v17_marginal_covariance(M,train,c,idx,fixed);
G=cell(n,1);rhs=cell(n,1);constant=zeros(n,1);weights=cell(n,1);eta=cell(n,1);DD=cell(n,1);QQ=DD;
count=0;failed=false;rootError=zeros(n,1);eventDerivative=zeros(n,1);eventLogJacobian=nan(n,1);
batch=[];
if ~strcmp(M.kind,'pinn') && all([train.failureObserved]) && n>1
 batch=v17_failure_clocks_batch(M,train,c);
end
for i=1:n
 U=train(i);C=cache{i};
 if U.failureObserved
  assert(abs(U.t(end)-U.failureTime)<1e-7*max(1,U.failureTime),'pi17:eventTime','Exact-failure TRAIN observations must end at the independently defined failure time.');
  if isempty(batch),[ee,D,q,speed,sensitivity,errorValue,valid]=v17_failure_clock(M,U,c);
  else,Ai=batch{i};ee=Ai.eta;D=Ai.D;q=[];speed=Ai.speed;sensitivity=Ai.sensitivity;errorValue=Ai.error;valid=Ai.valid;end
  rootError(i)=errorValue;eventDerivative(i)=sensitivity;
  if ~valid,failed=true;break;end
  eta{i}=ee;DD{i}=D;QQ{i}=q;
  eventLogJacobian(i)=log(max(speed,realmin))-log(max(sensitivity,realmin));
  weights{i}=v17_eta_logprior(ee,M,c)+eventLogJacobian(i);
 else
  % Integrate the original population prior over live clocks. Its mass is
  % NOT renormalized to survival; that mass is the censoring likelihood.
  [ee,D,q,logw]=v17_censored_clock_nodes(M,U,c);eta{i}=ee;DD{i}=D;QQ{i}=q;weights{i}=logw;
 end
 if ~any(isfinite(weights{i})),failed=true;break;end
 D=DD{i};nq=numel(eta{i});A=repmat(C.A0,1,1,nq);
 for channel=1:p
  rr=find(C.channel==channel);d=D(C.timeIndex(rr),:);
  col=find(idx==sub2ind([p 7],channel,2));if ~isempty(col),A(:,col,:)=reshape(C.W(:,rr)*d,C.n,1,nq);end
  col=find(idx==sub2ind([p 7],channel,7));if ~isempty(col),A(:,col,:)=reshape(C.W(:,rr)*(d.^2),C.n,1,nq);end
 end
 G{i}=pagemtimes(pagetranspose(A),A);rhs{i}=reshape(pagemtimes(pagetranspose(A),C.y),nf,nq);
 constant(i)=.5*(C.yy+C.logdet+C.n*log(2*pi));count=count+C.n+1;
 good=isfinite(U.inspection);
 if any(good),weights{i}=weights{i}-.5*sum(((D(good,:)-U.inspection(good))/c.inspectionSD).^2,1);count=count+sum(good);end
end
if failed
 loss=1e12+1e6*sum(rootError.^2);diagnostic=struct('emissionConverged',false,'emissionStationarity',Inf, ...
 'marginalUnitNLL',inf(n,1),'etaMean',nan(n,1),'etaSD',nan(n,1),'observationCount',count, ...
 'EMiterations',0,'EMtrace',[],'rawMarginalNLL',Inf,'proposal','Infeasible failure clock', ...
 'quadratureNodes',0,'exactFailureUnits',sum([train.failureObserved]),'censoredUnits',sum(~[train.failureObserved]), ...
 'maximumFailureClockError',max(rootError),'minimumFailureClockSensitivity',NaN, ...
 'terminalDamageAnchorUsed',false,'trainingLikelihood','event_time');
 M.marginalDiagnostic=diagnostic;return;
end
w=ones(p,7);w(:,1)=1e-6;w(:,7)=c.quadraticEmissionRidgeMultiplier;penalty=c.emissionRidge*diag(w(idx));
coef=M.C(idx);single=all(cellfun(@numel,eta)==1);
if single && c.marginalEMiterations>0
 normal=penalty;right=zeros(nf,1);
 for i=1:n,normal=normal+G{i};right=right+rhs{i};end
 coef=v17_psd_solve(normal,right);iterations=1;trace=[];
else
 [coef,iterations,trace]=v17_inner_profile(coef,G,rhs,constant,weights,penalty,count,c);
end
[value,gradient,~,unitNLL,post]=v17_linear_mixture(coef,G,rhs,constant,weights,penalty);
stationarity=norm(gradient,Inf)/max(count,1);converged=stationarity<c.innerProfileGradientTolerance;
M.C(idx)=coef;M.trainingEta=zeros(n,1);M.trainingEtaSD=zeros(n,1);M.trainingDMean=cell(n,1);M.trainingDVariance=cell(n,1);
for i=1:n
 M.trainingEta(i)=post{i}*eta{i}';M.trainingEtaSD(i)=sqrt(post{i}*((eta{i}-M.trainingEta(i)).^2)');
 M.trainingDMean{i}=DD{i}*post{i}';M.trainingDVariance{i}=sum((DD{i}-M.trainingDMean{i}).^2.*post{i},2);
end
prior=.5*(log(M.k/c.nominalRate)/c.rateLogPriorSD)^2+.5*((M.p-c.nominalLoadExponent)/c.exponentPriorSD)^2+ ...
 .5*((M.betaT-c.nominalTempCoefficient)/c.tempPriorSD)^2+.5*(log(M.unitSD/c.unitSD)/c.unitHyperLogSD)^2+ ...
 .5*sum((log(M.sensorSD/c.sensorSD)/c.measurementLogPriorSD).^2);
loss=(value+prior)/max(count,1);
if strcmp(M.kind,'pinn')
 ode=[];
 for i=1:n
  target=physics_rate(M,train(i).u).*exp(eta{i}).*(1+M.a*DD{i});
  good=QQ{i}>0 & target>0;rr=zeros(size(target));rr(good)=log(QQ{i}(good)./target(good));
  ode=[ode;sum(rr.^2.*post{i},2)]; %#ok<AGROW>
 end
 loss=loss+c.pinnPhysicsWeight*mean(ode)+c.networkPenalty*sum(pack_network(M.pinnNN).^2);
elseif M.bound>0
 r=discrepancy(M,M.reference.D,zeros(size(M.reference.D)),M.reference.u);um=accumarray(M.reference.unit,r,[],@mean);
 loss=loss+c.residualPenalty*mean(r.^2)+c.unitResidualPenalty*mean(um.^2)+c.networkPenalty*sum(pack_network(M.nn).^2);
end
diagnostic=struct('marginalUnitNLL',unitNLL,'etaMean',M.trainingEta,'etaSD',M.trainingEtaSD, ...
 'observationCount',count,'emissionConverged',converged,'emissionStationarity',stationarity,'EMiterations',iterations, ...
 'EMtrace',trace,'rawMarginalNLL',sum(unitNLL),'proposal','Exact failure-clock change of variables; proper survival integration for right censoring', ...
 'quadratureNodes',max(cellfun(@numel,eta)),'exactFailureUnits',sum([train.failureObserved]), ...
 'censoredUnits',sum(~[train.failureObserved]),'maximumFailureClockError',max(rootError), ...
 'minimumFailureClockSensitivity',min(eventDerivative([train.failureObserved])),'eventLogJacobian',eventLogJacobian, ...
 'terminalDamageAnchorUsed',false,'trainingLikelihood','event_time');
M.marginalDiagnostic=diagnostic;M.marginalTraining=true;M.trainingLikelihood='event_time';
end

function x=v17_psd_solve(A,b)
% Column scaling avoids a numerically weak quadratic-emission normal system.
s=sqrt(max(diag(A),eps));H=A./(s*s');right=b./s;
[L,flag]=chol((H+H')/2,'lower');
if flag==0,x=(L'\(L\right))./s;else,x=(pinv(H,1e-12)*right)./s;end
end

function [coef,it,trace]=v17_inner_profile(coef,G,rhs,constant,weight,penalty,count,c)
% Exact observed-mixture gradient/Hessian, used when censored clocks leave
% latent eta. Modified Newton plus Armijo; no silent fixed-iteration EM fit.
trace=zeros(0,3);it=0;if c.marginalEMiterations==0,return;end
for it=1:c.innerProfileMaximumIterations
 [f,g,H]=v17_linear_mixture(coef,G,rhs,constant,weight,penalty);
 if norm(g,Inf)/max(count,1)<c.innerProfileGradientTolerance,break;end
 scale=sqrt(max(abs(diag(H)),1e-7));S=(H+H')./(2*(scale*scale'));ev=min(eig(S));
 shift=max(1e-7,-ev+1e-4);direction=-((S+shift*eye(numel(g)))\(g./scale))./scale;
 if g'*direction>=0 || any(~isfinite(direction)),direction=-g./max(abs(diag(H)),1);end
 accepted=false;
 for j=0:25
  trial=coef+2^-j*direction;ff=v17_linear_mixture(trial,G,rhs,constant,weight,penalty);
  if ff<=f+1e-4*2^-j*(g'*direction),coef=trial;accepted=true;break;end
 end
 trace(end+1,:)=[f norm(g,Inf)/max(count,1) accepted]; %#ok<AGROW>
 if ~accepted,break;end
end
end

function [value,g,H,nll,post]=v17_linear_mixture(b,G,rhs,constant,logw,penalty)
n=numel(G);p=numel(b);value=.5*b'*penalty*b;g=penalty*b;H=penalty;nll=zeros(n,1);post=cell(n,1);
for i=1:n
 nq=size(rhs{i},2);Gb=reshape(pagemtimes(G{i},b),p,nq);
 conditional=constant(i)-b'*rhs{i}+.5*sum(b.*Gb,1);lp=logw{i}-conditional;
 mx=max(lp);assert(isfinite(mx),'pi17:eventLikelihood','No finite failure/survival likelihood mass');
 zz=mx+log(sum(exp(lp-mx)));ww=exp(lp-zz);post{i}=ww;nll(i)=-zz;value=value+nll(i);
 if nargout>1
  score=Gb-rhs{i};meanScore=score*ww';g=g+meanScore;
  H=H+sum(G{i}.*reshape(ww,1,1,nq),3)-(score.*ww)*score'+meanScore*meanScore';
 end
end
end

function logp=v17_eta_logprior(eta,M,c)
normalizer=erf(c.unitEffectMax/(sqrt(2)*M.unitSD));
logp=-.5*(eta/M.unitSD).^2-log(M.unitSD)-.5*log(2*pi)-log(normalizer);
logp(abs(eta)>c.unitEffectMax)=-Inf;
end

function [eta,D,q,terminalRate,sensitivity,errorValue,valid]=v17_failure_clock(M,U,c)
if strcmp(M.kind,'pinn') && (~isfield(c,'fastPinnClock') || c.fastPinnClock)
 [eta,D,q,terminalRate,sensitivity,errorValue,valid]=v17_direct_pinn_clock(M,U,c);return;
end
% Unique clock inversion for the scalar irreversible transition. The PINN
% uses a population exposure clock independent of eta, preserving uniqueness.
bare=physics_rate(M,U.u(1:end-1,:));exposure=sum(diff(U.t).*bare);
eta=log(max(c.Dcrit-U.initialD,eps)/max(exposure,realmin));eta=max(-c.unitEffectMax,min(c.unitEffectMax,eta));
lo=-c.unitEffectMax;hi=c.unitEffectMax;
for iteration=1:c.failureRootMaximumIterations
 [D,q,S]=v17_event_trajectory(M,U,eta,c);errorValue=D(end)-c.Dcrit;sensitivity=S(end);
 if abs(errorValue)<c.failureRootTolerance,break;end
 if errorValue>0,hi=eta;else,lo=eta;end
 proposed=eta-errorValue/max(sensitivity,eps);
 if ~isfinite(proposed) || proposed<=lo || proposed>=hi,proposed=(lo+hi)/2;end
 if abs(proposed-eta)<1e-13,break;end
 eta=proposed;
end
[D,q,S]=v17_event_trajectory(M,U,eta,c);errorValue=D(end)-c.Dcrit;sensitivity=S(end);
valid=abs(errorValue)<20*c.failureRootTolerance && sensitivity>0 && abs(eta)<c.unitEffectMax;
if strcmp(M.kind,'pinn')
 [~,~,E]=pinn_trajectory(M,U,eta,c);
 [terminalRate,~]=pinn_rate(M,E(end),U.t(end),U.u(max(1,end-1),:),eta,c);
else
 u=U.u(max(1,end-1),:);terminalRate=physics_rate(M,u)*exp(eta+discrepancy(M,c.Dcrit,0,u))*(1+M.a*c.Dcrit);
end
end

function [eta,D,q,logw]=v17_censored_clock_nodes(M,U,c)
[ends,~]=v17_event_trajectory(M,U,[-c.unitEffectMax c.unitEffectMax],c);hi=c.unitEffectMax;
if ends(end,1)>=c.Dcrit
 eta=-c.unitEffectMax;[D,q]=v17_event_trajectory(M,U,eta,c);logw=-Inf;return;
elseif ends(end,2)>=c.Dcrit
 V=U;V.failureObserved=true;V.failureTime=U.t(end);[hi,~,~,~,~,~,ok]=v17_failure_clock(M,V,c);
 assert(ok,'pi17:censorClock','Could not invert the censoring exposure clock');
end
[x,w]=v17_legendre_nodes(c.marginalQuadrature);lo=-c.unitEffectMax;
eta=(lo+hi)/2+(hi-lo)/2*x';logw=log((hi-lo)/2*w')+v17_eta_logprior(eta,M,c);
[D,q]=v17_event_trajectory(M,U,eta,c);
end

function [D,q,S]=v17_event_trajectory(M,H,eta,c)
eta=eta(:);N=numel(eta);K=numel(H.t);
if strcmp(M.kind,'pinn')
 [D,q]=pinn_trajectory(M,H,eta,c);S=D-H.initialD;return;
end
if M.bound==0 && M.a==0
 q=physics_rate(M,H.u)*exp(eta)';D=H.initialD+[zeros(1,N);cumsum(diff(H.t).*q(1:end-1,:),1)];S=D-H.initialD;return;
end
D=zeros(K,N)+H.initialD;S=zeros(K,N);q=zeros(K,N);
for k=2:K
 dt=H.t(k)-H.t(k-1);ns=max(1,ceil(dt/c.transitionStepHours));h=dt/ns;
 d=D(k-1,:)';s=S(k-1,:)';u=repmat(H.u(k-1,:),N,1);base=physics_rate(M,u).*exp(eta);
 for j=1:ns
  [rho,derivative]=v17_damage_discrepancy_sensitivity(M,d,u,c);r=base.*exp(rho).*(1+M.a*d);
  dr=r.*(derivative+M.a./(1+M.a*d));mid=d+.5*h*r;smid=s+.5*h*(r+dr.*s);
  [rho,derivative]=v17_damage_discrepancy_sensitivity(M,mid,u,c);rm=base.*exp(rho).*(1+M.a*mid);
  drm=rm.*(derivative+M.a./(1+M.a*mid));d=d+h*rm;s=s+h*(rm+drm.*smid);
 end
 D(k,:)=d';S(k,:)=s';
end
d=D(:);u=repmat(H.u,N,1);ee=repelem(eta,K);ee=ee(:);q=reshape(physics_rate(M,u).*exp(ee+discrepancy(M,d,zeros(size(d)),u)).*(1+M.a*d),K,N);
end

function [rho,derivative]=v17_damage_discrepancy_sensitivity(M,D,u,c)
rho=zeros(size(D));derivative=zeros(size(D));if M.bound==0,return;end
outside=any(u<M.projection.lo | u>M.projection.hi,2);u=min(M.projection.hi,max(M.projection.lo,u));
d=max(0,min(1,D/c.Dcrit));active=D>=0 & D<=c.Dcrit;
tl=tanh(log(max(u(:,1),1e-8))/c.loadFeatureScale);ts=tanh(log(max(u(:,2),1e-8))/c.speedFeatureScale);tt=tanh(u(:,3)/c.temperatureFeatureScale);
rbf=isfield(M,'residualFamily') && strcmp(M.residualFamily,'fixed_basis') && isfield(c,'basisFamily') && strcmp(c.basisFamily,'rbf');
if rbf
 [H,F]=v17_rbf_basis(D,u,c,numel(M.nn.w));
elseif isfield(M,'residualFamily') && strcmp(M.residualFamily,'fixed_basis')
 F=[pi*cos(pi*d) zeros(size(d)) tl ts 2*ones(size(d))]/c.Dcrit;
 H=[sin(pi*d) tt d.*tl d.*ts 2*d-1];
 for j=6:numel(M.nn.w),F(:,j)=j*pi*cos(j*pi*d)/c.Dcrit;H(:,j)=sin(j*pi*d);end
 F=F(:,1:numel(M.nn.w));H=H(:,1:numel(M.nn.w));
else
 d=D/c.Dcrit;
 if v17_flag(c,'residualOperatingMain'),Z=[2*d-1 2*d.^2-1 tl ts tt];Zp=[2*ones(size(d)) 4*d zeros(size(d)) zeros(size(d)) zeros(size(d))]/c.Dcrit;
 else,Z=[2*d-1 2*d.^2-1 d.*tl d.*ts tt];Zp=[2*ones(size(d)) 4*d tl ts zeros(size(d))]/c.Dcrit;end
 N=M.nn;h1=tanh(Z*N.W1'+N.b1');dh1=(Zp*N.W1').*(1-h1.^2);
 h2=tanh(h1*N.W2'+N.b2');H=h2;F=(dh1*N.W2').*(1-h2.^2);
 if numel(N.w)==size(N.W2,1)+3
  if v17_flag(c,'smoothDamageFeatures')
   t=tanh(2*d-1);dt=2*(1-t.^2)/c.Dcrit;F=[F dt 4*t.*dt (1-tanh(d).^2).*tt/c.Dcrit];
   H=[H t 2*t.^2-1 tanh(d).*tt];
  else
   dd=max(0,min(1,d));F=[F (2*ones(size(d))/c.Dcrit).*active (8*(2*dd-1)/c.Dcrit).*active (tt/c.Dcrit).*active];
   H=[H 2*dd-1 2*(2*dd-1).^2-1 dd.*tt];
  end
 end
end
if isfield(M,'residualFamily') && strcmp(M.residualFamily,'fixed_basis') && ~rbf,F=F.*active;end
Gprime=zeros(numel(D),size(M.projection.A,1));columns=score_columns(c);
if any(columns==5),Gprime(:,columns==5)=active./(1+M.a*D).^2;end
derivative=((F-Gprime*M.projection.A)./M.projection.sup)*M.nn.w;
G=physical_scores(M,D,u,c);rho=((H-G*M.projection.A)./M.projection.sup)*M.nn.w;
rho(outside)=0;derivative(outside)=0;
end

function batch=v17_failure_clocks_batch(M,units,c)
% Same midpoint law and per-unit time steps as the scalar reference. Only
% independent units are vectorized; no statistical approximation is added.
n=numel(units);K=max(arrayfun(@(U)numel(U.t),units));dt=zeros(K-1,n);u=zeros(K-1,n,3);D0=zeros(n,1);last=zeros(n,1);
for i=1:n
 N=numel(units(i).t);last(i)=N;dt(1:N-1,i)=diff(units(i).t);u(1:N-1,i,:)=reshape(units(i).u(1:end-1,:),N-1,1,3);D0(i)=units(i).initialD;
end
rate=reshape(physics_rate(M,reshape(u,[],3)),K-1,n);baseExposure=sum(dt.*rate,1)';
eta=log(max(c.Dcrit-D0,eps)./max(baseExposure,realmin));eta=max(-c.unitEffectMax,min(c.unitEffectMax,eta));
lo=-c.unitEffectMax*ones(n,1);hi=-lo;ends=sub2ind([K n],last,(1:n)');
for it=1:c.failureRootMaximumIterations
 [D,S]=v17_event_batch_trajectory(M,dt,u,rate,D0,eta,c);err=D(ends)-c.Dcrit;sensitivity=S(ends);
 done=abs(err)<c.failureRootTolerance;if all(done),break;end
 positive=err>0;hi(positive)=eta(positive);lo(~positive)=eta(~positive);
 proposed=eta-err./max(sensitivity,eps);bad=~isfinite(proposed) | proposed<=lo | proposed>=hi;proposed(bad)=(lo(bad)+hi(bad))/2;
 proposed(done)=eta(done);eta=proposed;
end
[D,S]=v17_event_batch_trajectory(M,dt,u,rate,D0,eta,c);batch=cell(n,1);
for i=1:n
 di=D(1:last(i),i);se=S(last(i),i);er=di(end)-c.Dcrit;ui=units(i).u(end-1,:);
 speed=physics_rate(M,ui)*exp(eta(i)+discrepancy(M,c.Dcrit,0,ui))*(1+M.a*c.Dcrit);
 batch{i}=struct('eta',eta(i),'D',di,'sensitivity',se,'error',er,'speed',speed, ...
  'valid',abs(er)<20*c.failureRootTolerance && se>0 && abs(eta(i))<c.unitEffectMax);
end
end

function [D,S]=v17_event_batch_trajectory(M,dt,u,rate,D0,eta,c)
[K,n]=size(dt);K=K+1;D=zeros(K,n);S=D;D(1,:)=D0';
if M.bound==0 && M.a==0,D=[D0';D0'+cumsum(dt.*rate.*exp(eta'),1)];S=D-D0';return;end
ns=max(1,ceil(dt/c.transitionStepHours));hs=dt./ns;
for k=2:K
 d=D(k-1,:)';s=S(k-1,:)';uk=reshape(u(k-1,:,:),n,3);base=rate(k-1,:)'.*exp(eta);
 for j=1:max(ns(k-1,:))
  h=hs(k-1,:)';h(j>ns(k-1,:)')=0;
  [rho,derivative]=v17_damage_discrepancy_sensitivity(M,d,uk,c);r=base.*exp(rho).*(1+M.a*d);dr=r.*(derivative+M.a./(1+M.a*d));
  mid=d+.5*h.*r;smid=s+.5*h.*(r+dr.*s);
  [rho,derivative]=v17_damage_discrepancy_sensitivity(M,mid,uk,c);r=base.*exp(rho).*(1+M.a*mid);dr=r.*(derivative+M.a./(1+M.a*mid));
  d=d+h.*r;s=s+h.*(r+dr.*smid);
 end
 D(k,:)=d';S(k,:)=s';
end
end

function [d,onFace]=v17_l1_face_direction(d,x,c)
% Restrict a search direction to the active L1 face: zero coordinates stay
% at zero and the outward normal component on nonzero ones is removed. An
% inward direction is returned unchanged. The -pg fallback can still move
% zero coordinates, so stationarity is judged by the full projected gradient.
onFace=false;
if ~isfield(c,'optimizerL1Indices') || isempty(c.optimizerL1Indices) || ~isfinite(c.optimizerL1Radius),return;end
ix=c.optimizerL1Indices(:);xi=x(ix);r=c.optimizerL1Radius;
if sum(abs(xi))<r*(1-1e-10),return;end
onFace=true;nz=abs(xi)>1e-12*max(1,r);s=sign(xi(nz));di=d(ix);
if s'*di(nz)+sum(abs(di(~nz)))>0
 di(~nz)=0;di(nz)=di(nz)-s*(s'*di(nz))/nnz(nz);d(ix)=di;
end
end

function x=v17_project_parameters(x,c)
[lo,hi]=v17_optimizer_bounds(c,numel(x));y=x;x=min(hi,max(lo,x));
if isfield(c,'optimizerL1Indices') && ~isempty(c.optimizerL1Indices)
 ix=c.optimizerL1Indices;r=c.optimizerL1Radius;
 if v17_flag(c,'exactL1Projection') && all(lo(ix)<=-r) && all(hi(ix)>=r)
  % 17.1.2: the ball lies inside the box, so the exact Euclidean projection
  % onto box-and-ball is the ball projection of the unclipped point.
  % Clipping first (v17.1.1) is not a projection when two or more
  % coordinates exceed the box, and distorted line-search candidates.
  x(ix)=project_l1(y(ix),r);
 else,x(ix)=project_l1(x(ix),r);end
end
end

function [M,opt,loss]=v17_curvature_polish(M,train,c,tag)
% Conditional output-space second-order audit, with TRAIN-only escapes.
% Hidden-weight uniqueness and a global minimum are not asserted.
opt=M.selectedMStep;loss=M.profileObjective;rows=cell(0,6);verified=false;checked=false;
if ~c.directNeuralCoordinates || M.bound==0 || c.curvatureEscapeCycles==0,return;end
for cycle=1:c.curvatureEscapeCycles+1
 [v,L]=v17_marginal_encode(M,train,c,false);ix=L.nx+(1:L.nn);
 cc=c;cc.optimizerLowerBound=L.lower;cc.optimizerUpperBound=L.upper;cc.optimizerL1Indices=L.l1Indices;cc.optimizerL1Radius=L.l1Radius;
 fun=@(z)v17_marginal_objective(z,M,L,train,c);f0=fun(v);H=zeros(numel(ix));step=c.curvatureStep;
 feasible=true;
 for j=1:numel(ix)
  vp=v;vm=v;vp(ix(j))=vp(ix(j))+2*step;vm(ix(j))=vm(ix(j))-2*step;
  if norm(vp-v17_project_parameters(vp,cc),Inf)>1e-10 || norm(vm-v17_project_parameters(vm,cc),Inf)>1e-10,feasible=false;end
 end
 if ~feasible,break;end
 checked=true;
 for j=1:numel(ix)
  vp=v;vm=v;vp(ix(j))=vp(ix(j))+step;vm(ix(j))=vm(ix(j))-step;H(j,j)=(fun(vp)+fun(vm)-2*f0)/step^2;
  for k=1:j-1
   pp=v;pm=v;mp=v;mm=v;pp(ix([j k]))=pp(ix([j k]))+step;mm(ix([j k]))=mm(ix([j k]))-step;
   pm(ix(j))=pm(ix(j))+step;pm(ix(k))=pm(ix(k))-step;mp(ix(j))=mp(ix(j))-step;mp(ix(k))=mp(ix(k))+step;
   H(j,k)=(fun(pp)-fun(pm)-fun(mp)+fun(mm))/(4*step^2);H(k,j)=H(j,k);
  end
 end
 [V,E]=eig((H+H')/2);[lambda,j]=min(diag(E));direction=zeros(size(v));direction(ix)=V(:,j);
 h=2*step;large=(fun(v+h*direction)+fun(v-h*direction)-2*f0)/h^2;
 verified=lambda<-c.curvatureTolerance && large<-c.curvatureTolerance;
 best=f0;point=v;
 if verified && cycle<=c.curvatureEscapeCycles
  for radius=[.05 .15 .3]
   for signValue=[-1 1]
    trial=v17_project_parameters(v+signValue*radius*direction,cc);value=fun(trial);
    if value<best-1e-9,best=value;point=trial;end
   end
  end
 end
 rows(end+1,:)={cycle,lambda,large,verified,f0,best}; %#ok<AGROW>
 fprintf('  %s curvature cycle %d: min %.4g, directional %.4g, verified negative=%d.\n',tag,cycle,lambda,large,verified);
 if best>=f0-1e-9,break;end
 [~,M]=v17_marginal_objective(point,M,L,train,c);
 if isfield(M,'marginalContinuation'),M=rmfield(M,'marginalContinuation');end
 [M,opt,loss]=v17_marginal_fit(M,train,c,c.functionalSteps,sprintf('%s_curvature%02d',tag,cycle),false);
end
M.curvatureAudit=struct('checked',checked,'verifiedNegativeCurvature',verified, ...
 'scope','TRAIN-only identifiable output coordinates; finite-step stability check, not a full-Hessian or deep-weight identification claim', ...
 'trace',cell2table(rows,'VariableNames',{'cycle','smallStepEigenvalue','largerDirectionalCurvature','verifiedNegative','beforeLoss','escapeLoss'}));
if verified,opt.exitflag=0;opt.converged=false;opt.status='verified_negative_output_curvature';M.selectedMStep=opt;end
end

function c=v17_consolidated_configuration(c,mode)
c.trainingLikelihood='event_time';c.failureRootTolerance=2e-10;c.failureRootMaximumIterations=28;
c.innerProfileMaximumIterations=160;c.innerProfileGradientTolerance=2e-8;
c.directNeuralCoordinates=true;c.encoderWeightBound=5;c.optimizerL1Indices=[];c.optimizerL1Radius=Inf;
c.gradientTolerance=5e-5;c.curvatureStep=.01;c.curvatureTolerance=2e-6;c.curvatureEscapeCycles=2;
c.requireResolvedPopulation=true;c.populationRecoverySteps=80;
c.jointRecoverySteps=60;c.recoverComparators=true;
c.observationSEMultiplier=2;c.maximumBParameterCorrelation=.995;c.minimumBSignalToNoise=.10;
c.policySpecificSelection=true;c.selectPrimaryFamily=true;c.policyOneSEMultiplier=1;
c.gateComparators={'Physics_SSM','Basis_hybrid','Inverse_PINN','LSTM','Bayesian_PF'};
c.enableDutyBlockSelection=true;c.dutyBlockLength=8;c.dutyValidationPaths=32;c.dutyValidationHorizonHours=64;
c.populationBootstrapMembers=0;c.bootstrapFitSteps=25;c.bootstrapEncoderSteps=5;c.bootstrapMinimumMembers=3;
c.bootstrapReplicates=Inf;c.bootstrapRefitEncoder=true;c.retryFailedExperiment=false;
% Publication figures (17.2): every font +3 pt over the MATLAB/plot default,
% 300 dpi raster; summary figures are also exported as vector PDF.
c.plotFontIncrement=3;c.exportVectorFigures=false;c.figureSize=[1800 1080];c.figureResolution=300;
c.enableFullInformation=false;c.enableProfiles=false;c.profilePoints=5;
c.encoderSteps=12;c.functionalSteps=65;c.marginalSteps=60;c.marginalCycles=2;
c.BrefineSteps=60;c.BrefineCycles=2;c.pinnIterations=55;c.pinnCycles=2;
c.forecastPaths=192;c.forecastReplicates=4;c.maxRunSeconds=3600;
c.seed=2026101901;c.label='v17 frozen development protocol; no forced superiority';
c.originalSource=fullfile(fileparts(mfilename('fullpath')),'Reference','BSFD_PI_DSSDM_Hierarchical_v14.m');
if ismember(mode,{'confirm','full','benchmark','data'})
 c.seed=2027101901;if ismember(mode,{'full','benchmark'}),c.seed=2028101901;end
 c.encoderSteps=30;c.functionalSteps=100;c.marginalSteps=100;c.populationRecoverySteps=140;
 c.jointRecoverySteps=120;
 c.populationBootstrapMembers=8;c.bootstrapFitSteps=45;c.bootstrapEncoderSteps=12;
 c.forecastPaths=512;c.forecastReplicates=6;c.maxRunSeconds=28800;
 c.maxDiagnosticUnits=2;c.dutyValidationPaths=64;c.enableProfiles=true;
end
if ismember(mode,{'smoke','quick'})
 c.encoderSteps=1;c.functionalSteps=4;c.marginalSteps=35;c.marginalCycles=1;
 c.BrefineSteps=25;c.BstartScreenSteps=2;c.BrefineFinalists=1;
 c.pinnIterations=3;c.pinnCycles=1;c.enableDutyBlockSelection=false;c.curvatureEscapeCycles=0;
 c.jointRecoverySteps=0;c.recoverComparators=false;
 c.populationBootstrapMembers=0;c.forecastPaths=30;c.forecastReplicates=2;c.maxRunSeconds=1800;
end
% v17: optional finite wall budget only when explicitly supplied by the user.
c.maxRunSeconds=Inf;c.requireResolvedPopulation=false;
c.savePointForecastsFirst=true;c.skipIneligibleBootstrap=true;c.fastPinnClock=true;
c.label='v17 uninterrupted synthetic benchmark; unresolved fits remain flagged';
c=v17_methodology_configuration(c,mode);
end

function c=v17_methodology_configuration(c,mode)
% v17 methodology revision. Every change answers a v16 diagnosis taken from
% TRAIN/VAL selection records; none was tuned on v16 TEST outcomes, and v16
% TEST fleets must not be reused as v17 confirmation. New seed family below.
% Optimisation: C1 damage features (no clamp kink at D=Dcrit), gradient
% refresh after a failed line search, explicitly labelled resolution-limited
% stationarity, and multi-start discrepancy fits.
c.smoothDamageFeatures=true;c.residualOperatingMain=true;
c.fdStepScale=1;c.lineSearchGradientRefresh=true;c.refreshGradientStepFactor=.25;
c.acceptResolutionLimited=true;c.resolutionGradientTolerance=5e-4;
c.stallWindow=10;c.stallRelativeTolerance=1e-8;c.residualStarts=2;
c.l1FaceDirection=true;c.faceDirectionFraction=.1;c.exactL1Projection=true;
c.earlyStallStop=true;c.stallStopWindow=10;c.stallStopRelativeTolerance=1e-7;c.stallRescueLimit=1;
% Discrepancy capacity: larger encoder and bound, only the constant log-rate
% (absorbed by k) is protected, and a smooth radial damage basis.
c.hidden1=5;c.hidden2=3;c.residualBounds=[0 .15 .30 .50];
c.protectFixedLoadSpeed=false;c.basisFamily='rbf';c.basisDamageCenters=5;c.basisWidthFactor=1;
% Selection: one gate. PI-DSSDM is a VAL-weighted linear pool of physics and
% the best eligible discrepancy candidate; weight 0 is the physics model.
c.primaryOneSEGate=false;c.stackSelection=true;c.stackWeights=[0 .25 .5 .75 1];c.stackOneSEMultiplier=0;
% Stochastic damage increments: gamma-process intensity kappa (hours) is a
% filtering/forecast hyperparameter selected on VAL; TRAIN fits stay exact.
c.processNoise=true;c.processKappaGrid=[0 .5 2 6];c.processEtaNodes=61;c.processParticles=64;c.processOutputParticles=1024;
c.parallelForecasts=true;
% Bands: origin-stratified split conformal (exchangeable CAL units at a fixed
% calendar origin). Unit-simultaneous bands are still exported and gated.
c.bandMethod='origin_stratified';
% Bootstrap: extra recovery round, more draws to reach the requested members;
% every attempt and the acceptance rate are reported.
c.bootstrapExtraRecovery=true;c.bootstrapMaximumAttempts=0;c.bootstrapLowAcceptance=.75;
% Physically motivated load-exponent misspecification that k cannot absorb.
c.truthAlternativeLoadExponent=4.5;
c.seed=2026102201;c.label='v17 development protocol; new seed family; no forced superiority';
c.scenarios=[c.scenarios {'fatigue_load_exponent'}];
if ismember(mode,{'confirm','full','benchmark','data'})
 c.seed=2027102201;if ismember(mode,{'full','benchmark'}),c.seed=2028102201;end
 c.functionalSteps=200;c.bootstrapMaximumAttempts=12;
 c.label='v17 frozen synthetic benchmark; 6 scenarios x 5 fleets; all results retained';
end
if ismember(mode,{'smoke','quick'})
 c.residualStarts=1;c.processKappaGrid=[0 2];c.processEtaNodes=21;c.processParticles=16;c.processOutputParticles=256;
 c.stackWeights=[0 .5 1];c.residualBounds=[0 .15];
end
c.scenarios=unique(c.scenarios,'stable');
c.processKappaSEMultiplier=1;
c=v17_equal_pinn_budget(c);
end

function c=v17_equal_pinn_budget(c)
% v17.1 comparator fairness: the inverse PINN receives the same number of
% starts and per-cycle optimiser iterations as one deep discrepancy start
% (plus its existing TRAIN recovery), and the same convergence rules.
c.pinnStarts=max(1,c.residualStarts);c.pinnIterations=c.functionalSteps;c.pinnCycles=max(2,c.marginalCycles);
end

function yes=v17_flag(c,name)
yes=isfield(c,name) && ~isempty(c.(name)) && all(logical(c.(name)));
end

function [models,routing]=v17_select_policy_models(models,names,val,Q,c,eid)
% Prespecified whole-model VAL selection. It never changes only the future
% neural rate while retaining an incompatible historical posterior.
rows=cell(0,10);original=models;
for m=1:numel(models)
 pool={};family={};cost=[];M=original{m};
 if m==1
  [pool,family,cost]=v17_add_candidate(pool,family,cost,original{4},'physics',0);
  if c.selectPrimaryFamily && numel(original)>=5
   [pool,family,cost]=v17_add_discrepancy_candidates(pool,family,cost,original{5},'basis',1,c);
  end
  [pool,family,cost]=v17_add_discrepancy_candidates(pool,family,cost,M,'deep',2,c);
 elseif strcmp(names{m},'Basis_hybrid')
  [pool,family,cost]=v17_add_candidate(pool,family,cost,original{4},'physics',0);
  [pool,family,cost]=v17_add_discrepancy_candidates(pool,family,cost,M,'basis',1,c);
 elseif strcmp(M.kind,'pinn') && isfield(M,'policyArchive')
  pool=M.policyArchive;family=repmat({'inverse_pinn'},size(pool));cost=1+(1:numel(pool))*1e-5;
 elseif strcmp(M.kind,'lstm') && isfield(M,'policyArchive')
  pool=M.policyArchive;family=repmat({'lstm'},size(pool));cost=cellfun(@(N)N.hidden,pool);
 else
  pool={M};family={v17_model_family(M)};cost=0;
 end
 if isempty(pool),pool={M};family={v17_model_family(M)};cost=0;end
 for j=1:numel(pool)
  N=pool{j};pool{j}=v17_strip_model_archive(N);
 end
 applied=struct();reference=[];
 for p=1:numel(c.policies)
  policy=c.policies{p};cc=c;cc.policies={policy};score=inf(numel(pool),1);units=nan(numel(val),numel(pool));ok=false(size(score));
  for j=1:numel(pool)
   ok(j)=v17_candidate_eligible(pool{j},c);
   if pool{j}.available,[score(j),units(:,j)]=stable_score(pool{j},val,Q,cc,eid);end
  end
  feasible=ok & isfinite(score);if ~any(feasible),feasible=isfinite(score);end
  if ~any(feasible)
   N=M;N.selectedFamily=v17_model_family(M);N.policySelectionEligible=false;applied.(policy)=N;
   if p==1,reference=N;end
   rows(end+1,:)={names{m},policy,1,N.selectedFamily,0,Inf,false,NaN,true,v17_model_bound(N)}; %#ok<AGROW>
   continue;
  end
  values=score;values(~feasible)=Inf;[~,best]=min(values);
  acceptable=false(size(score));se=zeros(size(score));
  for j=find(feasible)'
   gain=units(:,j)-units(:,best);gain=gain(isfinite(gain));se(j)=std(gain)/sqrt(max(1,numel(gain)));
   acceptable(j)=score(j)<=score(best)+c.policyOneSEMultiplier*se(j)+1e-12;
  end
  ix=find(acceptable);[~,order]=sortrows([cost(ix)' score(ix)],[1 2]);chosen=ix(order(1));
  stackRows=cell(0,10);
  if m==1 && v17_flag(c,'stackSelection')
   % v17 ONE gate for PI-DSSDM: linear pool of physics and the best eligible
   % discrepancy candidate, weight chosen on VAL; weight 0 is physics itself.
   [chosen,N,stackRows]=v17_stack_select(pool,family,score,units,feasible,ok,val,Q,cc,eid,names{m},policy);
  else
   N=pool{chosen};N.selectedFamily=family{chosen};N.validationScore=score(chosen);
  end
  if m==1 && v17_flag(c,'processNoise')
   [N,kappaRows]=v17_select_process_kappa(N,val,Q,cc,eid,names{m},policy);stackRows=[stackRows;kappaRows]; %#ok<AGROW>
  end
  N.policyValidation=policy;N.policySelectionEligible=v17_candidate_eligible(N,c);applied.(policy)=N;
  if p==1,reference=N;end
  for j=1:numel(pool)
   rows(end+1,:)={names{m},policy,j,family{j},cost(j),score(j),ok(j),se(j),j==chosen,v17_model_bound(pool{j})}; %#ok<AGROW>
  end
  rows=[rows;stackRows]; %#ok<AGROW>
 end
 reference.policyModels=applied;reference.label=names{m};
 if isfield(M,'selection'),reference.selection=M.selection;end
 if m==1
  reference.selection=M.selection;reference.physicsControl=original{4};reference.discrepancyCandidates=M.discrepancyCandidates;
  if ~isfield(reference,'networkTrace'),reference.networkTrace=table();end
  if ~isfield(reference,'residualTrace'),reference.residualTrace=table();end
 end
 models{m}=reference;
 fprintf('  VAL protocol selection %s: planned=%s, probabilistic=%s.\n',names{m}, ...
  applied.(c.policies{1}).selectedFamily,applied.(c.policies{end}).selectedFamily);
end
routing=cell2table(rows,'VariableNames',{'method','policy','candidate','family','complexityOrder', ...
 'validationLogRULLoss','eligible','pairedSEvsBest','selected','residualBound'});
end

function [chosen,N,rows]=v17_stack_select(pool,family,score,units,feasible,ok,val,Q,c,eid,name,policy)
% Linear pool p = (1-w) p_physics + w p_discrepancy of complete predictive RUL
% distributions. The discrepancy member is the best ELIGIBLE non-physics
% candidate on VAL; w is chosen on the same VAL criterion from a fixed grid,
% ties resolved toward physics. No TEST or CAL quantity enters.
rows=cell(0,10);phys=find(strcmp(family,'physics'),1);
candidates=find(feasible(:)' & ok(:)' & ~strcmp(family,'physics'));
if isempty(phys) || ~ok(phys) || isempty(candidates)
 values=score;values(~feasible)=Inf;
 if ~isempty(phys) && feasible(phys) && isempty(candidates),chosen=phys;else,[~,chosen]=min(values);end
 N=pool{chosen};N.selectedFamily=family{chosen};N.validationScore=score(chosen);return;
end
[~,k]=min(score(candidates));b=candidates(k);
weights=sort(unique(c.stackWeights(:)'));s=nan(size(weights));u=nan(numel(val),numel(weights));
for j=1:numel(weights)
 w=weights(j);
 if w==0,s(j)=score(phys);u(:,j)=units(:,phys);
 elseif w==1,s(j)=score(b);u(:,j)=units(:,b);
 else,S=v17_make_stack(pool{b},pool{phys},w);[s(j),u(:,j)]=stable_score(S,val,Q,c,eid);end
 fprintf('  STACK %s/%s weight %.2f on %s bound %.2f: VAL %.6g.\n',name,policy,w,family{b},v17_model_bound(pool{b}),s(j));
end
[~,best]=min(s);se=zeros(size(s));
for j=1:numel(s),g=u(:,j)-u(:,best);g=g(isfinite(g));se(j)=std(g)/sqrt(max(1,numel(g)));end
pick=find(s<=s(best)+c.stackOneSEMultiplier*se+1e-12,1,'first');w=weights(pick);
if w==0,chosen=phys;N=pool{phys};N.selectedFamily='physics';
elseif w==1,chosen=b;N=pool{b};N.selectedFamily=family{b};
else,chosen=b;N=v17_make_stack(pool{b},pool{phys},w);N.selectedFamily=['stack_' family{b}];end
N.validationScore=s(pick);N.stackCandidateFamily=family{b};N.stackCandidateBound=v17_model_bound(pool{b});
N.stackSelection=table(weights(:),s(:),se(:),(1:numel(s))'==pick,'VariableNames',{'discrepancyWeight','validationLogRULLoss','pairedSEvsBest','selected'});
for j=1:numel(weights)
 rows(end+1,:)={name,policy,0,sprintf('stack_w%.2f',weights(j)),weights(j),s(j),true,se(j),j==pick,v17_model_bound(pool{b})}; %#ok<AGROW>
end
end

function S=v17_make_stack(A,P,w)
S=A;S.stackPartner=v17_strip_model_archive(P);S.stackWeight=w;
end

function [N,rows]=v17_select_process_kappa(N,val,Q,c,eid,name,policy)
% Gamma damage-increment intensity for filtering/forecasting, chosen on VAL
% with ties resolved toward the deterministic clock (kappa=0).
grid=sort(unique([0 c.processKappaGrid(:)']));s=nan(size(grid));u=nan(numel(val),numel(grid));rows=cell(0,10);
base=N;if isfield(base,'processKappa'),base=rmfield(base,'processKappa');end
for j=1:numel(grid)
 K=base;if grid(j)>0,K.processKappa=grid(j);end
 [s(j),u(:,j)]=stable_score(K,val,Q,c,eid);
 fprintf('  PROCESS NOISE %s/%s kappa %.3g h: VAL %.6g.\n',name,policy,grid(j),s(j));
end
[~,best]=min(s);se=zeros(size(s));
for j=1:numel(s),g=u(:,j)-u(:,best);g=g(isfinite(g));se(j)=std(g)/sqrt(max(1,numel(g)));end
% v17.1 safeguard: kappa>0 is adopted only if its paired VAL gain over the
% deterministic clock exceeds processKappaSEMultiplier paired unit SEs. In
% the 12-fleet ASSESS run an unguarded tiny VAL gain selected kappa on a
% matched fleet and worsened TEST accuracy and numerical reproducibility.
pick=1;gainSE=nan(size(s));gain=zeros(size(s));
for j=2:numel(s)
 d=u(:,1)-u(:,j);d=d(isfinite(d));gain(j)=mean(d);gainSE(j)=std(d)/sqrt(max(1,numel(d)));
end
cand=find(gain>c.processKappaSEMultiplier*gainSE & gain>0);
if ~isempty(cand),[~,k]=min(s(cand));pick=cand(k);end
N=base;if grid(pick)>0,N.processKappa=grid(pick);end
N.validationScore=s(pick);
N.processKappaSelection=table(grid(:),s(:),gain(:),gainSE(:),(1:numel(s))'==pick,'VariableNames',{'kappa_h','validationLogRULLoss','pairedGainVsKappa0','pairedGainSE','selected'});
for j=1:numel(grid)
 rows(end+1,:)={name,policy,-1,sprintf('kappa_%.3gh',grid(j)),grid(j),s(j),true,gainSE(j),j==pick,v17_model_bound(N)}; %#ok<AGROW>
end
end

function models=v17_link_stack_partners(models,c)
% A stack's physics member must carry the SAME population-bootstrap members
% as Physics_SSM for that duty protocol. Re-link after selection/bootstrap.
for p=1:numel(c.policies)
 policy=c.policies{p};N=v17_for_policy(models{1},policy);
 if ~isfield(N,'stackPartner'),continue;end
 P=v17_for_policy(models{4},policy);
 fields={'policyModels','policyArchive','fitCandidates','BfitCandidates','discrepancyCandidates','physicsControl'};
 for j=1:numel(fields),if isfield(P,fields{j}),P=rmfield(P,fields{j});end,end
 N.stackPartner=P;
 if isfield(models{1},'policyModels'),models{1}.policyModels.(policy)=N;else,models{1}=N;end
end
end

function [A,B,w]=v17_stack_members(M)
A=rmfield(M,{'stackPartner','stackWeight'});B=v17_set_process_kappa(M.stackPartner,M);w=M.stackWeight;
end

function B=v17_set_process_kappa(B,M)
% The pooled physics member, including its bootstrap members, uses the same
% VAL-selected damage-increment intensity as the PI-DSSDM model M.
if isfield(M,'processKappa'),B.processKappa=M.processKappa;elseif isfield(B,'processKappa'),B=rmfield(B,'processKappa');end
if isfield(B,'populationMembers')
 for j=1:numel(B.populationMembers),B.populationMembers{j}=v17_set_process_kappa(B.populationMembers{j},M);end
end
end

function P=v17_stack_posterior(M,H,c)
[A,B,w]=v17_stack_members(M);post={model_posterior(A,H,c),model_posterior(B,H,c)};weights=[w 1-w];
P=post{1};P.D=[];P.B=[];P.eta=[];P.weights=[];
for j=1:2
 pp=post{j};P.D=[P.D;pp.D(:)];P.B=[P.B;pp.B(:)];P.eta=[P.eta;pp.eta(:)];P.weights=[P.weights;weights(j)*pp.weights(:)/sum(pp.weights)]; %#ok<AGROW>
end
P.memberPosteriors=post;P.stackWeights=weights;
if all(cellfun(@(p)isfield(p,'gridConverged'),post)),P.gridConverged=all(cellfun(@(p)p.gridConverged,post));end
if all(cellfun(@(p)isfield(p,'gridPointsUsed'),post)),P.gridPointsUsed=sum(cellfun(@(p)p.gridPointsUsed,post));end
P.status=sprintf('Linear pool: %.2f discrepancy model + %.2f physics model',w,1-w);
end

function [samples,info]=v17_stack_samples(M,H,P,bank,c)
[A,B,w]=v17_stack_members(M);members={A,B};weights=[w 1-w];samples=[];weight=[];rho=0;maximum=0;outside=0;
for j=1:2
 [ss,ii]=model_samples(members{j},H,P.memberPosteriors{j},bank,c);
 if isfield(ii,'sampleWeights'),ww=ii.sampleWeights(:);else,ww=ones(numel(ss),1)/numel(ss);end
 samples=[samples;ss(:)];weight=[weight;weights(j)*ww/sum(ww)]; %#ok<AGROW>
 if j==1 && isfield(ii,'rhoRMS'),rho=ii.rhoRMS;maximum=ii.rhoMaxAbs;outside=ii.outOfSupportFraction;end
end
info=struct('sampleWeights',weight,'rhoRMS',rho,'rhoMaxAbs',maximum,'outOfSupportFraction',outside);
end

function b=v17_model_bound(M)
b=0;if isfield(M,'bound'),b=M.bound;end
end

function [pool,family,cost]=v17_add_candidate(pool,family,cost,M,name,complexity)
pool{end+1}=M;family{end+1}=name;cost(end+1)=complexity;
end

function [pool,family,cost]=v17_add_discrepancy_candidates(pool,family,cost,M,name,complexity,c)
if M.bound>0,[pool,family,cost]=v17_add_candidate(pool,family,cost,M,name,complexity+M.bound);end
if isfield(M,'discrepancyCandidates')
 for j=1:numel(M.discrepancyCandidates)
  A=M.discrepancyCandidates{j};N=A.model;N.selectedMStep=A.optimizer;N.predictionOptimization=A.optimizer;N.jointOptimization=A.optimizer;
  if v17_candidate_eligible(N,c),[pool,family,cost]=v17_add_candidate(pool,family,cost,N,name,complexity+N.bound);end
 end
end
end

function yes=v17_candidate_eligible(M,c)
yes=M.available;
if strcmp(M.kind,'lstm'),return;end
yes=yes && isfield(M,'selectedMStep') && v17_converged(M.selectedMStep,c);
requireJoint=~isfield(c,'requireJointEncoderStationarity') || c.requireJointEncoderStationarity;
if isfield(M,'encoderStationarity') && requireJoint,yes=yes && M.encoderStationarity.jointStationary;end
if isfield(M,'curvatureAudit'),yes=yes && ~M.curvatureAudit.verifiedNegativeCurvature;end
if isfield(M,'stackPartner'),yes=yes && v17_candidate_eligible(M.stackPartner,c);end
end

function M=v17_strip_model_archive(M)
fields={'policyModels','policyArchive','fitCandidates','BfitCandidates','discrepancyCandidates','physicsControl','populationMembers','stackPartner','stackWeight'};
for j=1:numel(fields),if isfield(M,fields{j}),M=rmfield(M,fields{j});end,end
end

function family=v17_model_family(M)
if isfield(M,'stackPartner') && isfield(M,'stackWeight')
 family=['stack_' v17_model_family(rmfield(M,{'stackPartner','stackWeight'}))];return;
end
family=M.kind;
if strcmp(M.kind,'lstm'),family='lstm';elseif strcmp(M.kind,'pinn'),family='inverse_pinn';
elseif M.bound==0,family='physics';elseif isfield(M,'residualFamily') && strcmp(M.residualFamily,'fixed_basis'),family='basis';else,family='deep';end
end

function N=v17_for_policy(M,policy)
N=M;if isfield(M,'policyModels') && isfield(M.policyModels,policy),N=M.policyModels.(policy);end
end

function O=v17_policy_optimizer_summary(models,names,c)
O=table();
for p=1:numel(c.policies)
 active=cell(size(models));for m=1:numel(models),active{m}=v17_for_policy(models{m},c.policies{p});end
 T=optimizer_summary(active,names);T.policy=repmat(c.policies(p),height(T),1);O=[O;T]; %#ok<AGROW>
end
end

function v17_policy_reporting(E,c,e,runDir)
if ~isfield(E,'policyRouting'),return;end
writetable(E.policyRouting,fullfile(runDir,sprintf('Policy_model_selection_%02d.csv',e)));
fprintf('\nAPPLIED VAL-SELECTED MODELS BY FUTURE-DUTY PROTOCOL:\n');disp(E.policyRouting(E.policyRouting.selected,:));
fprintf('Primary family can be physics, basis or deep. A basis/physics selection is not reported as an active deep correction.\n');
fprintf('Reference state/parameter figures use the planned-duty model; forecast rows record the actual applied family.\n');
end

function [Q,T]=v17_select_duty_model(train,val,c,eid)
% The empirical law advances one declared duty-grid interval. Irregular
% physical telemetry must first be windowed onto that operating grid, with
% missing sensor values retained as NaN; a short terminal interval is allowed.
for i=1:numel(train)
 dt=diff(train(i).t);tol=1e-6*max(1,c.dutyStepHours);
 assert(all(abs(dt(1:end-1)-c.dutyStepHours)<tol) && dt(end)<=c.dutyStepHours+tol, ...
  'pi17:dutyResolution','TRAIN operating inputs must use dutyStepHours spacing, except a shorter terminal interval. Resample irregular inputs before fitting the empirical duty law.');
end
Q=fit_duty_model(train);Q.family='markov';Q.blockNext=zeros(size(Q.current,1),1);
offset=0;
for i=1:numel(train)
 n=size(train(i).u,1)-1;Q.blockNext(offset+(1:max(0,n-1)))=offset+(2:n);offset=offset+n;
end
rows=cell(0,4);
if ~c.enableDutyBlockSelection,T=cell2table(rows,'VariableNames',{'unit','markovEnergy','blockEnergy','gain'});return;end
scores=nan(numel(val),2);old=rng;cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
cc=c;cc.forecastHorizonHours=c.dutyValidationHorizonHours;
for i=1:numel(val)
 U=val(i);[ks,~]=origin_nodes(U,c);unitScores=cell(1,2);
 for k=ks
  H=causal_prefix(U,k);
  for family=1:2
   qq=Q;if family==2,qq.family='conditional_blocks';end
   rng(c.seed+eid*7919+i*109+k,'twister');bank=future_bank(H,'probabilistic',qq,cc,c.dutyValidationPaths);
   times=H.t(end)+[0;cumsum(bank.dt(1:end-1))];inside=times<=U.t(end);
   if sum(inside)<2,continue;end
   truth=interp1(U.t,U.u,times(inside),'previous');sim=bank.u(inside,:,:);
   truth=([log(max(truth(:,1:2),1e-8)) truth(:,3)]-Q.mean)./Q.sd;
   paths=zeros(sum(inside)*3,size(sim,2));
   for path=1:size(sim,2),a=reshape(sim(:,path,:),sum(inside),3);a=([log(max(a(:,1:2),1e-8)) a(:,3)]-Q.mean)./Q.sd;paths(:,path)=a(:);end
   target=truth(:);energy=mean(sqrt(mean((paths-target).^2,1)));
   energy=energy-.5*mean(sqrt(mean((paths-paths(:,[2:end 1])).^2,1)));
   unitScores{family}(end+1)=energy; %#ok<AGROW>
  end
 end
 for family=1:2,if ~isempty(unitScores{family}),scores(i,family)=mean(unitScores{family});end,end
 rows(end+1,:)={U.id,scores(i,1),scores(i,2),scores(i,1)-scores(i,2)}; %#ok<AGROW>
end
gain=scores(:,1)-scores(:,2);gain=gain(isfinite(gain));
if ~isempty(gain) && mean(gain)>std(gain)/sqrt(numel(gain)),Q.family='conditional_blocks';end
Q.validationDutyScope='TRAIN duty transitions; VAL operating trajectories only, no TEST or future sensor conditioning';
T=cell2table(rows,'VariableNames',{'unit','markovEnergy','blockEnergy','gain'});
fprintf('  Future-duty law selected on VAL operating forecasts: %s.\n',Q.family);
end

function yes=v17_bootstrap_required(c,evidence)
% 17.2: the unit bootstrap can be limited to the first replicate fleets of
% each scenario (bootstrapReplicates). Point forecasts and conformal bands
% are produced identically for every fleet.
yes=c.populationBootstrapMembers>0;
if yes && isfield(c,'bootstrapReplicates') && isfinite(c.bootstrapReplicates)
 yes=v17_evidence_replicate(evidence)<=c.bootstrapReplicates;
end
end

function rep=v17_evidence_replicate(evidence)
t=regexp(char(evidence),'rep(\d+)$','tokens','once');rep=1;if ~isempty(t),rep=str2double(t{1});end
end

function [models,T]=v17_bootstrap_models(models,names,train,c,eid)
% Cluster bootstrap of independent TRAIN units. Refit all free population
% coordinates, C and the chosen encoder. B/family/duty choices are held fixed;
% this is finite, architecture-conditional frequentist uncertainty, not a
% complete Bayesian posterior or uncertainty about an uncalibrated failure law.
rows=cell(0,9);cache=containers.Map('KeyType','char','ValueType','any');old=rng;cl=onCleanup(@()rng(old)); %#ok<NASGU>
for m=1:numel(models)
 if strcmp(models{m}.kind,'lstm'),continue;end
 for p=1:numel(c.policies)
  policy=c.policies{p};base=v17_for_policy(models{m},policy);members={};
  if c.skipIneligibleBootstrap && ~v17_candidate_eligible(base,c)
   base.bootstrapSuccessfulMembers=0;base.bootstrapRequestedMembers=c.populationBootstrapMembers;
   base.bootstrapAdequate=false;base.bootstrapStatus='skipped_ineligible_base_fit';
   if isfield(base,'populationMembers'),base=rmfield(base,'populationMembers');end
   rows(end+1,:)=[{names{m},policy} {0,0,NaN,0,NaN,false,false}]; %#ok<AGROW>
   if isfield(models{m},'policyModels'),models{m}.policyModels.(policy)=base;else,models{m}=base;end
   fprintf('  UQ SKIPPED %s/%s: base fit ineligible; point results retained, convergence gate remains HOLD.\n',names{m},policy);
   continue;
  end
  % Only fit-defining coordinates enter the reuse identity. PF shares the
  % physics parameter bootstrap, while retaining its separate SMC filter.
  identity=struct('family',v17_model_family(base),'useB',base.useB,'bound',base.bound, ...
   'parameters',[base.k base.p base.betaT base.a base.tau base.unitSD base.sensorSD], ...
   'C',base.C,'encoder',pack_network(base.nn));
  if strcmp(base.kind,'pinn'),identity.pinnEncoder=pack_network(base.pinnNN);end
  key=v17_hash_text(jsonencode(identity));
  if isKey(cache,key)
   A=cache(key);members=A.members;records=A.records;
  else
   records=cell(0,7);
   % v17: draw further resamples (up to bootstrapMaximumAttempts) until the
   % requested number of members is accepted. All attempts are recorded, and
   % a low acceptance rate is flagged: rejection conditions on fit success.
   attempts=max(c.populationBootstrapMembers,c.bootstrapMaximumAttempts);
   for b=1:attempts
    if numel(members)>=c.populationBootstrapMembers,break;end
    v17_deadline('check');rng(c.seed+eid*19001+b*503,'twister');ix=randi(numel(train),numel(train),1);sample=train(ix);
    N=v17_strip_model_archive(base);originalKind=N.kind;if strcmp(N.kind,'smc'),N.kind='observed';end
    fields={'marginalContinuation','curvatureAudit','encoderStationarity','predictionOptimization','jointOptimization'};
    for f=1:numel(fields),if isfield(N,fields{f}),N=rmfield(N,fields{f});end,end
    cc=c;cc.runtimeCandidateDir=fullfile(c.runtimeCandidateDir,sprintf('bootstrap_%s_%s_%02d',names{m},policy,b));
    if ~exist(cc.runtimeCandidateDir,'dir'),mkdir(cc.runtimeCandidateDir);end
    path=fullfile(cc.runtimeCandidateDir,'completed_member.mat');
    if isfile(path)
     S=load(path,'member','record');N=S.member;record=S.record;
    else
     if N.bound>0
      [~,N]=v17_event_profile(N,sample,cc);N.reference=observed_reference(N,sample,cc);N=project_network(N,cc);
     end
     learned=strcmp(N.kind,'pinn') || (N.bound>0 && ~strcmp(N.residualFamily,'fixed_basis'));
     % 17.2: bootstrapRefitEncoder=false gives an encoder-conditional
     % bootstrap (population, emission and output coordinates refitted; the
     % TRAIN encoder is held), the same conditioning as the primary fit.
     learned=learned && (~isfield(c,'bootstrapRefitEncoder') || c.bootstrapRefitEncoder);
     if learned
      [N,~,~]=v17_marginal_fit(N,sample,cc,c.bootstrapEncoderSteps,'bootstrap_encoder',true);
      if isfield(N,'marginalContinuation'),N=rmfield(N,'marginalContinuation');end
     end
     [N,opt,loss]=v17_marginal_fit(N,sample,cc,c.bootstrapFitSteps,'bootstrap_population',false);
     if ~v17_converged(opt,cc)
      if isfield(N,'marginalContinuation'),N=rmfield(N,'marginalContinuation');end
      [N,opt,loss]=v17_marginal_fit(N,sample,cc,c.populationRecoverySteps,'bootstrap_recovery',false);
     end
     if ~v17_converged(opt,cc) && v17_flag(c,'bootstrapExtraRecovery')
      % Second recovery continues from the saved BFGS state (curvature kept).
      [N,opt,loss]=v17_marginal_fit(N,sample,cc,c.populationRecoverySteps,'bootstrap_recovery2',false);
     end
     N.selectedMStep=opt;N.predictionOptimization=opt;N.jointOptimization=opt;
     if learned
      N=v17_joint_stationarity(N,sample,cc,'bootstrap_joint_KKT');
      if c.jointRecoverySteps>0 && ~N.encoderStationarity.jointStationary
       if isfield(N,'marginalContinuation'),N=rmfield(N,'marginalContinuation');end
       [N,opt,loss]=v17_marginal_fit(N,sample,cc,c.jointRecoverySteps,'bootstrap_joint_TRAIN_recovery',true);
       N.selectedMStep=opt;N.predictionOptimization=opt;N.jointOptimization=opt;
       N=v17_joint_stationarity(N,sample,cc,'bootstrap_joint_recovery_KKT');
      end
     end
     accepted=v17_candidate_eligible(N,cc);
     record={b,numel(unique(ix)),loss,opt.exitflag,opt.gradientNorm,accepted,learned};
     v17_save(path,struct('member',N,'record',{record}));
    end
    records(end+1,:)=record; %#ok<AGROW>
    if record{6},N.kind=originalKind;members{end+1}=N;end %#ok<AGROW>
    fprintf('  Population bootstrap %s/%s attempt %d (max %d), accepted=%d, TRAIN gradient %.4g.\n',names{m},policy,b,attempts,record{6},record{5});
   end
   cache(key)=struct('members',{members},'records',{records});
  end
  for b=1:size(records,1),rows(end+1,:)=[{names{m},policy} records(b,:)];end %#ok<AGROW>
  % Cached refits can be shared by identical fits (e.g. PI physics copy and
  % Physics_SSM); the forecast-only damage-increment intensity is per method.
  for b=1:numel(members),members{b}.kind=base.kind;members{b}=v17_set_process_kappa(members{b},base);end
  base.bootstrapSuccessfulMembers=numel(members);base.bootstrapRequestedMembers=c.populationBootstrapMembers;
  base.bootstrapAttempts=size(records,1);base.bootstrapAcceptanceRate=numel(members)/max(1,size(records,1));
  base.bootstrapSelectionBiasRisk=base.bootstrapAcceptanceRate<c.bootstrapLowAcceptance;
  if base.bootstrapSelectionBiasRisk
   fprintf('  UQ CAUTION %s/%s: acceptance %.0f%%; members are conditional on optimisation success.\n',names{m},policy,100*base.bootstrapAcceptanceRate);
  end
  base.bootstrapAdequate=numel(members)>=c.bootstrapMinimumMembers;
  if base.bootstrapAdequate,base.populationMembers=members;
  else,fprintf('  UQ UNRESOLVED %s/%s: %d/%d successful members; point-parameter bands retained and flagged.\n',names{m},policy,numel(members),c.populationBootstrapMembers);end
  if isfield(models{m},'policyModels'),models{m}.policyModels.(policy)=base;else,models{m}=base;end
 end
end
T=cell2table(rows,'VariableNames',{'method','policy','member','distinctTrainUnits','TRAINloss','exitflag','projectedGradient','accepted','encoderRefitted'});
end

function P=v17_population_posterior(M,H,c)
members=M.populationMembers;post=cell(size(members));
for j=1:numel(members),post{j}=model_posterior(members{j},H,c);end
P=post{1};P.D=[];P.B=[];P.eta=[];P.weights=[];
for j=1:numel(post)
 pp=post{j};P.D=[P.D;pp.D(:)];P.B=[P.B;pp.B(:)];P.eta=[P.eta;pp.eta(:)];P.weights=[P.weights;pp.weights(:)/numel(post)]; %#ok<AGROW>
end
P.memberPosteriors=post;P.populationMemberCount=numel(post);
if all(cellfun(@(p)isfield(p,'gridConverged'),post)),P.gridConverged=all(cellfun(@(p)p.gridConverged,post));end
if all(cellfun(@(p)isfield(p,'gridPointsUsed'),post)),P.gridPointsUsed=sum(cellfun(@(p)p.gridPointsUsed,post));end
end

function [samples,info]=v17_population_samples(M,H,P,bank,c)
samples=[];weight=[];rho=[];maximum=[];outside=[];
for j=1:numel(M.populationMembers)
 [ss,ii]=model_samples(M.populationMembers{j},H,P.memberPosteriors{j},bank,c);
 if isfield(ii,'sampleWeights'),w=ii.sampleWeights(:);else,w=ones(numel(ss),1)/numel(ss);end
 samples=[samples;ss(:)];weight=[weight;w/sum(w)/numel(M.populationMembers)]; %#ok<AGROW>
 if isfield(ii,'rhoRMS'),rho(end+1)=ii.rhoRMS;maximum(end+1)=ii.rhoMaxAbs;outside(end+1)=ii.outOfSupportFraction;end %#ok<AGROW>
end
info=struct('sampleWeights',weight,'rhoRMS',sqrt(mean(rho.^2)),'rhoMaxAbs',max([0 maximum]),'outOfSupportFraction',mean(outside));
end

function n=v17_population_count(M)
n=1;if isfield(M,'populationMembers'),n=numel(M.populationMembers);end
end

function M=v17_disable_future_residual(M)
M.bound=0;
if isfield(M,'populationMembers')
 for j=1:numel(M.populationMembers),M.populationMembers{j}=v17_disable_future_residual(M.populationMembers{j});end
end
end

function v17_consolidated_reporting(E,c,e,outDir)
M=E.models{1};d=M.marginalDiagnostic;
fprintf('\nV15 EVENT-TIME AND MODEL-SELECTION AUDIT:\n');
fprintf('TRAIN exact failures %d, right-censored units %d; maximum damage-clock root error %.4g.\n',d.exactFailureUnits,d.censoredUnits,d.maximumFailureClockError);
fprintf('Emission profile stationary=%d, scaled gradient %.4g; terminal-D anchor used=%d.\n',d.emissionConverged,d.emissionStationarity,d.terminalDamageAnchorUsed);
fprintf('B is a reversible residual observation state; eta is a static unit effect. Neither is an additional fatigue mechanism.\n');
if isfield(E.dutyModel,'family'),fprintf('Shared probabilistic duty law: %s; selected using VAL operating forecasts.\n',E.dutyModel.family);end
if ~v17_bootstrap_required(c,E.evidence),fprintf('UQ: global parameters conditional for this fleet (unit bootstrap not configured for it); bands are CAL-conformal.\n');
else,fprintf('Population uncertainty uses finite TRAIN-unit refits, conditional on the selected architecture, duty law and (if configured) TRAIN encoder.\n');end
if ~isempty(E.dutyValidation),writetable(E.dutyValidation,fullfile(outDir,sprintf('VAL_duty_energy_%02d.csv',e)));end
if ~isempty(E.bootstrapAudit),writetable(E.bootstrapAudit,fullfile(outDir,sprintf('Population_bootstrap_%02d.csv',e)));disp(E.bootstrapAudit);end
if ~c.makePlots,return;end
f=new_figure(c,sprintf('E%d v17 event likelihood and selected models',e));tiledlayout(2,2,'TileSpacing','compact');
nexttile;histogram(M.trainingEta);xlabel('TRAIN unit effect eta');ylabel('Units');title('Failure-clock-implied unit effects');grid on;
nexttile;bounds=zeros(numel(c.policies),1);families=cell(size(bounds));
for p=1:numel(c.policies),N=v17_for_policy(M,c.policies{p});bounds(p)=v17_model_bound(N);families{p}=v17_model_family(N);end
bar(bounds);xticks(1:numel(bounds));xticklabels(c.policies);ylabel('Selected log-rate bound');title('Applied primary family by duty');ylim([0 max(.2,1.4*max(bounds))]);
for p=1:numel(bounds),text(p,bounds(p)+.015,families{p},'HorizontalAlignment','center');end
nexttile;
if ~isempty(E.dutyValidation)
 T=E.dutyValidation;bar([T.markovEnergy T.blockEnergy]);xlabel('VAL unit');ylabel('Operating-path energy score');legend('One-step Markov','Conditional blocks');title('Duty law selection, lower is better');
else,text(.1,.5,'Duty-law selection disabled');axis off;end
nexttile;
if ~isempty(E.bootstrapAudit)
 T=E.bootstrapAudit;labels=unique(strcat(T.method,'/',T.policy),'stable');counts=zeros(numel(labels),1);
 for j=1:numel(labels),counts(j)=sum(T.accepted(strcmp(strcat(T.method,'/',T.policy),labels{j})));end
 barh(counts);yticks(1:numel(labels));yticklabels(labels);xline(c.bootstrapMinimumMembers,':');xlabel('Successful refits');title('Finite unit-bootstrap adequacy');
else,text(.1,.5,'Global parameter uncertainty omitted in this run');axis off;end
save_plot(f,outDir,sprintf('E%02d_v17_event_policy_uncertainty',e),c);
end

function T=v17_bootstrap_check(c)
% Small native exercise of actual unit resampling, population refits, saved
% member recovery and a member-specific posterior mixture. No RUL ranking.
c.trainUnits=4;c.validationUnits=3;c.calibrationUnits=10;c.testUnits=3;c.activeGradientWorkers=0;c.parallelMode='off';
c.populationBootstrapMembers=3;c.bootstrapMinimumMembers=3;c.bootstrapFitSteps=60;c.populationRecoverySteps=100;
c.policies={'planned','probabilistic'};c.makePlots=false;c.runtimeCandidateDir=fullfile(c.outputDir,['bootstrap_check_' datestr(now,'yyyymmdd_HHMMSS_FFF')]);mkdir(c.runtimeCandidateDir);
U=generate_fleet(c,'fatigue_matched',190772);train=strip_truth(U(1:4));M=v17_population_initializer(train,c,false);
[M,opt,~]=v17_marginal_fit(M,train,c,100,'bootstrap_reference',false);assert(v17_converged(opt,c));
[models,T]=v17_bootstrap_models({M},{'Physics_SSM'},train,c,1);assert(all(T.accepted));
N=v17_for_policy(models{1},'planned');assert(N.bootstrapAdequate && numel(N.populationMembers)==3);
H=causal_prefix(U(5),min(11,numel(U(5).t)));P=model_posterior(N,H,c);assert(abs(sum(P.weights)-1)<1e-12 && numel(P.memberPosteriors)==3);
[again,TT]=v17_bootstrap_models({M},{'Physics_SSM'},train,c,1);assert(isequaln(T,TT)); %#ok<ASGLU>
writetable(T,fullfile(c.runtimeCandidateDir,'Actual_bootstrap_refits.csv'));disp(T);
fprintf('Bootstrap refit, member mixture and saved-member reuse checks passed. %s\n',c.runtimeCandidateDir);
end

function G=v17_release_gate(R,G)
c=R.config;profile=true;selected=true;bootstrap=c.populationBootstrapMembers>0;families={};bootstrapFleets=0;
for e=1:numel(R.experiments)
 E=R.experiments{e};required=v17_bootstrap_required(c,E.evidence);bootstrapFleets=bootstrapFleets+required;
 for m=1:numel(E.models)
  for p=1:numel(c.policies)
   N=v17_for_policy(E.models{m},c.policies{p});
   if m==1,families{end+1}=v17_model_family(N);end %#ok<AGROW>
   if strcmp(N.kind,'lstm'),continue;end
   selected=selected && v17_candidate_eligible(N,c);
   profile=profile && isfield(N,'marginalDiagnostic') && N.marginalDiagnostic.emissionConverged && ~N.marginalDiagnostic.terminalDamageAnchorUsed;
   if required,bootstrap=bootstrap && isfield(N,'bootstrapAdequate') && N.bootstrapAdequate;end
  end
 end
end
rows={'proper_failure_survival_likelihood',profile && ~isempty(R.experiments),'Inference','Selected duty-specific mechanistic models use stationary event/survival profiles, no terminal-D anchor.'; ...
 'all_applied_policy_models_eligible',selected && ~isempty(R.experiments),'Inference','All applied mechanistic models pass their feasible-gradient and applicable encoder/curvature checks.'; ...
 'population_uncertainty_refits_available',bootstrap && bootstrapFleets>0,'Uncertainty',sprintf('Each selected mechanistic model has the configured minimum successful unit-bootstrap refits in the %d fleet(s) designated for the bootstrap sensitivity analysis.',bootstrapFleets)};
G.table=[G.table;cell2table(rows,'VariableNames',G.table.Properties.VariableNames)];G.primarySelectedFamilies=unique(families);
G.deepCorrectionActive=any(contains(families,'deep'));G.deepCorrectionActiveFraction=mean(contains(families,'deep'));
G.discrepancyActiveFraction=mean(~strcmp(families,'physics'));
populationResolved=~isempty(R.experiments);
for e=1:numel(R.experiments)
 M=R.experiments{e}.models{4};populationResolved=populationResolved && M.Bdecision.comparisonConverged;
end
G.table=[G.table;cell2table({'all_population_comparisons_resolved',populationResolved,'Inference','Unresolved B/no-B controls are collected but cannot qualify a final inference claim.'},'VariableNames',G.table.Properties.VariableNames)];
G.decision='HOLD';if all(G.table.passed),G.decision='GO';elseif ~ismember(c.workflowMode,{'confirm','full'}),G.decision='DEVELOPMENT_ONLY';end
end

function T=v17_event_tests(c)
% Production tests, independent of the retained v14 working-anchor kernel.
c.trainingLikelihood='event_time';c.directNeuralCoordinates=true;c.marginalEMiterations=80;c.marginalQuadrature=61;
c.profileDataSignature='';c.activeGradientWorkers=0;c.startParallelPool=false;
old=rng;cl=onCleanup(@()rng(old)); %#ok<NASGU>
rng(19511);names={};
U=struct('id','event_reference','t',(0:20:300)','u',ones(16,3), ...
 'y',zeros(16,3),'inspection',nan(16,1),'initialD',.01,'failureObserved',true,'failureTime',300,'plan',[]);
U.u(:,3)=0;
M=initial_model(U,c);M.kind='observed';M.useB=false;M.baselineFixed=false;M.bound=0;M.sigmaB=0;M.C(:,3)=0;
M.k=.002;M.a=0;M.unitSD=.22;M.trainingEta=0;M.sensorSD=[.045 .045 .045];M.config=c;
[eta,D,~,speed,sensitivity,errorValue,ok]=v17_failure_clock(M,U,c);
truth=log((1-U.initialD)/(M.k*U.failureTime));
assert(ok && abs(eta-truth)<1e-9 && abs(D(end)-1)<1e-9 && abs(errorValue)<1e-9);
names{end+1}='production exact failure-clock inversion matches the analytic Miner exposure root';
logdensity=v17_eta_logprior(eta,M,c)+log(speed/sensitivity);
expected=v17_eta_logprior(truth,M,c)-log(U.failureTime);
assert(abs(logdensity-expected)<1e-9);
names{end+1}='failure-time Jacobian gives the analytic truncated lognormal event density';
times=exp(linspace(log((1-U.initialD)/M.k)-c.unitEffectMax,log((1-U.initialD)/M.k)+c.unitEffectMax,20001));
ee=log((1-U.initialD)./(M.k*times));density=exp(v17_eta_logprior(ee,M,c))./times;
assert(abs(trapz(times,density)-1)<1e-6);
names{end+1}='exact failure-time density integrates to one over its declared population support';
U.y=emission_features(D,zeros(size(D)),U.u)*M.C'+.02*randn(size(U.y));
[f,F,diagnostic]=v17_event_profile(M,U,c);
assert(isfinite(f) && diagnostic.emissionConverged && diagnostic.emissionStationarity<c.innerProfileGradientTolerance);
assert(diagnostic.quadratureNodes==1 && ~diagnostic.terminalDamageAnchorUsed && F.trainingEtaSD==0);
names{end+1}='exact-failure production emission fit is convex GLS with no latent-mixture EM';
cc=c;cc.terminalDamageTolerance=.7;v17_fast_cache('reset');f2=v17_event_profile(M,U,cc);
assert(abs(f-f2)<1e-10);
names{end+1}='event likelihood is independent of the legacy terminal-damage tolerance';
N=F;N.bound=.3;N.nn=init_network(3,2,5);N.nn.w=[.02;-.01;.01;-.01;.015];
N.reference=struct('D',D,'B',zeros(size(D)),'u',U.u,'unit',ones(size(D)), ...
 'lo',[.8 .8 -.3],'hi',[1.2 1.2 .3]);
N.reference.G=physical_scores(N,D,U.u,c);N.reference.pinvG=pinv(N.reference.G,c.projectionTolerance);
N.reference.gmax=score_envelope(N,N.reference.lo,N.reference.hi,c);N=project_network(N,c);
[~,~,ss]=v17_event_trajectory(N,U,.1,c);[dp,~]=v17_event_trajectory(N,U,.1+1e-5,c);[dm,~]=v17_event_trajectory(N,U,.1-1e-5,c);
assert(max(abs(ss-(dp-dm)/2e-5),[],'all')<2e-7);
names{end+1}='production neural fatigue-clock sensitivity agrees with an independent eta difference';
[~,DD,~,~,sens,err,yes]=v17_failure_clock(N,U,c);
assert(yes && abs(err)<1e-8 && sens>0 && all(diff(DD)>=0));
names{end+1}='nonlinear bounded fatigue clock is monotone and reaches the failure criterion';
C=U;C.failureObserved=false;C.failureTime=NaN;C.y(:)=NaN;
[~,~,dg]=v17_event_profile(M,C,c);
upper=log((1-C.initialD)/(M.k*C.t(end)));z=erf(c.unitEffectMax/(sqrt(2)*M.unitSD));
prob=(.5*(1+erf(upper/(sqrt(2)*M.unitSD)))-.5*(1+erf(-c.unitEffectMax/(sqrt(2)*M.unitSD))))/z;
assert(abs(exp(-dg.marginalUnitNLL)-prob)<2e-7);
names{end+1}='right-censor likelihood retains the survival probability instead of renormalizing it away';
P=M;P.kind='pinn';P.pinnNN=init_network(c.pinnHidden1,c.pinnHidden2,5);P.pinnNN.w=.2*ones(c.pinnHidden2,1);
[d0,~,e0]=pinn_trajectory(P,U,0,c);[d1,~,e1]=pinn_trajectory(P,U,.4,c);
assert(max(abs(e1-e0),[],'all')<1e-12 && max(abs(d1-U.initialD-exp(.4)*(d0-U.initialD)),[],'all')<1e-10);
names{end+1}='PINN population exposure clock is independent of frailty and has a unique failure-time map';

% An independently differentiated small latent mixture exercises the exact
% censored-data coefficient gradient and observed Hessian, including the
% negative covariance-of-score term that a complete-data Hessian omits.
A=randn(7,3,4);G={pagemtimes(pagetranspose(A),A)};rhs={randn(3,4)};b=[.1;-.2;.05];
pen=.1*eye(3);[~,g,h]=v17_linear_mixture(b,G,rhs,.7,{log([.1 .2 .3 .4])},pen);
gg=zeros(3,1);hh=zeros(3);delta=1e-5;
for j=1:3
 bp=b;bm=b;bp(j)=bp(j)+delta;bm(j)=bm(j)-delta;
 [fp,gp]=v17_linear_mixture(bp,G,rhs,.7,{log([.1 .2 .3 .4])},pen);
 [fm,gm]=v17_linear_mixture(bm,G,rhs,.7,{log([.1 .2 .3 .4])},pen);
 gg(j)=(fp-fm)/(2*delta);hh(:,j)=(gp-gm)/(2*delta);
end
assert(max(abs(g-gg))<1e-7 && max(abs(h-hh),[],'all')<1e-6);
names{end+1}='censored-mixture exact gradient and observed Hessian match independent finite differences';

cc=c;cc.optimizerLowerBound=[-1;-1];cc.optimizerUpperBound=[1;1];cc.optimizerL1Indices=[1;2];cc.optimizerL1Radius=1;
cc.runtimeFitLabel='L1_KKT_reference';cc.runtimeCandidateDir='';cc.checkpointEveryIterations=100;
[xx,~,opt]=v17_bfgs(@(x)sum((x-2).^2),[0;0],20,cc,'');
assert(norm(xx-[.5;.5],Inf)<1e-6 && v17_converged(opt,cc) && sum(abs(xx))<=1+1e-12);
names{end+1}='production projected optimizer solves an independent L1-constrained KKT reference';

N=v17_marginal_context(N);[vv,L]=v17_marginal_encode(N,U,c,false);cc=c;
cc.optimizerLowerBound=L.lower;cc.optimizerUpperBound=L.upper;cc.optimizerL1Indices=L.l1Indices;cc.optimizerL1Radius=L.l1Radius;
vv(L.l1Indices)=2;vv=v17_project_parameters(vv,cc);[~,NN]=v17_marginal_objective(vv,N,L,U,c);
assert(sum(abs(NN.nn.w))<=NN.bound+1e-10 && max(abs(NN.nn.w-NN.bound*vv(L.l1Indices)))<1e-12);
names{end+1}='production direct residual coordinates obey the declared coefficient ball without saturation';
selected=v17_select_function_coordinates(NN,c);expected=NN.nn.w;expected(setdiff(1:numel(expected),selected.activeOutputIndices))=0;
assert(max(abs(selected.nn.w-expected))<1e-12);
names{end+1}='TRAIN output-rank selection preserves the direct warm-start coefficients on retained features';

cc=c;cc.policies={'planned','probabilistic'};cc.originHours=80;cc.forecastHorizonHours=400;
cc.forecastPaths=12;cc.forecastReplicates=2;cc.gridRefinementLevels=0;cc.policySpecificSelection=true;
cc.etaGridPoints=61;cc.coarseEtaPoints=21;cc.lstmBatch=4;
U.plan=struct('issuedAt',0,'t',[0;1000],'u',[1 1 0;1 1 0]);Q=fit_duty_model(U);
route=F;route.policyModels=struct('planned',F,'probabilistic',N);
[pred,~,~]=predict_group(U,1,{route},{'PI_DSSDM'},Q,cc,1,'SOFTWARE_TEST',false);
assert(strcmp(pred.selectedFamily{1},'physics') && strcmp(pred.selectedFamily{2},'deep'));
assert(pred.selectedResidualBound(1)==0 && pred.selectedResidualBound(2)==N.bound);
names{end+1}='production forecasts route the entire fitted model by duty protocol and disclose its family';

V=U;later=V.t>80;V.y(later,:)=1e8;V.u(later,:)=1e6;V.failureTime=9999;V.inspection(later)=.99;
[altered,~,~]=predict_group(V,1,{route},{'PI_DSSDM'},Q,cc,1,'SOFTWARE_TEST',false);
assert(isequaln(pred.predictedRUL_h,altered.predictedRUL_h) && isequaln(pred.estimatedD,altered.estimatedD));
names{end+1}='actual protocol-routed forecasts are immune to future sensors, inputs, inspections and failure labels';

cc.forecastHorizonHours=800;H=causal_prefix(U,5);ensemble=F;ensemble.populationMembers={F,F};
PP=model_posterior(F,H,cc);PE=model_posterior(ensemble,H,cc);bank=future_bank(H,'planned',Q,cc,12);
[s1,i1]=model_samples(F,H,PP,bank,cc);[s2,i2]=model_samples(ensemble,H,PE,bank,cc);
assert(abs(sum(PE.weights)-1)<1e-12 && abs(sum(i2.sampleWeights)-1)<1e-12);
assert(abs(v17_quantile(s1,i1,.5)-v17_quantile(s2,i2,.5))<1e-9);
assert(numel(PE.memberPosteriors)==2 && v17_population_count(ensemble)==2);
names{end+1}='population mixtures use member-specific causal posteriors and preserve identical-member distributions';

q=struct('current',[(1:8)' ones(8,1) zeros(8,1)],'next',[(2:9)' ones(8,1) zeros(8,1)], ...
 'mean',[0 0 0],'sd',[1 1 1],'family','conditional_blocks','blockNext',[2:8 0]', ...
 'nextNeighbors',ones(8,1));q.z=[log(q.current(:,1)) zeros(8,2)];cc.dutyBlockLength=4;
rng(718);bb=future_bank(H,'probabilistic',q,cc,12);loadHistory=bb.u(:,:,1);
for k=3:size(loadHistory,1)
 if mod(k-3,cc.dutyBlockLength)~=cc.dutyBlockLength-1
  assert(all(abs(loadHistory(k,:)-loadHistory(k-1,:)-1)<1e-12 | loadHistory(k,:)==2));
 end
end
assert(all(loadHistory(1,:)==H.u(end,1)));
names{end+1}='conditional duty blocks preserve TRAIN adjacency and the known first operating interval';

V=U;V.id='second_clock';V.t=V.t*.83;V.failureTime=V.t(end);V.u(:,1)=1.15;
B=v17_failure_clocks_batch(N,[U V],c);
for i=1:2
 units=[U V];[ee,dd,~,vv,ss]=v17_failure_clock(N,units(i),c);
 assert(abs(B{i}.eta-ee)<1e-9 && max(abs(B{i}.D-dd))<1e-9 && abs(B{i}.speed-vv)<1e-10 && abs(B{i}.sensitivity-ss)<1e-8);
end
names{end+1}='batched failure clocks match independent scalar midpoint paths and sensitivities for unequal unit time grids';

dd=[-.15;.35;1.2];uu=[1 1 0;1 1 0;1 1 0];[rho,sens]=v17_damage_discrepancy_sensitivity(N,dd,uu,c);
actual=discrepancy(N,dd,zeros(size(dd)),uu);fp=discrepancy(N,dd+1e-6,zeros(size(dd)),uu);fm=discrepancy(N,dd-1e-6,zeros(size(dd)),uu);
assert(max(abs(rho-actual))<1e-12 && max(abs(sens-(fp-fm)/2e-6))<1e-7);
uu(:,1)=100;[rho,sens]=v17_damage_discrepancy_sensitivity(N,dd,uu,c);assert(all(rho==0 & sens==0));
names{end+1}='fatigue-clock runtime value and sensitivity match inference inside and outside damage and operating support';
T=table(names',true(numel(names),1),'VariableNames',{'test','passed'});
end

function [D,q,E]=v17_pinn_vector_trajectory(M,H,eta,c)
% Exact vectorization of the original explicit-midpoint PINN clock. E is a
% population exposure clock and is independent of eta. Every original
% substep, left operating input and midpoint network evaluation is retained.
eta=eta(:);K=numel(H.t);A=zeros(K,1);ex=zeros(K,1);
if K>1
 dt=diff(H.t);ns=max(1,ceil(dt/c.transitionStepHours));h=dt./ns;
 er=c.nominalRate*H.u(1:end-1,1).^c.nominalLoadExponent.*H.u(1:end-1,2).*exp(c.nominalTempCoefficient*H.u(1:end-1,3));
 ex=[0;cumsum(dt.*er)];interval=repelem((1:K-1)',ns);
 first=cumsum([1;ns(1:end-1)]);sub=(1:numel(interval))'-repelem(first,ns)+.5;
 hh=h(interval);ee=ex(interval)+sub.*hh.*er(interval);tt=H.t(interval)+sub.*hh;
 rr=pinn_rate(M,ee,tt,H.u(interval,:),zeros(numel(interval),1),c);
 A=[0;cumsum(accumarray(interval,hh.*rr,[K-1 1],@sum,0))];
end
factor=exp(eta)';D=H.initialD+A*factor;
q=pinn_rate(M,ex,H.t,H.u,zeros(K,1),c)*factor;E=repmat(ex,1,numel(eta));
end

function [eta,D,q,speed,sensitivity,errorValue,valid]=v17_direct_pinn_clock(M,U,c)
% D(t,eta)=D0+exp(eta)*A(t). Invert exactly, retaining the original
% midpoint-discretized trajectory and event-density Jacobian.
[unitD,unitQ]=v17_pinn_vector_trajectory(M,U,0,c);A=unitD-U.initialD;
eta=log(max(c.Dcrit-U.initialD,realmin)/max(A(end),realmin));
D=U.initialD+exp(eta)*A;q=exp(eta)*unitQ;sensitivity=D(end)-U.initialD;
% The original event density uses the terminal left-limit operating input.
E=sum(diff(U.t).*(c.nominalRate*U.u(1:end-1,1).^c.nominalLoadExponent.*U.u(1:end-1,2).*exp(c.nominalTempCoefficient*U.u(1:end-1,3))));
speed=pinn_rate(M,E,U.t(end),U.u(max(1,end-1),:),eta,c);
errorValue=D(end)-c.Dcrit;
valid=isfinite(eta) && abs(eta)<c.unitEffectMax && abs(errorValue)<20*c.failureRootTolerance && sensitivity>0;
end

function [cal,test,filters,ablation,bands,cc]=v17_forecast_bundle(units,ids,models,methods,Q,c,eid,evidence,tag)
% POINT and FINAL namespaces are deliberately disjoint. A parameter-mixture
% forecast must never reuse a conditional point-parameter cache entry.
[vp,~,~]=v17_predict_cached(units,ids.validation,models,methods,Q,c,eid,evidence,false,[tag '_VAL']);
cc=c;cc.calibrationScales=v17_fit_band_scales(vp,c);
[cal,~,~]=v17_predict_cached(units,ids.calibration,models,methods,Q,cc,eid,evidence,false,[tag '_CAL']);
[test,filters,ablation]=v17_predict_cached(units,ids.test,models,methods,Q,cc,eid,evidence,true,[tag '_TEST']);
[test,bands]=calibrate_bands(cal,test,cc);
cal=v17_tag_forecasts(cal,models,methods,c);test=v17_tag_forecasts(test,models,methods,c);
end

function P=v17_tag_forecasts(P,models,methods,c)
P.estimationEligible=false(height(P),1);
for m=1:numel(models)
 for p=1:numel(c.policies)
  policy=c.policies{p};N=v17_for_policy(models{m},policy);
  z=strcmp(P.method,methods{m}) & strcmp(P.policy,policy);
  P.estimationEligible(z)=v17_candidate_eligible(N,c);
 end
end
end

function T=v17_tag_metrics(T,models,methods,c)
T.estimationEligible=false(height(T),1);
for m=1:numel(models)
 for p=1:numel(c.policies)
  policy=c.policies{p};N=v17_for_policy(models{m},policy);
  z=strcmp(T.method,methods{m}) & strcmp(T.policy,policy);
  T.estimationEligible(z)=v17_candidate_eligible(N,c);
 end
end
end

function yes=v17_has_population_members(models,c)
yes=false;
for m=1:numel(models)
 for p=1:numel(c.policies)
  N=v17_for_policy(models{m},c.policies{p});
  yes=yes || (isfield(N,'populationMembers') && ~isempty(N.populationMembers));
 end
end
end

function v17_export_point_results(S,models,methods,c,eid,runDir)
[T,A]=metrics(S.test,c);T=v17_tag_metrics(T,models,methods,c);
writetable(S.test,fullfile(runDir,sprintf('E%03d_POINT_conditional_predictions.csv',eid)));
writetable(T,fullfile(runDir,sprintf('E%03d_POINT_conditional_metrics.csv',eid)));
writetable(A,fullfile(runDir,sprintf('E%03d_POINT_conditional_alpha_lambda.csv',eid)));
fprintf('\nPOINT FORECASTS SAVED for experiment %d BEFORE population bootstrap.\n',eid);
fprintf('Conditional parameter estimates with CAL bands; population uncertainty not yet included.\n');
disp(T(:,{'method','policy','MAE_h','RMSE_h','bias_h','coverage','estimationEligible'}));
if c.makePlots
 f=new_figure(c,sprintf('E%d conditional point forecast checkpoint',eid));
 tiledlayout(1,numel(c.policies),'TileSpacing','compact');
 for p=1:numel(c.policies)
  nexttile;Q=T(strcmp(T.policy,c.policies{p}),:);bar(categorical(Q.method),Q.MAE_h);
  ylabel('Conditional point MAE, h');title([c.policies{p} ': population refits pending']);grid on;
 end
 save_plot(f,runDir,sprintf('E%02d_POINT_conditional_MAE',eid),c);
end
end

function T=v17_workflow_tests(c)
% Regression checks for the actual observed stop and expensive PINN path.
names={};cf=v17_configuration('full',configuration());
assert(isinf(cf.maxRunSeconds) && ~cf.requireResolvedPopulation && cf.savePointForecastsFirst && cf.skipIneligibleBootstrap);
assert(cf.trainUnits==24 && cf.replicates==5 && numel(cf.scenarios)==6 && cf.gradientTolerance==5e-5);
assert(ismember('fatigue_load_exponent',cf.scenarios) && cf.seed==2028102201 && cf.resolutionGradientTolerance==10*cf.gradientTolerance);
names{end+1}='FULL keeps 5 fleets per scenario (6 scenarios), original tolerance, new seed family, no wall-time stop';
ca=v17_configuration('assess',configuration());
assert(ca.trainUnits==24 && ca.validationUnits==10 && ca.calibrationUnits==24 && ca.testUnits==16 && ca.replicates==3);
assert(numel(ca.scenarios)==4 && ca.populationBootstrapMembers==0 && ca.jointRecoverySteps==0 && ca.seed==2030102201 && ca.gradientTolerance==5e-5);
names{end+1}='ASSESS keeps full unit splits and tolerance with its own seed family and reduced budgets';
for cfg={cf,ca}
 k=cfg{1};assert(k.pinnStarts==k.residualStarts && k.pinnIterations==k.functionalSteps && k.processKappaSEMultiplier==1);
end
names{end+1}='inverse PINN receives the deep model starts and per-cycle iteration budget; kappa needs a one-SE VAL gain';
% 17.2 fast FULL profile: same design and seeds, ASSESS-validated estimator,
% replicate-1 encoder-conditional bootstrap; 'full_exhaustive' keeps 17.1.
assert(strcmp(cf.fullProfile,'fast') && isequal(cf.residualBounds,[0 .30 .50]) && cf.jointRecoverySteps==0 && ~cf.requireJointEncoderStationarity);
assert(cf.populationBootstrapMembers==8 && cf.bootstrapReplicates==1 && ~cf.bootstrapRefitEncoder && cf.bootstrapMinimumMembers==5 && cf.validationUnits==10);
ce=v17_configuration('full_exhaustive',configuration());
assert(strcmp(ce.fullProfile,'exhaustive') && ce.functionalSteps==200 && ce.jointRecoverySteps==120 && isinf(ce.bootstrapReplicates) && ce.seed==cf.seed && ce.bootstrapRefitEncoder);
co=v17_configuration('confirm',configuration());assert(strcmp(co.fullProfile,'fast') && co.seed==2027102201 && isequal(co.residualBounds,cf.residualBounds));
assert(v17_bootstrap_required(cf,'SYNTHETIC:fatigue_matched:rep1') && ~v17_bootstrap_required(cf,'SYNTHETIC:fatigue_matched:rep2') && v17_bootstrap_required(ce,'SYNTHETIC:x:rep5'));
names{end+1}='fast FULL keeps design, splits and seeds; bootstrap limited to replicate 1; exhaustive profile unchanged';
% Fleet-level statistics against hand-computed references.
assert(abs(v17_signrank_p([1 2 3 4 5])-.0625)<1e-12 && abs(v17_sign_p([1 2 3 4 5])-.0625)<1e-12);
assert(abs(v17_signrank_p([-1 2 3 -4 5 6])-.3125)<1e-12 && v17_signrank_p([0 0])==1);
assert(max(abs(v17_holm([.01 .04 .03])-[.03 .06 .06]))<1e-12);
[lo,hi,tp]=v17_t_interval([1 2 3]);assert(abs(lo-(2-4.302652729911275/sqrt(3)))<1e-9 && abs(hi-(2+4.302652729911275/sqrt(3)))<1e-9 && abs(tp-.07417990022744862)<1e-9);
names{end+1}='paired t interval/p, exact Wilcoxon signed-rank, sign test and Holm match references';
% Publication style: every font exactly +3 pt, applied once.
f=figure('Visible','off');ax=axes(f);plot(ax,1:3);title(ax,'t');xlabel(ax,'x');lg=legend(ax,'a');lg.FontSize=8;tx=text(ax,1,1,'n');
before=[ax.FontSize ax.Title.FontSize ax.XLabel.FontSize lg.FontSize tx.FontSize];
v17_publication_style(f,3);after=[ax.FontSize ax.Title.FontSize ax.XLabel.FontSize lg.FontSize tx.FontSize];
v17_publication_style(f,3);again=[ax.FontSize ax.Title.FontSize ax.XLabel.FontSize lg.FontSize tx.FontSize];close(f);
assert(max(abs(after-before-3))<1e-9 && isequal(after,again));
names{end+1}='publication style adds exactly 3 pt to every font (ticks, title, labels, legend, text) and is idempotent';
% Publication layer end to end on a minimal ONE-fleet, ONE-scenario result
% (the case where bar() would otherwise collapse to a single series).
d=tempname;mkdir(d);cleanupDir=onCleanup(@()rmdir(d,'s'));
k=configuration();k.policies={'planned'};k.makePlots=true;k.showFigures=false;k.figureResolution=60;k.plotFontIncrement=3;k.figureSize=[900 600];k.workflowMode='full';
ev={'SYNTHETIC:fatigue_load_exponent:rep1'};mm={'PI_DSSDM';'Physics_SSM';'LSTM'};
Mt=table([1;1;1],repmat(ev,3,1),mm,repmat({'planned'},3,1),[10;12;20],[.9;.92;.8],[50;60;90],'VariableNames',{'experiment','evidence','method','policy','MAE_h','coverage','meanWidth_h'});
Al=table([1;1],{'PI_DSSDM';'Physics_SSM'},{'planned';'planned'},[0;0],[.5;.5],[3;3],[.9;.8],'VariableNames',{'experiment','method','policy','lambdaLower','lambdaUpper','forecasts','alphaLambdaAccuracy'});
Pt=table(repmat(ev,2,1),{'PI_DSSDM';'PI_DSSDM'},{'planned';'planned'},{'deep';'physics'},'VariableNames',{'evidence','method','policy','selectedFamily'});
mkdir(fullfile(d,'stages'));stageElapsedSeconds=60;stageComplete=true;save(fullfile(d,'stages','E001_primary.mat'),'stageElapsedSeconds','stageComplete');
RR=struct('version','test','config',k,'outputDir',d,'metrics',Mt,'alphaLambda',Al,'predictions',Pt,'experiments',{{struct()}},'plannedExperiments',1,'sourceSHA256','x');
PP=v17_publication_outputs(RR);
assert(isfile(fullfile(PP.outputDir,'Results_summary.md')) && isfile(fullfile(PP.outputDir,'Fig5_applied_family.png')) && isfile(fullfile(PP.outputDir,'Fig6_runtime_by_stage.pdf')));
assert(height(PP.paired)==4 && all(abs(PP.paired.meanGain_h(strcmp(PP.paired.comparator,'Physics SSM'))-2)<1e-12));
clear cleanupDir;
names{end+1}='publication tables, Fig1-Fig6 and summary build from a single-fleet result without refitting';
v17_deadline('start',Inf);assert(~v17_deadline('expired'));
names{end+1}='unlimited deadline remains active without triggering a pause';
cc=c;cc.trainUnits=3;cc.validationUnits=2;cc.calibrationUnits=10;cc.testUnits=2;
U=generate_fleet(cc,'fatigue_matched',160201);train=strip_truth(U(1:3));M=initial_model(train,cc);
M.kind='pinn';M.pinnNN=init_network(cc.pinnHidden1,cc.pinnHidden2,5);M.pinnNN.w(:)=.17;
M.baselineFixed=false;M.C(:,7)=0;
H=U(1);H.t=H.t+linspace(0,.37,numel(H.t))';H.initialD=.03;
eta=[-.43;0;.37];[D,q,E]=pinn_trajectory(M,H,eta,cc);[Dr,qr,Er]=v17_scalar_pinn_trajectory_reference(M,H,eta,cc);
assert(max(abs(D-Dr),[],'all')<2e-12 && max(abs(q-qr),[],'all')<2e-12 && max(abs(E-Er),[],'all')<2e-12);
names{end+1}='vectorized PINN matches original midpoint D, derivative and exposure on irregular intervals';
[ee,dd,qq,ss,se,er,ok]=v17_failure_clock(M,U(1),cc);[re,rd,rq,rs,rse,rer,rok]=v17_scalar_failure_clock_reference(M,U(1),cc);
assert(ok && rok && abs(ee-re)<2e-8 && max(abs(dd-rd))<2e-8 && max(abs(qq-rq))<2e-8);
assert(abs(ss-rs)<2e-8 && abs(se-rse)<2e-8 && abs(er-rer)<2e-8);
names{end+1}='direct PINN failure-clock inversion preserves scalar root, trajectory and event Jacobian';
slow=cc;slow.fastPinnClock=false;fast=cc;fast.fastPinnClock=true;
for censored=[false true]
 sample=train;
 if censored,sample(1).failureObserved=false;sample(1).failureTime=Inf;end
 [fa,MA]=v17_event_profile(M,sample,fast);[fb,MB]=v17_event_profile(M,sample,slow);
 assert(abs(fa-fb)<2e-8 && max(abs(MA.C(:)-MB.C(:)))<2e-7);
 assert(abs(MA.marginalDiagnostic.rawMarginalNLL-MB.marginalDiagnostic.rawMarginalNLL)<2e-6);
end
names{end+1}='accelerated PINN preserves profiled exact-failure and mixed censored likelihoods';
% Unresolved comparator refits are skipped BEFORE creating bootstrap folders.
cc.runtimeCandidateDir=tempname;mkdir(cc.runtimeCandidateDir);cl=onCleanup(@()v17_remove_test_dir(cc.runtimeCandidateDir)); %#ok<NASGU>
cc.populationBootstrapMembers=2;cc.skipIneligibleBootstrap=true;
N=M;N.selectedMStep=struct('exitflag',0,'gradientNorm',1,'converged',false);
[models,B]=v17_bootstrap_models({N},{'Inverse_PINN'},train,cc,1);
assert(height(B)==numel(cc.policies) && all(B.member==0) && ~any(B.accepted));
assert(~v17_has_population_members(models,cc) && ~models{1}.bootstrapAdequate);
assert(isempty(dir(fullfile(cc.runtimeCandidateDir,'bootstrap_*'))));
names{end+1}='ineligible base comparator gets an explicit skipped UQ record without refitting or false eligibility';
T=table(names',true(numel(names),1),'VariableNames',{'test','passed'});
end

function v17_remove_test_dir(folder)
resolved=char(java.io.File(folder).getCanonicalPath());allowed=char(java.io.File(tempdir).getCanonicalPath());
assert(startsWith(lower(resolved),[lower(allowed) filesep]) && ~strcmpi(resolved,allowed),'pi17:testCleanup','Unexpected cleanup path');
if isfolder(resolved),rmdir(resolved,'s');end
end

function B=v17_pinn_timing_check(c)
cc=c;cc.trainUnits=3;cc.validationUnits=2;cc.calibrationUnits=10;cc.testUnits=2;
U=generate_fleet(cc,'fatigue_matched',160201);M=initial_model(strip_truth(U(1:3)),cc);
M.kind='pinn';M.pinnNN=init_network(cc.pinnHidden1,cc.pinnHidden2,5);M.pinnNN.w(:)=.17;
H=U(1);pinn_trajectory(M,H,0,cc);v17_scalar_pinn_trajectory_reference(M,H,0,cc);
t=tic;for j=1:10,[D,q,E]=v17_scalar_pinn_trajectory_reference(M,H,[-.2;0;.2],cc);end;scalar=toc(t)/10;
t=tic;for j=1:10,[A,b,f]=pinn_trajectory(M,H,[-.2;0;.2],cc);end;fast=toc(t)/10;
B=table(scalar,fast,scalar/max(fast,eps),max(abs(D-A),[],'all'),max(abs(q-b),[],'all'),max(abs(E-f),[],'all'), ...
 'VariableNames',{'scalarSeconds','vectorizedSeconds','measuredSpeedup','maxDamageDifference','maxRateDifference','maxExposureDifference'});disp(B);
end

function [D,q,E]=v17_scalar_pinn_trajectory_reference(M,H,eta,c)
eta=eta(:);N=numel(eta);K=numel(H.t);D=zeros(K,N)+H.initialD;E=zeros(K,N);q=zeros(K,N);
for k=1:K
 if k>1
  dt=H.t(k)-H.t(k-1);ns=max(1,ceil(dt/c.transitionStepHours));h=dt/ns;
  d=D(k-1,:)';ex=E(k-1,:)';u=repmat(H.u(k-1,:),N,1);
  for j=1:ns
   tt=H.t(k-1)+(j-1)*h;[~,er]=pinn_rate(M,ex,tt,u,eta,c);
   [rmid,~]=pinn_rate(M,ex+.5*h*er,tt+.5*h,u,eta,c);d=d+h*rmid;ex=ex+h*er;
  end
  D(k,:)=d';E(k,:)=ex';
 end
 q(k,:)=pinn_rate(M,E(k,:)',H.t(k),repmat(H.u(k,:),N,1),eta,c)';
end
end


function [eta,D,q,terminalRate,sensitivity,errorValue,valid]=v17_scalar_failure_clock_reference(M,U,c)
% Unique clock inversion for the scalar irreversible transition. The PINN
% uses a population exposure clock independent of eta, preserving uniqueness.
bare=physics_rate(M,U.u(1:end-1,:));exposure=sum(diff(U.t).*bare);
eta=log(max(c.Dcrit-U.initialD,eps)/max(exposure,realmin));eta=max(-c.unitEffectMax,min(c.unitEffectMax,eta));
lo=-c.unitEffectMax;hi=c.unitEffectMax;
for iteration=1:c.failureRootMaximumIterations
 [D,q,S]=v17_event_trajectory(M,U,eta,c);errorValue=D(end)-c.Dcrit;sensitivity=S(end);
 if abs(errorValue)<c.failureRootTolerance,break;end
 if errorValue>0,hi=eta;else,lo=eta;end
 proposed=eta-errorValue/max(sensitivity,eps);
 if ~isfinite(proposed) || proposed<=lo || proposed>=hi,proposed=(lo+hi)/2;end
 if abs(proposed-eta)<1e-13,break;end
 eta=proposed;
end
[D,q,S]=v17_event_trajectory(M,U,eta,c);errorValue=D(end)-c.Dcrit;sensitivity=S(end);
valid=abs(errorValue)<20*c.failureRootTolerance && sensitivity>0 && abs(eta)<c.unitEffectMax;
if strcmp(M.kind,'pinn')
 [~,~,E]=pinn_trajectory(M,U,eta,c);
 [terminalRate,~]=pinn_rate(M,E(end),U.t(end),U.u(max(1,end-1),:),eta,c);
else
 u=U.u(max(1,end-1),:);terminalRate=physics_rate(M,u)*exp(eta+discrepancy(M,c.Dcrit,0,u))*(1+M.a*c.Dcrit);
end
end

