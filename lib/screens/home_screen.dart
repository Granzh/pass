import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/password_repository_service.dart';
import '../widgets/password_card.dart';
import 'add_password_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Passwords'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              // TODO: Navigate to settings
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search passwords...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.toLowerCase());
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildPasswordList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddPasswordScreen(),
            ),
          );
        },
        label: const Text('Add Password'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildPasswordList() {
    return Consumer<PasswordRepositoryService>(
      builder: (context, passwordService, _) {
        // In a real app, you would fetch passwords from the repository
        // For now, we'll show a placeholder
        final passwords = [
          {
            'id': '1',
            'name': 'Email',
            'username': 'user@example.com',
            'updatedAt': DateTime.now().subtract(const Duration(days: 1)),
          },
          {
            'id': '2',
            'name': 'Bank Account',
            'username': 'mybank',
            'updatedAt': DateTime.now().subtract(const Duration(days: 3)),
          },
          {
            'id': '3',
            'name': 'Social Media',
            'username': 'myusername',
            'updatedAt': DateTime.now().subtract(const Duration(days: 5)),
          },
        ];

        if (passwords.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  'No passwords yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the + button to add your first password',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          );
        }

        final filteredPasswords = _searchQuery.isEmpty
            ? passwords
            : passwords.where((password) {
                final name = password['name']?.toString().toLowerCase() ?? '';
                final username = password['username']?.toString().toLowerCase() ?? '';
                return name.contains(_searchQuery) || username.contains(_searchQuery);
              }).toList();

        if (filteredPasswords.isEmpty) {
          return Center(
            child: Text(
              'No matching passwords found',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          );
        }


        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: filteredPasswords.length,
          itemBuilder: (context, index) {
            final password = filteredPasswords[index];
            return PasswordCard(
              id: password['id'] as String,
              name: password['name'] as String,
              username: password['username'] as String?,
              updatedAt: password['updatedAt'] as DateTime,
              onTap: () {
                // TODO: Show password details
              },
            );
          },
        );
      },
    );
  }
}
