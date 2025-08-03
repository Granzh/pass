import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:logging/logging.dart';
import '../../core/utils/enums.dart';
import '../../models/git_repository_model.dart';
import '../../models/password_repository_profile.dart';
import '../../services/auth_services/app_oauth_service.dart';
import '../../services/git_services/git_api_service.dart';
import '../../services/auth_services/git_auth.dart';
import '../../services/GPG_services/gpg_key_service.dart';
import '../../services/password_repository_service.dart';
import '../../services/profile_services/repository_profile_manager.dart';

class AddEditProfileViewModel extends ChangeNotifier {
  final PasswordRepositoryService _passwordRepoService;
  final GPGService _gpgService;
  final RepositoryProfileManager _profileManager;
  final GitApiService _gitApiService;
  final AppOAuthService _appOAuthService;
  final SecureGitAuth _secureGitAuth;


  static final _log = Logger('AddEditProfileViewModel');


  final PasswordRepositoryProfile? _existingProfile;
  final PasswordSourceType? _initialSourceType;
  final Map<String, String>? _initialAuthTokens;
  final GitRepository? _initialSelectedGitRepo;

  PasswordSourceType? get existingProfileType => _existingProfile?.type;
  String? get existingProfileDisplayName => _existingProfile?.profileName;
  String? get existingProfileRepoCloneUrl => _existingProfile?.repositoryCloneUrl;
  String? get existingProfileRepoFullName => _existingProfile?.repositoryFullName;
  bool get existingProfileIsGitType => _existingProfile?.isGitType() ?? false;
  String? get existingProfileId => _existingProfile?.id;

  bool _isAuthenticatingOAuth = false;
  bool get isAuthenticatingOAuth => _isAuthenticatingOAuth;

  String? _oauthErrorMessage;
  String? get oauthErrorMessage => _oauthErrorMessage;

  bool get isEditing => _existingProfile != null;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isCheckingGpgKey = false;
  bool get isCheckingGpgKey => _isCheckingGpgKey;

  String? _gpgKeyStatusMessage;
  String? get gpgKeyStatusMessage => _gpgKeyStatusMessage;

  bool _isLoadingRepositories = false;
  bool get isLoadingRepositories => _isLoadingRepositories;

  String? _repositoryLoadingError;
  String? get repositoryLoadingError => _repositoryLoadingError;

  GitRepository? _selectedRemoteRepository;
  GitRepository? get selectedRemoteRepository => _selectedRemoteRepository;
  set selectedRemoteRepository(GitRepository? repo) {
    if (_selectedRemoteRepository?.id != repo?.id) {
      _selectedRemoteRepository = repo;
      _log.info('User selected repository: ${repo?.name}');
      notifyListeners();
    }
  }

  List<GitRepository>? _remoteRepositories;
  List<GitRepository>? get remoteRepositories => _remoteRepositories;


  bool _shouldGenerateOrReGenerateGpgKey = false;
  bool get shouldGenerateOrReGenerateGpgKey => _shouldGenerateOrReGenerateGpgKey;
  set shouldGenerateOrReGenerateGpgKey(bool value) {
    _shouldGenerateOrReGenerateGpgKey = value;
    if (isEditing) {
      if (_shouldGenerateOrReGenerateGpgKey) {
        _gpgKeyStatusMessage = "Будет сгенерирован НОВЫЙ GPG ключ, старый будет удален/заменен.";
      } else {
        _checkGpgKeyStatus(_existingProfile!.id);
      }
    } else {
      _gpgKeyStatusMessage = "Введите данные для нового GPG ключа.";
    }
    notifyListeners();
  }

  PasswordSourceType _selectedSourceType = PasswordSourceType.github;
  PasswordSourceType get selectedSourceType => _selectedSourceType;
  set selectedSourceType(PasswordSourceType value) {
    if (_selectedSourceType == value) return;

    _selectedSourceType = value;

    if (isEditing && _existingProfile != null) {
      if (_selectedSourceType == _existingProfile.type) {
        _checkGpgKeyStatus(_existingProfile.id);
      }
    }

    if (_selectedSourceType.isGitType) {
      _oauthErrorMessage = null;
      _repositoryLoadingError = null;
      _remoteRepositories = null;
      _selectedRemoteRepository = null;
      checkAuthenticationAndLoadRepos();
    } else {
      _remoteRepositories = null;
      _selectedRemoteRepository = null;
      _repositoryLoadingError = null;
      _oauthErrorMessage = null;
    }
    notifyListeners();
  }


  final StreamController<String> _errorMessagesController = StreamController<String>.broadcast();
  Stream<String> get errorMessages => _errorMessagesController.stream;

  final StreamController<String> _infoMessagesController = StreamController<String>.broadcast();
  Stream<String> get infoMessages => _infoMessagesController.stream;

  final StreamController<bool> _navigationPopController = StreamController<bool>.broadcast();
  Stream<bool> get navigationPop => _navigationPopController.stream;

  final StreamController<void> _requestChangeTypeConfirmationController = StreamController<void>.broadcast();
  Stream<void> get requestChangeTypeConfirmation => _requestChangeTypeConfirmationController.stream;

  AddEditProfileViewModel({
    required PasswordRepositoryService passwordRepoService,
    required GPGService gpgService,
    required RepositoryProfileManager profileManager,
    required GitApiService gitApiService,
    required AppOAuthService appOAuthService,
    required SecureGitAuth secureGitAuth,
    PasswordRepositoryProfile? existingProfile,
    PasswordSourceType? initialSourceType,
    Map<String, String>? initialAuthTokens,
    GitRepository? initialSelectedGitRepo,

  })  : _passwordRepoService = passwordRepoService,
        _gpgService = gpgService,
        _profileManager = profileManager,
        _gitApiService = gitApiService,
        _appOAuthService = appOAuthService,
        _secureGitAuth = secureGitAuth,
        _existingProfile = existingProfile,
        _initialSourceType = initialSourceType,
        _initialAuthTokens = initialAuthTokens,
        _initialSelectedGitRepo = initialSelectedGitRepo {
          _initialize();
        }

  void _initialize() {
    if (isEditing && _existingProfile != null) {
      final profile = _existingProfile;
      _selectedSourceType = profile.type;
      _checkGpgKeyStatus(profile.id);

      if (profile.isGitType() && profile.repositoryId != null) {
        _selectedRemoteRepository = GitRepository(
          id: profile.repositoryId!,
          name: profile.repositoryFullName,
          htmlUrl: profile.repositoryCloneUrl ?? '',
          providerName: profile.gitProviderName ??
              _selectedSourceType.toGitProvider?.name ?? '',
          isPrivate: profile.isPrivateRepository ?? false,
          defaultBranch: profile.defaultBranch ?? 'main',
          description: profile.repositoryDescription ?? '',
        );
        checkAuthenticationAndLoadRepos();
      }
    } else {
      _selectedSourceType = _initialSourceType ?? PasswordSourceType.github;
      _shouldGenerateOrReGenerateGpgKey = true;
      _gpgKeyStatusMessage = "Введите данные для нового GPG ключа.";

      if (_initialSelectedGitRepo != null && _selectedSourceType.isGitType) {
        _selectedRemoteRepository = _initialSelectedGitRepo;
      }

      if (_selectedSourceType.isGitType && _selectedRemoteRepository == null) {
        checkAuthenticationAndLoadRepos();
      }
    }
    notifyListeners();
  }

  Future<void> _checkGpgKeyStatus(String profileId) async {
    _isCheckingGpgKey = true;
    _gpgKeyStatusMessage = "Проверка GPG ключа...";
    notifyListeners();
    try {
      final hasKey = await _gpgService.hasKeyForProfileById(profileId);
      if (hasKey) {
        _gpgKeyStatusMessage = "GPG ключ уже настроен для этого профиля.";
        _shouldGenerateOrReGenerateGpgKey = false;
      } else {
        _gpgKeyStatusMessage = "GPG ключ не найден. Рекомендуется создать.";
        _shouldGenerateOrReGenerateGpgKey = true;
      }
    } catch (e) {
      _log.warning("Error checking GPG key status for profile $profileId: $e");
      _gpgKeyStatusMessage = "Ошибка проверки GPG ключа: $e";
      _shouldGenerateOrReGenerateGpgKey = true;
    } finally {
      _isCheckingGpgKey = false;
      notifyListeners();
    }
  }

  Future<void> proceedWithSave({
    required String profileName,
    required String localPath,
    String? gpgUserName,
    String? gpgUserEmail,
    String? gpgKeyPassphrase,
    bool changeTypeConfirmed = false,
  }) async {
    _log.info("Proceeding with save. ProfileName: $profileName, isEditing: $isEditing, selectedType: $_selectedSourceType");

    if (profileName.trim().isEmpty) {
      _errorMessagesController.add('Имя профиля не может быть пустым');
      return;
    }

    if ((_selectedSourceType == PasswordSourceType.github || _selectedSourceType == PasswordSourceType.gitlab) && _selectedRemoteRepository == null) {
      _errorMessagesController.add('Для Git-профиля не выбран удаленный репозиторий.');
      _log.severe("Attempted to save Git profile without a selected remote repository.");
      return;
    }

    if (_selectedSourceType == PasswordSourceType.localFolder && localPath.trim().isEmpty) {
      _errorMessagesController.add('Путь к локальной папке не может быть пустым');
      return;
    }

    if (_shouldGenerateOrReGenerateGpgKey) {
      if (gpgUserEmail == null || gpgUserEmail.trim().isEmpty) {
        _errorMessagesController.add('Email для GPG ключа обязателен при генерации нового ключа.');
        _isLoading = false;
        notifyListeners();
        return;
      }
      if (gpgKeyPassphrase == null || gpgKeyPassphrase.isEmpty) {
        _errorMessagesController.add('Парольная фраза для GPG ключа обязательна при генерации нового ключа.');
        _isLoading = false;
        notifyListeners();
        return;
      }
    }

    if (isEditing && _existingProfile != null && _selectedSourceType != _existingProfile.type && !changeTypeConfirmed) {
      _log.info("Requesting change type confirmation. Old: ${_existingProfile.type}, New: $_selectedSourceType");
      _requestChangeTypeConfirmationController.add(null);
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      if (isEditing && _existingProfile != null) {
        final currentProfile = _existingProfile;
        bool gpgNeedsUpdate = _shouldGenerateOrReGenerateGpgKey;
        bool nameNeedsUpdate = profileName.trim() != currentProfile.profileName;

        if (nameNeedsUpdate || gpgNeedsUpdate) {
          await _passwordRepoService.updateProfileDetails(
            profileId: currentProfile.id,
            newProfileName: nameNeedsUpdate ? profileName.trim() : null,
            shouldRegenerateGpgKey: _shouldGenerateOrReGenerateGpgKey,
            newGpgUserName: _shouldGenerateOrReGenerateGpgKey ? gpgUserName : null,
            newGpgUserEmail: _shouldGenerateOrReGenerateGpgKey ? gpgUserEmail?.trim() : null,
            newGpgPassphraseForRegen: _shouldGenerateOrReGenerateGpgKey ? gpgKeyPassphrase : null,
          );
          _log.info("Profile details (name/gpg) updated for ${currentProfile.id}");
        }

        if (_selectedSourceType != currentProfile.type) {
          _log.warning("Profile type change from ${currentProfile.type} to $_selectedSourceType for ${currentProfile.id} is not fully supported by the service yet. Re-cloning/init might be needed manually or after service update.");
          PasswordRepositoryProfile updatedProfileObject = currentProfile.copyWith(type: _selectedSourceType);
          if (_selectedSourceType == PasswordSourceType.localFolder) {
            updatedProfileObject = updatedProfileObject.copyWith(
              repositoryFullName: localPath.trim(),
              repositoryId: null,
              repositoryCloneUrl: null,
            );
          } else {
            if (_selectedRemoteRepository != null) {
              updatedProfileObject = updatedProfileObject.copyWith(
                gitProviderName: _selectedRemoteRepository!.providerName,
                repositoryId: _selectedRemoteRepository!.id.toString(),
                repositoryFullName: _selectedRemoteRepository!.name,
                repositoryCloneUrl: _selectedRemoteRepository!.htmlUrl,
                isPrivateRepository: _selectedRemoteRepository!.isPrivate,
                defaultBranch: _selectedRemoteRepository!.defaultBranch,
                repositoryDescription: _selectedRemoteRepository!.description,
              );
            } else {
              _errorMessagesController.add("Невозможно сменить тип на Git без предоставления информации о новом репозитории через OAuth.");
              _isLoading = false;
              notifyListeners();
              return;
            }
          }
          await _profileManager.updateProfile('', updatedProfileObject);
          _infoMessagesController.add('Тип профиля изменен. Может потребоваться ручная синхронизация или перезапуск.');


        } else if (_selectedSourceType.isGitType) {
          if (_selectedRemoteRepository != null && _selectedRemoteRepository!.id.toString() != currentProfile.repositoryId) {
            _log.info("Git repository changed for ${currentProfile.id} to ${_selectedRemoteRepository!.name}");
            await _passwordRepoService.updateGitRepositoryRemoteDetails(currentProfile.id, _selectedRemoteRepository!);
          }
        }

        _infoMessagesController.add('Профиль "${profileName.trim()}" обновлен.');

      } else { // --- ДОБАВЛЕНИЕ НОВОГО ПРОФИЛЯ ---
        _log.info("Creating new profile. Type: $_selectedSourceType");
        GitRepository? gitRepoInfoForCreate;
        String? explicitLocalFolderPathForCreate;

        if (_selectedSourceType.isGitType) {
          gitRepoInfoForCreate = _initialSelectedGitRepo;
        } else { // PasswordSourceType.localFolder
          explicitLocalFolderPathForCreate = localPath.trim();
        }

        await _passwordRepoService.createProfile(
          profileName: profileName.trim(),
          type: _selectedSourceType,
          gitProviderName: gitRepoInfoForCreate?.providerName,
          gitRepositoryInfo: gitRepoInfoForCreate,
          explicitLocalFolderPath: explicitLocalFolderPathForCreate,
          authTokens: _initialAuthTokens,
          gpgUserPassphrase: gpgKeyPassphrase!,
          generateNewGpgKey: _shouldGenerateOrReGenerateGpgKey,
          emailForGpg: gpgUserEmail?.trim(),
        );
        _infoMessagesController.add('Профиль "${profileName.trim()}" создан');
      }
      _navigationPopController.add(true);
    } catch (e, s) {
      _log.severe("Save profile error: $e", e, s);
      String errorMessage = e.toString().replaceFirst(RegExp(r".*Exception: "), "");
      _errorMessagesController.add('Ошибка сохранения профиля: $errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> startGitOAuthFlow(GitProvider provider) async {
    if (_isAuthenticatingOAuth) return;

    _isAuthenticatingOAuth = true;
    _oauthErrorMessage = null;
    _repositoryLoadingError = null;
    _remoteRepositories = null;
    _selectedRemoteRepository = null;
    notifyListeners();

    try {
      _log.info('Attempting OAuth for ${provider.toString()}');
      await _appOAuthService.authenticate(
        provider == GitProvider.github ? PasswordSourceType.github : PasswordSourceType.gitlab,
      );

      _log.info('OAuth successful for ${provider.toString()}. Tokens stored.');
      await loadRemoteRepositories(provider);

    } catch (e, s) {
      _log.severe('Error during OAuth flow for ${provider.toString()}: $e', e, s);
      String errorMessage = e.toString().replaceFirst(RegExp(r".*(Exception|Error): "), "");
      _oauthErrorMessage = 'Ошибка авторизации через ${provider.toString()}: $errorMessage';
    } finally {
      _isAuthenticatingOAuth = false;
      notifyListeners();
    }
  }

  Future<void> loadRemoteRepositories(GitProvider provider) async {
    if (_isLoadingRepositories) return;

    _isLoadingRepositories = true;
    _repositoryLoadingError = null;
    notifyListeners();

    try {
      final bool isAuthenticated = await _secureGitAuth.isAuthenticated(provider);
      if (!isAuthenticated) {
        _repositoryLoadingError = 'Необходимо авторизоваться через ${provider.toString()}.';
        _log.warning('Attempted to load repos for $provider without auth.');
        return;
      }

      final repos = await _gitApiService.getRepositories(provider);
      _remoteRepositories = repos;
      if (repos.isEmpty) {
        _infoMessagesController.add('Нет доступных репозиториев на ${provider.toString()}.');
      }
      _log.info('Loaded ${repos.length} repositories for ${provider.toString()}.');

    } on GitApiException catch (e, s) {
      _log.severe('GitApiException for ${provider.toString()}: ${e.message}', e, s);
      _repositoryLoadingError = 'Ошибка загрузки репозиториев: ${e.message}';
      if (e.statusCode == 401) {
        _repositoryLoadingError = 'Сессия истекла для ${provider.toString()}. Пожалуйста, войдите снова.';
      }
    } catch (e, s) {
      _log.severe('Error loading repositories for ${provider.toString()}: $e', e, s);
      _repositoryLoadingError = 'Произошла ошибка при загрузке репозиториев: ${e.toString()}';
    } finally {
      _isLoadingRepositories = false;
      notifyListeners();
    }
  }

  Future<void> checkAuthenticationAndLoadRepos() async {
    if (!_selectedSourceType.isGitType) {
      _remoteRepositories = null;
      _selectedRemoteRepository = null;
      _repositoryLoadingError = null;

      return;
    }

    final provider = _selectedSourceType.toGitProvider;
    if (provider == null) {
      _log.warning('Cannot determine Git provider for $_selectedSourceType');
      return;
    }

    try {
      final isAuthenticated = await _secureGitAuth.isAuthenticated(provider);

      if (isAuthenticated) {
        _log.info('User is authenticated with ${provider.toString()}. Loading repositories');
        await loadRemoteRepositories(provider);
      } else {
        _log.info('User is NOT authenticated with ${provider.toString()}.');

        _remoteRepositories = null;
        _selectedRemoteRepository = null;
        _repositoryLoadingError = null;
        notifyListeners();
      }
    } catch (e, s) {
      _log.severe("Error in checkAuthenticationAndLoadRepos for ${provider.toString()}: $e", e, s);
      _repositoryLoadingError = "Ошибка при проверке авторизации: ${e.toString()}";
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _errorMessagesController.close();
    _infoMessagesController.close();
    _navigationPopController.close();
    _requestChangeTypeConfirmationController.close();
    super.dispose();
  }
}