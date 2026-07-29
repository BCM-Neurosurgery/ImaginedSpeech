function run_block_1(config)
%RUN_BLOCK_1 Run randomized speech and imagery trials.

block=load_block1_content(config.block1.content_file);
if ~isfield(config,'session')||~isfolder(config.session.directory),error('ImaginedSpeech:MissingSession','Block 1 requires an initialized patient session.');end
oldSkip=Screen('Preference','SkipSyncTests',double(config.display.skip_sync_tests)); screenCleanup=onCleanup(@()cleanupScreen1(oldSkip));
KbName('UnifyKeyNames'); keys.enter=KbName('Return'); keys.escape=KbName(config.keys.abort); allowed=zeros(1,256);allowed([keys.enter keys.escape])=1;KbQueueCreate([],allowed);KbQueueStart;queueCleanup=onCleanup(@cleanupQueue1);
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
scale=config.block1.test_timing_scale;
for trial=1:trialCount
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
    if playAudio
        if ~waitAudio1(audioHandle,keys.escape,config.block1.test_audio_max_seconds),PsychPortAudio('Stop',audioHandle,0);task_killed;end
    else
        if ~waitUntil1(stimOnset+readingSeconds,keys.escape),task_killed;end
    end

    drawBlank1(window,config,diodeRect,true);silenceOnset=Screen('Flip',window);emit1(eventFile,config,silenceOnset,'SILENCE_ONSET',trial,row,NaN,NaN);
    drawBlank1(window,config,diodeRect,false);Screen('Flip',window,silenceOnset+flashOff);if ~waitUntil1(silenceOnset+silenceDuration,keys.escape),task_killed;end

    actionLabel=getActionLabel1(block.action_labels,row.trial_type);
    drawText1(window,rect,actionLabel,config.block1.action_text_size,config,diodeRect,true);revealOnset=Screen('Flip',window);emit1(eventFile,config,revealOnset,'TRIAL_TYPE_REVEAL',trial,row,NaN,NaN);
    drawText1(window,rect,actionLabel,config.block1.action_text_size,config,diodeRect,false);Screen('Flip',window,revealOnset+flashOff);if ~waitUntil1(revealOnset+revealDuration,keys.escape),task_killed;end

    KbQueueFlush;drawCue1(window,rect,config,diodeRect,true);cueOnset=Screen('Flip',window);emit1(eventFile,config,cueOnset,'ACTION_CUE_ONSET',trial,row,NaN,NaN);
    drawCue1(window,rect,config,diodeRect,false);Screen('Flip',window,cueOnset+flashOff);
    simulate=ismember(trial,config.block1.test_early_end_trials);[endedEarly,actionEnd,aborted]=waitAction1(cueOnset,maxAction,keys,simulate,toneState);if aborted,task_killed;end
    actionDuration=actionEnd-cueOnset;

    drawBlank1(window,config,diodeRect,true);itiOnset=Screen('Flip',window);emit1(eventFile,config,itiOnset,'ITI_ONSET',trial,row,endedEarly,actionDuration);
    drawBlank1(window,config,diodeRect,false);Screen('Flip',window,itiOnset+flashOff);if ~waitUntil1(itiOnset+itiDuration,keys.escape),task_killed;end
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
function ok=waitAudio1(h,esc,maxSeconds),ok=true;start=GetSecs;KbQueueFlush;while true,status=PsychPortAudio('GetStatus',h);if ~status.Active,return,end,[p,x]=KbQueueCheck;if p&&x(esc)>0,ok=false;return,end,if maxSeconds>0&&GetSecs-start>=maxSeconds,PsychPortAudio('Stop',h,0);return,end,WaitSecs('YieldSecs',.005);end,end
function ok=waitUntil1(deadline,esc),ok=true;KbQueueFlush;while GetSecs<deadline,[p,x]=KbQueueCheck;if p&&x(esc)>0,ok=false;return,end,WaitSecs('YieldSecs',.002);end,end
function [early,t,aborted]=waitAction1(onset,maxDuration,k,simulate,toneState),early=false;aborted=false;deadline=onset+maxDuration;while GetSecs<deadline,[p,x]=KbQueueCheck;if p&&x(k.escape)>0,t=GetSecs;aborted=true;return,end,if p&&x(k.enter)>0,early=true;t=x(k.enter);play_sync_tone(toneState,'block1_early_response');return,end,if simulate&&GetSecs>=onset+min(.05,maxDuration/2),early=true;t=GetSecs;play_sync_tone(toneState,'block1_early_response');return,end,WaitSecs('YieldSecs',.002);end,t=deadline;end
function v=csv1(v),v=['"' strrep(char(v),'"','""') '"'];end
function cleanupAudio1(h),if h<0,return,end,try,PsychPortAudio('Stop',h,0);catch,end,try,PsychPortAudio('Close',h);catch,end,end
function cleanupQueue1(),try,KbQueueStop;catch,end,try,KbQueueRelease;catch,end,end
function cleanupFiles1(a,b),if a>=0,fclose(a);end,if b>=0,fclose(b);end,end
function cleanupScreen1(o),try,ShowCursor;catch,end,try,Priority(0);catch,end,try,Screen('CloseAll');catch,end,try,Screen('Preference','SkipSyncTests',o);catch,end,end
