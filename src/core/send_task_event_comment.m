function send_task_event_comment(config, comment)
%SEND_TASK_EVENT_COMMENT Send one trial event to all lifecycle NSP instances.

if ~config.cbmex.enabled, return; end
if ~isfield(config.cbmex,'lifecycle') || ~config.cbmex.lifecycle.enabled
    error('ImaginedSpeech:MissingCommentLifecycle', ...
        'Cbmex comments require a lifecycle initialized by the master launcher.');
end
if strlength(string(comment))>127
    error('ImaginedSpeech:CommentTooLong','Cbmex comment exceeds 127 characters.');
end
for index=1:numel(config.cbmex.lifecycle.instances)
    cbmex('comment',config.cbmex.comment_rgba,config.cbmex.comment_charset, ...
        char(comment),'instance',config.cbmex.lifecycle.instances(index));
end
end
