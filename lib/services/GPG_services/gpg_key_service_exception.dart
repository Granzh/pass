abstract class GPGServiceException implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  GPGServiceException(this.message, {this.cause, this.stackTrace});

  @override
  String toString() {
    String result = 'GPGServiceException: $message';
    if (cause != null) {
      result += '\nCause: $cause';
    }
    return result;
  }
}

class GPGKeyNotFoundException extends GPGServiceException {
  final String profileId;
  GPGKeyNotFoundException(this.profileId, {Object? cause, StackTrace? stackTrace})
      : super('GPG key not found for profile: $profileId.', cause: cause, stackTrace: stackTrace);
}

/// Exception thrown when GPG key generation fails.
class GPGKeyGenerationException extends GPGServiceException {
  GPGKeyGenerationException(String message, {Object? cause, StackTrace? stackTrace})
      : super('Failed to generate GPG key: $message', cause: cause, stackTrace: stackTrace);
}

/// Exception thrown when a GPG encryption operation fails.
class GPGEncryptionException extends GPGServiceException {
  GPGEncryptionException(String message, {Object? cause, StackTrace? stackTrace})
      : super('GPG encryption failed: $message', cause: cause, stackTrace: stackTrace);
}

/// Exception thrown when a GPG decryption operation fails.
class GPGDecryptionException extends GPGServiceException {
  final bool isPassphraseError;

  GPGDecryptionException(String message, {this.isPassphraseError = false, Object? cause, StackTrace? stackTrace})
      : super('GPG decryption failed: $message', cause: cause, stackTrace: stackTrace);
}

/// Exception thrown when a GPG signing operation fails.
class GPGSigningException extends GPGServiceException {
  GPGSigningException(String message, {Object? cause, StackTrace? stackTrace})
      : super('GPG signing failed: $message', cause: cause, stackTrace: stackTrace);
}

/// Exception thrown when GPG signature verification fails.
class GPGVerificationException extends GPGServiceException {
  GPGVerificationException(String message, {Object? cause, StackTrace? stackTrace})
      : super('GPG signature verification failed: $message', cause: cause, stackTrace: stackTrace);
}

/// Exception thrown for general file operation errors within GPGService.
class GPGFileOperationException extends GPGServiceException {
  final String filePath;
  GPGFileOperationException(String message, this.filePath, {Object? cause, StackTrace? stackTrace})
      : super('GPG file operation error for "$filePath": $message', cause: cause, stackTrace: stackTrace);
}

/// Exception thrown when attempting to import a GPG key fails.
class GPGImportException extends GPGServiceException {
  GPGImportException(String message, {Object? cause, StackTrace? stackTrace})
      : super('Failed to import GPG key: $message', cause: cause, stackTrace: stackTrace);
}