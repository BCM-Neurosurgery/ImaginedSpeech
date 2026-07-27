function config = load_task_config(configPath, projectRoot)
%LOAD_TASK_CONFIG Load and minimally validate the task's JSON configuration.

if ~isfile(configPath)
    error('ImaginedSpeech:MissingConfig', 'Configuration not found: %s', configPath);
end

config = jsondecode(fileread(configPath));
requiredSections = {'display', 'launcher', 'placeholder', 'block0', 'block1', 'block2', 'block3', 'block4', 'keys', ...
    'photodiode', 'cbmex', 'paths'};
for index = 1:numel(requiredSections)
    section = requiredSections{index};
    if ~isfield(config, section)
        error('ImaginedSpeech:InvalidConfig', 'Missing config section: %s', section);
    end
end

if config.schema_version ~= 1
    error('ImaginedSpeech:InvalidConfig', ...
        'Unsupported config schema_version: %g', config.schema_version);
end
if ~isscalar(config.placeholder.duration_seconds) || ...
        ~isfinite(config.placeholder.duration_seconds) || ...
        config.placeholder.duration_seconds <= 0
    error('ImaginedSpeech:InvalidConfig', ...
        'placeholder.duration_seconds must be a positive finite scalar.');
end
if numel(config.display.background_rgb) ~= 3 || ...
        numel(config.display.text_rgb) ~= 3
    error('ImaginedSpeech:InvalidConfig', 'Display colors must be RGB triplets.');
end
if ~isscalar(config.block0.auto_advance_seconds) || ...
        ~isfinite(config.block0.auto_advance_seconds) || ...
        config.block0.auto_advance_seconds < 0
    error('ImaginedSpeech:InvalidConfig', ...
        'block0.auto_advance_seconds must be a finite nonnegative scalar.');
end
if config.block0.horizontal_margin_percent <= 0 || ...
        config.block0.horizontal_margin_percent >= 45
    error('ImaginedSpeech:InvalidConfig', ...
        'block0.horizontal_margin_percent must be between 0 and 45.');
end

config.project_root = projectRoot;
config.paths.task_data = fullfile(projectRoot, config.paths.task_data);
config.paths.output = fullfile(projectRoot, config.paths.output);
if ~isfolder(config.paths.patient_data) && ~isfile(config.paths.patient_data)
    % Preserve absolute configured paths; relative paths are project-rooted.
    if ~isAbsolutePath(config.paths.patient_data)
        config.paths.patient_data = fullfile(projectRoot, config.paths.patient_data);
    end
end
config.block0.content_file = fullfile(config.paths.task_data, ...
    config.block0.content_file);
config.block1.content_file = fullfile(config.paths.task_data, ...
    config.block1.content_file);
config.block2.content_file = fullfile(config.paths.task_data, ...
    config.block2.content_file);
config.block3.content_file = fullfile(config.paths.task_data, ...
    config.block3.content_file);
config.block4.content_file = fullfile(config.paths.task_data, ...
    config.block4.content_file);
end

function tf = isAbsolutePath(pathValue)
tf = ~isempty(regexp(char(pathValue), '^[A-Za-z]:[\\/]|^\\\\', 'once'));
end
