import 'package:uuid/uuid.dart';

// lib/models/password_entry.dart

class PasswordEntry {
  final String id; // Может быть равен entryName + folderPath
  final String entryName; // Имя файла (без .gpg и пути)
  final String folderPath; // Относительный путь к папке, пустой для корня
  String password; // Сам пароль (первая строка в файле)
  Map<String, String> metadata; // Остальные данные как ключ-значение
  // Общие поля, которые можно извлечь из metadata или установить по умолчанию
  String? get url => metadata['url'] ?? metadata['URL'];
  String? get username => metadata['username'] ?? metadata['user'] ?? metadata['login'];
  String? get notes => metadata['notes'] ?? metadata['comment'];
  // Даты можно хранить в metadata или генерировать при чтении/записи файла
  // Для простоты пока не будем их строго парсить из метаданных, а использовать время файла.
  // Если они важны, можно добавить ключи типа 'createdAt', 'updatedAt' в metadata.
  DateTime lastModified; // Время последней модификации файла, используется вместо createdAt/updatedAt

  PasswordEntry({
    String? id,
    required this.entryName,
    this.folderPath = '',
    required this.password,
    Map<String, String>? metadata,
    required this.lastModified,
  })  : id = id ?? const Uuid().v4(), // Или лучше использовать fullPath как ID
        metadata = metadata ?? {};

  String get fullPath => folderPath.isEmpty ? entryName : '$folderPath/$entryName';

  /// Конвертирует PasswordEntry в строку для сохранения в .gpg файл (перед шифрованием)
  String toPassFileContent() {
    final buffer = StringBuffer();
    buffer.writeln(password); // Пароль на первой строке

    // Добавляем остальные метаданные, если они есть
    metadata.forEach((key, value) {
      // Пропускаем "стандартные" поля, если они уже были извлечены,
      // или убедимся, что они не дублируются, если это нежелательно.
      // Здесь для простоты просто записываем все из metadata.
      if (value.isNotEmpty) { // Не записываем пустые значения
        buffer.writeln('$key: $value');
      }
    });
    return buffer.toString().trim(); // trim, чтобы убрать лишнюю последнюю пустую строку
  }

  /// Создает PasswordEntry из расшифрованного содержимого .gpg файла
  factory PasswordEntry.fromPassFileContent(
      String decryptedContent,
      String entryNameFromFile,
      String folderPathFromFile,
      DateTime fileLastModified,
      ) {
    final lines = decryptedContent.split('\n');
    if (lines.isEmpty) {
      throw const FormatException("Decrypted GPG content is empty.");
    }

    final String pass = lines.first;
    final Map<String, String> meta = {};

    if (lines.length > 1) {
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue; // Пропускаем пустые строки

        final parts = line.split(':');
        if (parts.length >= 2) {
          final key = parts.first.trim();
          final value = parts.sublist(1).join(':').trim(); // Все после первого ':'
          meta[key] = value;
        } else {
          // Строка не в формате ключ:значение, можно ее добавить в "notes" или специальное поле
          meta['line_$i'] = line; // или проигнорировать
        }
      }
    }

    return PasswordEntry(
      // id: '$folderPathFromFile/$entryNameFromFile'.replaceAll(RegExp(r'[/\\]+'), '/'), // Нормализуем ID
      id: const Uuid().v4(), // Или используйте более детерминированный ID, если нужно
      entryName: entryNameFromFile,
      folderPath: folderPathFromFile,
      password: pass,
      metadata: meta,
      lastModified: fileLastModified,
    );
  }

  // Обновление специфичных полей (пример)
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

  // Для создания копии с изменениями (если нужно)
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
      metadata: metadata ?? Map.from(this.metadata), // Глубокое копирование карты
      lastModified: lastModified ?? this.lastModified,
    );
  }
}