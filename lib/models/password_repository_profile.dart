
enum PasswordSourceType {
  github,
  gitlab,
  localFolder
}


String passwordSourceTypeToString(PasswordSourceType type) {
  return type.toString().split('.').last;
}

PasswordSourceType passwordSourceTypeFromString(String type) {
  return PasswordSourceType.values.firstWhere(
      (e) => type == e.toString().split('.').last,
      orElse: () => throw ArgumentError('Unknown PasswordSourceType: $type')
  );
}

class PasswordRepositoryProfile {
  final String id;
  String profileName;
  final PasswordSourceType type;
  final String? gitProviderName;
  final String? repositoryId;
  final String repositoryFullName;
  final String? defaultBranch;
  final DateTime createdAt;
  final String? accessTokenKey;
  final String? refreshTokenKey;
  final String? localPath;

  PasswordRepositoryProfile({
    required this.id,
    required this.profileName,
    required this.type,
    this.gitProviderName,
    this.repositoryId,
    required this.repositoryFullName,
    this.defaultBranch,
    DateTime? createdAt,
    this.accessTokenKey,
    this.refreshTokenKey,
    this.localPath
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profileName': profileName,
      'type': passwordSourceTypeToString(type),
      'gitProviderName': gitProviderName,
      'repositoryId': repositoryId,
      'repositoryFullName': repositoryFullName,
      'defaultBranch': defaultBranch,
      'createdAt': createdAt.toIso8601String(),
      'accessTokenKey': accessTokenKey,
      'refreshTokenKey': refreshTokenKey,
      'localPath': localPath
    };
  }

  factory PasswordRepositoryProfile.fromJson(Map<String, dynamic> json) {
    return PasswordRepositoryProfile(
      id: json['id'] as String,
      profileName: json['profileName'] as String,
      type: passwordSourceTypeFromString(json['type'] as String),
      gitProviderName: json['gitProviderName'] as String?,
      repositoryId: json['repositoryId'] as String?,
      repositoryFullName: json['repositoryFullName'] as String,
      defaultBranch: json['defaultBranch'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      accessTokenKey: json['accessTokenKey'] as String?,
      refreshTokenKey: json['refreshTokenKey'] as String?,
      localPath: json['localPath'] as String?
    );
  }

  static String generateAccessTokenKey(String profileId) => 'profile_${profileId}_access_token';
  static String generateRefreshTokenKey(String profileId) => 'profile_${profileId}_refresh_token';
}
