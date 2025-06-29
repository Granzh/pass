import 'package:flutter/material.dart';

import 'package:pass/models/password_repository_profile.dart';
import 'package:provider/provider.dart';

import '../../models/password_entry.dart';
import '../../services/password_repository_service.dart';

class PasswordListScreen extends StatefulWidget {
  final String profileId;

  const PasswordListScreen({
    super.key,
    required this.profileId,
  });

  @override
  State<PasswordListScreen> createState() => _PasswordListScreenState();
}

class _PasswordListScreenState extends State<PasswordListScreen> {
  late PasswordRepositoryService _passwordRepoService;
  PasswordRepositoryProfile? _profile; // Для отображения имени профиля в AppBar

  List<PasswordEntry>? _passwordEntries;
  String? _error;
  bool _isLoading = true;
  String? _gpgPassphrase; // Для хранения введенной парольной фразы

  @override
  void initState() {
    super.initState();
    _passwordRepoService = Provider.of<PasswordRepositoryService>(context, listen: false);
    _profile = _passwordRepoService.getProfiles().firstWhere((p) => p.id == widget.profileId);
    _loadPasswordEntries();
  }

  Future<void> _loadPasswordEntries({String? newPassphrase}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Если парольная фраза еще не установлена или была предоставлена новая (например, после неудачной попытки)
    if (_gpgPassphrase == null || newPassphrase != null) {
      if (newPassphrase != null) {
        _gpgPassphrase = newPassphrase;
      } else {
        // Запрашиваем парольную фразу, если она еще не была введена
    final String? enteredPassphrase = await _showPassphraseDialog();
    if (enteredPassphrase == null) {
      // Пользователь отменил ввод, остаемся на экране или возвращаемся назад
      setState(() {
        _isLoading = false;
        _error = 'Парольная фраза не введена.';
      });
      if (mounted && Navigator.canPop(context)) {
        // Можно добавить задержку перед pop, чтобы пользователь увидел сообщение
        // Future.delayed(const Duration(seconds: 2), () {
        //   if (mounted && Navigator.canPop(context)) Navigator.pop(context);
        // });
      }
      return;
    }
    _gpgPassphrase = enteredPassphrase;
      }
    }

    if (_gpgPassphrase == null || _gpgPassphrase!.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Парольная фраза не может быть пустой.';
      });
      _gpgPassphrase = null; // Сбрасываем, чтобы запросить снова
      return;
    }

    try {
      final entries = await _passwordRepoService.getAllPasswordEntries(
        profileId: widget.profileId,
        userGpgPassphrase: _gpgPassphrase!,
      );
      if (!mounted) return;
      setState(() {
        _passwordEntries = entries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка загрузки паролей: $e';
        _isLoading = false;
        if (e.toString().contains('Incorrect GPG passphrase')) {
          _gpgPassphrase = null; // Сбрасываем парольную фразу при ошибке, чтобы запросить снова
        }
      });
    }
  }

  Future<String?> _showPassphraseDialog() async {
    if (!mounted) return null;
    return await showDialog<String>(
      context: context,
      barrierDismissible: false, // Нельзя закрыть диалог, нажав вне его
      builder: (BuildContext dialogContext) {
        TextEditingController controller = TextEditingController();
        return AlertDialog(
          title: const Text('GPG Парольная фраза'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Для доступа к паролям профиля "${_profile?.profileName ?? ''}" введите парольную фразу GPG.'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: "Парольная фраза",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () => Navigator.of(dialogContext).pop(), // Возвращаем null
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  Navigator.of(dialogContext).pop(controller.text);
                } else {
                  // Можно показать ошибку прямо в диалоге, но для простоты просто не закрываем
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _navigateToAddEntry() {
    // TODO: Навигация на экран добавления/редактирования пароля
    // Navigator.push(
    //   context,
    //   MaterialPageRoute(builder: (_) => AddEditPasswordEntryScreen(profileId: widget.profileId)),
    // ).then((value) {
    //   // Если пароль был добавлен/изменен, перезагружаем список
    //   if (value == true && _gpgPassphrase != null) { // value == true может быть флагом успеха
    //     _loadPasswordEntries(newPassphrase: _gpgPassphrase); // Перезагружаем с текущей фразой
    //   }
    // });
    print('Переход на экран добавления новой записи пароля');
  }

  void _navigateToViewEntry(PasswordEntry entry) {
    // TODO: Навигация на экран просмотра/редактирования пароля
    // Navigator.push(
    //   context,
    //   MaterialPageRoute(builder: (_) => ViewPasswordEntryScreen(profileId: widget.profileId, entry: entry, gpgPassphrase: _gpgPassphrase!)),
    // ).then((value) {
    //   // Если пароль был изменен/удален, перезагружаем список
    //   if (value == true && _gpgPassphrase != null) {
    //     _loadPasswordEntries(newPassphrase: _gpgPassphrase);
    //   }
    // });
    print('Переход на экран просмотра записи: ${entry.fullPath}');
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_profile?.profileName ?? 'Пароли'),
        actions: [
          if (_error != null && _error!.contains('Incorrect GPG passphrase'))
            IconButton(
              icon: const Icon(Icons.vpn_key),
              tooltip: 'Ввести парольную фразу снова',
              onPressed: () => _loadPasswordEntries(), // Попытка загрузить снова (запросит фразу)
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: (_gpgPassphrase != null && !_isLoading) ? _navigateToAddEntry : null, // Активна, если фраза введена и не идет загрузка
        tooltip: 'Добавить пароль',
        child: const Icon(Icons.add),
        backgroundColor: (_gpgPassphrase != null && !_isLoading) ? Theme.of(context).colorScheme.secondary : Colors.grey,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700, fontSize: 16),
              ),
              const SizedBox(height: 20),
              if (_error!.contains('Incorrect GPG passphrase') || _error!.contains('Passphrase cannot be empty') || _error!.contains('Passphrase cannot be empty'))
                ElevatedButton(
                  onPressed: () => _loadPasswordEntries(), // Попытка загрузить снова
                  child: const Text('Retry'),
                ),
              ElevatedButton(
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (_passwordEntries == null || _passwordEntries!.isEmpty) {
      return const Center(
        child: Text(
          'Passwords not found.\nPress "+", to add a new password.',
          textAlign: TextAlign.center,
        ),
      );
    }

    // TODO: Группировка по папкам или просто плоский список для начала
    // Для простоты сейчас - плоский список
    return ListView.builder(
      itemCount: _passwordEntries!.length,
      itemBuilder: (context, index) {
        final entry = _passwordEntries![index];
        return ListTile(
          leading: Icon(entry.folderPath.isNotEmpty ? Icons.folder_open_outlined : Icons.vpn_key_outlined),
          title: Text(entry.entryName),
          subtitle: Text(entry.folderPath.isNotEmpty ? entry.folderPath : 'Root'),
          onTap: () => _navigateToViewEntry(entry),
        );
      },
    );
  }
}