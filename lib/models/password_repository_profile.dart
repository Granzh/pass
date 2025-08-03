import '../core/utils/enums.dart';


class PasswordRepositoryProfile {
  final String id;
  String profileName;
  final PasswordSourceType type;
  final String? gitProviderName; // e.g., "github", "gitlab"

  // Git repository specific details
  final String? repositoryId; // ID from the provider (e.g., GitHub repo ID)
  final String repositoryFullName; // e.g., "username/repositoryName"
  final String? repositoryShortName; // e.g., "repositoryName" - for folder name
  final String? repositoryCloneUrl;  // e.g., "https://github.com/username/reponame.git"
  final String? repositoryDescription;
  final bool? isPrivateRepository;
  final String? defaultBranch;

  final String? gpgUserName;

  final DateTime createdAt;
  String? accessTokenKey;
  String? refreshTokenKey;
  String? localPath;

  PasswordRepositoryProfile({
    required this.id,
    required this.profileName,
    required this.type,
    this.gitProviderName,
    this.repositoryId,
    required this.repositoryFullName,
    this.repositoryShortName,
    this.repositoryCloneUrl,
    this.repositoryDescription,
    this.isPrivateRepository,
    this.defaultBranch,
    this.gpgUserName,
    DateTime? createdAt,
    this.accessTokenKey,
    this.refreshTokenKey,
    this.localPath,
  }) : createdAt = createdAt ?? DateTime.now();

  static PasswordRepositoryProfile empty() {
    return PasswordRepositoryProfile(
      id: '',
      profileName: 'Unknown Profile',
      repositoryFullName: 'Unknown Repository',
      type: PasswordSourceType.unknown,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profileName': profileName,
      'type': PasswordSourceType.passwordSourceTypeToString(type),
      'gitProviderName': gitProviderName,
      'repositoryId': repositoryId,
      'repositoryFullName': repositoryFullName,
      'repositoryShortName': repositoryShortName,
      'repositoryCloneUrl': repositoryCloneUrl,
      'repositoryDescription': repositoryDescription,
      'isPrivateRepository': isPrivateRepository,
      'defaultBranch': defaultBranch,
      'gpgUserName': gpgUserName,
      'createdAt': createdAt.toIso8601String(),
      'accessTokenKey': accessTokenKey,
      'refreshTokenKey': refreshTokenKey,
      'localPath': localPath,
    };
  }

  factory PasswordRepositoryProfile.fromJson(Map<String, dynamic> json) {
    return PasswordRepositoryProfile(
      id: json['id'] as String,
      profileName: json['profileName'] as String,
      type: PasswordSourceType.passwordSourceTypeFromString(json['type'] as String),
      gitProviderName: json['gitProviderName'] as String?,
      repositoryId: json['repositoryId'] as String?,
      repositoryFullName: json['repositoryFullName'] as String,
      repositoryShortName: json['repositoryShortName'] as String?,
      repositoryCloneUrl: json['repositoryCloneUrl'] as String?,
      repositoryDescription: json['repositoryDescription'] as String?,
      isPrivateRepository: json['isPrivateRepository'] as bool?,
      defaultBranch: json['defaultBranch'] as String?,
      gpgUserName: json['gpgUserName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      accessTokenKey: json['accessTokenKey'] as String?,
      refreshTokenKey: json['refreshTokenKey'] as String?,
      localPath: json['localPath'] as String?,
    );
  }

  static String generateAccessTokenKey(String profileId) => 'profile_${profileId}_access_token';
  static String generateRefreshTokenKey(String profileId) => 'profile_${profileId}_refresh_token';

  PasswordRepositoryProfile copyWith({
    String? id,
    String? profileName,
    PasswordSourceType? type,
    String? gitProviderName,
    String? repositoryId,
    String? repositoryFullName,
    String? repositoryShortName,
    String? repositoryCloneUrl,
    String? repositoryDescription,
    bool? isPrivateRepository,
    String? defaultBranch,
    String? gpgUserName,
    DateTime? createdAt,
    String? accessTokenKey,
    String? refreshTokenKey,
    String? localPath,
  }) {
    return PasswordRepositoryProfile(
      id: id ?? this.id,
      profileName: profileName ?? this.profileName,
      type: type ?? this.type,
      gitProviderName: gitProviderName ?? this.gitProviderName,
      repositoryId: repositoryId ?? this.repositoryId,
      repositoryFullName: repositoryFullName ?? this.repositoryFullName,
      repositoryShortName: repositoryShortName ?? this.repositoryShortName,
      repositoryCloneUrl: repositoryCloneUrl ?? this.repositoryCloneUrl,
      repositoryDescription: repositoryDescription ?? this.repositoryDescription,
      isPrivateRepository: isPrivateRepository ?? this.isPrivateRepository,
      defaultBranch: defaultBranch ?? this.defaultBranch,
      gpgUserName: gpgUserName ?? this.gpgUserName,
      createdAt: createdAt ?? this.createdAt,
      accessTokenKey: accessTokenKey ?? this.accessTokenKey,
      refreshTokenKey: refreshTokenKey ?? this.refreshTokenKey,
      localPath: localPath ?? this.localPath,
    );
  }

  bool isGitType() => type != PasswordSourceType.localFolder;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PasswordRepositoryProfile &&
        other.id == id &&
        other.profileName == profileName &&
        other.type == type &&
        other.gitProviderName == gitProviderName &&
        other.repositoryId == repositoryId &&
        other.repositoryFullName == repositoryFullName &&
        other.repositoryShortName == repositoryShortName &&
        other.repositoryCloneUrl == repositoryCloneUrl &&
        other.repositoryDescription == repositoryDescription &&
        other.isPrivateRepository == isPrivateRepository &&
        other.defaultBranch == defaultBranch &&
        other.gpgUserName == gpgUserName &&
        other.createdAt == createdAt &&
        other.accessTokenKey == accessTokenKey &&
        other.refreshTokenKey == refreshTokenKey &&
        other.localPath == localPath;
  }

  @override
  int get hashCode {
    return id.hashCode ^
    profileName.hashCode ^
    type.hashCode ^
    gitProviderName.hashCode ^
    repositoryId.hashCode ^
    repositoryFullName.hashCode ^
    repositoryShortName.hashCode ^
    repositoryCloneUrl.hashCode ^
    repositoryDescription.hashCode ^
    isPrivateRepository.hashCode ^
    defaultBranch.hashCode ^
    gpgUserName.hashCode ^
    createdAt.hashCode ^
    accessTokenKey.hashCode ^
    refreshTokenKey.hashCode ^
    localPath.hashCode;
  }
}
