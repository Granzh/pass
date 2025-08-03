import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import '../../core/utils/enums.dart';
import '../../models/git_repository_model.dart';
import '../../models/password_repository_profile.dart';
import '../../services/auth_services/app_oauth_service.dart';
import '../../services/auth_services/git_auth.dart';
import '../../services/git_services/git_api_service.dart';
import '../../services/GPG_services/gpg_key_service.dart';
import '../../services/password_repository_service.dart';
import 'dart:async';
import '../../services/profile_services/repository_profile_manager.dart';
import '../view_models/add_edit_profile_view_model.dart';

class AddEditProfileScreen extends StatefulWidget {
  static const String routeName = 'add-edit-profile';

  final PasswordRepositoryProfile? existingProfile;
  final PasswordSourceType? initialSourceType;
  final String? initialRepoUrl;
  final Map<String, String>? initialAuthTokens;
  final String? initialProfileName;
  final GitRepository? initialSelectedGitRepo;

  const AddEditProfileScreen({
    super.key,
    this.existingProfile,
    this.initialSourceType,
    this.initialRepoUrl,
    this.initialAuthTokens,
    this.initialProfileName,
    this.initialSelectedGitRepo,
  });

  bool get isEditing => existingProfile != null;

  @override
  State<AddEditProfileScreen> createState() => _AddEditProfileScreenState();
}

class _AddEditProfileScreenState extends State<AddEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  static final _log = Logger('AddEditProfileScreen');
  late AddEditProfileViewModel _viewModel;

  late TextEditingController _profileNameController;
  late TextEditingController _gitRepoUrlController;
  late TextEditingController _localPathController;

  late TextEditingController _gpgUserNameController;
  late TextEditingController _gpgUserEmailController;
  late TextEditingController _gpgKeyPassphraseController;

  StreamSubscription? _errorSubscription;
  StreamSubscription? _infoSubscription;
  StreamSubscription? _navPopSubscription;
  StreamSubscription? _confirmChangeTypeSubscription;

  @override
  void initState() {
    super.initState();

    _viewModel = AddEditProfileViewModel(
      passwordRepoService: context.read<PasswordRepositoryService>(),
      gpgService: context.read<GPGService>(),
      profileManager: context.read<RepositoryProfileManager>(),
      appOAuthService: context.read<AppOAuthService>(),
      gitApiService: context.read<GitApiService>(),
      secureGitAuth: context.read<SecureGitAuth>(),
      existingProfile: widget.existingProfile,
      initialSourceType: widget.initialSourceType,
      initialAuthTokens: widget.initialAuthTokens,
      initialSelectedGitRepo: widget.initialSelectedGitRepo,
    );

    _profileNameController = TextEditingController();
    _gitRepoUrlController = TextEditingController();
    _localPathController = TextEditingController();
    _gpgUserNameController = TextEditingController();
    _gpgUserEmailController = TextEditingController();
    _gpgKeyPassphraseController = TextEditingController();

    _profileNameController.text = widget.isEditing
        ? widget.existingProfile!.profileName
        : (widget.initialProfileName ??
        (_viewModel.selectedRemoteRepository?.name ??
            (widget.initialSelectedGitRepo?.name ?? '')));

    if (widget.isEditing) {
      final profile = widget.existingProfile!;

      if (!_viewModel.shouldGenerateOrReGenerateGpgKey) {
        _gpgUserNameController.text = profile.gpgUserName ?? profile.profileName;
      } else {
        _gpgUserNameController.text = _profileNameController.text;
      }
    } else {
      _gpgUserNameController.text = _profileNameController.text;
    }

    _errorSubscription = _viewModel.errorMessages.listen((message) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5)
          )
        );
      }
    });

    _infoSubscription = _viewModel.infoMessages.listen((message) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    });

    _navPopSubscription = _viewModel.navigationPop.listen((success) {
      if (mounted && success) {
        Navigator.of(context).pop(true);
      }
    });

    _confirmChangeTypeSubscription =
        _viewModel.requestChangeTypeConfirmation.listen((_) async {
          if (mounted) {
            final confirmed = await _showChangeTypeConfirmationDialog();
            if (confirmed == true) {
              _triggerSave(changeTypeConfirmed: true);
            }
          }
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<bool?> _showChangeTypeConfirmationDialog() async {
    final existingProfileId = _viewModel.isEditing ? _viewModel.existingProfileId : "новый_профиль";
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Смена типа профиля'),
          content: Text(
            'ВНИМАНИЕ!\nСмена типа профиля с "${_viewModel.existingProfileType?.displayName ?? 'текущего'}" на "${_viewModel.selectedSourceType.displayName}" приведет к УДАЛЕНИЮ всех локальных данных текущего репозитория (папка repositories/$existingProfileId).\n' // <-- ИСПРАВЛЕНО
                'Новый репозиторий будет настроен "с нуля".\n\nЭто действие необратимо для локальных данных. Существующий GPG ключ (если он был) останется привязанным к этому профилю, если вы не решите его перегенерировать.\n\nПродолжить?',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Продолжить'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
  }

  void _triggerSave({bool changeTypeConfirmed = false}) {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save(); // Не обязательно, если контроллеры используются напрямую
      _viewModel.proceedWithSave(
        profileName: _profileNameController.text.trim(),
        // gitRepoUrlFromForm: _gitRepoUrlController.text.trim(), // Больше не нужен, ViewModel берет из selectedRemoteRepository
        localPath: _localPathController.text.trim(),
        gpgUserName: _gpgUserNameController.text.trim(),
        gpgUserEmail: _gpgUserEmailController.text.trim(),
        gpgKeyPassphrase: _gpgKeyPassphraseController.text,
        changeTypeConfirmed: changeTypeConfirmed,
      );
    }
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    _infoSubscription?.cancel();
    _navPopSubscription?.cancel();
    _confirmChangeTypeSubscription?.cancel();

    _profileNameController.dispose();
    _gitRepoUrlController.dispose();
    _localPathController.dispose();
    _gpgUserNameController.dispose();
    _gpgUserEmailController.dispose();
    _gpgKeyPassphraseController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewModel, // Передаем уже созданный _viewModel
      child: Consumer<AddEditProfileViewModel>(
        builder: (context, vm, child) { // vm здесь это _viewModel
          bool isGitType = vm.selectedSourceType.isGitType; // Используем расширение из ViewModel
          bool isLocalType = vm.selectedSourceType == PasswordSourceType.localFolder;

          // Обновление текстовых контроллеров на основе ViewModel
          // Это должно происходить здесь, чтобы UI реагировал на изменения в ViewModel
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;

            // Имя профиля (если selectedRemoteRepository изменился и имя профиля было основано на нем)
            if (!vm.isEditing && _profileNameController.text.isEmpty && vm.selectedRemoteRepository != null) {
              _profileNameController.text = vm.selectedRemoteRepository!.name;
            }
            // GPG User Name, если генерируем ключ и имя контроллера GPG пусто или равно старому имени профиля
            if (vm.shouldGenerateOrReGenerateGpgKey &&
                (_gpgUserNameController.text.isEmpty ||
                    (vm.isEditing && vm.existingProfileDisplayName != null && _gpgUserNameController.text == vm.existingProfileDisplayName) ||
                    (!vm.isEditing && _gpgUserNameController.text != _profileNameController.text)
                )
            ) {
              _gpgUserNameController.text = _profileNameController.text;
            }


            if (isGitType) {
              _localPathController.clear();
              // URL репозитория теперь берется из vm.selectedRemoteRepository
              final expectedUrl = vm.selectedRemoteRepository?.htmlUrl ??
                  (vm.isEditing && vm.existingProfileIsGitType && vm.selectedSourceType == vm.existingProfileType
                      ? vm.existingProfileRepoCloneUrl ?? vm.existingProfileRepoFullName
                      : '');
              if (_gitRepoUrlController.text != expectedUrl) {
                _gitRepoUrlController.text = expectedUrl!;
              }
            } else if (isLocalType) {
              _gitRepoUrlController.clear();
              // Для LocalFolder, если это новый профиль или тип изменился на Local,
              // _localPathController может быть инициализирован widget.initialRepoUrl или оставаться пустым.
              // Пользователь выберет его через FilePicker.
              // Если редактируем существующий LocalFolder, он уже будет заполнен из profile.repositoryFullName
              if (!vm.isEditing || (vm.isEditing && vm.existingProfileType != PasswordSourceType.localFolder && vm.selectedSourceType == PasswordSourceType.localFolder)) {
                if (_localPathController.text.isEmpty && widget.initialRepoUrl != null){
                  // _localPathController.text = widget.initialRepoUrl; // Или пусть пользователь выбирает
                }
              } else if (vm.isEditing && vm.existingProfileType == PasswordSourceType.localFolder) {
                if (_localPathController.text != vm.existingProfileRepoFullName) {
                  _localPathController.text = vm.existingProfileRepoFullName ?? '';
                }
              }
            }
          });


          // Определяем, будет ли поле URL/Пути readOnly
          bool isRepoPathReadOnly = false;
          if (isGitType) {
            // Для Git-типов URL всегда readOnly, так как он определяется выбранным репозиторием.
            isRepoPathReadOnly = true;
          } else if (isLocalType) {
            // Для LocalFolder поле редактируемо, если это новый профиль,
            // или если мы редактируем профиль и сменили тип на LocalFolder (т.е. старый не Local),
            // или если мы редактируем существующий LocalFolder.
            isRepoPathReadOnly = vm.isEditing &&
                vm.existingProfileType != PasswordSourceType.localFolder &&
                vm.selectedSourceType != PasswordSourceType.localFolder;
            if (vm.isEditing && vm.existingProfileType == PasswordSourceType.localFolder && vm.selectedSourceType == PasswordSourceType.localFolder) {
              isRepoPathReadOnly = false; // Редактируем локальный, тип не менялся
            } else if (vm.isEditing && vm.existingProfileType != PasswordSourceType.localFolder && vm.selectedSourceType == PasswordSourceType.localFolder) {
              isRepoPathReadOnly = false; // Сменили на локальный, путь должен быть редактируемым (или через пикер)
            } else if (!vm.isEditing) {
              isRepoPathReadOnly = false; // Новый локальный
            }
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(vm.isEditing ? 'Редактировать Профиль' : 'Добавить Профиль'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.save_outlined),
                  tooltip: 'Сохранить профиль',
                  onPressed: (vm.isLoading || vm.isCheckingGpgKey || vm.isAuthenticatingOAuth || vm.isLoadingRepositories) // Блокируем при любой загрузке
                      ? null
                      : () => _triggerSave(),
                ),
              ],
            ),
            body: Opacity(
              opacity: (vm.isLoading || vm.isAuthenticatingOAuth || vm.isLoadingRepositories) ? 0.5 : 1.0, // Учитываем разные загрузки
              child: AbsorbPointer(
                absorbing: (vm.isLoading || vm.isAuthenticatingOAuth || vm.isLoadingRepositories),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        TextFormField(
                          controller: _profileNameController,
                          // ... (остальные свойства TextFormField)
                          onChanged: (value) {
                            // Логика обновления gpgUserNameController уже в addPostFrameCallback
                          },
                        ),
                        const SizedBox(height: 16),
                        const Text('Тип Хранилища:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        DropdownButtonFormField<PasswordSourceType>(
                          value: vm.selectedSourceType,
                          decoration: const InputDecoration(border: OutlineInputBorder()),
                          items: PasswordSourceType.values.map((PasswordSourceType type) {
                            return DropdownMenuItem<PasswordSourceType>(
                              value: type,
                              child: Text(type.displayName),
                            );
                          }).toList(),
                          onChanged: (PasswordSourceType? newValue) {
                            if (newValue != null) {
                              vm.selectedSourceType = newValue;
                              // Если новый тип - Git, и репозитории еще не загружены/не аутентифицирован,
                              // можно инициировать проверку/загрузку.
                              if (newValue.isGitType) {
                                vm.checkAuthenticationAndLoadRepos();
                              }
                              // Очистка контроллеров URL/Path и их обновление
                              // теперь происходит в WidgetsBinding.instance.addPostFrameCallback выше.
                            }
                          },
                        ),
                        const SizedBox(height: 16),

                        // --- Секция для Git-типов ---
                        if (isGitType) ...[
                          // Кнопки OAuth
                          if (vm.selectedSourceType == PasswordSourceType.github)
                            ElevatedButton.icon(
                              icon: const Icon(Icons.login), // Можно использовать FontAwesome иконку GitHub
                              label: const Text('Войти через GitHub'),
                              onPressed: vm.isAuthenticatingOAuth ? null : () => vm.startGitOAuthFlow(GitProvider.github),
                            ),
                          if (vm.selectedSourceType == PasswordSourceType.gitlab)
                            ElevatedButton.icon(
                              icon: const Icon(Icons.login), // Можно использовать FontAwesome иконку GitLab
                              label: const Text('Войти через GitLab'),
                              onPressed: vm.isAuthenticatingOAuth ? null : () => vm.startGitOAuthFlow(GitProvider.gitlab),
                            ),
                          if (vm.isAuthenticatingOAuth)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(width: 8), Text("Авторизация...")]),
                            ),
                          if (vm.oauthErrorMessage != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text(vm.oauthErrorMessage!, style: const TextStyle(color: Colors.red)),
                            ),
                          const SizedBox(height: 10),

                          // Поле URL (теперь в основном read-only)
                          TextFormField(
                            controller: _gitRepoUrlController,
                            readOnly: true, // Всегда readOnly, т.к. управляется выбором репозитория
                            decoration: InputDecoration(
                              labelText: 'URL Git Репозитория',
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.grey[200],
                            ),
                            // Валидатор не нужен, если поле read-only и заполняется программно
                          ),
                          const SizedBox(height: 10),

                          // Загрузка и выбор репозитория
                          if (vm.isLoadingRepositories)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(width: 8), Text("Загрузка репозиториев...")]),
                            ),
                          if (vm.repositoryLoadingError != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Column(
                                children: [
                                  Text(vm.repositoryLoadingError!, style: const TextStyle(color: Colors.red)),
                                  // Предложить повторить OAuth, если ошибка связана с авторизацией
                                  if(vm.repositoryLoadingError!.contains("вториз")) // Простая проверка
                                    ElevatedButton(
                                        onPressed: () {
                                          final provider = vm.selectedSourceType.toGitProvider;
                                          if (provider != null) vm.startGitOAuthFlow(provider);
                                        },
                                        child: Text("Повторить вход через ${vm.selectedSourceType.displayName}")
                                    )
                                ],
                              ),
                            ),

                          if (!vm.isLoadingRepositories && vm.remoteRepositories != null)
                            DropdownButtonFormField<GitRepository>(
                              value: vm.selectedRemoteRepository,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Выберите репозиторий *',
                                border: OutlineInputBorder(),
                              ),
                              hint: vm.remoteRepositories!.isEmpty
                                  ? const Text("Нет доступных репозиториев")
                                  : const Text("Выберите репозиторий"),
                              items: vm.remoteRepositories!.map((GitRepository repo) {
                                return DropdownMenuItem<GitRepository>(
                                  value: repo,
                                  child: Text(repo.name, overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: vm.remoteRepositories!.isEmpty ? null : (GitRepository? newValue) {
                                vm.selectedRemoteRepository = newValue;
                                // _gitRepoUrlController обновится через WidgetsBinding.instance.addPostFrameCallback
                                // Если имя профиля пустое, можно его предзаполнить именем репозитория
                                if (!vm.isEditing && _profileNameController.text.isEmpty && newValue != null) {
                                  _profileNameController.text = newValue.name;
                                }
                              },
                              validator: (value) => (isGitType && value == null)
                                  ? 'Выберите удаленный репозиторий'
                                  : null,
                            ),
                        ],

                        // --- Секция для LocalFolder ---
                        if (isLocalType)
                          TextFormField(
                            controller: _localPathController,
                            readOnly: isRepoPathReadOnly, // Управляется выше
                            decoration: InputDecoration(
                              labelText: 'Путь к локальной папке *',
                              border: const OutlineInputBorder(),
                              hintText: 'Например, /Users/user/pass-store',
                              filled: isRepoPathReadOnly,
                              fillColor:
                              isRepoPathReadOnly ? Colors.grey[200] : null,
                            ),
                            validator: (v) => (isLocalType &&
                                (v == null || v.trim().isEmpty))
                                ? 'Путь к локальной папке не может быть пустым'
                                : null,
                          ),
                        if (isLocalType && !vm.isEditing)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.folder_open),
                              label: const Text("Выбрать папку"),
                              onPressed: (vm.isLoading) ? null : () async {
                                final scaffoldMessenger = ScaffoldMessenger.of(context);

                                String? directoryPath;
                                bool pickerError = false;
                                String errorMessage = '';

                                try {
                                  directoryPath = await FilePicker.platform.getDirectoryPath(
                                    dialogTitle: 'Выберите папку для хранилища',
                                  );
                                } catch (e) {
                                  _log.warning("Ошибка при вызове FilePicker: $e");
                                  pickerError = true;
                                  errorMessage = 'Ошибка при открытии диалога выбора папки: $e';
                                }

                                if (!mounted) return;

                                if (pickerError) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(content: Text(errorMessage)),
                                  );
                                  return;
                                }

                                if (directoryPath != null) {
                                  _localPathController.text = directoryPath;
                                } else {
                                  scaffoldMessenger.showSnackBar(
                                    const SnackBar(content: Text('Выбор папки отменен.')),
                                  );
                                }
                              },
                            ),
                          ),

                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 10),

                        // --- Секция GPG ---
                        // (Ваш код для GPG выглядит хорошо, можно оставить как есть,
                        //  только убедиться, что on OnChanged у Switch обновляет
                        //  _gpgUserNameController, если нужно, что вы уже делаете)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('GPG Ключ:',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                            if (vm.isEditing)
                              Row(
                                children: [
                                  Text(
                                      vm.shouldGenerateOrReGenerateGpgKey
                                          ? "Сгенерировать новый"
                                          : "Использовать существующий",
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[700])),
                                  Switch(
                                    value: vm.shouldGenerateOrReGenerateGpgKey,
                                    onChanged: (vm.isCheckingGpgKey ||
                                        vm.isLoading)
                                        ? null
                                        : (bool value) {
                                      vm.shouldGenerateOrReGenerateGpgKey = value;
                                      // Если переключаем на "сгенерировать новый",
                                      // и имя GPG было от старого профиля,
                                      // обновляем его на текущее имя профиля.
                                      if (value && _gpgUserNameController.text != _profileNameController.text) {
                                        _gpgUserNameController.text = _profileNameController.text;
                                      }
                                    },
                                  ),
                                ],
                              ),
                          ],
                        ),
                        if (vm.isCheckingGpgKey)
                          const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Row(children: [
                                CircularProgressIndicator(strokeWidth: 2),
                                SizedBox(width: 8),
                                Text("Проверка GPG ключа...")
                              ])),
                        if (vm.gpgKeyStatusMessage != null &&
                            vm.gpgKeyStatusMessage!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Text(
                              vm.gpgKeyStatusMessage!,
                              style: TextStyle(
                                  color: vm.gpgKeyStatusMessage!
                                      .toLowerCase()
                                      .contains("ошибка")
                                      ? Colors.red
                                      : Colors.grey[700]),
                            ),
                          ),
                        if (vm.shouldGenerateOrReGenerateGpgKey) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _gpgUserNameController,
                            decoration: InputDecoration(
                              labelText: 'Имя пользователя для GPG ключа *',
                              hintText: _profileNameController.text.isNotEmpty
                                  ? 'Например, "${_profileNameController.text}"'
                                  : 'Например, "John Doe"',
                              border: const OutlineInputBorder(),
                            ),
                            validator: (v) => (vm.shouldGenerateOrReGenerateGpgKey &&
                                (v == null || v.trim().isEmpty))
                                ? 'Имя пользователя для GPG обязательно'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _gpgUserEmailController,
                            decoration: const InputDecoration(
                                labelText: 'Email для GPG ключа *',
                                hintText: 'Например, user@example.com',
                                border: OutlineInputBorder()),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (vm.shouldGenerateOrReGenerateGpgKey) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Email для GPG ключа обязателен';
                                }
                                if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+")
                                    .hasMatch(v.trim())) {
                                  return 'Введите корректный email';
                                }
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _gpgKeyPassphraseController,
                            decoration: InputDecoration(
                              labelText: 'Парольная фраза для GPG ключа *',
                              hintText: vm.isEditing && !vm.shouldGenerateOrReGenerateGpgKey
                                  ? '(оставьте пустым, если не меняете)'
                                  : 'Надежная парольная фраза',
                              border: const OutlineInputBorder(),
                            ),
                            obscureText: true,
                            validator: (v) {
                              if (vm.shouldGenerateOrReGenerateGpgKey &&
                                  (v == null || v.isEmpty)) {
                                return 'Парольная фраза обязательна для нового GPG ключа';
                              }
                              return null;
                            },
                          ),
                        ],

                        const SizedBox(height: 24),
                        if (vm.isLoading)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(width: 16), Text("Сохранение профиля...")]),
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            icon: const Icon(Icons.save),
                            label: const Text('Сохранить Профиль'),
                            // ...
                            onPressed: (vm.isCheckingGpgKey || vm.isAuthenticatingOAuth || vm.isLoadingRepositories) // Проверяем все состояния загрузки
                                ? null
                                : () => _triggerSave(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}