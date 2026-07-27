function run_block_0(config)
%RUN_BLOCK_0 Present the data-driven instructions slide deck.

% Read and validate all participant-facing content before opening the timed
% display. No task-data files are accessed while slides are presented.
content = load_block0_content(config.block0.content_file);

oldSkipSyncTests = Screen('Preference', 'SkipSyncTests', ...
    double(config.display.skip_sync_tests));
cleanup = onCleanup(@() cleanupBlock0(oldSkipSyncTests)); %#ok<NASGU>

KbName('UnifyKeyNames');
enterKeys = KbName('Return');
abortKey = KbName(config.keys.abort);
allowedKeys = zeros(1, 256);
allowedKeys(enterKeys) = 1;
allowedKeys(abortKey) = 1;
KbQueueCreate([], allowedKeys);
KbQueueStart;

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
[window, rect] = PsychImaging('OpenWindow', screenIndex, ...
    config.display.background_rgb(:)', windowRect);
HideCursor(window);
Screen('TextFont', window, config.display.font_name);

screenWidth = RectWidth(rect);
screenHeight = RectHeight(rect);
margin = screenWidth * config.block0.horizontal_margin_percent / 100;
wrapWidth = max(20, floor((screenWidth - 2 * margin) / ...
    (config.block0.body_size * 0.55)));

for slideIndex = 1:numel(content.slides)
    slide = content.slides(slideIndex);
    Screen('FillRect', window, config.display.background_rgb(:)');

    Screen('TextSize', window, config.block0.title_size);
    DrawFormattedText(window, slide.title, 'center', screenHeight * 0.14, ...
        config.display.text_rgb(:)', wrapWidth, [], [], 1.25);

    Screen('TextSize', window, config.block0.body_size);
    DrawFormattedText(window, slide.body, margin, screenHeight * 0.31, ...
        config.display.text_rgb(:)', wrapWidth, [], [], 1.35);

    if slideIndex == numel(content.slides)
        prompt = content.final_navigation_prompt;
    else
        prompt = content.navigation_prompt;
    end
    footer = sprintf('%s\n\n%d of %d', prompt, slideIndex, numel(content.slides));
    Screen('TextSize', window, config.block0.footer_size);
    DrawFormattedText(window, footer, 'center', screenHeight * 0.82, ...
        config.display.text_rgb(:)', wrapWidth, [], [], 1.15);
    Screen('Flip', window);

    if ~waitForAdvance(config.block0.auto_advance_seconds, enterKeys, abortKey)
        task_killed;
    end
end

    function advance = waitForAdvance(autoAdvanceSeconds, acceptedEnterKeys, escapeKey)
        advance = false;
        KbQueueFlush;
        if autoAdvanceSeconds > 0
            deadline = GetSecs + autoAdvanceSeconds;
        else
            deadline = Inf;
        end
        while GetSecs < deadline
            [pressed, firstPress] = KbQueueCheck;
            if pressed
                if firstPress(escapeKey) > 0
                    return;
                end
                if any(firstPress(acceptedEnterKeys) > 0)
                    advance = true;
                    return;
                end
                KbQueueFlush;
            end
            WaitSecs('YieldSecs', 0.005);
        end
        advance = true;
    end

end

function cleanupBlock0(oldSkipSyncTests)
% Cleanup must also succeed after a partial initialization failure.
try
    KbQueueStop;
catch
end
try
    KbQueueRelease;
catch
end
ShowCursor;
Priority(0);
Screen('CloseAll');
Screen('Preference', 'SkipSyncTests', oldSkipSyncTests);
end
