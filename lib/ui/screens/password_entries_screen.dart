import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import '../../core/utils/enums.dart';
import '../../models/password_entry.dart';
import '../view_models/password_entries_view_model.dart';

class PasswordEntriesScreen extends StatefulWidget {
  const PasswordEntriesScreen({super.key});

  static const String routeName = '/password-entries';

  @override
  State<PasswordEntriesScreen> createState() => _PasswordEntriesScreenState();
}

class _PasswordEntriesScreenState extends State<PasswordEntriesScreen> {
  final _passphraseController = TextEditingController();
  final _searchController = TextEditingController();
  late PasswordEntriesViewModel _viewModel;
  static final _log = Logger('PasswordEntriesScreen');

  @override
  void initState() {
    super.initState();

    _viewModel = Provider.of<PasswordEntriesViewModel>(context, listen: false);

    _viewModel.navigationEvents.listen((event) {
      if (!mounted) return;
      if (event.destination == PasswordEntriesNavigation.toAddEntry) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => AddEditPasswordEntryScreen(profileId: _viewModel.currentActiveProfile!.id),
        ));
      } else if (event.destination == PasswordEntriesNavigation.toEditEntry && event.entryToEdit != null) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => AddEditPasswordEntryScreen(
            profileId: _viewModel.currentActiveProfile!.id,
            entryToEdit: event.entryToEdit,
          ),
        ));
      }
    }).onError((error) {
      _log.severe('Error in navigation stream: $error');
    });

    _viewModel.infoMessages.listen((message) {
      if (mounted && message.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }).onError((error) {
      _log.severe('Error in info message stream: $error');
    });

    if (_viewModel.searchQuery.isNotEmpty) {
      _searchController.text = _viewModel.searchQuery;
    }
    _searchController.addListener(() {
      _viewModel.updateSearchQuery(_searchController.text);
    });

    // Первоначальная загрузка записей, если профиль уже активен
    // ViewModel сама должна это делать при инициализации или смене профиля,
    // но на всякий случай, если экран создается и ViewModel уже имеет активный профиль.
    // Если ViewModel.loadEntries() уже вызывается при _onActiveProfileChanged, это может быть излишне.
    // Убедитесь, что нет двойного вызова.
    // if (_viewModel.currentActiveProfile != null && _viewModel.entries.isEmpty && !_viewModel.isLoading) {
    //   _viewModel.loadEntries(); // Это может запросить пароль, если он нужен и не был введен
    // }
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    _searchController.dispose();
    // Подписки на стримы (_viewModel.navigationEvents и _viewModel.infoMessages)
    // будут автоматически закрыты, когда ViewModel будет disposed, если они StreamController.broadcast()
    // или если вы их тут отмените вручную, если это необходимо (например, если это не broadcast стримы).
    // viewModel сама должна управлять закрытием своих StreamController в своем dispose().
    super.dispose();
  }

  void _submitPassphrase() {
    if (_passphraseController.text.isNotEmpty) {
      _viewModel.loadEntries(gpgPassphrase: _passphraseController.text);
      _passphraseController.clear(); // Очищаем поле после отправки
    } else {
      // Можно показать сообщение, что поле пароля не должно быть пустым
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Passphrase cannot be empty.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Используем Consumer для перестроения UI при изменении ViewModel
    return Consumer<PasswordEntriesViewModel>(
      builder: (context, viewModel, child) {
        // Сохраняем ссылку на viewModel, чтобы не писать viewModel. везде
        // _viewModel = viewModel; // Уже инициализировали в initState

        return Scaffold(
          appBar: AppBar(
            title: Text(viewModel.currentActiveProfile?.profileName ?? "Entries"),
            bottom: PreferredSize( // Для поля поиска
              preferredSize: const Size.fromHeight(kToolbarHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Search entries...",
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor.withAlpha(200),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        viewModel.updateSearchQuery('');
                      },
                    )
                        : null,
                  ),
                  // onChanged: (query) => viewModel.updateSearchQuery(query), // Уже через addListener
                ),
              ),
            ),
          ),
          body: _buildBody(viewModel),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              viewModel.navigateToAddEntry();
            },
            tooltip: "Add new entry",
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  Widget _buildBody(PasswordEntriesViewModel viewModel) {
    if (viewModel.isLoading && viewModel.entries.isEmpty && !viewModel.needsGpgPassphrase) {
      // Показываем главный индикатор загрузки только если список пуст и это не запрос пароля
      return const Center(child: CircularProgressIndicator());
    }

    if (viewModel.needsGpgPassphrase) {
      return _buildPassphraseInput(viewModel);
    }

    if (viewModel.errorMessage != null && !viewModel.needsGpgPassphrase) {
      // Показываем ошибку, если это не ошибка "нужен пароль" (она обрабатывается _buildPassphraseInput)
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                viewModel.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => viewModel.loadEntries(), // Попытаться загрузить снова (может снова запросить пароль)
                child: const Text("Retry"),
              )
            ],
          ),
        ),
      );
    }

    if (viewModel.filteredEntries.isEmpty && _searchController.text.isNotEmpty) {
      return const Center(
        child: Text("No entries found matching your search.", style: TextStyle(fontSize: 16)),
      );
    }

    if (viewModel.filteredEntries.isEmpty && _searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_encryption_gmailerrorred_outlined, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              "No password entries found.",
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              "Tap the '+' button to add your first entry.",
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (viewModel.currentActiveProfile != null) // Предлагаем обновить, если вдруг что-то не так
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text("Refresh"),
                onPressed: () => viewModel.loadEntries(),
              ),
          ],
        ),
      );
    }

    // Отображение списка записей
    return RefreshIndicator(
      onRefresh: () async {
        // Принудительное обновление. Это может снова запросить парольную фразу,
        // если ViewModel её не кэширует.
        await viewModel.loadEntries();
      },
      child: ListView.builder(
        itemCount: viewModel.filteredEntries.length,
        itemBuilder: (context, index) {
          final entry = viewModel.filteredEntries[index];
          return Card( // Используем Card для лучшего визуального разделения
            margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: ListTile(
              title: Text(entry.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.username != null && entry.username!.isNotEmpty)
                    Text("Username: ${entry.username!}"),
                  if (entry.url != null && entry.url!.isNotEmpty)
                    Text("URL: ${entry.url!}", overflow: TextOverflow.ellipsis),
                  Text(entry.path, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: "Copy password",
                    onPressed: () {
                      viewModel.copyToClipboard(entry.password, "'${entry.name}' password");
                    },
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'edit') {
                        viewModel.navigateToEditEntry(entry);
                      } else if (value == 'delete') {
                        _showDeleteConfirmationDialog(entry);
                      } else if (value == 'copy_username' && entry.username != null) {
                        viewModel.copyToClipboard(entry.username!, "'${entry.name}' username");
                      } else if (value == 'copy_url' && entry.url != null) {
                        viewModel.copyToClipboard(entry.url!, "'${entry.name}' URL");
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: ListTile(leading: Icon(Icons.edit), title: Text('Edit')),
                      ),
                      if (entry.username != null && entry.username!.isNotEmpty)
                        const PopupMenuItem<String>(
                          value: 'copy_username',
                          child: ListTile(leading: Icon(Icons.person), title: Text('Copy Username')),
                        ),
                      if (entry.url != null && entry.url!.isNotEmpty)
                        const PopupMenuItem<String>(
                          value: 'copy_url',
                          child: ListTile(leading: Icon(Icons.link), title: Text('Copy URL')),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red))),
                      ),
                    ],
                  ),
                ],
              ),
              onTap: () {
                // Можно сделать главным действием по тапу копирование пароля
                // или переход к деталям/редактированию, если это более приоритетно
                viewModel.copyToClipboard(entry.password, "'${entry.name}' password");
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildPassphraseInput(PasswordEntriesViewModel viewModel) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            "GPG Passphrase Required",
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            "Profile '${viewModel.currentActiveProfile?.profileName ?? 'current'}' is protected. Please enter the GPG passphrase to unlock.",
            textAlign: TextAlign.center,
          ),
          if (viewModel.errorMessage != null && viewModel.errorMessage!.contains("passphrase")) // Показываем ошибку только если она про пароль
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                viewModel.errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: _passphraseController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: "GPG Passphrase",
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submitPassphrase(),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _submitPassphrase,
            child: const Text("Unlock Profile"),
          ),
          // Можно добавить кнопку "Отмена" или "Сменить профиль"
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirmationDialog(PasswordEntry entry) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Are you sure you want to delete the entry "${entry.name}"?'),
                const Text('This action cannot be undone.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Закрыть диалог
                _viewModel.deleteEntry(entry);    // Вызвать удаление
              },
            ),
          ],
        );
      },
    );
  }
}

// Заглушка для AddEditPasswordEntryScreen, замените на ваш реальный экран
class AddEditPasswordEntryScreen extends StatelessWidget {
  final String profileId;
  final PasswordEntry? entryToEdit;

  const AddEditPasswordEntryScreen({
    super.key,
    required this.profileId,
    this.entryToEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(entryToEdit == null ? "Add New Entry" : "Edit Entry"),
      ),
      body: Center(
        child: Text(
            "${entryToEdit == null ? "Add" : "Edit"} screen for profile $profileId\nEntry to edit: ${entryToEdit?.name ?? 'None'}"),
      ),
    );
  }
}