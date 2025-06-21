import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../services/password_repository_service.dart';
import '../services/gpg_key_service.dart';
import '../widgets/repository_type_card.dart';
import '../logic/password_repository_profile.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to Pass'),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            Text(
              'Add your first password repository',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Choose where you want to store your passwords securely',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RepositoryTypeCard(
                    icon: Icons.cloud_upload,
                    title: 'GitHub',
                    description: 'Store your passwords in a private GitHub repository',
                    onTap: () => _navigateToGitProvider(context, 'GitHub'),
                  ),
                  const SizedBox(height: 16),
                  RepositoryTypeCard(
                    icon: Icons.storage,
                    title: 'GitLab',
                    description: 'Use GitLab to store and sync your passwords',
                    onTap: () => _navigateToGitProvider(context, 'GitLab'),
                  ),
                  const SizedBox(height: 16),
                  RepositoryTypeCard(
                    icon: Icons.folder,
                    title: 'Local Folder',
                    description: 'Store passwords locally on this device only',
                    onTap: () => _navigateToLocalSetup(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToGitProvider(BuildContext context, String provider) {
    // TODO: Implement navigation to Git provider setup
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$provider setup coming soon')),
    );
  }

  Future<void> _navigateToLocalSetup(BuildContext context) async {
    try {
      // Show loading indicator
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // Get the app's documents directory as the default location
      final appDocDir = await getApplicationDocumentsDirectory();
      final defaultPath = path.join(appDocDir.path, 'passwords');
      
      // Create the directory if it doesn't exist
      final dir = Directory(defaultPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Add the local repository profile
      final passwordService = Provider.of<PasswordRepositoryService>(context, listen: false);
      final gpgService = GPGService();
      
      // Create a new profile
      final profileId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Generate a secure passphrase
      final passphrase = _generateSecurePassphrase();
      
      // Generate GPG key pair
      final gpgKey = await gpgService.generateKeyPair(
        'pass-local-$profileId',
        passphrase,
      );
      
      // Save the GPG key
      await gpgService.saveKeyForProfileById(profileId, gpgKey);
      
      // Add the repository with the generated profile ID
      await passwordService.addRepository(
        id: profileId,
        name: 'Local Passwords',
        type: PasswordSourceType.localFolder,
        repositoryFullName: 'local',
      );
      
      // Set as active profile
      await passwordService.setActiveProfile(profileId);

      // Dismiss loading indicator
      if (context.mounted) {
        Navigator.of(context).pop();
        // Navigate to home screen
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error setting up local repository: $e')),
        );
      }
    }
  }
  
  // Generate a secure passphrase for GPG key
  String _generateSecurePassphrase() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    final passphrase = base64Url.encode(values);
    return passphrase;
  }
}
