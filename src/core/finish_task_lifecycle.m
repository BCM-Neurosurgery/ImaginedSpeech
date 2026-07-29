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
fprintf('[lifecycle] sending %s to %d NSP instance(s)...\n',strtrim(comment),numel(lifecycle.instances));

% Send the comment to every instance first, and only close connections
% afterward (in a separate pass, after a short pause). Interleaving
% comment-then-close per instance risked tearing a connection down before
% its comment had actually flushed to the NSP; closing is also isolated in
% its own try/catch per instance so one bad handle cannot skip closing the
% rest or abort this function before it returns.
for index=1:numel(lifecycle.instances)
    instance=lifecycle.instances(index);
    try
        cbmex('comment',color,0,comment,'instance',instance);
    catch commentError
        warning('ImaginedSpeech:LifecycleCommentFailed', ...
            'Could not send %s to instance %d: %s',event,instance,commentError.message);
    end
end
fprintf('[lifecycle] %s sent; closing NSP connection(s)...\n',strtrim(comment));

try, WaitSecs(0.05); catch, end
for index=1:numel(lifecycle.instances)
    instance=lifecycle.instances(index);
    try
        cbmex('close','instance',instance);
    catch closeError
        warning('ImaginedSpeech:LifecycleCloseFailed', ...
            'Could not close NSP instance %d: %s',instance,closeError.message);
    end
end
fprintf('[lifecycle] done: %s\n',comment);
end
