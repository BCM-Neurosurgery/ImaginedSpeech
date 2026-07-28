function run_block_4(config)
%RUN_BLOCK_4 Administer the data-driven VVIQ survey.

survey=load_block4_content(config.block4.content_file);
if ~isfield(config,'session') || ~isfolder(config.session.directory)
    error('ImaginedSpeech:MissingSession','Block 4 requires an initialized patient session.');
end
oldSkip=Screen('Preference','SkipSyncTests',double(config.display.skip_sync_tests));
screenCleanup=onCleanup(@()cleanupScreen4(oldSkip));
KbName('UnifyKeyNames');
keys.enter=KbName('Return'); keys.up=KbName('UpArrow'); keys.down=KbName('DownArrow'); keys.escape=KbName(config.keys.abort); keys.deselect=KbName(config.keys.deselect);
allowed=zeros(1,256); allowed([keys.enter keys.up keys.down keys.escape keys.deselect])=1;
KbQueueCreate([],allowed); KbQueueStart; queueCleanup=onCleanup(@cleanupQueue4);

screens=Screen('Screens'); if config.display.screen_index<0, screenIndex=max(screens); else, screenIndex=config.display.screen_index; end
windowRect=[]; if config.display.debug_windowed, windowRect=config.display.debug_window_rect(:)'; end
[window,rect]=PsychImaging('OpenWindow',screenIndex,config.display.background_rgb(:)',windowRect);
HideCursor(window); Screen('TextFont',window,config.display.font_name); ifi=Screen('GetFlipInterval',window);
diodeRect=[config.photodiode.margin_px, RectHeight(rect)-config.photodiode.margin_px-config.photodiode.size_px(2), config.photodiode.margin_px+config.photodiode.size_px(1), RectHeight(rect)-config.photodiode.margin_px];

toneState=init_sync_tones(config);
toneCleanup=onCleanup(@()finish_sync_tones(toneState));

runId=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
eventFile=fopen(fullfile(config.session.directory,['block4_' runId '_events.csv']),'w');
responseFile=fopen(fullfile(config.session.directory,['block4_' runId '_responses.csv']),'w');
summaryFile=fullfile(config.session.directory,['block4_' runId '_summary.json']);
if eventFile<0 || responseFile<0, error('ImaginedSpeech:OutputOpenFailed','Cannot create Block 4 logs.'); end
fileCleanup=onCleanup(@()cleanupFiles4(eventFile,responseFile));
fprintf(eventFile,'event_timestamp,event,section_id,item_id,choice_id,choice_value\n');
fprintf(responseFile,'item_number,section_id,item_id,choice_id,choice_text,choice_value,question_onset,pick_time,submit_time\n');

sources=struct('label',{'vviq_survey'},'path',{config.block4.content_file});
save_run_snapshot(config,4,runId,sources);

drawIntro4(window,rect,survey,config,diodeRect); Screen('Flip',window);
if ~waitIntro4(keys,config.block4.test_auto_advance_seconds), task_killed; end
KbReleaseWait; itemNumber=0; totalScore=0;
play_sync_tone(toneState,'block_start');
for sectionIndex=1:numel(survey.sections)
    section=survey.sections(sectionIndex);
    for sectionItem=1:numel(section.items)
        itemNumber=itemNumber+1; item=section.items(sectionItem); highlight=1; selected=0;
        drawItem4(window,rect,section,item,survey,highlight,selected,itemNumber,config,diodeRect,true);
        onset=Screen('Flip',window); play_sync_tone(toneState,'block4_question_onset'); emit4(eventFile,config,onset,'QUESTION_SHOW',section.id,item.id,'',NaN);
        drawItem4(window,rect,section,item,survey,highlight,selected,itemNumber,config,diodeRect,false);
        Screen('Flip',window,onset+0.5*ifi); KbQueueFlush;
        pickTime=NaN;
        while true
            [action,actionTime]=waitAction4(keys,config.block4.test_auto_advance_seconds);
            if action=="abort", task_killed;
            elseif action=="up" && selected==0, highlight=mod(highlight-2,numel(survey.choices))+1;
            elseif action=="down" && selected==0, highlight=mod(highlight,numel(survey.choices))+1;
            elseif action=="enter" && selected==0
                selected=highlight; pickTime=actionTime; choice=survey.choices(selected);
                drawItem4(window,rect,section,item,survey,highlight,selected,itemNumber,config,diodeRect,true);
                flash=Screen('Flip',window); emit4(eventFile,config,flash,'ANSWER_PICK',section.id,item.id,choice.id,choice.value);
                drawItem4(window,rect,section,item,survey,highlight,selected,itemNumber,config,diodeRect,false);
                Screen('Flip',window,flash+0.5*ifi); KbQueueFlush; continue;
            elseif action=="deselect" && selected>0
                previousChoice=survey.choices(selected); selected=0; pickTime=NaN;
                drawItem4(window,rect,section,item,survey,highlight,selected,itemNumber,config,diodeRect,true);
                flash=Screen('Flip',window); emit4(eventFile,config,flash,'ANSWER_DESELECT',section.id,item.id,previousChoice.id,previousChoice.value);
                drawItem4(window,rect,section,item,survey,highlight,selected,itemNumber,config,diodeRect,false);
                Screen('Flip',window,flash+0.5*ifi); KbQueueFlush; continue;
            elseif action=="enter" && selected>0
                submitTime=actionTime; choice=survey.choices(selected);
                drawItem4(window,rect,section,item,survey,highlight,selected,itemNumber,config,diodeRect,true);
                flash=Screen('Flip',window); emit4(eventFile,config,flash,'ANSWER_SUBMIT',section.id,item.id,choice.id,choice.value);
                fprintf(responseFile,'%d,%s,%s,%s,%s,%d,%.9f,%.9f,%.9f\n',itemNumber,csv4(section.id),csv4(item.id),csv4(choice.id),csv4(choice.text),choice.value,onset,pickTime,submitTime);
                totalScore=totalScore+choice.value; break;
            end
            drawItem4(window,rect,section,item,survey,highlight,selected,itemNumber,config,diodeRect,false); Screen('Flip',window); KbQueueFlush;
        end
    end
end
summary=struct('survey_id',survey.survey_id,'patient_id',config.session.patient_id,'items_completed',itemNumber,'total_score',totalScore,'minimum',survey.scoring.minimum,'maximum',survey.scoring.maximum,'direction',survey.scoring.direction);
fid=fopen(summaryFile,'w'); if fid<0, error('ImaginedSpeech:OutputOpenFailed','Cannot create VVIQ summary.'); end
summaryCleanup=onCleanup(@()fclose(fid)); fwrite(fid,jsonencode(summary,PrettyPrint=true),'char');
end

function drawIntro4(w,r,s,c,d), Screen('FillRect',w,c.display.background_rgb(:)'); Screen('TextSize',w,40); DrawFormattedText(w,s.title,'center',RectHeight(r)*.18,c.display.text_rgb(:)',60); Screen('TextSize',w,25); DrawFormattedText(w,s.instructions,'center',RectHeight(r)*.38,c.display.text_rgb(:)',75,[],[],1.3); DrawFormattedText(w,s.begin_prompt,'center',RectHeight(r)*.78,c.display.text_rgb(:)'); drawDiode4(w,c,d,false); end
function drawItem4(w,r,section,item,s,highlight,selected,n,c,d,on)
Screen('FillRect',w,c.display.background_rgb(:)'); Screen('TextSize',w,c.block4.context_size); DrawFormattedText(w,section.prompt,'center',RectHeight(r)*.07,c.display.text_rgb(:)',78,[],[],1.15); Screen('TextSize',w,c.block4.question_size); DrawFormattedText(w,item.text,'center',RectHeight(r)*.28,c.display.text_rgb(:)',65);
for k=1:numel(s.choices), color=c.display.text_rgb(:)'; prefix='  '; if k==highlight, color=c.block4.highlight_rgb(:)'; prefix='> '; end, if k==selected, color=c.block4.selected_rgb(:)'; prefix='X '; end, Screen('TextSize',w,c.block4.choice_size); DrawFormattedText(w,[prefix s.choices(k).text],RectWidth(r)*.12,RectHeight(r)*(.43+.068*(k-1)),color,82); end
if selected==0,prompt=s.navigation_prompt;else,prompt=s.submit_prompt;end, Screen('TextSize',w,c.block4.footer_size); DrawFormattedText(w,sprintf('%s\n\n%d of 16',prompt,n),'center',RectHeight(r)*.84,c.display.text_rgb(:)',90); drawDiode4(w,c,d,on);
end
function drawDiode4(w,c,d,on), if ~c.photodiode.enabled,return,end,if on,color=c.photodiode.on_rgb;else,color=c.photodiode.off_rgb;end,Screen('FillRect',w,color(:)',d);end
function emit4(f,c,t,e,section,item,choice,value), comment=sprintf('B4_%s q=%s',e,item);if ~isempty(choice),comment=sprintf('%s answer=%s',comment,choice);end,if strlength(comment)>127,error('ImaginedSpeech:CommentTooLong','Cbmex comment too long.'),end,send_task_event_comment(c,comment);fprintf(f,'%.9f,%s,%s,%s,%s,%.0f\n',t,e,section,item,choice,value);end
function ok=waitIntro4(k,a),KbQueueFlush;ok=false;if a>0,d=GetSecs+a;else,d=Inf;end,while GetSecs<d,[p,x]=KbQueueCheck;if p&&x(k.escape)>0,return,end,if p&&x(k.enter)>0,ok=true;return,end,WaitSecs('YieldSecs',.005);end,ok=true;end
function [a,t]=waitAction4(k,auto),if auto>0,d=GetSecs+auto;else,d=Inf;end,while GetSecs<d,[p,x]=KbQueueCheck;if p,if x(k.escape)>0,a="abort";t=x(k.escape);return,end,if x(k.up)>0,a="up";t=x(k.up);return,end,if x(k.down)>0,a="down";t=x(k.down);return,end,if x(k.deselect)>0,a="deselect";t=x(k.deselect);return,end,if x(k.enter)>0,a="enter";t=x(k.enter);return,end,end,WaitSecs('YieldSecs',.005);end,a="enter";t=GetSecs;end
function v=csv4(v),v=['"' strrep(char(v),'"','""') '"'];end
function cleanupQueue4(),try,KbQueueStop;catch,end,try,KbQueueRelease;catch,end,end
function cleanupFiles4(a,b),if a>=0,fclose(a);end,if b>=0,fclose(b);end,end
function cleanupScreen4(o),ShowCursor;Priority(0);Screen('CloseAll');Screen('Preference','SkipSyncTests',o);end
