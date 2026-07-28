function finish_sync_tones(toneState)
%FINISH_SYNC_TONES Play the block_end tone to completion, then release the device.
%
% Intended for onCleanup, so it fires exactly once at the very end of a
% block run regardless of whether the block finished normally, was
% aborted, or errored. Unlike play_sync_tone, this waits for the tone to
% finish playing before closing the device, so the closing Close call
% cannot truncate it.

if ~toneState.enabled || toneState.handle < 0
    return;
end
try
    PsychPortAudio('FillBuffer', toneState.handle, toneState.tones.block_end);
    PsychPortAudio('Start', toneState.handle, 1, 0, 1);
    PsychPortAudio('Stop', toneState.handle, 1);
catch
end
try
    PsychPortAudio('Close', toneState.handle);
catch
end
end
