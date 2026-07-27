function finish_task_lifecycle(lifecycle, event)
%FINISH_TASK_LIFECYCLE Send TaskStop/TaskKill/TaskErr and close NSP links.

if ~lifecycle.enabled, return; end
switch event
    case 'stop', code='$TASKSTOP '; color=16711935;
    case 'kill', code='$TASKKILL '; color=255;
    case 'error', code='$TASKERR '; color=255;
    otherwise, error('ImaginedSpeech:InvalidLifecycleEvent','Unknown lifecycle event: %s',event);
end
comment=[code sprintf('EMU-%04d',lifecycle.emu_id)];
for index=1:numel(lifecycle.instances)
    instance=lifecycle.instances(index);
    try
        cbmex('comment',color,0,comment,'instance',instance);
    catch commentError
        warning('ImaginedSpeech:LifecycleCommentFailed', ...
            'Could not send %s to instance %d: %s',event,instance,commentError.message);
    end
    try, cbmex('close','instance',instance); catch, end
end
fprintf('%s\n',comment);
end
