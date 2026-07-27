function run_block_placeholder(config, blockNumber, blockName)
%RUN_BLOCK_PLACEHOLDER Open a timed PTB screen for an unimplemented block.

oldSkipSyncTests = Screen('Preference', 'SkipSyncTests', ...
    double(config.display.skip_sync_tests));
cleanup = onCleanup(@() cleanupPsychtoolbox(oldSkipSyncTests)); %#ok<NASGU>

KbName('UnifyKeyNames');
screens = Screen('Screens');
if config.display.screen_index < 0
    screenIndex = max(screens);
else
    screenIndex = config.display.screen_index;
    if ~ismember(screenIndex, screens)
        error('ImaginedSpeech:InvalidScreen', ...
            'Configured screen_index %d is unavailable.', screenIndex);
    end
end

windowRect = [];
if config.display.debug_windowed
    windowRect = config.display.debug_window_rect(:)';
end
[window, ~] = PsychImaging('OpenWindow', screenIndex, ...
    config.display.background_rgb(:)', windowRect);
HideCursor(window);
Screen('TextFont', window, config.display.font_name);
Screen('TextSize', window, config.display.font_size);

message = sprintf(['Block %d: %s\n\n' ...
    'Placeholder screen - implementation coming next.\n\n' ...
    'Press ESC to close early.'], blockNumber, blockName);
DrawFormattedText(window, message, 'center', 'center', ...
    config.display.text_rgb(:)');
Screen('Flip', window);

abortKey = KbName(config.keys.abort);
deadline = GetSecs + config.placeholder.duration_seconds;
while GetSecs < deadline
    [keyDown, ~, keyCodes] = KbCheck;
    if keyDown && keyCodes(abortKey)
        task_killed;
    end
    WaitSecs('YieldSecs', 0.01);
end
end

function cleanupPsychtoolbox(oldSkipSyncTests)
ShowCursor;
Priority(0);
Screen('CloseAll');
Screen('Preference', 'SkipSyncTests', oldSkipSyncTests);
end
