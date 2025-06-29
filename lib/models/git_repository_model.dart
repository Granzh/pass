import '../services/appauth.dart';

class GitRepository {
  final String id;
  final String name; // full_name для GitHub, name_with_namespace или path_with_namespace для GitLab
  final String description;
  final String htmlUrl; // Ссылка на репозиторий в вебе
  final bool isPrivate;
  final String defaultBranch; // Важно для клонирования/загрузки

  GitRepository({
    required this.id,
    required this.name,
    required this.description,
    required this.htmlUrl,
    required this.isPrivate,
    required this.defaultBranch,
  });

  factory GitRepository.fromJson(Map<String, dynamic> json, String provider) {
    if (provider == GitProvider.github.name) {
      return GitRepository(
        id: json['id'].toString(),
        name: json['full_name'] ?? 'Без имени',
        description: json['description'] ?? '',
        htmlUrl: json['html_url'] ?? '',
        isPrivate: json['private'] ?? true,
        defaultBranch: json['default_branch'] ?? 'main',
      );
    } else if (provider == GitProvider.gitlab.name) {
      return GitRepository(
        id: json['id'].toString(),
        name: json['path_with_namespace'] ?? 'Без имени',
        description: json['description'] ?? '',
        htmlUrl: json['web_url'] ?? '',
        isPrivate: json['visibility'] == 'private', // "public", "internal", "private"
        defaultBranch: json['default_branch'] ?? 'main',
      );
    }
    throw ArgumentError('Неизвестный провайдер в GitRepository.fromJson');
  }

  @override
  String toString() {
    return 'GitRepository{id: $id, name: $name, isPrivate: $isPrivate, defaultBranch: $defaultBranch}';
  }
}