function play_sync_tone(toneState, toneName)
%PLAY_SYNC_TONE Fire a preloaded sync tone without blocking the caller.
%
% Playback is started and left to run in the background (matching how the
% photodiode flip and Cbmex comment are fired without waiting on each
% other), so a sync tone never delays the timing of the phase it marks.

if ~toneState.enabled
    return;
end
if ~isfield(toneState.tones, toneName)
    error('ImaginedSpeech:UnknownSyncTone', 'No audio_sync tone configured for: %s', toneName);
end
PsychPortAudio('FillBuffer', toneState.handle, toneState.tones.(toneName));
PsychPortAudio('Start', toneState.handle, 1, 0, 0);
end
