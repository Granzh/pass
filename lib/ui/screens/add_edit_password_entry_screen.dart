import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import '../../core/utils/enums.dart';
import '../../models/password_entry.dart';
import '../view_models/add_edit_password_entry_view_model.dart';

class AddEditPasswordEntryScreen extends StatefulWidget {
  final String profileId;
  final PasswordEntry? entryToEdit; // null для режима добавления

  const AddEditPasswordEntryScreen({
    super.key,
    required this.profileId,
    this.entryToEdit,
  });

  static const String routeName = '/add-edit-password-entry';

  @override
  State<AddEditPasswordEntryScreen> createState() =>
      _AddEditPasswordEntryScreenState();
}

class _AddEditPasswordEntryScreenState
    extends State<AddEditPasswordEntryScreen> {
  static final _log = Logger('AddEditPasswordEntryScreen');
  final _formKey = GlobalKey<FormState>();

  // Контроллеры для текстовых полей
  late TextEditingController _entryNameController;
  late TextEditingController _folderPathController;
  late TextEditingController _passwordController;
  late TextEditingController _urlController;
  late TextEditingController _usernameController;
  late TextEditingController _notesController;

  // Для кастомных метаданных будем управлять списком контроллеров
  final List<TextEditingController> _customMetaKeyControllers = [];
  final List<TextEditingController> _customMetaValueControllers = [];

  late AddEditPasswordEntryViewModel _viewModel;
  bool _isPasswordVisible = false;
  String? _cachedGpgPassphrase; // Для временного хранения парольной фразы

  @override
  void initState() {
    super.initState();

    _viewModel = Provider.of<AddEditPasswordEntryViewModel>(context, listen: false);

    _entryNameController = TextEditingController(text: _viewModel.entryName);
    _folderPathController = TextEditingController(text: _viewModel.folderPath);
    _passwordController = TextEditingController(text: _viewModel.password);
    _urlController = TextEditingController(text: _viewModel.url);
    _usernameController = TextEditingController(text: _viewModel.username);
    _notesController = TextEditingController(text: _viewModel.notes);

    // Инициализация контроллеров для существующих кастомных метаданных
    _viewModel.customMetadata.forEach((key, value) {
      _customMetaKeyControllers.add(TextEditingController(text: key));
      _customMetaValueControllers.add(TextEditingController(text: value));
    });

    // Подписываемся на изменения в ViewModel, чтобы обновлять контроллеры, если нужно
    // (например, после генерации пароля)
    _viewModel.addListener(_onViewModelChanged);

    // Подписываемся на навигационные события
    _viewModel.navigationEvents.listen((event) {
      if (!mounted) return;
      if (event == AddEditEntryNavigation.backToList) {
        Navigator.of(context).pop();
      }
    }).onError((error, stackTrace) {
      _log.warning("Error in navigation stream", error, stackTrace);
    });

    // TODO: Подумать, как получить/запросить _cachedGpgPassphrase, если он нужен для сохранения
    // Например, если он был введен на предыдущем экране и сохранен в каком-то общем сервисе
    // final activeProfileService = Provider.of<ActiveProfileService>(context, listen: false);
    // _cachedGpgPassphrase = activeProfileService.getCachedPassphrase();
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    // Обновляем контроллеры, если ViewModel изменила соответствующие поля
    // Это важно, например, для поля пароля после генерации
    if (_passwordController.text != _viewModel.password) {
      _passwordController.text = _viewModel.password;
    }
    // Можно добавить обновления для других полей, если ViewModel их меняет программно

    // Обновление UI для кастомных метаданных, если они изменились в ViewModel
    // (например, если бы ViewModel могла добавлять/удалять их программно)
    // Этот сценарий более сложен и требует синхронизации списков контроллеров
    // с `_viewModel.customMetadata`. Пока что будем полагаться на `setState` при
    // добавлении/удалении поля в UI.
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _entryNameController.dispose();
    _folderPathController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _notesController.dispose();
    for (var controller in _customMetaKeyControllers) {
      controller.dispose();
    }
    for (var controller in _customMetaValueControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _saveEntry() async {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState?.save(); // Вызовет onSaved у TextFormField

      // Обновляем ViewModel из контроллеров перед сохранением
      _viewModel.updateEntryName(_entryNameController.text);
      _viewModel.updateFolderPath(_folderPathController.text);
      _viewModel.updatePassword(_passwordController.text);
      _viewModel.updateUrl(_urlController.text);
      _viewModel.updateUsername(_usernameController.text);
      _viewModel.updateNotes(_notesController.text);

      // Обновляем кастомные метаданные в ViewModel
      // Сначала очистим старые, потом добавим текущие из контроллеров
      // (Это упрощенный подход; более надежно было бы сравнивать и обновлять)
      _viewModel.customMetadata.keys.toList().forEach(_viewModel.removeCustomMetadataField);
      for (int i = 0; i < _customMetaKeyControllers.length; i++) {
        final key = _customMetaKeyControllers[i].text;
        final value = _customMetaValueControllers[i].text;
        if (key.isNotEmpty) {
          _viewModel.addCustomMetadataField(key, value);
        }
      }

      // --- ОБРАБОТКА GPG PASSPHRASE ---
      String? gpgPassphrase = _cachedGpgPassphrase;
      if (gpgPassphrase == null) {
        // Запросить парольную фразу у пользователя
        gpgPassphrase = await _showGpgPassphraseDialog();
        if (gpgPassphrase == null || gpgPassphrase.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('GPG passphrase is required to save.')),
            );
          }
          return; // Не сохранять без парольной фразы
        }
        // Можно кэшировать для последующих быстрых сохранений на этом экране, если нужно
        // _cachedGpgPassphrase = gpgPassphrase;
      }

      await _viewModel.saveEntry(userGpgPassphrase: gpgPassphrase);

      // Ошибки будут отображены через Consumer<AddEditPasswordEntryViewModel>
      // и навигация произойдет через _viewModel.navigationEvents.listen
    } else {
      _log.info("Form validation failed.");
      // Можно показать SnackBar, что форма невалидна
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please correct the errors in the form.')),
      );
    }
  }

  Future<String?> _showGpgPassphraseDialog() async {
    final passphraseController = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('GPG Passphrase Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please enter the GPG passphrase for the current profile to save the entry.'),
              const SizedBox(height: 16),
              TextField(
                controller: passphraseController,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'GPG Passphrase',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Возвращает null
              },
            ),
            ElevatedButton(
              child: const Text('Confirm'),
              onPressed: () {
                Navigator.of(dialogContext).pop(passphraseController.text);
              },
            ),
          ],
        );
      },
    );
  }

  void _addCustomMetadataField() {
    setState(() {
      _customMetaKeyControllers.add(TextEditingController());
      _customMetaValueControllers.add(TextEditingController());
    });
  }

  void _removeCustomMetadataField(int index) {
    setState(() {
      _customMetaKeyControllers[index].dispose();
      _customMetaValueControllers[index].dispose();
      _customMetaKeyControllers.removeAt(index);
      _customMetaValueControllers.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entryToEdit == null ? 'Add New Entry' : 'Edit Entry'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save Entry',
            onPressed: _viewModel.isLoading ? null : _saveEntry,
          ),
        ],
      ),
      body: Consumer<AddEditPasswordEntryViewModel>(
        builder: (context, viewModel, child) {
          // Если есть глобальная ошибка от ViewModel (например, ошибка сохранения)
          if (viewModel.errorMessage != null && !viewModel.isLoading) {
            // Показываем SnackBar с ошибкой асинхронно, чтобы не вызвать ошибку build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) { // Дополнительная проверка
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(viewModel.errorMessage!),
                    backgroundColor: Colors.red,
                  ),
                );
                // Сбрасываем ошибку в ViewModel после показа, чтобы она не висела
                viewModel.clearErrorMessage(); // Вам нужно будет добавить этот метод в ViewModel
              }
            });
          }

          return Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: ListView( // Используем ListView для прокрутки, если форма длинная
                    children: <Widget>[
                      // --- Entry Name ---
                      TextFormField(
                        controller: _entryNameController,
                        decoration: const InputDecoration(labelText: 'Entry Name (e.g., website/service)'),
                        validator: viewModel.validateEntryName,
                        onChanged: (value) => viewModel.updateEntryName(value), // Для "живой" валидации, если нужно
                      ),
                      const SizedBox(height: 16),

                      // --- Folder Path (Optional) ---
                      TextFormField(
                        controller: _folderPathController,
                        decoration: const InputDecoration(
                          labelText: 'Folder Path (optional, e.g., work/email)',
                          hintText: 'Leave empty for root',
                        ),
                        onChanged: (value) => viewModel.updateFolderPath(value),
                      ),
                      const SizedBox(height: 16),

                      // --- Password ---
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min, // Чтобы Row не занимал всю ширину
                            children: [
                              IconButton(
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.autorenew), // Иконка для генерации
                                tooltip: 'Generate Password',
                                onPressed: () {
                                  // Можно показать диалог для настройки параметров генерации
                                  viewModel.generateNewPassword();
                                  // _passwordController.text = viewModel.password; // Обновится через _onViewModelChanged
                                },
                              ),
                            ],
                          ),
                        ),
                        obscureText: !_isPasswordVisible,
                        validator: viewModel.validatePassword,
                        onChanged: (value) => viewModel.updatePassword(value),
                      ),
                      const SizedBox(height: 16),

                      // --- URL (Optional) ---
                      TextFormField(
                        controller: _urlController,
                        decoration: const InputDecoration(labelText: 'URL (optional)'),
                        keyboardType: TextInputType.url,
                        validator: viewModel.validateUrl,
                        onChanged: (value) => viewModel.updateUrl(value),
                      ),
                      const SizedBox(height: 16),

                      // --- Username (Optional) ---
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(labelText: 'Username/Login (optional)'),
                        onChanged: (value) => viewModel.updateUsername(value),
                      ),
                      const SizedBox(height: 16),

                      // --- Notes (Optional) ---
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          alignLabelWithHint: true, // Для лучшего вида с многострочным полем
                        ),
                        maxLines: 3,
                        minLines: 1,
                        onChanged: (value) => viewModel.updateNotes(value),
                      ),
                      const SizedBox(height: 24),

                      // --- Custom Metadata ---
                      Text('Custom Fields', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_customMetaKeyControllers.isEmpty)
                        const Text('No custom fields yet. Tap + to add.', style: TextStyle(color: Colors.grey)),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(), // Отключаем скролл вложенного ListView
                        itemCount: _customMetaKeyControllers.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _customMetaKeyControllers[index],
                                    decoration: InputDecoration(labelText: 'Field ${index + 1} Name'),
                                    // validator: (value) => (value == null || value.isEmpty) ? 'Key cannot be empty' : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: _customMetaValueControllers[index],
                                    decoration: InputDecoration(labelText: 'Field ${index + 1} Value'),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                  onPressed: () => _removeCustomMetadataField(index),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Add Custom Field'),
                          onPressed: _addCustomMetadataField,
                        ),
                      ),
                      const SizedBox(height: 70), // Отступ для FAB, если он будет
                    ],
                  ),
                ),
              ),
              // --- Индикатор загрузки ---
              if (viewModel.isLoading)
                Container(
                  color: Colors.black.withAlpha(77),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          );
        },
      ),
      // Можно добавить FAB для сохранения, если не используется AppBar action
      // floatingActionButton: FloatingActionButton.extended(
      //   onPressed: _viewModel.isLoading ? null : _saveEntry,
      //   label: const Text('Save Entry'),
      //   icon: const Icon(Icons.save),
      // ),
    );
  }
}
