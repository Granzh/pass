import 'package:app_links/app_links.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:pass/services/auth_services/app_oauth_service.dart';
import 'package:pass/services/auth_services/git_auth.dart';
import 'package:pass/services/git_services/git_api_service.dart';
import 'package:pass/services/git_services/git_orchestrator.dart';
import 'package:pass/services/git_services/git_service.dart';
import 'package:pass/services/GPG_services/gpg_key_service.dart';
import 'package:pass/services/GPG_services/gpg_session_service.dart';
import 'package:pass/services/password_services/password_entry_service.dart';
import 'package:pass/services/password_repository_service.dart';
import 'package:pass/services/profile_services/repository_profile_manager.dart';
import 'package:pass/ui/screens/add_edit_password_entry_screen.dart';
import 'package:pass/ui/screens/add_edit_profile_screen.dart';
import 'package:pass/ui/view_models/add_edit_password_entry_view_model.dart';
import 'package:pass/ui/view_models/add_edit_profile_view_model.dart';
import 'package:pass/ui/view_models/password_entries_view_model.dart';
import 'package:provider/provider.dart';

import 'core/utils/enums.dart';
import 'core/utils/pgp_provider.dart';
import 'models/git_repository_model.dart';
import 'models/password_entry.dart';
import 'models/password_repository_profile.dart';
import 'ui/screens/profile_list_screen.dart';
import 'ui/view_models/profile_list_view_model.dart';

void _setupLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}');
    if (record.error != null) {
      // ignore: avoid_print
      print('ERROR: ${record.error}, STACKTRACE: ${record.stackTrace}');
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _setupLogging();

  final FlutterSecureStorage secureStorage = FlutterSecureStorage();
  DefaultPGPProvider pgpProvider = DefaultPGPProvider();
  FileSystem fileSystem = LocalFileSystem();
  Client httpClient = Client();
  AppLinks appLinks = AppLinks();

  final gpgService = GPGService(
      secureStorage: secureStorage,
      pgpProvider: pgpProvider,
      fileSystem: fileSystem
  );
  final secureGitAuth = SecureGitAuth(
      secureStorage: secureStorage,
      deviceInfo: DeviceInfoPlugin(),
  );
  final gitApiService = GitApiService(
      secureGitAuth: secureGitAuth,
      httpClient: httpClient
  );
  final gitService = GitService(
      secureStorage: secureStorage,
      fileSystem: fileSystem
  );
  final appOAuthService = AppOAuthService(
      appLinks: appLinks,
      secureGitAuth: secureGitAuth
  );
  final profileManager = RepositoryProfileManager(
      secureStorage: secureStorage
  );
  final entryService = PasswordEntryService(
      gitService: gitService,
      profileManager: profileManager,
      gpgService: gpgService
  );

  final gitOrchestrator = GitOrchestrator(
    gitService: gitService,
    profileManager: profileManager,
  );

  final passwordRepoService = PasswordRepositoryService(
    gpgService: gpgService,
    profileManager: profileManager,
    entryService: entryService,
    gitOrchestrator: gitOrchestrator,
    secureStorage: secureStorage,
  );

  final gpgSessionService = GPGSessionService();



  runApp(MyApp(
    secureGitAuth: secureGitAuth,
    passwordRepositoryService: passwordRepoService,
    gpgService: gpgService,
    gpgSessionService: gpgSessionService,
    profileManager: profileManager,
    gitApiService: gitApiService,
    appOAuthService: appOAuthService,
  ));
}

class MyApp extends StatelessWidget {
  final PasswordRepositoryService passwordRepositoryService;
  final GPGService gpgService;
  final GPGSessionService gpgSessionService;
  final RepositoryProfileManager profileManager;
  final GitApiService gitApiService;
  final AppOAuthService appOAuthService;
  final SecureGitAuth secureGitAuth;

  const MyApp({
    super.key,
    required this.secureGitAuth,
    required this.passwordRepositoryService,
    required this.gpgService,
    required this.gpgSessionService,
    required this.profileManager,
    required this.gitApiService,
    required this.appOAuthService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SecureGitAuth>.value(value: secureGitAuth),
        Provider<PasswordRepositoryService>.value(value: passwordRepositoryService),
        Provider<GPGService>.value(value: gpgService),
        ChangeNotifierProvider<GPGSessionService>.value(value: gpgSessionService), // GPGSessionService - ChangeNotifier
        Provider<RepositoryProfileManager>.value(value: profileManager),
        Provider<GitApiService>.value(value: gitApiService),
        Provider<AppOAuthService>.value(value: appOAuthService),

        ChangeNotifierProvider<ProfileListViewModel>(
          create: (_) => ProfileListViewModel(passwordRepoService: passwordRepositoryService),
        ),
        ChangeNotifierProvider<PasswordEntriesViewModel>(
          create: (_) => PasswordEntriesViewModel(
            passwordRepoService: passwordRepositoryService,
            gpgSessionService: gpgSessionService,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Password Manager',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: ProfileListScreen(),
        onGenerateRoute: (settings) {
          if (settings.name == AddEditProfileScreen.routeName) {
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              builder: (context) {
                return ChangeNotifierProvider<AddEditProfileViewModel>(
                  create: (ctx) => AddEditProfileViewModel(
                    secureGitAuth: Provider.of<SecureGitAuth>(ctx, listen: false),
                    passwordRepoService: Provider.of<PasswordRepositoryService>(ctx, listen: false),
                    gpgService: Provider.of<GPGService>(ctx, listen: false),
                    profileManager: Provider.of<RepositoryProfileManager>(ctx, listen: false),
                    gitApiService: Provider.of<GitApiService>(ctx, listen: false),
                    appOAuthService: Provider.of<AppOAuthService>(ctx, listen: false),
                    existingProfile: args?['profileToEdit'] as PasswordRepositoryProfile?,
                    initialSourceType: args?['initialSourceType'] as PasswordSourceType?,
                    initialAuthTokens: args?['initialAuthTokens'] as Map<String, String>?,
                    initialSelectedGitRepo: args?['initialSelectedGitRepo'] as GitRepository?,
                  ),
                  child: AddEditProfileScreen(),
                );
              },
            );
          }
          if (settings.name == AddEditPasswordEntryScreen.routeName) {
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (context) {
                return ChangeNotifierProvider<AddEditPasswordEntryViewModel>(
                  create: (ctx) => AddEditPasswordEntryViewModel(
                    passwordRepoService: Provider.of<PasswordRepositoryService>(ctx, listen: false),
                    gpgSessionService: Provider.of<GPGSessionService>(ctx, listen: false),
                    profileId: args['profileId'] as String,
                    entryToEdit: args['entryToEdit'] as PasswordEntry?,
                  ),
                  child: AddEditPasswordEntryScreen(
                    profileId: args['profileId'] as String,
                    entryToEdit: args['entryToEdit'] as PasswordEntry?,
                  ),
                );
              },
            );
          }
          return MaterialPageRoute(builder: (_) => ProfileListScreen());
        },
      ),
    );
  }
}