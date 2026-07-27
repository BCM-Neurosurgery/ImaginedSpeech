function lifecycle = start_task_lifecycle(config, blockNumber)
%START_TASK_LIFECYCLE Mirror TaskComment('start') with persistent NSP links.

lifecycle = struct('enabled', false, 'instances', [], 'emu_id', NaN, ...
    'task_id', '', 'connections_open', false);
if ~config.cbmex.enabled, return; end

required = {'cbmex','getIPAddressesFromPortNames','getNextLogEntry','setNextLogEntry'};
for index = 1:numel(required)
    if exist(required{index}, 'file') == 0
        error('ImaginedSpeech:MissingLifecycleDependency', ...
            'Comments are enabled but %s is unavailable.', required{index});
    end
end

addresses = getIPAddressesFromPortNames({'NSP1','NSP2'});
instances = [];
for index = 1:numel(addresses)
    try
        cbmex('open','central-addr',addresses{index},'instance',index-1);
        instances(end+1) = index-1; %#ok<AGROW>
        fprintf('NSP%d Active\n',index);
    catch
    end
end
if isempty(instances)
    error('ImaginedSpeech:NoOnlineNSP', ...
        'Comments are enabled, but no Blackrock NSP connection could be opened.');
end

emuNumber = NaN;
try
    [emuNumber, ~] = getNextLogEntry;
    if isempty(emuNumber) || ~isscalar(emuNumber) || ~isfinite(emuNumber)
        error('ImaginedSpeech:InvalidPatientLog','Could not obtain the next EMU log number.');
    end
    taskStem = sprintf('%s_Block%d_%s',config.cbmex.task_name,blockNumber,config.session.patient_id);
    taskId = sprintf('EMU-%04d_%s',emuNumber,taskStem);
    if numel(taskId)+7 > 92
        error('ImaginedSpeech:TaskIdTooLong','Task ID exceeds TaskComment''s 92-character limit.');
    end
    emuId = sprintf('EMU-%04d',emuNumber);
    for index = 1:numel(instances)
        cbmex('comment',65280,0,['$TASKSTART ' emuId],'instance',instances(index));
        suffix = '';
        if numel(instances)>1, suffix=sprintf('_NSP-%d',index); end
        cbmex('comment',65280,0,['$TASKID ' taskId suffix],'instance',instances(index));
    end
    % This is the patient-log increment performed by TaskComment('start').
    setNextLogEntry(taskId);
    [nextNumber, ~, patientLog] = getNextLogEntry;
    if nextNumber ~= emuNumber + 1 || isempty(patientLog) || ...
            ~strcmp(string(patientLog.task_id(end)), string(taskId))
        error('ImaginedSpeech:PatientLogIncrementFailed', ...
            'TaskStart did not produce the expected CurrentPatientLog entry.');
    end
    lifecycle = struct('enabled',true,'instances',instances,'emu_id',emuNumber, ...
        'task_id',taskId,'connections_open',true);
catch startError
    if isfinite(emuNumber)
        for index=1:numel(instances)
            try
                cbmex('comment',255,0,['$TASKERR ' sprintf('EMU-%04d',emuNumber)], ...
                    'instance',instances(index));
            catch
            end
        end
    end
    closeInstances(instances);
    rethrow(startError);
end
end

function closeInstances(instances)
for index=1:numel(instances)
    try, cbmex('close','instance',instances(index)); catch, end
end
end
