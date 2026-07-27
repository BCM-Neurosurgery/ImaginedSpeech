function assert_psychtoolbox_available()
%ASSERT_PSYCHTOOLBOX_AVAILABLE Fail early with a useful setup message.

requiredFunctions = {'Screen', 'KbCheck', 'KbName', 'WaitSecs'};
missing = requiredFunctions(cellfun(@(name) exist(name, 'file') == 0, requiredFunctions));
if ~isempty(missing)
    error('ImaginedSpeech:MissingPsychtoolbox', ...
        'Psychtoolbox is unavailable. Missing: %s', strjoin(missing, ', '));
end
end
