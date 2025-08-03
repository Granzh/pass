import '../core/utils/enums.dart';

class GitRepository {
  final String id;
  final String name; // full_name для GitHub, name_with_namespace или path_with_namespace для GitLab
  final String description;
  final String htmlUrl;
  final bool isPrivate;
  final String defaultBranch;
  final String providerName;

  GitRepository({
    required this.id,
    required this.name,
    required this.description,
    required this.htmlUrl,
    required this.isPrivate,
    required this.defaultBranch,
    required this.providerName,
  });

  factory GitRepository.fromJson(Map<String, dynamic> json, String provider) {
    if (provider == GitProvider.github.name) {
      return GitRepository(
        id: json['id'].toString(),
        name: json['full_name'] ?? 'Unnamed GitHub Repo',
        description: json['description'] ?? '',
        htmlUrl: json['html_url'] ?? '',
        isPrivate: json['private'] as bool? ?? false,
        defaultBranch: json['default_branch'] ?? 'main',
        providerName: provider,
      );
    } else if (provider == GitProvider.gitlab.name) {
      return GitRepository(
        id: json['id'].toString(),
        name: json['path_with_namespace'] ?? 'Unnamed GitLab Repo',
        description: json['description'] ?? '',
        htmlUrl: json['web_url'] ?? '',
        isPrivate: (json['visibility'] as String? ?? 'public') == 'private', // "public", "internal", "private"
        defaultBranch: json['default_branch'] ?? 'main',
        providerName: provider,
      );
    }
    throw ArgumentError('Unknown provider in GitRepository.fromJson');
  }

  @override
  String toString() {
    return 'GitRepository{id: $id, name: $name, isPrivate: $isPrivate, defaultBranch: $defaultBranch}';
  }

  factory GitRepository.fromStoredJson(Map<String, dynamic> json) {
    return GitRepository(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      htmlUrl: json['htmlUrl'] as String,
      isPrivate: json['isPrivate'] as bool,
      defaultBranch: json['defaultBranch'] as String,
      providerName:json['providerName'] as String,
    );
  }

  GitRepository copyWith({
    String? id,
    String? name,
    String? description,
    String? htmlUrl,
    bool? isPrivate,
    String? defaultBranch,
    String? providerName,
  }) {
    return GitRepository(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      htmlUrl: htmlUrl ?? this.htmlUrl,
      isPrivate: isPrivate ?? this.isPrivate,
      defaultBranch: defaultBranch ?? this.defaultBranch,
      providerName: providerName ?? this.providerName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GitRepository &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          providerName == other.providerName;

  @override
  int get hashCode => id.hashCode ^ providerName.hashCode ^ name.hashCode;
}