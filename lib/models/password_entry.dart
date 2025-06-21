import 'package:uuid/uuid.dart';

class PasswordEntry {
  final String id;
  final String entryName; // само имя пароля
  final String password;
  final String? url;
  final String? notes;
  final String? folderPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  PasswordEntry({
    String? id,
    required this.entryName,
    required this.password,
    this.url,
    this.notes,
    this.folderPath = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': entryName,
      'password': password,
      'url': url,
      'notes': notes,
      'folderPath': folderPath,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory PasswordEntry.fromJson(Map<String, dynamic> json) {
    return PasswordEntry(
      id: json['id'] as String,
      entryName: json['name'] as String,
      password: json['password'] as String,
      url: json['url'] as String?,
      notes: json['notes'] as String?,
      folderPath: json['folderPath'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  PasswordEntry copyWith({
    String? id,
    String? name,
    String? password,
    String? url,
    String? notes,
    String? folderPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PasswordEntry(
      id: id ?? this.id,
      entryName: name ?? entryName,
      password: password ?? this.password,
      url: url ?? this.url,
      notes: notes ?? this.notes,
      folderPath: folderPath ?? this.folderPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
