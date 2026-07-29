function name = task_block_name(blockNumber)
%TASK_BLOCK_NAME Compact, comment-safe name for each block, used in task/cbmex naming.

names = {'Instructions', 'SpeechImagery', 'ImageEncoding', 'StoriesComprehension', 'VVIQ'};
if ~isscalar(blockNumber) || blockNumber < 0 || blockNumber > 4 || blockNumber ~= fix(blockNumber)
    error('ImaginedSpeech:InvalidBlockNumber', 'Block number must be an integer from 0 to 4.');
end
name = names{blockNumber + 1};
end
