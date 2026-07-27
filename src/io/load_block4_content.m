function survey = load_block4_content(contentPath)
%LOAD_BLOCK4_CONTENT Load and validate the data-driven VVIQ survey.

if ~isfile(contentPath)
    error('ImaginedSpeech:MissingBlock4Content', 'Block 4 survey not found: %s', contentPath);
end
survey = jsondecode(fileread(contentPath));
required = {'schema_version','survey_id','title','instructions','begin_prompt','navigation_prompt', ...
    'submit_prompt','scoring','choices','sections'};
for index=1:numel(required)
    if ~isfield(survey,required{index}), error('ImaginedSpeech:InvalidBlock4Content','Missing field: %s',required{index}); end
end
if survey.schema_version~=1 || numel(survey.choices)~=5
    error('ImaginedSpeech:InvalidBlock4Content','VVIQ requires schema version 1 and five choices.');
end
choiceIds=string({survey.choices.id}); values=[survey.choices.value];
if numel(unique(choiceIds))~=5 || ~isequal(values,1:5)
    error('ImaginedSpeech:InvalidBlock4Content','Choice IDs must be unique with values 1 through 5.');
end
itemIds=strings(0); itemCount=0;
for sectionIndex=1:numel(survey.sections)
    section=survey.sections(sectionIndex);
    if ~isfield(section,'id') || ~isfield(section,'prompt') || ~isfield(section,'items')
        error('ImaginedSpeech:InvalidBlock4Content','Invalid section %d.',sectionIndex);
    end
    for itemIndex=1:numel(section.items)
        item=section.items(itemIndex);
        if ~isfield(item,'id') || ~isfield(item,'text') || strlength(string(item.text))==0
            error('ImaginedSpeech:InvalidBlock4Content','Invalid item in section %s.',section.id);
        end
        itemCount=itemCount+1; itemIds(itemCount)=string(item.id); %#ok<AGROW>
    end
end
if itemCount~=16 || numel(unique(itemIds))~=16
    error('ImaginedSpeech:InvalidBlock4Content','VVIQ requires 16 uniquely identified items.');
end
if survey.scoring.minimum~=16 || survey.scoring.maximum~=80
    error('ImaginedSpeech:InvalidBlock4Content','Scoring bounds do not match 16 items rated 1-5.');
end
end
