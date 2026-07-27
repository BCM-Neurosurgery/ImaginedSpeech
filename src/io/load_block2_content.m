function block = load_block2_content(contentPath)
%LOAD_BLOCK2_CONTENT Validate schedules and preload all unique speech audio.

if ~isfile(contentPath), error('ImaginedSpeech:MissingBlock2Content','Block 2 manifest not found: %s',contentPath); end
block=jsondecode(fileread(contentPath));
required={'schema_version','block_id','schedule_file','audio_manifest_file','ready_title','ready_text','ready_prompt','action_labels'};
for index=1:numel(required), if ~isfield(block,required{index}), error('ImaginedSpeech:InvalidBlock2Content','Missing field: %s',required{index}); end, end
if block.schema_version~=1, error('ImaginedSpeech:InvalidBlock2Content','Unsupported Block 2 schema version.'); end
baseDir=fileparts(contentPath); schedulePath=fullfile(baseDir,block.schedule_file); audioManifestPath=fullfile(baseDir,block.audio_manifest_file);
if ~isfile(schedulePath)||~isfile(audioManifestPath), error('ImaginedSpeech:MissingBlock2Data','Schedule or audio manifest is missing.'); end
schedule=readtable(schedulePath,'TextType','string'); audioManifest=readtable(audioManifestPath,'TextType','string');
scheduleRequired=["trial_number","word","trial_type","silent_period_duration","inter_trial_interval_duration"];
audioRequired=["stimulus_id","stimulus_text","audio_file"];
if ~all(ismember(scheduleRequired,string(schedule.Properties.VariableNames)))||~all(ismember(audioRequired,string(audioManifest.Properties.VariableNames))), error('ImaginedSpeech:InvalidBlock2Data','CSV columns are invalid.'); end
if height(schedule)~=540||numel(unique(schedule.trial_number))~=540||~isequal(schedule.trial_number,(1:540)'), error('ImaginedSpeech:InvalidBlock2Data','Schedule must contain ordered unique trials 1 through 540.'); end
allowed=["speaking","imagine speaking","visually imagine"];
if any(~ismember(schedule.trial_type,allowed))||any(~isfinite(schedule.silent_period_duration))||any(schedule.silent_period_duration<0)||any(~isfinite(schedule.inter_trial_interval_duration))||any(schedule.inter_trial_interval_duration<0), error('ImaginedSpeech:InvalidBlock2Data','Schedule contains invalid trial types or durations.'); end
if numel(unique(audioManifest.stimulus_text))~=height(audioManifest)||numel(unique(audioManifest.stimulus_id))~=height(audioManifest), error('ImaginedSpeech:InvalidBlock2Data','Audio manifest IDs and texts must be unique.'); end

textMap=containers.Map(cellstr(audioManifest.stimulus_text),num2cell(1:height(audioManifest)));
audio=repmat(struct('stimulus_id','','text','','path','','samples',[],'sample_rate',NaN),height(audioManifest),1);
audioDir=fileparts(audioManifestPath);
for index=1:height(audioManifest)
    audioPath=fullfile(audioDir,audioManifest.audio_file(index));
    if ~isfile(audioPath), error('ImaginedSpeech:MissingSpeechAudio','Missing audio: %s',audioPath); end
    [samples,rate]=audioread(audioPath); if isempty(samples)||any(~isfinite(samples),'all'), error('ImaginedSpeech:InvalidSpeechAudio','Invalid audio: %s',audioPath); end
    if size(samples,2)==1,samples=repmat(samples,1,2);elseif size(samples,2)~=2,error('ImaginedSpeech:InvalidSpeechAudio','Audio must be mono or stereo: %s',audioPath);end
    audio(index)=struct('stimulus_id',char(audioManifest.stimulus_id(index)),'text',char(audioManifest.stimulus_text(index)),'path',char(audioPath),'samples',samples','sample_rate',rate);
end
if numel(unique([audio.sample_rate]))~=1,error('ImaginedSpeech:InvalidSpeechAudio','All clips must share one sample rate.');end
schedule.audio_index=zeros(height(schedule),1); schedule.stimulus_id=strings(height(schedule),1); schedule.is_phrase=false(height(schedule),1);
for trial=1:height(schedule)
    text=char(schedule.word(trial)); if ~isKey(textMap,text),error('ImaginedSpeech:MissingAudioMapping','No audio mapping for: %s',text);end
    index=textMap(text); schedule.audio_index(trial)=index; schedule.stimulus_id(trial)=string(audio(index).stimulus_id); schedule.is_phrase(trial)=contains(strtrim(schedule.word(trial))," ");
end
block.schedule=schedule; block.audio=audio; block.schedule_path=schedulePath; block.audio_manifest_path=audioManifestPath;
end
