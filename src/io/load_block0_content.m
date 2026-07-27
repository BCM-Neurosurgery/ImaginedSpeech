function content = load_block0_content(contentPath)
%LOAD_BLOCK0_CONTENT Load and validate the Block 0 instruction deck.

if ~isfile(contentPath)
    error('ImaginedSpeech:MissingBlock0Content', ...
        'Block 0 content not found: %s', contentPath);
end

content = jsondecode(fileread(contentPath));
requiredFields = {'schema_version', 'deck_id', 'navigation_prompt', ...
    'final_navigation_prompt', 'slides'};
for index = 1:numel(requiredFields)
    field = requiredFields{index};
    if ~isfield(content, field)
        error('ImaginedSpeech:InvalidBlock0Content', ...
            'Block 0 content is missing field: %s', field);
    end
end
if content.schema_version ~= 1
    error('ImaginedSpeech:InvalidBlock0Content', ...
        'Unsupported Block 0 schema_version: %g', content.schema_version);
end
if isempty(content.slides) || ~isstruct(content.slides)
    error('ImaginedSpeech:InvalidBlock0Content', ...
        'Block 0 must contain at least one slide.');
end

slideIds = strings(numel(content.slides), 1);
for index = 1:numel(content.slides)
    slide = content.slides(index);
    for field = {'id', 'title', 'body'}
        if ~isfield(slide, field{1}) || strlength(string(slide.(field{1}))) == 0
            error('ImaginedSpeech:InvalidBlock0Content', ...
                'Slide %d has a missing or empty %s.', index, field{1});
        end
    end
    slideIds(index) = string(slide.id);
end
if numel(unique(slideIds)) ~= numel(slideIds)
    error('ImaginedSpeech:InvalidBlock0Content', 'Block 0 slide IDs must be unique.');
end
end
