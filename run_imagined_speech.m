
function run_imagined_speech()
%RUN_IMAGINED_SPEECH Launch the Imagined Speech block selector.

projectRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(projectRoot, 'src', 'config'));
addpath(fullfile(projectRoot, 'src', 'core'));
addpath(fullfile(projectRoot, 'src', 'blocks'));
addpath(fullfile(projectRoot, 'src', 'io'));

configPath = fullfile(projectRoot, 'config', 'task_config.json');
config = load_task_config(configPath, projectRoot);
assert_psychtoolbox_available();

[blockNumber, patientId] = select_task_block(config.launcher);
if isempty(blockNumber)
    fprintf('Imagined Speech launcher closed without selecting a block.\n');
    return;
end

config.session = create_patient_session(config.paths.patient_data, patientId);

blockRunners = {@run_block_0, @run_block_1, @run_block_2, ...
    @run_block_3, @run_block_4};
lifecycle = start_task_lifecycle(config, blockNumber);
config.cbmex.lifecycle = lifecycle;
try
    blockRunners{blockNumber + 1}(config);
    finish_task_lifecycle(lifecycle, 'stop');
catch taskError
    if strcmp(taskError.identifier, 'ImaginedSpeech:TaskKilled')
        finish_task_lifecycle(lifecycle, 'kill');
        fprintf('Imagined Speech Block %d ended early by Escape.\n', blockNumber);
    else
        finish_task_lifecycle(lifecycle, 'error');
        rethrow(taskError);
    end
end
end
