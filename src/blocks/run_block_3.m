function run_block_3(config)
%RUN_BLOCK_3 Present two stories followed by comprehension questions.

content = load_block3_content(config.block3.content_file);
oldSkip = Screen('Preference', 'SkipSyncTests', double(config.display.skip_sync_tests));
state = struct('audio', [], 'eventFile', -1, ...
    'responseFile', -1);
screenCleanup = onCleanup(@() cleanupBlock3Screen(oldSkip));

KbName('UnifyKeyNames');
keys.enter = KbName('Return');
keys.up = KbName('UpArrow');
keys.down = KbName('DownArrow');
keys.escape = KbName(config.keys.abort);
keys.deselect = KbName(config.keys.deselect);
keys.pause = KbName(config.keys.pause);
allowed = zeros(1, 256);
allowed([keys.enter, keys.up, keys.down, keys.escape, keys.deselect, keys.pause]) = 1;
KbQueueCreate([], allowed);
KbQueueStart;
queueCleanup = onCleanup(@cleanupBlock3Queue);

screens = Screen('Screens');
if config.display.screen_index < 0
    screenIndex = max(screens);
else
    screenIndex = config.display.screen_index;
end
windowRect = [];
if config.display.debug_windowed
    windowRect = config.display.debug_window_rect(:)';
end
[window, rect] = PsychImaging('OpenWindow', screenIndex, ...
    config.display.background_rgb(:)', windowRect);
HideCursor(window);
% Raise scheduling priority for the timed portion of the block so OS-level
% preemption (background processes, the DWM compositor, etc.) is less likely
% to delay a Flip past its target and cause a dropped/mistimed frame. Reset
% to 0 happens in cleanup, which already assumed this was being done.
Priority(MaxPriority(window));
Screen('TextFont', window, config.display.font_name);
ifi = Screen('GetFlipInterval', window);
diodeRect = makeDiodeRect(rect, config.photodiode);
% Hold each sync flash on for flash_frames refresh cycles (not just one) so a
% single dropped/jittered frame can't make the pulse too brief for the
% photodiode/DAQ to reliably register.
flashOff = (config.photodiode.flash_frames - 0.5) * ifi;

InitializePsychSound(1);
sampleRate = content.stories(1).sample_rate;
state.audio = PsychPortAudio('Open', [], 1, 1, sampleRate, 2);
audioCleanup = onCleanup(@() cleanupBlock3Audio(state.audio));

toneState = init_sync_tones(config);
toneCleanup = onCleanup(@() finish_sync_tones(toneState));

if ~isfield(config, 'session') || ~isfolder(config.session.directory)
    error('ImaginedSpeech:MissingSession', 'Block 3 requires an initialized patient session.');
end
runId = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
state.eventFile = fopen(fullfile(config.session.directory, ...
    ['block3_' runId '_events.csv']), 'w');
state.responseFile = fopen(fullfile(config.session.directory, ...
    ['block3_' runId '_responses.csv']), 'w');
if state.eventFile < 0 || state.responseFile < 0
    error('ImaginedSpeech:OutputOpenFailed', 'Could not create Block 3 output files.');
end
fileCleanup = onCleanup(@() cleanupBlock3Files( ...
    state.eventFile, state.responseFile));
fprintf(state.eventFile, 'timestamp,event,story_id,question_id,choice_id\n');
fprintf(state.responseFile, ['story_id,question_id,choice_id,choice_text,' ...
    'correct_choice_id,is_correct,question_onset,pick_time,submit_time\n']);

sources = struct('label', {'block3_manifest'}, 'path', {config.block3.content_file});
for storySourceIndex = 1:numel(content.stories)
    sources(end + 1) = struct('label', ['story_audio_' char(content.stories(storySourceIndex).id)], ...
        'path', content.stories(storySourceIndex).audio_path); %#ok<AGROW>
end
save_run_snapshot(config, 3, runId, sources);

switch string(config.block3.start_position)
    case "story_1", startStoryIndex = 1; skipStartAudio = false;
    case "comprehension_1", startStoryIndex = 1; skipStartAudio = true;
    case "story_2", startStoryIndex = 2; skipStartAudio = false;
    case "comprehension_2", startStoryIndex = 2; skipStartAudio = true;
end

play_sync_tone(toneState, 'block_start');
for storyIndex = startStoryIndex:numel(content.stories)
    story = content.stories(storyIndex);
    % start_position lets a run resume mid-block: "comprehension_N" skips
    % straight to story N's questions, entirely bypassing its ready screen
    % and audio playback (only ever applies to the first story iterated,
    % never a later one in the same run).
    if ~(skipStartAudio && storyIndex == startStoryIndex)
        PsychPortAudio('FillBuffer', state.audio, story.audio_samples);
        drawReady(window, rect, story.title, content.ready_prompt, config, diodeRect, false);
        Screen('Flip', window);
        if ~waitForEnter(keys, config.block3.test_auto_advance_seconds)
            task_killed;
        end

        drawListening(window, rect, content.listening_text, config, diodeRect, true);
        targetTime = GetSecs + 2 * ifi;
        PsychPortAudio('Start', state.audio, 1, targetTime, 0);
        onset = Screen('Flip', window, targetTime);
        emitAfterPhotodiode(state, config, onset, 'STORY_START', story.id, '', '');
        drawListening(window, rect, content.listening_text, config, diodeRect, false);
        Screen('Flip', window, onset + flashOff);
        listeningRedraw = @() drawListening(window, rect, content.listening_text, config, diodeRect, false);
        storyDuration = size(story.audio_samples, 2) / story.sample_rate;
        if ~waitForStory(state.audio, keys, config.block3.test_max_story_seconds, ...
                window, config, diodeRect, ifi, state, story, listeningRedraw, toneState, storyDuration)
            PsychPortAudio('Stop', state.audio, 0);
            task_killed;
        end
    end

    for questionIndex = 1:numel(story.questions)
        question = story.questions(questionIndex);
        highlight = 1;
        selected = 0;
        drawQuestion(window, rect, question, highlight, selected, content, ...
            config, diodeRect, true);
        questionOnset = Screen('Flip', window);
        play_sync_tone(toneState, 'block3_question_onset');
        emitAfterPhotodiode(state, config, questionOnset, 'QUESTION_SHOW', ...
            story.id, question.id, '');
        drawQuestion(window, rect, question, highlight, selected, content, ...
            config, diodeRect, false);
        Screen('Flip', window, questionOnset + flashOff);
        KbQueueFlush;

        pickTime = NaN;
        while true
            autoDelay = config.block3.test_auto_advance_seconds;
            [action, actionTime] = waitForQuestionAction(keys, autoDelay);
            if action == "abort"
                task_killed;
            elseif action == "up" && selected == 0
                highlight = mod(highlight - 2, numel(question.choices)) + 1;
                drawQuestion(window, rect, question, highlight, selected, content, ...
                    config, diodeRect, true);
                flipTime = Screen('Flip', window);
                emitAfterPhotodiode(state, config, flipTime, 'HIGHLIGHT_MOVE', ...
                    story.id, question.id, sprintf('up:%d', highlight));
                drawQuestion(window, rect, question, highlight, selected, content, ...
                    config, diodeRect, false);
                Screen('Flip', window, flipTime + flashOff);
                KbQueueFlush;
                continue;
            elseif action == "down" && selected == 0
                highlight = mod(highlight, numel(question.choices)) + 1;
                drawQuestion(window, rect, question, highlight, selected, content, ...
                    config, diodeRect, true);
                flipTime = Screen('Flip', window);
                emitAfterPhotodiode(state, config, flipTime, 'HIGHLIGHT_MOVE', ...
                    story.id, question.id, sprintf('down:%d', highlight));
                drawQuestion(window, rect, question, highlight, selected, content, ...
                    config, diodeRect, false);
                Screen('Flip', window, flipTime + flashOff);
                KbQueueFlush;
                continue;
            elseif action == "enter" && selected == 0
                selected = highlight;
                pickTime = actionTime;
                choice = question.choices(selected);
                drawQuestion(window, rect, question, highlight, selected, content, ...
                    config, diodeRect, true);
                flipTime = Screen('Flip', window);
                emitAfterPhotodiode(state, config, flipTime, 'ANSWER_PICK', ...
                    story.id, question.id, choice.id);
                drawQuestion(window, rect, question, highlight, selected, content, ...
                    config, diodeRect, false);
                Screen('Flip', window, flipTime + flashOff);
                KbQueueFlush;
                continue;
            elseif action == "deselect" && selected > 0
                previousChoice = question.choices(selected);
                selected = 0;
                pickTime = NaN;
                drawQuestion(window, rect, question, highlight, selected, content, ...
                    config, diodeRect, true);
                flipTime = Screen('Flip', window);
                emitAfterPhotodiode(state, config, flipTime, 'ANSWER_DESELECT', ...
                    story.id, question.id, previousChoice.id);
                drawQuestion(window, rect, question, highlight, selected, content, ...
                    config, diodeRect, false);
                Screen('Flip', window, flipTime + flashOff);
                KbQueueFlush;
                continue;
            elseif action == "enter" && selected > 0
                submitTime = actionTime;
                choice = question.choices(selected);
                drawQuestion(window, rect, question, highlight, selected, content, ...
                    config, diodeRect, true);
                flipTime = Screen('Flip', window);
                emitAfterPhotodiode(state, config, flipTime, 'ANSWER_SUBMIT', ...
                    story.id, question.id, choice.id);
                isCorrect = strcmp(choice.id, question.correct_choice_id);
                fprintf(state.responseFile, '%s,%s,%s,%s,%s,%d,%.9f,%.9f,%.9f\n', ...
                    csvText(story.id), csvText(question.id), csvText(choice.id), ...
                    csvText(choice.text), csvText(question.correct_choice_id), ...
                    isCorrect, questionOnset, pickTime, submitTime);
                break;
            end
            drawQuestion(window, rect, question, highlight, selected, content, ...
                config, diodeRect, false);
            Screen('Flip', window);
            KbQueueFlush;
        end
    end
end
end

function drawReady(window, rect, titleText, prompt, config, diodeRect, diodeOn)
Screen('FillRect', window, config.display.background_rgb(:)');
Screen('TextSize', window, config.block3.title_size);
DrawFormattedText(window, titleText, 'center', RectHeight(rect) * 0.32, config.display.text_rgb(:)');
Screen('TextSize', window, config.block3.question_size);
DrawFormattedText(window, prompt, 'center', RectHeight(rect) * 0.58, config.display.text_rgb(:)');
drawDiode(window, config, diodeRect, diodeOn);
end

function drawListening(window, ~, textValue, config, diodeRect, diodeOn)
Screen('FillRect', window, config.display.background_rgb(:)');
Screen('TextSize', window, config.block3.question_size);
DrawFormattedText(window, textValue, 'center', 'center', config.display.text_rgb(:)');
drawDiode(window, config, diodeRect, diodeOn);
end

function drawQuestion(window, rect, question, highlight, selected, content, config, diodeRect, diodeOn)
Screen('FillRect', window, config.display.background_rgb(:)');
Screen('TextSize', window, config.block3.question_size);
DrawFormattedText(window, question.text, 'center', RectHeight(rect) * 0.16, config.display.text_rgb(:)', 52);
for index = 1:numel(question.choices)
    choice = question.choices(index);
    prefix = '  ';
    color = config.display.text_rgb(:)';
    if index == highlight
        prefix = '> ';
        color = config.block3.highlight_rgb(:)';
    end
    if index == selected
        prefix = 'X ';
        color = config.block3.selected_rgb(:)';
    end
    Screen('TextSize', window, config.block3.choice_size);
    DrawFormattedText(window, [prefix choice.text], RectWidth(rect) * 0.25, ...
        RectHeight(rect) * (0.38 + 0.12 * (index - 1)), color, 45);
end
if selected == 0
    prompt = content.question_navigation_prompt;
else
    prompt = content.question_submit_prompt;
end
Screen('TextSize', window, config.block3.footer_size);
DrawFormattedText(window, prompt, 'center', RectHeight(rect) * 0.82, config.display.text_rgb(:)', 70);
drawDiode(window, config, diodeRect, diodeOn);
end

function rect = makeDiodeRect(windowRect, diode)
w = diode.size_px(1); h = diode.size_px(2); margin = diode.margin_px;
rect = [margin, RectHeight(windowRect)-margin-h, margin+w, RectHeight(windowRect)-margin];
end

function drawDiode(window, config, rect, isOn)
if ~config.photodiode.enabled, return; end
if isOn, color = config.photodiode.on_rgb; else, color = config.photodiode.off_rgb; end
Screen('FillRect', window, color(:)', rect);
end

function emitAfterPhotodiode(state, config, timestamp, eventName, storyId, questionId, choiceId)
comment = sprintf('B3_%s story=%s', eventName, storyId);
if ~isempty(questionId), comment = sprintf('%s q=%s', comment, questionId); end
if ~isempty(choiceId), comment = sprintf('%s choice=%s', comment, choiceId); end
if strlength(comment) > 127, error('ImaginedSpeech:CommentTooLong', 'Cbmex comment exceeds 127 characters.'); end
% Ordering is intentional: caller's Screen flip (photodiode) has completed
% before this function sends the higher-latency Cbmex comment.
send_task_event_comment(config, comment);
fprintf(state.eventFile, '%.9f,%s,%s,%s,%s\n', timestamp, eventName, ...
    storyId, questionId, choiceId);
end

function proceed = waitForEnter(keys, autoSeconds)
KbQueueFlush; proceed = false;
if autoSeconds > 0, deadline = GetSecs + autoSeconds; else, deadline = Inf; end
while GetSecs < deadline
    [pressed, first] = KbQueueCheck;
    if pressed
        if first(keys.escape) > 0, return; end
        if first(keys.enter) > 0, proceed = true; return; end
        KbQueueFlush;
    end
    WaitSecs('YieldSecs', 0.005);
end
proceed = true;
end

function proceed = waitForStory(audioHandle, keys, maxSeconds, window, config, diodeRect, ifi, state, story, redrawFcn, toneState, storyDuration)
% Deadline-driven (not PsychPortAudio('GetStatus',audioHandle).Active-driven):
% the loop's stopping condition is the analytically-known story duration,
% exactly like every other pausable phase in this task, rather than
% repeatedly polling audio device status. An earlier version of this
% function drove the while-loop off GetStatus().Active, which was suspected
% of (and reproduced as) making a non-blocking resume Start's Active flag
% read false too early; that fix alone did not resolve real-hardware
% unresponsiveness during the story, which pointed at a second, independent
% cause below.
%
% This wait also temporarily drops MATLAB's OS scheduling priority back to
% normal for its duration (restored on every exit path via onCleanup). The
% block raises priority to MaxPriority(window) to protect Screen('Flip', ...)
% timing against OS preemption, but no further flip happens anywhere in this
% function until it returns -- there is nothing timing-critical here for
% elevated priority to protect. Running a multi-minute busy-poll loop at
% elevated OS priority is suspected of starving the keyboard input path
% (PsychHID's listener) of enough scheduling time to ever deliver a
% keypress into the KbQueue, which would explain why Escape/pause were
% undetectable for an entire story on real hardware despite this loop's
% logic checking for them every ~10ms: short clips (Block 1) never run long
% enough at elevated priority for that starvation to compound into total
% unresponsiveness, but a multi-minute story does.
priorPriority = Priority(0);
restorePriority = onCleanup(@() Priority(priorPriority));

proceed = true; playStart = GetSecs; deadline = playStart + storyDuration;
if maxSeconds > 0, deadline = min(deadline, playStart + maxSeconds); end
KbQueueFlush;
while GetSecs < deadline
    [pressed, first] = KbQueueCheck;
    if pressed && first(keys.escape) > 0, proceed = false; PsychPortAudio('Stop', audioHandle, 0); return; end
    if pressed && first(keys.pause) > 0
        positionSecs = PsychPortAudio('GetStatus', audioHandle).PositionSecs;
        PsychPortAudio('Stop', audioHandle, 1);
        [pauseDuration, aborted, onT, resT] = wait_for_pause_resume(window, config, diodeRect, ifi, keys, toneState);
        emitAfterPhotodiode(state, config, onT, 'PAUSE_ON', story.id, '', '');
        if aborted, proceed = false; return; end
        emitAfterPhotodiode(state, config, resT, 'PAUSE_RESUME', story.id, '', '');
        startSample = max(1, round(positionSecs * story.sample_rate) + 1);
        if startSample <= size(story.audio_samples, 2)
            PsychPortAudio('FillBuffer', audioHandle, story.audio_samples(:, startSample:end));
            PsychPortAudio('Start', audioHandle, 1, 0, 1);
        end
        deadline = deadline + pauseDuration;
        redrawFcn(); Screen('Flip', window);
        KbQueueFlush;
        continue;
    end
    WaitSecs('YieldSecs', 0.01);
end
PsychPortAudio('Stop', audioHandle, 0);
end

function [action, timestamp] = waitForQuestionAction(keys, autoSeconds)
if autoSeconds > 0, deadline = GetSecs + autoSeconds; else, deadline = Inf; end
while GetSecs < deadline
    [pressed, first] = KbQueueCheck;
    if pressed
        if first(keys.escape) > 0, action = "abort"; timestamp = first(keys.escape); return; end
        if first(keys.up) > 0, action = "up"; timestamp = first(keys.up); return; end
        if first(keys.down) > 0, action = "down"; timestamp = first(keys.down); return; end
        if first(keys.deselect) > 0, action = "deselect"; timestamp = first(keys.deselect); return; end
        if first(keys.enter) > 0, action = "enter"; timestamp = first(keys.enter); return; end
        KbQueueFlush;
    end
    WaitSecs('YieldSecs', 0.005);
end
action = "enter"; timestamp = GetSecs;
end

function value = csvText(value)
value = ['"' strrep(char(value), '"', '""') '"'];
end

function cleanupBlock3Audio(audioHandle)
try, PsychPortAudio('Stop', audioHandle, 0); catch, end
try, PsychPortAudio('Close', audioHandle); catch, end
end

function cleanupBlock3Queue()
try, KbQueueStop; catch, end
try, KbQueueRelease; catch, end
end

function cleanupBlock3Files(eventFile, responseFile)
if eventFile >= 0, fclose(eventFile); end
if responseFile >= 0, fclose(responseFile); end
end

function cleanupBlock3Screen(oldSkip)
try, ShowCursor; catch, end
try, Priority(0); catch, end
try, Screen('CloseAll'); catch, end
try, Screen('Preference', 'SkipSyncTests', oldSkip); catch, end
end
