function block = load_block3_content(contentPath)
%LOAD_BLOCK3_CONTENT Validate and preload all Block 3 content and audio.

if ~isfile(contentPath)
    error('ImaginedSpeech:MissingBlock3Content', 'Block 3 content not found: %s', contentPath);
end
block = jsondecode(fileread(contentPath));
required = {'schema_version', 'block_id', 'ready_prompt', 'listening_text', ...
    'question_navigation_prompt', 'question_submit_prompt', 'stories'};
for index = 1:numel(required)
    if ~isfield(block, required{index})
        error('ImaginedSpeech:InvalidBlock3Content', 'Missing field: %s', required{index});
    end
end
if block.schema_version ~= 1 || numel(block.stories) ~= 2
    error('ImaginedSpeech:InvalidBlock3Content', ...
        'Block 3 requires schema version 1 and exactly two stories.');
end

baseDir = fileparts(contentPath);
questionIds = strings(0);
for storyIndex = 1:numel(block.stories)
    story = block.stories(storyIndex);
    audioPath = fullfile(baseDir, story.audio_file);
    if ~isfile(audioPath)
        error('ImaginedSpeech:MissingStoryAudio', 'Story audio not found: %s', audioPath);
    end
    [samples, sampleRate] = audioread(audioPath);
    if isempty(samples) || any(~isfinite(samples), 'all')
        error('ImaginedSpeech:InvalidStoryAudio', 'Invalid samples in: %s', audioPath);
    end
    if size(samples, 2) == 1
        samples = repmat(samples, 1, 2);
    elseif size(samples, 2) ~= 2
        error('ImaginedSpeech:InvalidStoryAudio', 'Audio must be mono or stereo: %s', audioPath);
    end
    block.stories(storyIndex).audio_samples = samples';
    block.stories(storyIndex).sample_rate = sampleRate;
    block.stories(storyIndex).audio_path = audioPath;

    for questionIndex = 1:numel(story.questions)
        question = story.questions(questionIndex);
        if numel(question.choices) < 2
            error('ImaginedSpeech:InvalidBlock3Content', ...
                'Question %s must have at least two choices.', question.id);
        end
        choiceIds = string({question.choices.id});
        if numel(unique(choiceIds)) ~= numel(choiceIds) || ...
                ~ismember(string(question.correct_choice_id), choiceIds)
            error('ImaginedSpeech:InvalidBlock3Content', ...
                'Question %s has invalid choice IDs or answer key.', question.id);
        end
        questionIds(end + 1) = string(question.id); %#ok<AGROW>
    end
end
if numel(unique(questionIds)) ~= numel(questionIds)
    error('ImaginedSpeech:InvalidBlock3Content', 'Question IDs must be unique.');
end
if numel(unique([block.stories.sample_rate])) ~= 1
    error('ImaginedSpeech:InvalidStoryAudio', 'All stories must use one sample rate.');
end
end
