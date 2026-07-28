function toneState = init_sync_tones(config)
%INIT_SYNC_TONES Open a dedicated audio-sync playback device and preload all configured tones.
%
% Sync tones use their own PsychPortAudio handle, independent of any
% stimulus-audio device a block may also open, so tone playback never
% competes with in-progress story/word/phrase audio for a buffer. When
% audio_sync.enabled is false (the default), this is a no-op: no device is
% opened and play_sync_tone/finish_sync_tones become no-ops too.

toneState = struct('enabled', logical(config.audio_sync.enabled), 'handle', -1, 'tones', struct());
if ~toneState.enabled
    return;
end

InitializePsychSound(1);
if config.audio_sync.device_index < 0
    deviceIndex = [];
else
    deviceIndex = config.audio_sync.device_index;
end
toneState.handle = PsychPortAudio('Open', deviceIndex, 1, 1, config.audio_sync.sample_rate, 2);

toneNames = fieldnames(config.audio_sync.tones);
for index = 1:numel(toneNames)
    name = toneNames{index};
    spec = config.audio_sync.tones.(name);
    toneState.tones.(name) = build_sync_tone(spec.frequency_hz, spec.duration_ms, ...
        config.audio_sync.sample_rate, config.audio_sync.volume);
end
end
