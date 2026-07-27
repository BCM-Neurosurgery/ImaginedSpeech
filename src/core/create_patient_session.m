function session = create_patient_session(saveRoot, patientId)
%CREATE_PATIENT_SESSION Create a unique time-indexed patient output folder.

patientId = char(strtrim(string(patientId)));
if isempty(regexp(patientId, '^[A-Za-z0-9_-]+$', 'once'))
    error('ImaginedSpeech:InvalidPatientId', ...
        'Patient ID may contain only letters, numbers, underscores, and hyphens.');
end
if ~isfolder(saveRoot)
    [ok, message] = mkdir(saveRoot);
    if ~ok, error('ImaginedSpeech:CreateSaveRootFailed', '%s', message); end
end
patientDir = fullfile(saveRoot, patientId);
if ~isfolder(patientDir)
    [ok, message] = mkdir(patientDir);
    if ~ok, error('ImaginedSpeech:CreatePatientDirFailed', '%s', message); end
end

timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
sessionDir = fullfile(patientDir, timestamp);
suffix = 0;
while isfolder(sessionDir)
    suffix = suffix + 1;
    sessionDir = fullfile(patientDir, sprintf('%s_%02d', timestamp, suffix));
end
[ok, message] = mkdir(sessionDir);
if ~ok, error('ImaginedSpeech:CreateSessionDirFailed', '%s', message); end

session = struct('patient_id', patientId, 'timestamp', timestamp, ...
    'directory', sessionDir);
metadataPath = fullfile(sessionDir, 'session.json');
fileId = fopen(metadataPath, 'w');
if fileId < 0, error('ImaginedSpeech:SessionMetadataFailed', 'Cannot write %s', metadataPath); end
cleanup = onCleanup(@() fclose(fileId)); %#ok<NASGU>
fwrite(fileId, jsonencode(session, PrettyPrint=true), 'char');
end
