// lib/ui/screens/profile_list_screen.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pass/ui/screens/password_list_screen.dart';
import 'package:provider/provider.dart';

import '../../models/password_repository_profile.dart';
import '../../services/password_repository_service.dart';
import 'add_edit_profile_screen.dart'; // Или ваш выбранный state management
// Импортируйте экран добавления профиля, когда он будет создан
// import 'add_edit_profile_screen.dart';

class ProfileListScreen extends StatefulWidget {
  const ProfileListScreen({super.key});

  @override
  State<ProfileListScreen> createState() => _ProfileListScreenState();
}

class _ProfileListScreenState extends State<ProfileListScreen> {
  Future<String?> _showPassphraseDialog() async {
    // Теперь context доступен из State (this.context)
    if (!mounted) return null; // Проверка перед использованием context в showDialog
    return await showDialog<String>(
      context: context, // Используем this.context
      builder: (BuildContext dialogContext) { // Используем новый dialogContext для билдера диалога
        TextEditingController controller = TextEditingController();
        return AlertDialog(
          title: const Text('Enter passphrase'), // ... (заголовок)
          content: TextField( // ... (содержимое)
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(hintText: "Passphrase for GPG"),
          ),
          actions: <Widget>[ // ... (действия)
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(), // Используем dialogContext
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(dialogContext).pop(controller.text), // Используем dialogContext
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showDeleteConfirmationDialog(String profileName) async {
    if (!mounted) return null;
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Sure?'),
          content: Text('Are you sure you want to delete "$profileName"? All data and GPG keys will be lost!'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showAddProfileSourceSelectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) { // Важно использовать context из builder для Navigator.pop
        return SimpleDialog(
          title: const Text('Выберите источник хранилища'),
          children: <Widget>[
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext); // Закрываем диалог
                _navigateToOAuthFlow(context, PasswordSourceType.github); // Передаем context от ProfileListScreen
              },
              child: const ListTile(
                leading: Icon(Icons.code), // Замените на иконку GitHub
                title: Text('GitHub'),
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext);
                _navigateToOAuthFlow(context, PasswordSourceType.gitlab);
              },
              child: const ListTile(
                leading: Icon(Icons.code_off), // Замените на иконку GitLab
                title: Text('GitLab'),
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext);
                _pickLocalFolder(context);
              },
              child: const ListTile(
                leading: Icon(Icons.folder_open),
                title: Text('Локальная папка'),
              ),
            ),
          ],
        );
      },
    );
  }

  void _navigateToOAuthFlow(BuildContext pageContext, PasswordSourceType type) async {
    // Здесь будет логика OAuth 2.0
    print('Запускаем OAuth для: ${type.name}');
    // После успешного OAuth и выбора репозитория, мы получим URL репозитория и токен.
    // Затем перейдем на AddEditProfileScreen с предзаполненными данными.

    // --- ЭТО ЗАГЛУШКА ---
    // В реальности здесь будет сложный асинхронный процесс
    String? fakeRepoUrl;
    Map<String, String>? fakeAuthTokens; // access_token, refresh_token

    if (type == PasswordSourceType.github) {
      // Имитация успешного OAuth
      await Future.delayed(const Duration(seconds: 1)); // Имитация задержки сети
      fakeRepoUrl = "https://github.com/user/test-repo.git";
      fakeAuthTokens = {"access_token": "fake_github_access_token", "refresh_token": "fake_github_refresh_token"};
      print('OAuth для GitHub ЗАВЕРШЕН (имитация). Репозиторий: $fakeRepoUrl');
    } else if (type == PasswordSourceType.gitlab) {
      await Future.delayed(const Duration(seconds: 1));
      fakeRepoUrl = "https://gitlab.com/user/another-repo.git";
      fakeAuthTokens = {"access_token": "fake_gitlab_access_token", "refresh_token": "fake_gitlab_refresh_token"};
      print('OAuth для GitLab ЗАВЕРШЕН (имитация). Репозиторий: $fakeRepoUrl');
    }

    if (fakeRepoUrl != null && fakeAuthTokens != null) {
      if (!pageContext.mounted) return;
      // Переход на AddEditProfileScreen с предзаполненными данными
      Navigator.push(
        pageContext,
        MaterialPageRoute(
          builder: (context) => AddEditProfileScreen(
            // Мы не передаем existingProfile, т.к. это новый профиль
            initialSourceType: type,
            initialRepoUrl: fakeRepoUrl,
            initialAuthTokens: fakeAuthTokens,
            // Можно также передать имя репозитория для предзаполнения имени профиля
            // initialProfileName: "My ${type.name} Passwords",
          ),
        ),
      ).then((value) {
        if (value == true) { // Если AddEditProfileScreen вернул true (успешное сохранение)
          // Обновите список профилей в ProfileListScreen
          // Например, вызвав метод загрузки профилей
          // _loadProfiles();
        }
      });
    } else {
      // Обработка ошибки OAuth или отмены пользователем
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(content: Text('Не удалось подключиться к ${type.name} или процесс был отменен.')),
      );
    }
  }

  void _pickLocalFolder(BuildContext pageContext) async {
    print('Выбираем локальную папку');
    String? selectedDirectory;

    // --- Используем file_picker для выбора директории ---
    // Убедитесь, что `file_picker` добавлен в pubspec.yaml
    // dependencies:
    //   file_picker: ^latest_version
    try {
      selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Выберите папку для хранения паролей',
      );
    } catch (e) {
      print('Ошибка при выборе папки: $e');
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(content: Text('Ошибка при выборе папки: $e')),
      );
      return;
    }


    if (selectedDirectory != null) {
      print('Выбрана папка: $selectedDirectory');
      if (!pageContext.mounted) return;
      // Переход на AddEditProfileScreen с предзаполненными данными
      Navigator.push(
        pageContext,
        MaterialPageRoute(
          builder: (context) => AddEditProfileScreen(
            initialSourceType: PasswordSourceType.localFolder,
            initialRepoUrl: selectedDirectory, // Для LocalFolder URL это путь
            // initialProfileName: "Мои локальные пароли",
          ),
        ),
      ).then((value) {
        if (value == true) {
          // Обновите список профилей
          // _loadProfiles();
        }
      });
    } else {
      // Пользователь отменил выбор папки
      print('Выбор папки отменен');
    }
  }

  @override
  Widget build(BuildContext context) {
    final passwordRepoService = Provider.of<PasswordRepositoryService>(context, listen: false);

    return Scaffold(
      appBar: AppBar( actions: [
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Add profile',
          onPressed: () {
            _showAddProfileSourceSelectionDialog(context);
          },
        ),
      ]),
      body: StreamBuilder<List<PasswordRepositoryProfile>>(
        stream: passwordRepoService.profilesStream,
        initialData: passwordRepoService.getProfiles(),
        builder: (context, snapshot) {
          // ... (логика StreamBuilder) ...
          final profiles = snapshot.data!;
          // ...

          return ListView.builder(
            itemCount: profiles.length,
            itemBuilder: (context, index) {
              final profile = profiles[index];
              // ...
              return ListTile(
                // ...
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.settings_remote, color: Colors.blue),
                      tooltip: 'Synchronize profile',
                      onPressed: () async {
                        // Сохраняем ссылку на ScaffoldMessenger ДО await
                        final scaffoldMessenger = ScaffoldMessenger.of(this.context); // Используем this.context из State
                        String? passphrase;
                        if (profile.type != PasswordSourceType.localFolder) {
                          passphrase = await _showPassphraseDialog(); // Вызываем метод стейта
                          if (passphrase == null) return;
                        }
                        try {
                          await passwordRepoService.syncRepository(profile.id, passphrase ?? "");
                          if (!mounted) return; // Проверка после await
                          scaffoldMessenger.showSnackBar(
                            SnackBar(content: Text('Profile ${profile.profileName} synchronized')),
                          );
                        } catch (e) {
                          if (!mounted) return; // Проверка после await
                          scaffoldMessenger.showSnackBar(
                            SnackBar(content: Text('Synchronization error: $e'), backgroundColor: Colors.red),
                          );
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'Delete profile',
                      onPressed: () async {
                        final scaffoldMessenger = ScaffoldMessenger.of(this.context);
                        final confirmed = await _showDeleteConfirmationDialog(profile.profileName);
                        if (confirmed == true) {
                          try {
                            await passwordRepoService.removeRepository(profile.id);
                            if (!mounted) return;
                            scaffoldMessenger.showSnackBar(
                              SnackBar(content: Text('Profile ${profile.profileName} deleted')),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            scaffoldMessenger.showSnackBar(
                              SnackBar(content: Text('Error deleting profile: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
                onTap: () async {
                  final passwordRepoService = Provider.of<PasswordRepositoryService>(context, listen: false);
                  final bool alreadyActive = passwordRepoService.getActiveProfile()?.id == profile.id;
                  if (!alreadyActive) {
                    await passwordRepoService.setActiveProfile(profile.id);
                  }

                  String? gpgPassphrase;

                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PasswordListScreen(profileId: profile.id),
                    ),
                  );
                  // Для setActiveProfile обычно не нужен context после await,
                  // так как StreamBuilder сам перерисуется.
                  // Но если бы тут была навигация, то понадобилась бы проверка mounted.
                  // ...
                },
              );
            },
          );
        },
      ),
    );
  }
}