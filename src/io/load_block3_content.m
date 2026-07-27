function block = load_block3_content(contentPath)
%LOAD_BLOCK3_CONTENT Validate schedule and preload all unique image pixels.

if ~isfile(contentPath)
    error('ImaginedSpeech:MissingBlock3Content', 'Block 3 manifest not found: %s', contentPath);
end
block = jsondecode(fileread(contentPath));
required = {'schema_version', 'block_id', 'schedule_file', ...
    'ready_title', 'ready_text', 'ready_prompt'};
for index = 1:numel(required)
    if ~isfield(block, required{index})
        error('ImaginedSpeech:InvalidBlock3Content', 'Missing field: %s', required{index});
    end
end
if block.schema_version ~= 1
    error('ImaginedSpeech:InvalidBlock3Content', 'Unsupported Block 3 schema version.');
end

baseDir = fileparts(contentPath);
schedulePath = fullfile(baseDir, block.schedule_file);
if ~isfile(schedulePath)
    error('ImaginedSpeech:MissingImageSchedule', 'Image schedule not found: %s', schedulePath);
end
schedule = readtable(schedulePath, 'TextType', 'string');
requiredColumns = ["image_name", "image_type", "repeated_consecutively"];
if ~all(ismember(requiredColumns, string(schedule.Properties.VariableNames)))
    error('ImaginedSpeech:InvalidImageSchedule', 'Image schedule columns are invalid.');
end
if isempty(schedule) || any(~ismember(schedule.repeated_consecutively, ["Yes", "No"]))
    error('ImaginedSpeech:InvalidImageSchedule', 'Schedule is empty or has invalid repeat flags.');
end

allFiles = dir(fullfile(baseDir, '**', '*'));
allFiles = allFiles(~[allFiles.isdir]);
names = string({allFiles.name});
if numel(unique(names)) ~= numel(names)
    error('ImaginedSpeech:AmbiguousImageNames', 'Image filenames must be unique across subdirectories.');
end

uniqueNames = unique(schedule.image_name, 'stable');
images = repmat(struct('name', '', 'path', '', 'pixels', []), numel(uniqueNames), 1);
nameToIndex = containers.Map('KeyType', 'char', 'ValueType', 'double');
for index = 1:numel(uniqueNames)
    match = find(names == uniqueNames(index));
    if numel(match) ~= 1
        error('ImaginedSpeech:MissingImage', 'Expected one file named %s; found %d.', uniqueNames(index), numel(match));
    end
    imagePath = fullfile(allFiles(match).folder, allFiles(match).name);
    [pixels, map] = imread(imagePath);
    if ~isempty(map), pixels = uint8(ind2rgb(pixels, map) * 255); end
    if ismatrix(pixels), pixels = repmat(pixels, 1, 1, 3); end
    images(index).name = char(uniqueNames(index));
    images(index).path = imagePath;
    images(index).pixels = pixels;
    nameToIndex(char(uniqueNames(index))) = index;
end

schedule.image_index = zeros(height(schedule), 1);
schedule.is_target = false(height(schedule), 1);
for trial = 1:height(schedule)
    schedule.image_index(trial) = nameToIndex(char(schedule.image_name(trial)));
    if trial > 1
        schedule.is_target(trial) = schedule.image_name(trial) == schedule.image_name(trial - 1);
    end
end

% The supplied flag marks both members of a repeated pair. Verify that every
% computed one-back target is marked without misclassifying the pair's first image.
if any(schedule.is_target & schedule.repeated_consecutively ~= "Yes")
    error('ImaginedSpeech:InvalidImageSchedule', ...
        'A computed consecutive repeat is not marked Yes in the supplied schedule.');
end
block.schedule = schedule;
block.images = images;
block.schedule_path = schedulePath;
end
