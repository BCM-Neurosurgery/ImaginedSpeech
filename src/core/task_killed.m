function task_killed()
%TASK_KILLED Raise the controlled Escape termination recognized by launcher.
throwAsCaller(MException('ImaginedSpeech:TaskKilled', ...
    'The participant or experimenter pressed Escape.'));
end
