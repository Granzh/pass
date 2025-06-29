import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/git_repository_model.dart';
import '../../models/password_repository_profile.dart';
import '../../services/gpg_key_service.dart';
import '../../services/password_repository_service.dart';

class AddEditProfileScreen extends StatefulWidget{
  final PasswordRepositoryProfile? existingProfile;
  final PasswordSourceType? initialSourceType;
  final String? initialRepoUrl;
  final Map<String, String>? initialAuthTokens;
  final String? initialProfileName;

  const AddEditProfileScreen({
    super.key,
    this.existingProfile,
    this.initialSourceType,
    this.initialRepoUrl,
    this.initialAuthTokens,
    this.initialProfileName
  });

  bool get isEditing => existingProfile != null;

  @override
  State<AddEditProfileScreen> createState() => _AddEditProfileScreenState();
}


class _AddEditProfileScreenState extends State<AddEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late PasswordRepositoryService _passwordRepoService;
  // Если PasswordRepositoryService не имеет метода hasKeyForProfile, то GPGService нужен напрямую
  late GPGService _gpgService;


  late TextEditingController _profileNameController;
  late TextEditingController _gitRepoUrlController;
  late TextEditingController _localPathController;

  late TextEditingController _gpgUserNameController;
  late TextEditingController _gpgUserEmailController;
  late TextEditingController _gpgKeyPassphraseController;

  PasswordSourceType _selectedSourceType = PasswordSourceType.github;
  String? _gpgKeyStatusMessage; // Сообщение о статусе GPG ключа
  bool _shouldGenerateOrReGenerateGpgKey = false;
  bool _isLoading = false;
  bool _isCheckingGpgKey = true; // Флаг для начальной проверки ключа

  @override
  void initState() {
    super.initState();
    _passwordRepoService = Provider.of<PasswordRepositoryService>(context, listen: false);
    _gpgService = Provider.of<GPGService>(context, listen: false); // Получаем GPGService

    _profileNameController = TextEditingController();
    _gitRepoUrlController = TextEditingController();
    _localPathController = TextEditingController(); // Инициализируем всегда
    _gpgUserNameController = TextEditingController();
    _gpgUserEmailController = TextEditingController();
    _gpgKeyPassphraseController = TextEditingController();

    if (widget.isEditing && widget.existingProfile != null) {
      final profile = widget.existingProfile!;
      _profileNameController.text = profile.profileName;
      _selectedSourceType = profile.type;
      _localPathController.text = profile.localPath ?? ''; // Для Git clone path

      if (profile.type == PasswordSourceType.github || profile.type == PasswordSourceType.gitlab) {
        _gitRepoUrlController.text = profile.repositoryFullName;
      } else { // PasswordSourceType.localFolder
        // Если для localFolder основной путь хранится в localPath, а не repositoryFullName
        // или если repositoryFullName это путь для localFolder, а localPath для него null
        _localPathController.text = profile.repositoryFullName; // Предполагая, что это основной путь для local
      }
      _checkGpgKeyStatus(profile.id);
    } else {
      _selectedSourceType = widget.initialSourceType ?? PasswordSourceType.github;

      if (widget.initialRepoUrl != null) {
        if (_selectedSourceType == PasswordSourceType.localFolder) {
          _localPathController.text = widget.initialRepoUrl!;
        } else {
          _gitRepoUrlController.text = widget.initialProfileName!;
        }
      }
    }
  }

  Future<void> _checkGpgKeyStatus(String profileId) async {
    setState(() { _isCheckingGpgKey = true; });
    try {
      // Используем напрямую GPGService, если в PasswordRepositoryService нет обертки
      final hasKey = await _gpgService.hasKeyForProfileById(profileId);
      if (!mounted) return;

      if (hasKey) {
        _gpgKeyStatusMessage = "GPG ключ настроен для этого профиля.";
        _shouldGenerateOrReGenerateGpgKey = false; // По умолчанию не перегенерируем, если ключ есть
      } else {
        _gpgKeyStatusMessage = "GPG ключ не настроен. Рекомендуется создать.";
        _shouldGenerateOrReGenerateGpgKey = true;
      }
    } catch (e) {
      if (!mounted) return;
      _gpgKeyStatusMessage = "Ошибка проверки GPG ключа: $e";
      _shouldGenerateOrReGenerateGpgKey = true; // Предлагаем создать, если ошибка
    } finally {
      if (!mounted) return;
      setState(() { _isCheckingGpgKey = false; });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // --- Предупреждение при смене типа ---
    if (widget.isEditing && widget.existingProfile != null && _selectedSourceType != widget.existingProfile!.type) {
      final confirmChangeType = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Смена типа профиля'),
            content: Text(
              'ВНИМАНИЕ!\nСмена типа профиля с "${widget.existingProfile!.type.name}" на "$_selectedSourceType.name" приведет к УДАЛЕНИЮ всех локальных данных текущего репозитория (папка repositories/${widget.existingProfile!.id}). '
                  'Новый репозиторий будет настроен "с нуля".\n\nЭто действие необратимо для локальных данных. Существующий GPG ключ (если он был) останется привязанным к этому профилю.\n\nПродолжить?',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Отмена'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Продолжить'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          );
        },
      );
      if (confirmChangeType != true) {
        return;
      }
    }

    setState(() { _isLoading = true; });

    String profileNameInput = _profileNameController.text.trim();
    String? gpgUserNameForNewKey, gpgUserEmailForNewKey, gpgPassphraseForNewKey;

    if (_shouldGenerateOrReGenerateGpgKey) {
      gpgUserNameForNewKey = _gpgUserNameController.text.trim();
      gpgUserEmailForNewKey = _gpgUserEmailController.text.trim();
      gpgPassphraseForNewKey = _gpgKeyPassphraseController.text;

      if (gpgUserNameForNewKey.isEmpty || gpgUserEmailForNewKey.isEmpty || gpgPassphraseForNewKey.isEmpty) {
        if (!mounted) return;
        setState(() { _isLoading = false; });
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Для генерации/перегенерации GPG ключа укажите Имя, Email и Парольную фразу для ключа.'), backgroundColor: Colors.red),
        );
        return;
      }
    } else if (!widget.isEditing) {
      if (!mounted) return;
      setState(() { _isLoading = false; });
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Критическая ошибка: Новый профиль должен генерировать GPG ключ. Пожалуйста, проверьте данные GPG.'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      String repositoryFullNameValue; // Это будет либо URL (для Git), либо путь (для LocalFolder)
      String? gitProviderNameValue;
      String? defaultBranchValue;

      if (_selectedSourceType == PasswordSourceType.github || _selectedSourceType == PasswordSourceType.gitlab) {
        repositoryFullNameValue = _gitRepoUrlController.text.trim(); // Используем _gitRepoUrlController
        gitProviderNameValue = _selectedSourceType == PasswordSourceType.github ? 'github' : 'gitlab';

        if (widget.isEditing && _selectedSourceType == widget.existingProfile!.type) {
          defaultBranchValue = widget.existingProfile!.defaultBranch;
        } else {
          defaultBranchValue = 'main';
        }
      } else { // PasswordSourceType.localFolder
        repositoryFullNameValue = _localPathController.text.trim(); // Используем _localPathController
        gitProviderNameValue = null;
        defaultBranchValue = null;
      }

      if (widget.isEditing && widget.existingProfile != null) {
        // --- РЕДАКТИРОВАНИЕ ПРОФИЛЯ ---
        final existingProfileId = widget.existingProfile!.id;

        await _passwordRepoService.updateRepository(
          profileId: existingProfileId,
          newProfileName: profileNameInput,
          newType: _selectedSourceType,
          newRepositoryFullName: repositoryFullNameValue,
          newGitProviderName: gitProviderNameValue,
          newDefaultBranch: defaultBranchValue,
          shouldRegenerateGpgKey: _shouldGenerateOrReGenerateGpgKey,
          newGpgUserName: _shouldGenerateOrReGenerateGpgKey ? (gpgUserNameForNewKey ?? profileNameInput) : null,
          newGpgUserEmail: _shouldGenerateOrReGenerateGpgKey ? gpgUserEmailForNewKey : null,
          newGpgPassphrase: _shouldGenerateOrReGenerateGpgKey ? gpgPassphraseForNewKey : null,
        );
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Профиль "$profileNameInput" обновлен')),
        );

      } else {
        // --- ДОБАВЛЕНИЕ НОВОГО ПРОФИЛЯ ---
        if (!_shouldGenerateOrReGenerateGpgKey || gpgUserNameForNewKey == null || gpgUserEmailForNewKey == null || gpgPassphraseForNewKey == null) {
          throw Exception("Критическая ошибка: Данные для GPG ключа не были предоставлены для нового профиля.");
        }

        GitRepository? gitRepoInfoForAdd;
        String? localFolderPathForAdd; // Это будет то же, что и repositoryFullNameValue для типа LocalFolder

        if (_selectedSourceType == PasswordSourceType.github || _selectedSourceType == PasswordSourceType.gitlab) {
          gitRepoInfoForAdd = GitRepository(
            id: '',
            name: repositoryFullNameValue,
            htmlUrl: repositoryFullNameValue,
            description: '',
            isPrivate: true,
            defaultBranch: defaultBranchValue ?? 'main',
          );
        } else { // PasswordSourceType.localFolder
          // Для addRepository параметр localFolderPath ожидает путь к локальной папке
          localFolderPathForAdd = repositoryFullNameValue;
        }

        await _passwordRepoService.addRepository(
          profileName: profileNameInput,
          type: _selectedSourceType,
          gitProviderName: gitProviderNameValue,
          gitRepositoryInfo: gitRepoInfoForAdd, // Будет null для LocalFolder
          localFolderPath: localFolderPathForAdd, // Будет repositoryFullNameValue для LocalFolder, null для Git
          defaultBranch: defaultBranchValue,
          gpgUserPassphrase: gpgPassphraseForNewKey,
          generateNewGpgKey: true,
          email: gpgUserEmailForNewKey,
        );
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Профиль "$profileNameInput" создан')),
        );
      }
      if (!mounted) return;
      navigator.pop(true);

    } catch (e) {
      if (!mounted) return;
      String errorMessage = 'Ошибка сохранения профиля.';
      if (e is Exception) {
        errorMessage = 'Ошибка сохранения профиля: ${e.toString().replaceFirst("Exception: ", "")}';
      }
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    } finally {
      if (!mounted) return;
      setState(() { _isLoading = false; });
    }
  }

  @override
  void dispose() {
    _profileNameController.dispose();
    _gitRepoUrlController.dispose();
    _localPathController.dispose();
    _gpgUserNameController.dispose();
    _gpgUserEmailController.dispose();
    _gpgKeyPassphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool showGpgInputFields = _shouldGenerateOrReGenerateGpgKey;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Редактировать Профиль' : 'Добавить Профиль'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Сохранить профиль',
            onPressed: (_isLoading || _isCheckingGpgKey) ? null : _saveProfile,
          ),
        ],
      ),
      body: (_isLoading)
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                controller: _profileNameController,
                decoration: const InputDecoration(labelText: 'Имя профиля *'),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Имя профиля не может быть пустым' : null,
                onChanged: (value) {
                  // Если создаем новый профиль и имя для GPG ключа еще не заполнено,
                  // можно автоматически подставить имя профиля.
                  // Пользователь все равно сможет его изменить.
                  if (!widget.isEditing && _shouldGenerateOrReGenerateGpgKey && _gpgUserNameController.text.isEmpty) {
                    // Либо если _gpgUserNameController отслеживает _profileNameController при создании
                    // _gpgUserNameController.text = value; // Раскомментируйте, если хотите такое поведение
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text('Тип Хранилища:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              RadioListTile<PasswordSourceType>(
                title: const Text('GitHub Репозиторий'),
                value: PasswordSourceType.github,
                groupValue: _selectedSourceType,
                onChanged: (v) => setState(() => _selectedSourceType = v!),
              ),
              RadioListTile<PasswordSourceType>(
                title: const Text('GitLab Репозиторий'),
                value: PasswordSourceType.gitlab,
                groupValue: _selectedSourceType,
                onChanged: (v) => setState(() => _selectedSourceType = v!),
              ),
              RadioListTile<PasswordSourceType>(
                title: const Text('Локальная Папка'),
                value: PasswordSourceType.localFolder,
                groupValue: _selectedSourceType,
                onChanged: (v) => setState(() => _selectedSourceType = v!),
              ),
              const SizedBox(height: 12),

              if (_selectedSourceType == PasswordSourceType.github || _selectedSourceType == PasswordSourceType.gitlab)
                TextFormField(
                  controller: _gitRepoUrlController,
                  decoration: InputDecoration(
                      labelText: 'URL ${_selectedSourceType == PasswordSourceType.github ? "GitHub" : "GitLab"} Репозитория *',
                      hintText: 'git@${_selectedSourceType == PasswordSourceType.github ? "github.com" : "gitlab.com"}:user/repo.git или https://...'
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'URL репозитория не может быть пустым' : null,
                )
              else // PasswordSourceType.localFolder
                TextFormField(
                  controller: _localPathController,
                  decoration: const InputDecoration(
                    labelText: 'Путь к локальной папке *',
                    hintText: 'Например, /Users/user/my_passwords',
                  ),
                  validator: (v) {
                    if (_selectedSourceType == PasswordSourceType.localFolder && (v == null || v.trim().isEmpty)) {
                      return 'Путь к локальной папке не может быть пустым';
                    }
                    return null;
                  },
                  // Для десктопа можно добавить иконку выбора папки
                  // suffixIcon: IconButton(icon: Icon(Icons.folder_open), onPressed: _pickFolder),
                ),

              const SizedBox(height: 20),
              const Text('Настройки GPG Ключа:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),

              if (_isCheckingGpgKey)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                // При редактировании даем возможность переключить генерацию/регенерацию
                if (widget.isEditing)
                  CheckboxListTile(
                    title: Text(_gpgKeyStatusMessage?.startsWith("GPG ключ настроен") ?? false
                        ? 'Перегенерировать GPG ключ'
                        : 'Создать/Настроить GPG ключ для этого профиля'),
                    value: _shouldGenerateOrReGenerateGpgKey,
                    onChanged: (bool? value) {
                      setState(() {
                        _shouldGenerateOrReGenerateGpgKey = value ?? false;
                        // Если снимаем галочку, а ключ не был настроен, возможно, стоит вернуть сообщение об этом
                        if (!_shouldGenerateOrReGenerateGpgKey && !(_gpgKeyStatusMessage?.startsWith("GPG ключ настроен") ?? false)) {
                          _gpgKeyStatusMessage = "GPG ключ не настроен. Рекомендуется создать/перегенерировать.";
                        } else if (_shouldGenerateOrReGenerateGpgKey && (_gpgKeyStatusMessage?.startsWith("GPG ключ настроен") ?? false)){
                          _gpgKeyStatusMessage = "Будет сгенерирован НОВЫЙ GPG ключ, старый будет заменен.";
                        }
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                // Сообщение о статусе GPG ключа (если не редактирование, то оно статично "Будет сгенерирован...")
                if (!widget.isEditing || !(_gpgKeyStatusMessage?.startsWith("GPG ключ настроен") ?? false) || _shouldGenerateOrReGenerateGpgKey)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                    child: Text(
                      _gpgKeyStatusMessage ?? ( _shouldGenerateOrReGenerateGpgKey
                          ? "Введите данные для нового GPG ключа."
                          : "GPG ключ будет использован существующий."), // Это сообщение может не показываться из-за условия выше
                      style: TextStyle(color: Theme.of(context).hintColor),
                    ),
                  ),
              ],

              if (showGpgInputFields) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _gpgUserNameController,
                  decoration: const InputDecoration(labelText: 'Имя для GPG ключа (User Name) *'),
                  validator: (value) {
                    if (showGpgInputFields && (value == null || value.trim().isEmpty)) {
                      return 'Имя для GPG ключа не может быть пустым';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _gpgUserEmailController,
                  decoration: const InputDecoration(labelText: 'Email для GPG ключа *'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (showGpgInputFields) {
                      if (value == null || value.trim().isEmpty) return 'Email для GPG ключа не может быть пустым';
                      if (!value.contains('@') || !value.contains('.')) return 'Введите корректный Email'; // Простая проверка
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _gpgKeyPassphraseController,
                  decoration: const InputDecoration(labelText: 'Парольная фраза для GPG ключа *'),
                  obscureText: true,
                  validator: (value) {
                    if (showGpgInputFields && (value == null || value.isEmpty)) { // Пароль не триммим для проверки на пустоту
                      return 'Парольная фраза для GPG ключа не может быть пустой';
                    }
                    // Можно добавить проверку на сложность пароля
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 24), // Отступ перед невидимой кнопкой сохранения (если она нужна была бы)
            ],
          ),
        ),
      ),
    );
  }
}