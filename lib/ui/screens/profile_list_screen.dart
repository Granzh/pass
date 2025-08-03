// lib/ui/screens/profile_list_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/enums.dart';
import '../../models/password_repository_profile.dart';
import '../view_models/profile_list_view_model.dart';
import 'add_edit_profile_screen.dart'; // Или ваш выбранный state management
// import 'add_edit_profile_screen.dart';

class ProfileListScreen extends StatefulWidget {
  const ProfileListScreen({super.key});

  @override
  State<ProfileListScreen> createState() => _ProfileListScreenState();
}

class _ProfileListScreenState extends State<ProfileListScreen> {
  late ProfileListViewModel _viewModel;
  StreamSubscription? _navSubscription;
  StreamSubscription? _infoSubscription;

  @override
  void initState() {
    super.initState();
    // ViewModel будет создан через Provider в build методе
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel = Provider.of<ProfileListViewModel>(context, listen: false); // Получаем VM
    // listen:false потому что Consumer будет слушать изменения

    _navSubscription?.cancel();
    _navSubscription = _viewModel.navigationEvents.listen((event) {
      if (!mounted) return;
      if (event.destination == PasswordListNavigation.toAddProfile) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const AddEditProfileScreen(), // Передаем нужные параметры, если есть
        )).then((_) => _viewModel.refreshProfiles()); // Обновляем список после возврата
      } else if (event.destination == PasswordListNavigation.toEditProfile && event.profileToEdit != null) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AddEditProfileScreen(existingProfile: event.profileToEdit),
        )).then((_) => _viewModel.refreshProfiles()); // Обновляем список после возврата
      }
      // else if (event.destination == ProfileListNavigation.toPasswordList) {
      // TODO: Навигация на экран списка паролей для активного профиля
      //   Navigator.of(context).push(MaterialPageRoute(builder: (_) => PasswordEntriesScreen()));
      // }
    });

    _infoSubscription?.cancel();
    _infoSubscription = _viewModel.infoMessages.listen((message) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    });
  }


  @override
  void dispose() {
    _navSubscription?.cancel();
    _infoSubscription?.cancel();
    // ViewModel не dispose'ится здесь, если он предоставлен через Provider выше по дереву
    // и его жизненный цикл дольше, чем у этого экрана.
    // Если ViewModel создается специально для этого экрана и больше нигде не нужен,
    // то можно было бы его здесь dispose'ить.
    super.dispose();
  }

  void _showDeleteConfirmationDialog(PasswordRepositoryProfile profile) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        bool deleteLocalData = true; // По умолчанию
        return StatefulBuilder( // Для обновления чекбокса внутри диалога
            builder: (context, setStateDialog) {
              return AlertDialog(
                title: Text('Удалить профиль "${profile.profileName}"?'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Это действие необратимо.'),
                    if (profile.isGitType() || profile.type == PasswordSourceType.localFolder)
                      CheckboxListTile(
                        title: const Text("Удалить локальные данные"),
                        value: deleteLocalData,
                        onChanged: (bool? value) {
                          setStateDialog(() {
                            deleteLocalData = value ?? true;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    child: const Text('Отмена'),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Удалить'),
                    onPressed: () async {
                      Navigator.of(dialogContext).pop(); // Закрываем диалог
                      await _viewModel.deleteProfile(profile.id, deleteLocalData: deleteLocalData);
                      // Сообщение об успехе/ошибке придет через _infoSubscription или будет в _viewModel.errorMessage
                    },
                  ),
                ],
              );
            }
        );
      },
    );
  }

  void _showProfileActions(PasswordRepositoryProfile profile) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Редактировать'),
                onTap: () {
                  Navigator.of(context).pop(); // Закрыть bottom sheet
                  _viewModel.navigateToEditProfile(profile);
                },
              ),
              // if (profile.isGitType) // Опция синхронизации только для Git-типов
              // ListTile(
              //   leading: Icon(Icons.sync_outlined),
              //   title: Text('Синхронизировать'),
              //   onTap: () {
              //     Navigator.of(context).pop();
              //     // _viewModel.syncProfile(profile.id); // TODO: Реализовать
              //      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Синхронизация для ${profile.profileName} еще не реализована')));
              //   },
              // ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Удалить', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.of(context).pop(); // Закрыть bottom sheet
                  _showDeleteConfirmationDialog(profile);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профили Хранилищ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить список',
            onPressed: () => _viewModel.refreshProfiles(),
          ),
        ],
      ),
      body: Consumer<ProfileListViewModel>( // Используем Consumer для перестройки UI
        builder: (context, vm, child) {
          if (vm.isLoading && vm.profiles.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (vm.errorMessage != null && vm.profiles.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Ошибка: ${vm.errorMessage}', style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    ElevatedButton(onPressed: () => vm.refreshProfiles(), child: const Text('Попробовать снова'))
                  ],
                ),
              ),
            );
          }

          if (vm.profiles.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Профили не найдены.', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text('Нажмите "+", чтобы добавить новый профиль.'),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text("Добавить профиль"),
                    onPressed: () => vm.navigateToAddProfile(),
                  )
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: vm.profiles.length,
            itemBuilder: (context, index) {
              final profile = vm.profiles[index];
              final bool isActive = vm.activeProfileId == profile.id;

              IconData typeIcon;
              switch (profile.type) {
                case PasswordSourceType.github:
                  typeIcon = Icons.code; // TODO: Найти подходящую иконку GitHub
                  break;
                case PasswordSourceType.gitlab:
                  typeIcon = Icons.code_off; // TODO: Найти подходящую иконку GitLab
                  break;
                case PasswordSourceType.localFolder:
                  typeIcon = Icons.folder_outlined;
                  break;
                default:
                  typeIcon = Icons.storage_outlined;
              }

              return Card(
                elevation: isActive ? 4.0 : 1.0,
                shape: isActive
                    ? RoundedRectangleBorder(
                  side: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                  borderRadius: BorderRadius.circular(8),
                )
                    : RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isActive ? Theme.of(context).primaryColor.withAlpha(51) : Colors.grey.shade200,
                    child: Icon(typeIcon, color: isActive ? Theme.of(context).primaryColor : Colors.grey.shade700),
                  ),
                  title: Text(profile.profileName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    profile.isGitType()
                        ? (profile.repositoryCloneUrl ?? profile.repositoryFullName)
                        : profile.repositoryFullName,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert_outlined),
                    tooltip: 'Действия',
                    onPressed: () => _showProfileActions(profile),
                  ),
                  onTap: () {
                    // При нажатии делаем профиль активным
                    // И в будущем можно сразу переходить к списку паролей этого профиля
                    vm.setActiveProfile(profile.id);
                  },
                  onLongPress: () => _showProfileActions(profile),
                  selected: isActive,
                  selectedTileColor: Theme.of(context).primaryColor.withAlpha(13),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _viewModel.navigateToAddProfile(),
        tooltip: 'Добавить профиль',
        child: const Icon(Icons.add),
      ),
    );
  }
}