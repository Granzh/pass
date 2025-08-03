enum PasswordSourceType {
  github,
  gitlab,
  localFolder,
  gitSsh,
  unknown;

  String get displayName {
    switch (this) {
      case PasswordSourceType.github:
        return 'github';
      case PasswordSourceType.gitlab:
        return 'gitlab';
      case PasswordSourceType.localFolder:
        return 'localFolder';
      case PasswordSourceType.gitSsh:
        return 'gitSsh';
      case PasswordSourceType.unknown:
        return 'unknown';
    }
  }

  bool get isGitType {
    switch (this) {
      case PasswordSourceType.github:
      case PasswordSourceType.gitlab:
      case PasswordSourceType.gitSsh:
        return true;
      case PasswordSourceType.localFolder:
      case PasswordSourceType.unknown:
        return false;
    }
  }

  GitProvider? get toGitProvider {
    switch (this) {
      case PasswordSourceType.github:
        return GitProvider.github;
      case PasswordSourceType.gitlab:
        return GitProvider.gitlab;
      case PasswordSourceType.localFolder:
      case PasswordSourceType.gitSsh:
      case PasswordSourceType.unknown:
        return null;
    }
  }

  static String passwordSourceTypeToString(PasswordSourceType type) {
    return type.toString().split('.').last;
  }

  static PasswordSourceType passwordSourceTypeFromString(String type) {
    return PasswordSourceType.values.firstWhere(
            (e) => type == e.toString().split('.').last,
        orElse: () => PasswordSourceType.unknown,
    );
  }
}



enum GitAuthType { oauth, ssh }

enum GitProvider {
  github,
  gitlab;

  @override
  String toString() => this == GitProvider.github ? 'github' : 'gitlab';

  static GitProvider? fromString(String value) {
    return GitProvider.values.firstWhere(
          (e) => e.toString() == value.toLowerCase(),
      orElse: () => throw ArgumentError('Invalid GitProvider: $value'),
    );
  }

  String get name {
    switch (this) {
      case GitProvider.github:
        return 'github';
      case GitProvider.gitlab:
        return 'gitlab';
    }
  }
}

enum PasswordListNavigation {
  toAddProfile,
  toEditProfile,
}

enum PasswordEntriesNavigation {
  toAddEntry,
  toEditEntry,
}

enum AddEditEntryNavigation {
  backToList,
}