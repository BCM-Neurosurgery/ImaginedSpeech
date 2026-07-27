function run_block_3(config)
%RUN_BLOCK_3 Run the image one-back encoding task.

block = load_block3_content(config.block3.content_file);
if ~isfield(config, 'session') || ~isfolder(config.session.directory)
    error('ImaginedSpeech:MissingSession', 'Block 3 requires an initialized patient session.');
end
oldSkip = Screen('Preference', 'SkipSyncTests', double(config.display.skip_sync_tests));
screenCleanup = onCleanup(@() cleanupScreen(oldSkip));

KbName('UnifyKeyNames');
keys.enter = KbName('Return'); keys.escape = KbName(config.keys.abort);
allowed = zeros(1, 256); allowed([keys.enter keys.escape]) = 1;
KbQueueCreate([], allowed); KbQueueStart;
queueCleanup = onCleanup(@cleanupQueue);

screens = Screen('Screens');
if config.display.screen_index < 0, screenIndex = max(screens); else, screenIndex = config.display.screen_index; end
windowRect = [];
if config.display.debug_windowed, windowRect = config.display.debug_window_rect(:)'; end
[window, rect] = PsychImaging('OpenWindow', screenIndex, config.display.background_rgb(:)', windowRect);
HideCursor(window); Screen('TextFont', window, config.display.font_name);
ifi = Screen('GetFlipInterval', window);
diodeRect = makeDiodeRect3(rect, config.photodiode);

textures = zeros(numel(block.images), 1);
for index = 1:numel(block.images)
    textures(index) = Screen('MakeTexture', window, block.images(index).pixels);
end
textureCleanup = onCleanup(@() cleanupTextures(textures));

runId = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
eventFile = fopen(fullfile(config.session.directory, ['block3_' runId '_events.csv']), 'w');
responseFile = fopen(fullfile(config.session.directory, ['block3_' runId '_responses.csv']), 'w');
if eventFile < 0 || responseFile < 0, error('ImaginedSpeech:OutputOpenFailed', 'Cannot create Block 3 logs.'); end
fileCleanup = onCleanup(@() cleanupFiles(eventFile, responseFile));
fprintf(eventFile, 'event_timestamp,event,trial,image_name,key_timestamp\n');
fprintf(responseFile, ['trial,image_name,image_type,schedule_repeat_flag,is_target,' ...
    'responded,response_time,reaction_time,outcome,image_onset\n']);

drawReady3(window, rect, block, config, diodeRect, false); Screen('Flip', window);
if ~waitReady3(keys, config.block3.test_response_trials), task_killed; end
KbReleaseWait; KbQueueFlush;

trialCount = height(block.schedule);
if config.block3.test_max_trials > 0, trialCount = min(trialCount, config.block3.test_max_trials); end
nextOnset = GetSecs + 2 * ifi;
for trial = 1:trialCount
    row = block.schedule(trial, :);
    texture = textures(row.image_index);
    destination = fitTextureRect(Screen('Rect', texture), rect, 0.8);
    drawImage3(window, texture, destination, config, diodeRect, true);
    onset = Screen('Flip', window, nextOnset);
    emit3(eventFile, config, onset, 'IMAGE_ONSET', trial, row.image_name, NaN);
    drawImage3(window, texture, destination, config, diodeRect, false);
    Screen('Flip', window, onset + 0.5 * ifi);
    KbQueueFlush;

    responded = false; responseTime = NaN;
    imageOffset = onset + config.block3.image_on_seconds;
    trialEnd = imageOffset + config.block3.image_off_seconds;
    autoRespond = ismember(trial, config.block3.test_response_trials);
    [responded, responseTime, aborted] = collectPhase(window, texture, destination, ...
        true, imageOffset, responded, responseTime, autoRespond, onset, keys, ...
        config, diodeRect, eventFile, trial, row.image_name, ifi);
    if aborted, task_killed; end
    Screen('FillRect', window, config.display.background_rgb(:)');
    drawDiode3(window, config, diodeRect, false); Screen('Flip', window, imageOffset);
    [responded, responseTime, aborted] = collectPhase(window, texture, destination, ...
        false, trialEnd, responded, responseTime, autoRespond, onset, keys, ...
        config, diodeRect, eventFile, trial, row.image_name, ifi);
    if aborted, task_killed; end

    if row.is_target && responded, outcome = 'hit';
    elseif row.is_target, outcome = 'miss';
    elseif responded, outcome = 'false_alarm';
    else, outcome = 'correct_rejection'; end
    fprintf(responseFile, '%d,%s,%s,%s,%d,%d,%.9f,%.9f,%s,%.9f\n', ...
        trial, csv3(row.image_name), csv3(row.image_type), csv3(row.repeated_consecutively), ...
        row.is_target, responded, responseTime, responseTime - onset, outcome, onset);
    nextOnset = trialEnd;
end
% Release the precreated textures before the onscreen window's cleanup runs.
% The cleanup guard remains in place for errors and participant aborts.
Screen('Close', textures);
textures(:) = 0;
end

function [responded, responseTime, aborted] = collectPhase(window, texture, destination, imageVisible, deadline, responded, responseTime, autoRespond, onset, keys, config, diodeRect, eventFile, trial, imageName, ifi)
aborted = false;
while GetSecs < deadline
    [pressed, first] = KbQueueCheck;
    if pressed && first(keys.escape) > 0, aborted = true; return; end
    simulated = autoRespond && ~responded && GetSecs >= onset + 0.05;
    actual = pressed && first(keys.enter) > 0;
    if ~responded && (actual || simulated)
        if actual, responseTime = first(keys.enter); else, responseTime = GetSecs; end
        responded = true;
        if imageVisible, drawImage3(window, texture, destination, config, diodeRect, true);
        else, Screen('FillRect', window, config.display.background_rgb(:)'); drawDiode3(window, config, diodeRect, true); end
        flashTime = Screen('Flip', window);
        emit3(eventFile, config, flashTime, 'RESPONSE', trial, imageName, responseTime);
        if imageVisible, drawImage3(window, texture, destination, config, diodeRect, false);
        else, Screen('FillRect', window, config.display.background_rgb(:)'); drawDiode3(window, config, diodeRect, false); end
        Screen('Flip', window, flashTime + 0.5 * ifi); KbQueueFlush;
    end
    WaitSecs('YieldSecs', 0.002);
end
end

function drawReady3(window, rect, block, config, diodeRect, on)
Screen('FillRect', window, config.display.background_rgb(:)'); Screen('TextSize', window, 42);
DrawFormattedText(window, block.ready_title, 'center', RectHeight(rect)*0.25, config.display.text_rgb(:)');
Screen('TextSize', window, 28); DrawFormattedText(window, block.ready_text, 'center', RectHeight(rect)*0.45, config.display.text_rgb(:)', 60);
DrawFormattedText(window, block.ready_prompt, 'center', RectHeight(rect)*0.75, config.display.text_rgb(:)');
drawDiode3(window, config, diodeRect, on);
end

function drawImage3(window, texture, destination, config, diodeRect, on)
Screen('FillRect', window, config.display.background_rgb(:)'); Screen('DrawTexture', window, texture, [], destination);
drawDiode3(window, config, diodeRect, on);
end

function destination = fitTextureRect(source, target, fraction)
scale = min(RectWidth(target)*fraction/RectWidth(source), RectHeight(target)*fraction/RectHeight(source));
destination = CenterRectOnPointd([0 0 RectWidth(source)*scale RectHeight(source)*scale], RectWidth(target)/2, RectHeight(target)/2);
end

function rect = makeDiodeRect3(windowRect, diode)
rect = [diode.margin_px, RectHeight(windowRect)-diode.margin_px-diode.size_px(2), diode.margin_px+diode.size_px(1), RectHeight(windowRect)-diode.margin_px];
end
function drawDiode3(window, config, rect, on)
if ~config.photodiode.enabled, return; end
if on, color=config.photodiode.on_rgb; else, color=config.photodiode.off_rgb; end
Screen('FillRect', window, color(:)', rect);
end
function emit3(fileId, config, timestamp, eventName, trial, imageName, keyTime)
comment = sprintf('B3_%s trial=%d image=%s', eventName, trial, imageName);
if strlength(comment)>127, error('ImaginedSpeech:CommentTooLong','Cbmex comment too long.'); end
send_task_event_comment(config,comment);
fprintf(fileId,'%.9f,%s,%d,%s,%.9f\n',timestamp,eventName,trial,imageName,keyTime);
end
function proceed = waitReady3(keys, testResponses)
KbQueueFlush; proceed=false; auto=~isempty(testResponses); if auto, deadline=GetSecs+0.1; else, deadline=Inf; end
while GetSecs<deadline
    [pressed,first]=KbQueueCheck; if pressed && first(keys.escape)>0, return; end
    if pressed && first(keys.enter)>0, proceed=true; return; end
    WaitSecs('YieldSecs',0.005);
end
proceed=true;
end
function value=csv3(value), value=['"' strrep(char(value),'"','""') '"']; end
function cleanupQueue(), try, KbQueueStop; catch, end, try, KbQueueRelease; catch, end, end
function cleanupTextures(textureHandles), try, Screen('Close', textureHandles); catch, end, end
function cleanupFiles(a,b), if a>=0, fclose(a); end, if b>=0, fclose(b); end, end
function cleanupScreen(oldSkip), ShowCursor; Priority(0); Screen('CloseAll'); Screen('Preference','SkipSyncTests',oldSkip); end
