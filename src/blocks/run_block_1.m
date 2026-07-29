function run_block_1(config)
%RUN_BLOCK_1 Run randomized speech and imagery trials.

block=load_block1_content(config.block1.content_file);
if ~isfield(config,'session')||~isfolder(config.session.directory),error('ImaginedSpeech:MissingSession','Block 1 requires an initialized patient session.');end
oldSkip=Screen('Preference','SkipSyncTests',double(config.display.skip_sync_tests)); screenCleanup=onCleanup(@()cleanupScreen1(oldSkip));
KbName('UnifyKeyNames'); keys.enter=KbName('Return'); keys.escape=KbName(config.keys.abort); keys.pause=KbName(config.keys.pause); allowed=zeros(1,256);allowed([keys.enter keys.escape keys.pause])=1;KbQueueCreate([],allowed);KbQueueStart;queueCleanup=onCleanup(@cleanupQueue1);
screens=Screen('Screens');if config.display.screen_index<0,screenIndex=max(screens);else,screenIndex=config.display.screen_index;end
windowRect=[];if config.display.debug_windowed,windowRect=config.display.debug_window_rect(:)';end
[window,rect]=PsychImaging('OpenWindow',screenIndex,config.display.background_rgb(:)',windowRect);HideCursor(window);Priority(MaxPriority(window));Screen('TextFont',window,config.display.font_name);ifi=Screen('GetFlipInterval',window);
diodeRect=[config.photodiode.margin_px,RectHeight(rect)-config.photodiode.margin_px-config.photodiode.size_px(2),config.photodiode.margin_px+config.photodiode.size_px(1),RectHeight(rect)-config.photodiode.margin_px];
% Hold each sync flash on for flash_frames refresh cycles (not just one) so a
% single dropped/jittered frame can't make the pulse too brief for the
% photodiode/DAQ to reliably register.
flashOff=(config.photodiode.flash_frames-0.5)*ifi;
mode=string(config.block1.presentation_mode);showText=mode~="listening";playAudio=mode~="reading";
if playAudio
    InitializePsychSound(1);audioHandle=PsychPortAudio('Open',[],1,1,block.audio(1).sample_rate,2);
else
    audioHandle=-1;
end
audioCleanup=onCleanup(@()cleanupAudio1(audioHandle));

toneState=init_sync_tones(config);toneCleanup=onCleanup(@()finish_sync_tones(toneState));

runId=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));eventFile=fopen(fullfile(config.session.directory,['block1_' runId '_events.csv']),'w');trialFile=fopen(fullfile(config.session.directory,['block1_' runId '_trials.csv']),'w');
if eventFile<0||trialFile<0,error('ImaginedSpeech:OutputOpenFailed','Cannot create Block 1 logs.');end
fileCleanup=onCleanup(@()cleanupFiles1(eventFile,trialFile));
fprintf(eventFile,'timestamp,event,trial,stimulus_id,stimulus_text,trial_type,early_end,action_duration\n');
fprintf(trialFile,['trial,stimulus_id,stimulus_text,trial_type,is_phrase,stimulus_onset,silence_onset,' ...
    'reveal_onset,cue_onset,iti_onset,ended_early,action_duration,silence_duration,iti_duration\n']);

sources=struct('label',{'block1_manifest','schedule','audio_manifest'}, ...
    'path',{config.block1.content_file,block.schedule_path,block.audio_manifest_path});
save_run_snapshot(config,1,runId,sources);

drawReady1(window,rect,block,config,diodeRect);Screen('Flip',window);
if ~waitReady1(keys,config.block1.test_max_trials),task_killed;end
KbReleaseWait;KbQueueFlush;
play_sync_tone(toneState,'block_start');
trialCount=height(block.schedule);if config.block1.test_max_trials>0,trialCount=min(trialCount,config.block1.test_max_trials);end
if config.block1.start_trial>trialCount
    error('ImaginedSpeech:InvalidStartTrial','block1.start_trial (%d) exceeds the number of available trials (%d).',config.block1.start_trial,trialCount);
end
scale=config.block1.test_timing_scale;
for trial=config.block1.start_trial:trialCount
    row=block.schedule(trial,:);audio=block.audio(row.audio_index);
    silenceDuration=config.block1.default_silence_seconds;if config.block1.use_schedule_silence,silenceDuration=row.silent_period_duration;end
    itiDuration=config.block1.default_iti_seconds;if config.block1.use_schedule_iti,itiDuration=row.inter_trial_interval_duration;end
    silenceDuration=silenceDuration*scale;itiDuration=itiDuration*scale;revealDuration=config.block1.reveal_seconds*scale;
    if row.is_phrase,maxAction=config.block1.phrase_action_seconds;else,maxAction=config.block1.word_action_seconds;end,maxAction=maxAction*scale;
    if row.is_phrase,readingSeconds=config.block1.reading_only_phrase_seconds;else,readingSeconds=config.block1.reading_only_word_seconds;end,readingSeconds=readingSeconds*scale;

    if showText,drawText1(window,rect,row.word,config.block1.stimulus_text_size,config,diodeRect,true);
    else,drawBlank1(window,config,diodeRect,true);end
    target=GetSecs+2*ifi;
    if playAudio,PsychPortAudio('FillBuffer',audioHandle,audio.samples);PsychPortAudio('Start',audioHandle,1,target,0);end
    stimOnset=Screen('Flip',window,target);
    if playAudio,emit1(eventFile,config,stimOnset,'AUDIO_ONSET',trial,row,NaN,NaN);
    else,play_sync_tone(toneState,'block1_reading_stimulus_onset');emit1(eventFile,config,stimOnset,'STIMULUS_ONSET',trial,row,NaN,NaN);end
    if showText,drawText1(window,rect,row.word,config.block1.stimulus_text_size,config,diodeRect,false);
    else,drawBlank1(window,config,diodeRect,false);end
    Screen('Flip',window,stimOnset+flashOff);
    if showText,stimRedraw=@() drawText1(window,rect,row.word,config.block1.stimulus_text_size,config,diodeRect,false);
    else,stimRedraw=@() drawBlank1(window,config,diodeRect,false);end
    if playAudio
        audioDuration=size(audio.samples,2)/audio.sample_rate;
        if ~waitAudio1(audioHandle,keys,config.block1.test_audio_max_seconds,window,config,diodeRect,ifi,eventFile,trial,row,audio.samples,audio.sample_rate,stimRedraw,toneState,audioDuration),PsychPortAudio('Stop',audioHandle,0);task_killed;end
    else
        if ~waitUntil1(stimOnset+readingSeconds,keys,window,config,diodeRect,ifi,eventFile,trial,row,stimRedraw,toneState),task_killed;end
    end

    drawBlank1(window,config,diodeRect,true);silenceOnset=Screen('Flip',window);emit1(eventFile,config,silenceOnset,'SILENCE_ONSET',trial,row,NaN,NaN);
    drawBlank1(window,config,diodeRect,false);Screen('Flip',window,silenceOnset+flashOff);
    blankRedraw=@() drawBlank1(window,config,diodeRect,false);
    if ~waitUntil1(silenceOnset+silenceDuration,keys,window,config,diodeRect,ifi,eventFile,trial,row,blankRedraw,toneState),task_killed;end

    actionLabel=getActionLabel1(block.action_labels,row.trial_type);
    drawText1(window,rect,actionLabel,config.block1.action_text_size,config,diodeRect,true);revealOnset=Screen('Flip',window);emit1(eventFile,config,revealOnset,'TRIAL_TYPE_REVEAL',trial,row,NaN,NaN);
    drawText1(window,rect,actionLabel,config.block1.action_text_size,config,diodeRect,false);Screen('Flip',window,revealOnset+flashOff);
    revealRedraw=@() drawText1(window,rect,actionLabel,config.block1.action_text_size,config,diodeRect,false);
    if ~waitUntil1(revealOnset+revealDuration,keys,window,config,diodeRect,ifi,eventFile,trial,row,revealRedraw,toneState),task_killed;end

    KbQueueFlush;drawCue1(window,rect,config,diodeRect,true);cueOnset=Screen('Flip',window);play_sync_tone(toneState,'block1_action_cue_onset');emit1(eventFile,config,cueOnset,'ACTION_CUE_ONSET',trial,row,NaN,NaN);
    drawCue1(window,rect,config,diodeRect,false);Screen('Flip',window,cueOnset+flashOff);
    cueRedraw=@() drawCue1(window,rect,config,diodeRect,false);
    simulate=ismember(trial,config.block1.test_early_end_trials);
    [endedEarly,actionEnd,aborted]=waitAction1(cueOnset,maxAction,keys,simulate,toneState,window,config,diodeRect,ifi,eventFile,trial,row,cueRedraw);
    if aborted,task_killed;end
    actionDuration=actionEnd-cueOnset;

    drawBlank1(window,config,diodeRect,true);itiOnset=Screen('Flip',window);play_sync_tone(toneState,'block1_action_cue_offset');emit1(eventFile,config,itiOnset,'ITI_ONSET',trial,row,endedEarly,actionDuration);
    drawBlank1(window,config,diodeRect,false);Screen('Flip',window,itiOnset+flashOff);
    if ~waitUntil1(itiOnset+itiDuration,keys,window,config,diodeRect,ifi,eventFile,trial,row,blankRedraw,toneState),task_killed;end
    fprintf(trialFile,'%d,%s,%s,%s,%d,%.9f,%.9f,%.9f,%.9f,%.9f,%d,%.9f,%.6f,%.6f\n',trial,csv1(row.stimulus_id),csv1(row.word),csv1(row.trial_type),row.is_phrase,stimOnset,silenceOnset,revealOnset,cueOnset,itiOnset,endedEarly,actionDuration,silenceDuration,itiDuration);
end
end

function label=getActionLabel1(labels,trialType)
switch char(trialType),case 'speaking',label=labels.speaking;case 'imagine speaking',label=labels.imagineSpeaking;case 'visually imagine',label=labels.visuallyImagine;otherwise,error('ImaginedSpeech:InvalidTrialType','Unknown trial type.');end
end
function drawReady1(w,r,b,c,d),Screen('FillRect',w,c.display.background_rgb(:)');Screen('TextSize',w,42);DrawFormattedText(w,b.ready_title,'center',RectHeight(r)*.2,c.display.text_rgb(:)',65);Screen('TextSize',w,27);DrawFormattedText(w,b.ready_text,'center',RectHeight(r)*.4,c.display.text_rgb(:)',75,[],[],1.25);DrawFormattedText(w,b.ready_prompt,'center',RectHeight(r)*.8,c.display.text_rgb(:)');drawDiode1(w,c,d,false);end
function drawText1(w,r,textValue,sizeValue,c,d,on),Screen('FillRect',w,c.display.background_rgb(:)');Screen('TextSize',w,sizeValue);DrawFormattedText(w,char(textValue),'center','center',c.display.text_rgb(:)',70);drawDiode1(w,c,d,on);end
function drawCue1(w,r,c,d,on),Screen('FillRect',w,c.display.background_rgb(:)');s=c.block1.cue_square_size_px;box=CenterRectOnPointd([0 0 s s],RectWidth(r)/2,RectHeight(r)/2);Screen('FillRect',w,[0 255 0],box);drawDiode1(w,c,d,on);end
function drawBlank1(w,c,d,on),Screen('FillRect',w,c.display.background_rgb(:)');drawDiode1(w,c,d,on);end
function drawDiode1(w,c,d,on),if ~c.photodiode.enabled,return,end,if on,color=c.photodiode.on_rgb;else,color=c.photodiode.off_rgb;end,Screen('FillRect',w,color(:)',d);end
function emit1(f,c,t,e,n,row,early,duration),comment=sprintf('B1_%s trial=%d text=%s type=%s',e,n,char(row.word),char(row.trial_type));if strcmp(e,'ITI_ONSET'),comment=sprintf('%s enter_early=%d action_s=%.3f',comment,early,duration);end,if strlength(comment)>127,error('ImaginedSpeech:CommentTooLong','Cbmex comment too long: %s',comment);end,send_task_event_comment(c,comment);fprintf(f,'%.9f,%s,%d,%s,%s,%s,%.0f,%.9f\n',t,e,n,row.stimulus_id,row.word,row.trial_type,early,duration);end
function ok=waitReady1(k,testTrials),KbQueueFlush;ok=false;if testTrials>0,d=GetSecs+.1;else,d=Inf;end,while GetSecs<d,[p,x]=KbQueueCheck;if p&&x(k.escape)>0,return,end,if p&&x(k.enter)>0,ok=true;return,end,WaitSecs('YieldSecs',.005);end,ok=true;end
function ok=waitAudio1(h,keys,maxSeconds,window,config,diodeRect,ifi,eventFile,trial,row,fullSamples,sampleRate,redrawFcn,toneState,audioDuration)
% Deadline-driven (not PsychPortAudio('GetStatus',h).Active-driven): the
% analytically-known clip duration is used as the loop's stopping
% condition, exactly like every other pausable phase in this block, rather
% than repeatedly polling audio device status. This matters for keyboard
% responsiveness: an early version of this function (and the equivalent in
% Block 3, for the much longer story audio) drove its while-loop off
% GetStatus().Active, which on real hardware could leave Escape/pause
% undetected for the entire clip -- reproduced and fixed for the long-audio
% case in Block 3; ported the same fix here since word/phrase clips are
% short enough that the same latent bug would be easy to miss in testing.
ok=true;playStart=GetSecs;deadline=playStart+audioDuration;
if maxSeconds>0,deadline=min(deadline,playStart+maxSeconds);end
KbQueueFlush;
while GetSecs<deadline
    [p,x]=KbQueueCheck;
    if p&&x(keys.escape)>0,ok=false;PsychPortAudio('Stop',h,0);return,end
    if p&&x(keys.pause)>0
        positionSecs=PsychPortAudio('GetStatus',h).PositionSecs;
        PsychPortAudio('Stop',h,1);
        [pauseDuration,aborted,onT,resT]=wait_for_pause_resume(window,config,diodeRect,ifi,keys,toneState);
        emit1(eventFile,config,onT,'PAUSE_ON',trial,row,NaN,NaN);
        if aborted,ok=false;return,end
        emit1(eventFile,config,resT,'PAUSE_RESUME',trial,row,NaN,NaN);
        startSample=max(1,round(positionSecs*sampleRate)+1);
        if startSample<=size(fullSamples,2)
            PsychPortAudio('FillBuffer',h,fullSamples(:,startSample:end));
            PsychPortAudio('Start',h,1,0,1);
        end
        deadline=deadline+pauseDuration;
        redrawFcn();Screen('Flip',window);KbQueueFlush;
        continue;
    end
    WaitSecs('YieldSecs',.005);
end
PsychPortAudio('Stop',h,0);
end
function ok=waitUntil1(deadline,keys,window,config,diodeRect,ifi,eventFile,trial,row,redrawFcn,toneState)
ok=true;KbQueueFlush;
while GetSecs<deadline
    [p,x]=KbQueueCheck;
    if p&&x(keys.escape)>0,ok=false;return,end
    if p&&x(keys.pause)>0
        [pauseDuration,aborted,onT,resT]=wait_for_pause_resume(window,config,diodeRect,ifi,keys,toneState);
        emit1(eventFile,config,onT,'PAUSE_ON',trial,row,NaN,NaN);
        if aborted,ok=false;return,end
        emit1(eventFile,config,resT,'PAUSE_RESUME',trial,row,NaN,NaN);
        deadline=deadline+pauseDuration;
        redrawFcn();Screen('Flip',window);KbQueueFlush;
        continue;
    end
    WaitSecs('YieldSecs',.002);
end
end
function [early,t,aborted]=waitAction1(onset,maxDuration,keys,simulate,toneState,window,config,diodeRect,ifi,eventFile,trial,row,redrawFcn)
early=false;aborted=false;deadline=onset+maxDuration;
while GetSecs<deadline
    [p,x]=KbQueueCheck;
    if p&&x(keys.escape)>0,t=GetSecs;aborted=true;return,end
    if p&&x(keys.pause)>0
        [pauseDuration,pausedAborted,onT,resT]=wait_for_pause_resume(window,config,diodeRect,ifi,keys,toneState);
        emit1(eventFile,config,onT,'PAUSE_ON',trial,row,NaN,NaN);
        if pausedAborted,t=GetSecs;aborted=true;return,end
        emit1(eventFile,config,resT,'PAUSE_RESUME',trial,row,NaN,NaN);
        deadline=deadline+pauseDuration;
        redrawFcn();Screen('Flip',window);KbQueueFlush;
        continue;
    end
    if p&&x(keys.enter)>0,early=true;t=x(keys.enter);play_sync_tone(toneState,'block1_early_response');return,end
    if simulate&&GetSecs>=onset+min(.05,maxDuration/2),early=true;t=GetSecs;play_sync_tone(toneState,'block1_early_response');return,end
    WaitSecs('YieldSecs',.002);
end
t=deadline;
end
function v=csv1(v),v=['"' strrep(char(v),'"','""') '"'];end
function cleanupAudio1(h),if h<0,return,end,try,PsychPortAudio('Stop',h,0);catch,end,try,PsychPortAudio('Close',h);catch,end,end
function cleanupQueue1(),try,KbQueueStop;catch,end,try,KbQueueRelease;catch,end,end
function cleanupFiles1(a,b),if a>=0,fclose(a);end,if b>=0,fclose(b);end,end
function cleanupScreen1(o),try,ShowCursor;catch,end,try,Priority(0);catch,end,try,Screen('CloseAll');catch,end,try,Screen('Preference','SkipSyncTests',o);catch,end,end
