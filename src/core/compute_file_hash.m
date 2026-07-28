function hashHex = compute_file_hash(filePath)
%COMPUTE_FILE_HASH Return the lowercase hex SHA-256 digest of a file's bytes.

fileId = fopen(filePath, 'rb');
if fileId < 0
    error('ImaginedSpeech:HashFileOpenFailed', 'Cannot open file for hashing: %s', filePath);
end
cleanup = onCleanup(@() fclose(fileId));
bytes = fread(fileId, Inf, '*uint8');

digestAlgorithm = java.security.MessageDigest.getInstance('SHA-256');
digestAlgorithm.update(bytes);
hashBytes = typecast(digestAlgorithm.digest(), 'uint8');
hashHex = lower(reshape(dec2hex(double(hashBytes), 2)', 1, []));
end
