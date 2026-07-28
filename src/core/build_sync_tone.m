function samples = build_sync_tone(frequencyHz, durationMs, sampleRate, volume)
%BUILD_SYNC_TONE Synthesize a short stereo pure-tone burst for audio sync signals.
%
% A brief linear fade in/out (5 ms, or half the tone if shorter) avoids the
% audible click a hard-edged tone would otherwise produce.

numSamples = round(sampleRate * durationMs / 1000);
t = (0:numSamples - 1) / sampleRate;
tone = sin(2 * pi * frequencyHz * t);

fadeSamples = min(round(0.005 * sampleRate), floor(numSamples / 2));
fadeSamples = max(fadeSamples, 1);
envelope = ones(1, numSamples);
envelope(1:fadeSamples) = linspace(0, 1, fadeSamples);
envelope(end - fadeSamples + 1:end) = linspace(1, 0, fadeSamples);

tone = tone .* envelope * volume;
samples = [tone; tone];
end
