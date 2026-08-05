function lifecycle = start_task_lifecycle(config, blockNumber)
%START_TASK_LIFECYCLE Mirror TaskComment('start') with persistent NSP links.
%
% Exactly one of config.cbmex.enabled / config.matcbsdk.enabled may be true
% (enforced by load_task_config); whichever is set selects the backend that
% opens NSP connections and sends TaskStart/TaskID/TaskStop/TaskKill/TaskErr
% comments. cbmex addresses each physical NSP by IP (discovered via
% getIPAddressesFromPortNames) and a numeric 'instance'; matcbsdk instead
% opens one Session per configured device_type (e.g. "NSP", or "HUB1"/"HUB2"
% for a multi-NSP Central setup), since its Session wrapper has no
% equivalent IP-based discovery.
%
% The +CurrentPatientLog EMU-number allocation (getNextLogEntry/
% setNextLogEntry) is optional per backend (cbmex.use_patient_log /
% matcbsdk.use_patient_log) — some rigs don't have that patient log set up
% at all. When disabled, no patient-log function is called, and every
% TaskStart/TaskID/TaskStop/TaskKill/TaskErr comment uses the patient ID
% directly in place of an EMU-#### label.

lifecycle = struct('enabled', false, 'backend', "none", 'instances', [], ...
    'sessions', {{}}, 'labels', strings(1, 0), 'emu_id', NaN, 'id_label', '', ...
    'task_id', '', 'connections_open', false);
if ~config.cbmex.enabled && ~config.matcbsdk.enabled
    return;
end

if config.cbmex.enabled
    backend = "cbmex";
    taskName = config.cbmex.task_name;
    usePatientLog = config.cbmex.use_patient_log;
    required = {'cbmex', 'getIPAddressesFromPortNames'};
else
    backend = "matcbsdk";
    taskName = config.matcbsdk.task_name;
    usePatientLog = config.matcbsdk.use_patient_log;
    required = {'Session', 'matcbsdk'};
end
if usePatientLog
    required = [required, {'getNextLogEntry', 'setNextLogEntry'}];
end
for index = 1:numel(required)
    if exist(required{index}, 'file') == 0
        error('ImaginedSpeech:MissingLifecycleDependency', ...
            'Comments are enabled but %s is unavailable.', required{index});
    end
end

instances = [];
sessions = {};
labels = strings(1, 0);
if backend == "cbmex"
    addresses = getIPAddressesFromPortNames({'NSP1', 'NSP2'});
    for index = 1:numel(addresses)
        try
            cbmex('open', 'central-addr', addresses{index}, 'instance', index - 1);
            instances(end + 1) = index - 1; %#ok<AGROW>
            labels(end + 1) = sprintf('NSP-%d', index); %#ok<AGROW>
            fprintf('NSP%d Active\n', index);
        catch
        end
    end
    openCount = numel(instances);
else
    deviceTypes = cellstr(config.matcbsdk.device_types);
    for index = 1:numel(deviceTypes)
        try
            sessions{end + 1} = Session(deviceTypes{index}, config.matcbsdk.callback_queue_depth); %#ok<AGROW>
            labels(end + 1) = string(deviceTypes{index}); %#ok<AGROW>
            fprintf('%s Active\n', deviceTypes{index});
        catch
        end
    end
    openCount = numel(sessions);
end
if openCount == 0
    error('ImaginedSpeech:NoOnlineNSP', ...
        'Comments are enabled, but no Blackrock NSP connection could be opened.');
end

emuNumber = NaN;
try
    if usePatientLog
        [emuNumber, ~] = getNextLogEntry;
        if isempty(emuNumber) || ~isscalar(emuNumber) || ~isfinite(emuNumber)
            error('ImaginedSpeech:InvalidPatientLog', 'Could not obtain the next EMU log number.');
        end
        idLabel = sprintf('EMU-%04d', emuNumber);
    else
        idLabel = char(config.session.patient_id);
    end
    taskStem = sprintf('%s_%s_%s', taskName, task_block_name(blockNumber), config.session.patient_id);
    taskId = sprintf('%s_%s', idLabel, taskStem);
    if numel(taskId) + 7 > 92
        error('ImaginedSpeech:TaskIdTooLong', 'Task ID exceeds TaskComment''s 92-character limit.');
    end
    sendStartComments(backend, instances, sessions, labels, idLabel, taskId);
    if usePatientLog
        % This is the patient-log increment performed by TaskComment('start').
        setNextLogEntry(taskId);
        [nextNumber, ~, patientLog] = getNextLogEntry;
        if nextNumber ~= emuNumber + 1 || isempty(patientLog) || ...
                ~strcmp(string(patientLog.task_id(end)), string(taskId))
            error('ImaginedSpeech:PatientLogIncrementFailed', ...
                'TaskStart did not produce the expected CurrentPatientLog entry.');
        end
    end
    lifecycle = struct('enabled', true, 'backend', backend, 'instances', instances, ...
        'sessions', {sessions}, 'labels', labels, 'emu_id', emuNumber, 'id_label', idLabel, ...
        'task_id', taskId, 'connections_open', true);
catch startError
    try
        if usePatientLog
            if isfinite(emuNumber)
                sendComment(backend, instances, sessions, 255, 0, ...
                    ['$TASKERR ' sprintf('EMU-%04d', emuNumber)]);
            end
        else
            sendComment(backend, instances, sessions, 255, 0, ...
                ['$TASKERR ' char(config.session.patient_id)]);
        end
    catch
    end
    closeAll(backend, instances, sessions);
    rethrow(startError);
end
end

function sendStartComments(backend, instances, sessions, labels, idLabel, taskId)
count = numel(instances) + numel(sessions);
if backend == "cbmex"
    for index = 1:numel(instances)
        cbmex('comment', 65280, 0, ['$TASKSTART ' idLabel], 'instance', instances(index));
        suffix = ''; if count > 1, suffix = sprintf('_%s', labels(index)); end
        cbmex('comment', 65280, 0, ['$TASKID ' taskId char(suffix)], 'instance', instances(index));
    end
else
    for index = 1:numel(sessions)
        sessions{index}.send_comment(['$TASKSTART ' idLabel], 65280, 0);
        suffix = ''; if count > 1, suffix = sprintf('_%s', labels(index)); end
        sessions{index}.send_comment(['$TASKID ' taskId char(suffix)], 65280, 0);
    end
end
end

function sendComment(backend, instances, sessions, color, charset, text)
if backend == "cbmex"
    for index = 1:numel(instances)
        cbmex('comment', color, charset, text, 'instance', instances(index));
    end
else
    for index = 1:numel(sessions)
        sessions{index}.send_comment(text, color, charset);
    end
end
end

function closeAll(backend, instances, sessions)
if backend == "cbmex"
    for index = 1:numel(instances)
        try, cbmex('close', 'instance', instances(index)); catch, end
    end
else
    for index = 1:numel(sessions)
        try, sessions{index}.close(); catch, end
    end
end
end
