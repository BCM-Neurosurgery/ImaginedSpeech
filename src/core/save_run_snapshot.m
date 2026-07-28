function save_run_snapshot(config, blockNumber, runId, sources)
%SAVE_RUN_SNAPSHOT Persist resolved config, environment, and content provenance for one block run.
%
% sources is a struct array with fields label and path identifying every
% task-data file that determined this run's stimuli/schedule (manifests,
% schedules, survey data). Their SHA-256 hashes are computed once here,
% before any timed trial, so a run remains fully reproducible even if the
% same-named task-data file is edited or swapped before a later run; the
% per-trial CSV logs already carry the presented-stimulus identity for
% every trial that actually executed.

for index = 1:numel(sources)
    sources(index).sha256 = compute_file_hash(sources(index).path);
end

snapshot = struct( ...
    'schema_version', 1, ...
    'block_number', blockNumber, ...
    'run_id', runId, ...
    'saved_at', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS')), ...
    'config', config, ...
    'environment', struct( ...
        'matlab_version', version, ...
        'computer', computer, ...
        'psychtoolbox_version', PsychtoolboxVersion, ...
        'hostname', getComputerHostname()), ...
    'content_sources', sources);

matPath = fullfile(config.session.directory, sprintf('block%d_%s_config.mat', blockNumber, runId));
save(matPath, 'snapshot');
end

function name = getComputerHostname()
name = char(getenv('COMPUTERNAME'));
if isempty(name)
    name = char(getenv('HOSTNAME'));
end
end
