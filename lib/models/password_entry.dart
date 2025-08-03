import 'package:uuid/uuid.dart';

// lib/models/password_entry.dart

class PasswordEntry {
  final String id; // uuid
  final String entryName; // file name
  final String folderPath; // folder path, empty for root
  String password; // password (first line in file)
  Map<String, String> metadata;
  String get name => entryName;
  String get path => fullPath;
  String? get url => metadata['url'] ?? metadata['URL'];
  String? get username => metadata['username'] ?? metadata['user'] ?? metadata['login'];
  String? get notes => metadata['notes'] ?? metadata['comment'];
  DateTime lastModified;

  PasswordEntry({
    String? id,
    required this.entryName,
    this.folderPath = '',
    required this.password,
    Map<String, String>? metadata,
    required this.lastModified,
  })  : id = id ?? const Uuid().v4(),
        metadata = metadata ?? {};

  String get fullPath => folderPath.isEmpty ? entryName : '$folderPath/$entryName';

  String toPassFileContent() {
    final buffer = StringBuffer();
    buffer.writeln(password);

    metadata.forEach((key, value) {
      if (value.isNotEmpty) {
        buffer.writeln('$key: $value');
      }
    });
    return buffer.toString().trim();
  }

  factory PasswordEntry.fromPassFileContent(
      String decryptedContent,
      String entryNameFromFile,
      String folderPathFromFile,
      DateTime fileLastModified,
      ) {
    if (decryptedContent.isEmpty) {
      throw const FormatException("Decrypted GPG content is empty.");
    }
    final lines = decryptedContent.split('\n');


    final String pass = lines.first.trim();
    final Map<String, String> meta = {};

    if (lines.length > 1) {
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final parts = line.split(':');
        if (parts.length >= 2) {
          final key = parts.first.trim();
          final value = parts.sublist(1).join(':').trim();
          meta[key] = value;
        } else {
          meta['line_$i'] = line;
        }
      }
    }

    return PasswordEntry(
      id: const Uuid().v4(),
      entryName: entryNameFromFile,
      folderPath: folderPathFromFile,
      password: pass,
      metadata: meta,
      lastModified: fileLastModified,
    );
  }

  void updateUrl(String? newUrl) {
    if (newUrl == null || newUrl.isEmpty) {
      metadata.remove('url');
      metadata.remove('URL');
    } else {
      metadata['url'] = newUrl;
    }
  }

  void updateUsername(String? newUsername) {
    if (newUsername == null || newUsername.isEmpty) {
      metadata.remove('username');
      metadata.remove('user');
      metadata.remove('login');
    } else {
      metadata['username'] = newUsername;
    }
  }

  void updateNotes(String? newNotes) {
    if (newNotes == null || newNotes.isEmpty) {
      metadata.remove('notes');
    } else {
      metadata['notes'] = newNotes;
    }
  }

  PasswordEntry copyWith({
    String? id,
    String? entryName,
    String? folderPath,
    String? password,
    Map<String, String>? metadata,
    DateTime? lastModified,
  }) {
    return PasswordEntry(
      id: id ?? this.id,
      entryName: entryName ?? this.entryName,
      folderPath: folderPath ?? this.folderPath,
      password: password ?? this.password,
      metadata: metadata ?? Map.from(this.metadata),
      lastModified: lastModified ?? this.lastModified,
    );
  }
}