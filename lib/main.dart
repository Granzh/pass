import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:pass/services/auth_services/app_oauth_service.dart';
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
import 'models/git_repository_model.dart';
import 'models/password_entry.dart';
import 'models/password_repository_profile.dart';
import 'ui/screens/profile_list_screen.dart';
import 'ui/view_models/profile_list_view_model.dart';

void _setupLogging() {
  Logger.root.level = Level.ALL; // Установите нужный уровень логирования
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
  WidgetsFlutterBinding.ensureInitialized(); // Обязательно для асинхронных операций до runApp
  _setupLogging();

  final gpgService = GPGService();
  final gitApiService = GitApiService();
  final appOAuthService = AppOAuthService();
  final profileManager = RepositoryProfileManager();
  final entryService = PasswordEntryService();
  final gitService = GitService();

  final gitOrchestrator = GitOrchestrator(
    gitService: gitService,
    profileManager: profileManager,
  );

  // PasswordRepositoryService может зависеть от других сервисов
  final passwordRepoService = PasswordRepositoryService(
    gpgService: gpgService,
    profileManager: profileManager,
    entryService: entryService,
    gitOrchestrator: gitOrchestrator,
    secureStorage: secureStorage,
  );

  final gpgSessionService = GPGSessionService();



  runApp(MyApp(
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

  const MyApp({
    super.key,
    required this.passwordRepositoryService,
    required this.gpgService,
    required this.gpgSessionService,
    required this.profileManager,
    required this.gitApiService,
    required this.appOAuthService,
  });

  @override
  Widget build(BuildContext context) {
    // MultiProvider используется для предоставления нескольких сервисов/объектов
    // вниз по дереву виджетов.
    return MultiProvider(
      providers: [
        // Предоставляем основные сервисы, которые могут понадобиться в разных частях приложения
        Provider<PasswordRepositoryService>.value(value: passwordRepositoryService),
        Provider<GPGService>.value(value: gpgService),
        ChangeNotifierProvider<GPGSessionService>.value(value: gpgSessionService), // GPGSessionService - ChangeNotifier
        Provider<RepositoryProfileManager>.value(value: profileManager),
        Provider<GitApiService>.value(value: gitApiService),
        Provider<AppOAuthService>.value(value: appOAuthService),

        // ViewModel для экранов верхнего уровня можно предоставить здесь,
        // или создавать их непосредственно на самих экранах, если они не нужны до этого.
        // Для ProfileListViewModel и PasswordEntriesViewModel это может быть уместно здесь,
        // так как они управляют основными данными приложения.
        ChangeNotifierProvider<ProfileListViewModel>(
          create: (_) => ProfileListViewModel(passwordRepoService: passwordRepositoryService),
        ),
        ChangeNotifierProvider<PasswordEntriesViewModel>(
          create: (_) => PasswordEntriesViewModel(
            passwordRepoService: passwordRepositoryService,
            gpgSessionService: gpgSessionService, // Передаем GPGSessionService
          ),
        ),
        // AddEditProfileViewModel и AddEditPasswordEntryViewModel обычно создаются
        // на своих экранах, так как они специфичны для контекста (редактирование конкретного элемента)
        // и часто требуют параметры в конструкторе (например, ID редактируемого элемента).
      ],
      child: MaterialApp(
        title: 'Password Manager', // Замените на ваше название
        theme: ThemeData( // Настройте вашу тему
          primarySwatch: Colors.blue,
          // visualDensity: VisualDensity.adaptivePlatformDensity, // Для адаптивного UI
        ),
        // Начальный экран вашего приложения
        home: ProfileListScreen(), // Или другой начальный экран
        // Вы можете определить именованные маршруты здесь для навигации
        // routes: {
        //   '/profileList': (context) => ProfileListScreen(),
        //   '/passwordEntries': (context) => PasswordEntriesScreen(),
        //   // Для экранов добавления/редактирования часто используется Navigator.push с передачей аргументов,
        //   // а не именованные маршруты, так как им нужны данные.
        // },
        // onGenerateRoute можно использовать для более сложной логики маршрутизации,
        // особенно если нужно передавать аргументы на экраны Add/Edit.
        onGenerateRoute: (settings) {
          // Логика для создания маршрутов, особенно для передачи аргументов
          // Например, для AddEditProfileScreen:
          if (settings.name == AddEditProfileScreen.routeName) {
            final args = settings.arguments as Map<String, dynamic>?; // Пример аргументов
            return MaterialPageRoute(
              builder: (context) {
                // AddEditProfileViewModel создается ЗДЕСЬ, получая зависимости из Provider
                return ChangeNotifierProvider<AddEditProfileViewModel>(
                  create: (ctx) => AddEditProfileViewModel(
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
          // Аналогично для AddEditPasswordEntryScreen
          if (settings.name == AddEditPasswordEntryScreen.routeName) {
            final args = settings.arguments as Map<String, dynamic>; // Предполагаем, что аргументы всегда есть
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
                    // Если экран принимает параметры напрямую, передайте их
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