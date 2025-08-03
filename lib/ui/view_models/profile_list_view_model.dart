import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:logging/logging.dart';

import '../../core/utils/enums.dart';
import '../../models/password_repository_profile.dart';
import '../../services/password_repository_service.dart';

class ProfileListNavigationEvent {
  final PasswordListNavigation destination;
  final PasswordRepositoryProfile? profileToEdit;

  ProfileListNavigationEvent(this.destination, {this.profileToEdit});
}

class ProfileListViewModel extends ChangeNotifier {
  final PasswordRepositoryService _passwordRepoService;
  static final _log = Logger('ProfileListViewModel');

  ProfileListViewModel({required PasswordRepositoryService passwordRepoService})
      : _passwordRepoService = passwordRepoService {
    _log.info("ProfileListViewModel created.");
    _loadProfiles();
    _profilesSubscription = _passwordRepoService.profilesStream.listen(
            (profiles) {
          _log.info("Received updated profiles list with ${profiles.length} items.");
          _profiles = profiles;
          _isLoading = false;
          notifyListeners();
        },
        onError: (error) {
          _log.severe("Error in profiles stream: $error");
          _errorMessage = "Ошибка загрузки списка профилей: $error";
          _isLoading = false;
          notifyListeners();
        }
    );
  }

  StreamSubscription<List<PasswordRepositoryProfile>>? _profilesSubscription;

  List<PasswordRepositoryProfile> _profiles = [];
  List<PasswordRepositoryProfile> get profiles => _profiles;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _activeProfileId;
  String? get activeProfileId => _activeProfileId;

  final StreamController<ProfileListNavigationEvent> _navigationController = StreamController.broadcast();
  Stream<ProfileListNavigationEvent> get navigationEvents => _navigationController.stream;

  final StreamController<String> _infoMessageController = StreamController.broadcast();
  Stream<String> get infoMessages => _infoMessageController.stream;


  Future<void> _loadProfiles() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _passwordRepoService.loadProfiles();
      _log.info("Initial profiles load initiated.");
    } catch (e) {
      _log.severe("Failed to load profiles: $e");
      _errorMessage = "Не удалось загрузить профили: $e";
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshProfiles() async {
    _log.info("Refreshing profiles list...");
    await _loadProfiles();
  }

  Future<void> setActiveProfile(String profileId) async {
    _log.info("Attempting to set active profile: $profileId");
    if (_activeProfileId == profileId) {
      _log.info("Profile $profileId is already active.");
      return;
    }
    try {
      _activeProfileId = profileId;
      _log.info("Profile $profileId set as active.");
      _infoMessageController.add("Профиль '${_profiles.firstWhere((p) => p.id == profileId).profileName}' активирован.");
      notifyListeners();
    } catch (e) {
      _log.severe("Failed to set active profile $profileId: $e");
      _errorMessage = "Ошибка активации профиля: $e";
      notifyListeners();
    }
  }

  Future<bool> deleteProfile(String profileId, {bool deleteLocalData = true}) async {
    _log.info("Attempting to delete profile: $profileId with local data: $deleteLocalData");
    final profileName = _profiles.firstWhere((p) => p.id == profileId, orElse: () => PasswordRepositoryProfile.empty()).profileName;
    try {
      await _passwordRepoService.deleteProfile(profileId, deleteLocalData: deleteLocalData);
      _log.info("Profile $profileId deleted successfully.");
      _infoMessageController.add("Профиль '$profileName' удален.");
      return true;
    } catch (e) {
      _log.severe("Failed to delete profile $profileId: $e");
      _errorMessage = "Ошибка удаления профиля '$profileName': $e";
      notifyListeners();
      return false;
    }
  }

  void navigateToAddProfile() {
    _log.info("Navigating to AddProfile screen.");
    _navigationController.add(ProfileListNavigationEvent(PasswordListNavigation.toAddProfile));
  }

  void navigateToEditProfile(PasswordRepositoryProfile profile) {
    _log.info("Navigating to EditProfile screen for profile: ${profile.id}");
    _navigationController.add(ProfileListNavigationEvent(PasswordListNavigation.toEditProfile, profileToEdit: profile));
  }


  @override
  void dispose() {
    _log.info("ProfileListViewModel disposed.");
    _profilesSubscription?.cancel();
    _navigationController.close();
    _infoMessageController.close();
    super.dispose();
  }
}