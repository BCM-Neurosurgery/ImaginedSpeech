function [pauseDuration, aborted, onsetTime, resumeTime] = wait_for_pause_resume(window, config, diodeRect, ifi, keys, toneState)
%WAIT_FOR_PAUSE_RESUME Show a pause overlay and block until the pause key is pressed again.
%
% Draws a "PAUSED" screen (replacing whatever was on screen) and blocks
% until the participant/experimenter presses the pause key again, or
% Escape (which still aborts immediately, even from the pause screen).
% Returns the elapsed wall-clock duration of the pause so callers can shift
% any in-flight deadline or audio-playback position forward by exactly that
% amount, and the flip timestamps of the pause-onset and resume flashes so
% callers can log/comment them through their own per-block event emitter
% (Cbmex/matcbsdk logging is left to the caller, which already has the
% trial/story context needed; the photodiode flash and the audio_sync
% pause_on/pause_resume tone, if enabled, are both handled here since
% neither needs any block-specific context).
%
% Callers must redraw their own current phase's visual immediately after a
% non-aborted return (the pause overlay has overwritten it on screen).

rect = Screen('Rect', window);
flashOff = (config.photodiode.flash_frames - 0.5) * ifi;

drawPauseOverlay(window, rect, config, diodeRect, true);
onsetTime = Screen('Flip', window);
play_sync_tone(toneState, 'pause_on');
drawPauseOverlay(window, rect, config, diodeRect, false);
Screen('Flip', window, onsetTime + flashOff);

aborted = false;
KbQueueFlush;
while true
    [pressed, first] = KbQueueCheck;
    if pressed && first(keys.escape) > 0, aborted = true; break; end
    if pressed && first(keys.pause) > 0, break; end
    WaitSecs('YieldSecs', 0.01);
end
KbQueueFlush;

if aborted
    resumeTime = GetSecs;
    pauseDuration = resumeTime - onsetTime;
    return;
end

drawPauseOverlay(window, rect, config, diodeRect, true);
resumeTime = Screen('Flip', window);
play_sync_tone(toneState, 'pause_resume');
drawPauseOverlay(window, rect, config, diodeRect, false);
Screen('Flip', window, resumeTime + flashOff);

pauseDuration = resumeTime - onsetTime;
end

function drawPauseOverlay(window, rect, config, diodeRect, diodeOn)
Screen('FillRect', window, config.display.background_rgb(:)');
Screen('TextSize', window, 44);
DrawFormattedText(window, 'PAUSED', 'center', RectHeight(rect) * 0.45, config.display.text_rgb(:)');
Screen('TextSize', window, 26);
DrawFormattedText(window, sprintf('Press %s to resume', upper(char(config.keys.pause))), ...
    'center', RectHeight(rect) * 0.55, config.display.text_rgb(:)');
if config.photodiode.enabled
    if diodeOn, color = config.photodiode.on_rgb; else, color = config.photodiode.off_rgb; end
    Screen('FillRect', window, color(:)', diodeRect);
end
end
