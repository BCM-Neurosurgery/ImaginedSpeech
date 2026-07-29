function run_block_2(config)
%RUN_BLOCK_2 Run the image one-back encoding task.

block = load_block2_content(config.block2.content_file);
if ~isfield(config, 'session') || ~isfolder(config.session.directory)
    error('ImaginedSpeech:MissingSession', 'Block 2 requires an initialized patient session.');
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
% Raise scheduling priority for the timed portion of the block so OS-level
% preemption (background processes, the DWM compositor, etc.) is less likely
% to delay a Flip past its target and cause a dropped/mistimed frame. Reset
% to 0 happens in cleanup, which already assumed this was being done.
HideCursor(window); Priority(MaxPriority(window)); Screen('TextFont', window, config.display.font_name);
ifi = Screen('GetFlipInterval', window);
diodeRect = makeDiodeRect2(rect, config.photodiode);
% Hold each sync flash on for flash_frames refresh cycles (not just one) so a
% single dropped/jittered frame can't make the pulse too brief for the
% photodiode/DAQ to reliably register.
flashOff = (config.photodiode.flash_frames - 0.5) * ifi;

textures = zeros(numel(block.images), 1);
for index = 1:numel(block.images)
    textures(index) = Screen('MakeTexture', window, block.images(index).pixels);
end
textureCleanup = onCleanup(@() cleanupTextures(textures));

toneState = init_sync_tones(config);
toneCleanup = onCleanup(@() finish_sync_tones(toneState));

runId = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
eventFile = fopen(fullfile(config.session.directory, ['block2_' runId '_events.csv']), 'w');
responseFile = fopen(fullfile(config.session.directory, ['block2_' runId '_responses.csv']), 'w');
if eventFile < 0 || responseFile < 0, error('ImaginedSpeech:OutputOpenFailed', 'Cannot create Block 2 logs.'); end
fileCleanup = onCleanup(@() cleanupFiles(eventFile, responseFile));
fprintf(eventFile, 'event_timestamp,event,trial,image_name,key_timestamp\n');
fprintf(responseFile, ['trial,image_name,image_type,schedule_repeat_flag,is_target,' ...
    'responded,response_time,reaction_time,outcome,image_onset\n']);

sources = struct('label', {'block2_manifest', 'schedule'}, ...
    'path', {config.block2.content_file, block.schedule_path});
save_run_snapshot(config, 2, runId, sources);

drawReady2(window, rect, block, config, diodeRect, false); Screen('Flip', window);
if ~waitReady2(keys, config.block2.test_response_trials), task_killed; end
KbReleaseWait; KbQueueFlush;
play_sync_tone(toneState, 'block_start');

trialCount = height(block.schedule);
if config.block2.test_max_trials > 0, trialCount = min(trialCount, config.block2.test_max_trials); end
nextOnset = GetSecs + 2 * ifi;
for trial = 1:trialCount
    row = block.schedule(trial, :);
    texture = textures(row.image_index);
    destination = fitTextureRect(Screen('Rect', texture), rect, config.block2.image_display_fraction);
    drawImage2(window, texture, destination, config, diodeRect, true);
    onset = Screen('Flip', window, nextOnset);
    play_sync_tone(toneState, 'block2_image_onset');
    emit2(eventFile, config, onset, 'IMAGE_ONSET', trial, row.image_name, NaN);
    drawImage2(window, texture, destination, config, diodeRect, false);
    Screen('Flip', window, onset + flashOff);
    KbQueueFlush;

    responded = false; responseTime = NaN;
    imageOffset = onset + config.block2.image_on_seconds;
    trialEnd = imageOffset + config.block2.image_off_seconds;
    autoRespond = ismember(trial, config.block2.test_response_trials);
    [responded, responseTime, aborted, respFlashEnd] = collectPhase(window, texture, destination, ...
        true, imageOffset, responded, responseTime, autoRespond, onset, keys, ...
        config, diodeRect, eventFile, trial, row.image_name, ifi, toneState);
    if aborted, task_killed; end
    % No flash/comment on the image-off transition itself -- only IMAGE_ONSET
    % and RESPONSE are marked. A RESPONSE flash landing near imageOffset was
    % otherwise liable to sit right next to this transition's own flash and
    % blend into it on the photodiode, which is what made proccing inconsistent.
    Screen('FillRect', window, config.display.background_rgb(:)');
    drawDiode2(window, config, diodeRect, false); Screen('Flip', window, imageOffset);
    [responded, responseTime, aborted, respFlashEnd2] = collectPhase(window, texture, destination, ...
        false, trialEnd, responded, responseTime, autoRespond, onset, keys, ...
        config, diodeRect, eventFile, trial, row.image_name, ifi, toneState);
    if aborted, task_killed; end
    if ~isnan(respFlashEnd2), respFlashEnd = respFlashEnd2; end

    if row.is_target && responded, outcome = 'hit';
    elseif row.is_target, outcome = 'miss';
    elseif responded, outcome = 'false_alarm';
    else, outcome = 'correct_rejection'; end
    fprintf(responseFile, '%d,%s,%s,%s,%d,%d,%.9f,%.9f,%s,%.9f\n', ...
        trial, csv2(row.image_name), csv2(row.image_type), csv2(row.repeated_consecutively), ...
        row.is_target, responded, responseTime, responseTime - onset, outcome, onset);
    % A RESPONSE flash can land anywhere up to trialEnd (participants often
    % react after the image itself has already gone off-screen). If one
    % happened right before trialEnd, pushing the next trial's IMAGE_ONSET
    % flash out until that RESPONSE flash has fully finished prevents the two
    % flashes from landing close enough together to blend on the photodiode.
    nextOnset = trialEnd;
    if ~isnan(respFlashEnd), nextOnset = max(nextOnset, respFlashEnd + flashOff); end
end
% textureCleanup (registered above, right after the textures were created)
% already closes these textures exactly once on every exit path via onCleanup's
% LIFO ordering -- it fires before screenCleanup regardless of whether this
% function returns normally, is ended early by Escape, or errors. Do not also
% close them here: Screen('Close') on an already-closed texture handle is a
% double-free that can crash MATLAB outright rather than raising a catchable error.
end

function [responded, responseTime, aborted, flashEnd] = collectPhase(window, texture, destination, imageVisible, deadline, responded, responseTime, autoRespond, onset, keys, config, diodeRect, eventFile, trial, imageName, ifi, toneState)
aborted = false;
flashEnd = NaN; % actual completion time of this call's RESPONSE flash, if any; NaN if no response occurred here
while GetSecs < deadline
    [pressed, first] = KbQueueCheck;
    if pressed && first(keys.escape) > 0, aborted = true; return; end
    simulated = autoRespond && ~responded && GetSecs >= onset + 0.05;
    actual = pressed && first(keys.enter) > 0;
    if ~responded && (actual || simulated)
        if actual, responseTime = first(keys.enter); else, responseTime = GetSecs; end
        responded = true;
        play_sync_tone(toneState, 'block2_response');
        if imageVisible, drawImage2(window, texture, destination, config, diodeRect, true);
        else, Screen('FillRect', window, config.display.background_rgb(:)'); drawDiode2(window, config, diodeRect, true); end
        flashTime = Screen('Flip', window);
        emit2(eventFile, config, flashTime, 'RESPONSE', trial, imageName, responseTime);
        if imageVisible, drawImage2(window, texture, destination, config, diodeRect, false);
        else, Screen('FillRect', window, config.display.background_rgb(:)'); drawDiode2(window, config, diodeRect, false); end
        flashEnd = Screen('Flip', window, flashTime + (config.photodiode.flash_frames - 0.5) * ifi); KbQueueFlush;
    end
    WaitSecs('YieldSecs', 0.002);
end
end

function drawReady2(window, rect, block, config, diodeRect, on)
Screen('FillRect', window, config.display.background_rgb(:)'); Screen('TextSize', window, 42);
DrawFormattedText(window, block.ready_title, 'center', RectHeight(rect)*0.25, config.display.text_rgb(:)');
Screen('TextSize', window, 28); DrawFormattedText(window, block.ready_text, 'center', RectHeight(rect)*0.45, config.display.text_rgb(:)', 60);
DrawFormattedText(window, block.ready_prompt, 'center', RectHeight(rect)*0.75, config.display.text_rgb(:)');
drawDiode2(window, config, diodeRect, on);
end

function drawImage2(window, texture, destination, config, diodeRect, on)
Screen('FillRect', window, config.display.background_rgb(:)'); Screen('DrawTexture', window, texture, [], destination);
drawDiode2(window, config, diodeRect, on);
end

function destination = fitTextureRect(source, target, fraction)
scale = min(RectWidth(target)*fraction/RectWidth(source), RectHeight(target)*fraction/RectHeight(source));
destination = CenterRectOnPointd([0 0 RectWidth(source)*scale RectHeight(source)*scale], RectWidth(target)/2, RectHeight(target)/2);
end

function rect = makeDiodeRect2(windowRect, diode)
rect = [diode.margin_px, RectHeight(windowRect)-diode.margin_px-diode.size_px(2), diode.margin_px+diode.size_px(1), RectHeight(windowRect)-diode.margin_px];
end
function drawDiode2(window, config, rect, on)
if ~config.photodiode.enabled, return; end
if on, color=config.photodiode.on_rgb; else, color=config.photodiode.off_rgb; end
Screen('FillRect', window, color(:)', rect);
end
function emit2(fileId, config, timestamp, eventName, trial, imageName, keyTime)
comment = sprintf('B2_%s trial=%d image=%s', eventName, trial, imageName);
if strlength(comment)>127, error('ImaginedSpeech:CommentTooLong','Cbmex comment too long.'); end
send_task_event_comment(config,comment);
fprintf(fileId,'%.9f,%s,%d,%s,%.9f\n',timestamp,eventName,trial,imageName,keyTime);
end
function proceed = waitReady2(keys, testResponses)
KbQueueFlush; proceed=false; auto=~isempty(testResponses); if auto, deadline=GetSecs+0.1; else, deadline=Inf; end
while GetSecs<deadline
    [pressed,first]=KbQueueCheck; if pressed && first(keys.escape)>0, return; end
    if pressed && first(keys.enter)>0, proceed=true; return; end
    WaitSecs('YieldSecs',0.005);
end
proceed=true;
end
function value=csv2(value), value=['"' strrep(char(value),'"','""') '"']; end
function cleanupQueue(), try, KbQueueStop; catch, end, try, KbQueueRelease; catch, end, end
function cleanupTextures(textureHandles), try, Screen('Close', textureHandles); catch, end, end
function cleanupFiles(a,b), if a>=0, fclose(a); end, if b>=0, fclose(b); end, end
function cleanupScreen(oldSkip), try, ShowCursor; catch, end, try, Priority(0); catch, end, try, Screen('CloseAll'); catch, end, try, Screen('Preference','SkipSyncTests',oldSkip); catch, end, end
