// lib/ui/screens/add_edit_password_entry_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/password_entry.dart';
import '../../services/password_repository_service.dart';

class AddEditPasswordEntryScreen extends StatefulWidget {
  final String profileId;
  final String gpgPassphrase; // Необходима для шифрования при сохранении
  final PasswordEntry? existingEntry; // Если null, то это добавление новой записи

  const AddEditPasswordEntryScreen({
    super.key,
    required this.profileId,
    required this.gpgPassphrase,
    this.existingEntry,
  });

  bool get isEditing => existingEntry != null;

  @override
  State<AddEditPasswordEntryScreen> createState() => _AddEditPasswordEntryScreenState();
}

class _AddEditPasswordEntryScreenState extends State<AddEditPasswordEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late PasswordRepositoryService _passwordRepoService;

  // Контроллеры для текстовых полей
  late TextEditingController _entryNameController;
  late TextEditingController _passwordController;
  late TextEditingController _usernameController;
  late TextEditingController _urlController;
  late TextEditingController _notesController;
  late TextEditingController _customFieldsController; // Для дополнительных полей

  bool _isLoading = false;
  bool _generatePassword = true; // Флаг для автогенерации пароля при добавлении
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _passwordRepoService = Provider.of<PasswordRepositoryService>(context, listen: false);

    String initialEntryNameOrFullPath = widget.existingEntry?.fullPath ?? '';

    _entryNameController = TextEditingController(text: initialEntryNameOrFullPath);
    _passwordController = TextEditingController(text: widget.existingEntry?.password ?? '');
    _usernameController = TextEditingController(text: widget.existingEntry?.username ?? '');
    _urlController = TextEditingController(text: widget.existingEntry?.url ?? '');
    _notesController = TextEditingController(text: widget.existingEntry?.notes ?? '');

    // Собираем кастомные поля в одну строку для простоты редактирования
    // При сохранении нужно будет их распарсить обратно в Map
    final customMeta = Map<String, String>.from(widget.existingEntry?.metadata ?? {});
    customMeta.removeWhere((key, value) => ['username', 'user', 'login', 'url', 'URL', 'notes', 'comment'].contains(key));

    final customFieldsText = customMeta.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
    _customFieldsController = TextEditingController(text: customFieldsText);



    if (widget.isEditing && _passwordController.text.isNotEmpty) {
      _generatePassword = false; // Не генерируем пароль, если он уже есть при редактировании
    } else if (!widget.isEditing) {
      // Если это новая запись и мы хотим автогенерацию
      _generateAndSetPassword();
    }
  }

  void _generateAndSetPassword() {
    if (_generatePassword) {
      // Простая генерация пароля (можно заменить на более сложный генератор)
      final newPassword = _passwordRepoService.generateRandomPassword(); // Предполагаем, что такой метод есть в сервисе
      _passwordController.text = newPassword;
    }
  }

  Map<String, String> _parseCustomFields() {
    final Map<String, String> fields = {};
    final lines = _customFieldsController.text.split('\n');
    for (final line in lines) {
      final parts = line.split(':');
      if (parts.length >= 2) {
        final key = parts[0].trim();
        final value = parts.sublist(1).join(':').trim(); // На случай если в значении есть ':'
        if (key.isNotEmpty) {
          fields[key] = value;
        }
      }
    }
    return fields;
  }

  Future<void> _saveEntry() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    _formKey.currentState!.save();

    setState(() {
      _isLoading = true;
    });

    // Извлечение имени файла и пути из контроллера _entryNameController
    final String fullPathInput = _entryNameController.text.trim();
    String entryNameFinal;
    String folderPathFinal;

    if (fullPathInput.contains('/')) {
      entryNameFinal = fullPathInput.substring(fullPathInput.lastIndexOf('/') + 1);
      folderPathFinal = fullPathInput.substring(0, fullPathInput.lastIndexOf('/'));
    } else {
      entryNameFinal = fullPathInput;
      folderPathFinal = '';
    }

    // Проверка, что entryNameFinal не пустой после извлечения
    if (entryNameFinal.isEmpty) {
      setState(() { _isLoading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry name cannot be empty or end with "/"'), backgroundColor: Colors.red),
      );
      return;
    }


    // Формируем metadata
    final Map<String, String> metadataToSave = {};
    if (_usernameController.text.trim().isNotEmpty) {
      metadataToSave['username'] = _usernameController.text.trim(); // Сохраняем как 'username'
    }
    if (_urlController.text.trim().isNotEmpty) {
      metadataToSave['url'] = _urlController.text.trim();
    }
    if (_notesController.text.trim().isNotEmpty) {
      metadataToSave['notes'] = _notesController.text.trim();
    }

    // Добавляем кастомные поля из _customFieldsController
    final customFieldsLines = _customFieldsController.text.split('\n');
    for (final line in customFieldsLines) {
      final parts = line.split(':');
      if (parts.length >= 2) {
        final key = parts[0].trim();
        final value = parts.sublist(1).join(':').trim();
        if (key.isNotEmpty && !metadataToSave.containsKey(key)) { // Не перезаписываем стандартные ключи, если они уже есть
          metadataToSave[key] = value;
        }
      }
    }

    final PasswordEntry entryToSave = PasswordEntry(
      // id будет сгенерирован в конструкторе PasswordEntry, если не предоставлен
      entryName: entryNameFinal,
      folderPath: folderPathFinal,
      password: _passwordController.text,
      metadata: metadataToSave,
      lastModified: widget.existingEntry?.lastModified ?? DateTime.now(), // Для новой записи ставим DateTime.now()
      // Для существующей можно взять старое значение,
      // или DateTime.now() если хотим обновить время изменения
      // Файловая система сама обновит время файла при записи.
      // Передача DateTime.now() здесь в основном для консистентности объекта,
      // но реальное lastModified файла будет установлено при сохранении.
      // Можно и вовсе не передавать, если сервис сам обработает.
      // Но конструктор требует.
    );


    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await _passwordRepoService.savePasswordEntry(
        profileId: widget.profileId,
        entry: entryToSave,
        userGpgPassphrase: widget.gpgPassphrase,
      );
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Entry "${entryToSave.fullPath}" ${widget.isEditing ? "updated" : "saved"}')),
      );
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error saving entry: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteEntry() async {
    if (!widget.isEditing || widget.existingEntry == null) return;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm deletion'),
        content: Text('Are you sure you want to delete "${widget.existingEntry!.fullPath}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _isLoading = true;
    });

    try {
      await _passwordRepoService.deletePasswordEntry(
        profileId: widget.profileId,
        entryName: widget.existingEntry!.entryName,
        folderPath: widget.existingEntry!.folderPath,
        // userGpgPassphrase для удаления не всегда нужна, но может быть для git commit/push
      );
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Entry "${widget.existingEntry!.fullPath}" deleted')),
      );
      navigator.pop(true); // Возвращаем true, чтобы предыдущий экран обновил список
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error deleting entry: $e'), backgroundColor: Colors.red),
      );
    }
  }


  @override
  void dispose() {
    _entryNameController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    _customFieldsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Редактировать Запись' : 'Добавить Запись'),
        actions: [
          if (widget.isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Удалить запись',
              onPressed: _isLoading ? null : _deleteEntry,
            ),
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Сохранить',
            onPressed: _isLoading ? null : _saveEntry,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                controller: _entryNameController,
                // ВАЖНО: Теперь это поле для ПОЛНОГО ПУТИ к записи
                decoration: const InputDecoration(labelText: 'Путь к записи', hintText: 'например, services/email/gmail или work/project_a/server_key'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Путь к записи не может быть пустым';
                  }
                  if (value.trim().endsWith('/')) {
                    return 'Путь не должен заканчиваться на "/"';
                  }
                  if (value.endsWith('.gpg')) {
                    return 'Не указывайте расширение .gpg';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              if (!widget.isEditing)
                CheckboxListTile(
                  title: const Text('Сгенерировать пароль'),
                  value: _generatePassword,
                  onChanged: (bool? value) {
                    setState(() {
                      _generatePassword = value ?? false;
                      if (_generatePassword) {
                        _generateAndSetPassword();
                      } else if (!widget.isEditing) {
                        _passwordController.clear();
                      }
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Пароль',
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () {
                      setState(() { _obscurePassword = !_obscurePassword; });
                    },
                  ),
                ),
                obscureText: _obscurePassword,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Пароль не может быть пустым';
                  }
                  return null;
                },
                readOnly: _generatePassword && !widget.isEditing,
              ),
              if (_generatePassword && !widget.isEditing)
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Сгенерировать другой'),
                  onPressed: _generateAndSetPassword,
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController, // Изменено с _loginController
                decoration: const InputDecoration(labelText: 'Логин/Имя пользователя'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(labelText: 'URL/Веб-сайт'),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Заметки', alignLabelWithHint: true),
                maxLines: 3,
                keyboardType: TextInputType.multiline,
              ),
              const SizedBox(height: 16),
              const Text('Дополнительные поля (ключ: значение, каждое с новой строки):', style: TextStyle(fontWeight: FontWeight.bold)),
              TextFormField(
                controller: _customFieldsController,
                decoration: const InputDecoration(hintText: 'например, security_question: My first pet\npin_code: 1234', alignLabelWithHint: true),
                maxLines: null,
                keyboardType: TextInputType.multiline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
