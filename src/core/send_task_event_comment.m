function send_task_event_comment(config, comment)
%SEND_TASK_EVENT_COMMENT Send one trial event to every open NSP connection.
%
% Routes through whichever backend the master launcher's lifecycle opened
% (config.comment_lifecycle.backend is "cbmex" or "matcbsdk"); a no-op when
% neither backend is enabled.

if ~config.cbmex.enabled && ~config.matcbsdk.enabled, return; end
if ~isfield(config,'comment_lifecycle') || ~config.comment_lifecycle.enabled
    error('ImaginedSpeech:MissingCommentLifecycle', ...
        'Comments require a lifecycle initialized by the master launcher.');
end
if strlength(string(comment))>127
    error('ImaginedSpeech:CommentTooLong','Cbmex comment exceeds 127 characters.');
end
lifecycle = config.comment_lifecycle;
if lifecycle.backend == "cbmex"
    for index=1:numel(lifecycle.instances)
        cbmex('comment',config.cbmex.comment_rgba,config.cbmex.comment_charset, ...
            char(comment),'instance',lifecycle.instances(index));
    end
else
    for index=1:numel(lifecycle.sessions)
        lifecycle.sessions{index}.send_comment(char(comment), ...
            config.matcbsdk.comment_rgba, config.matcbsdk.comment_charset);
    end
end
end
