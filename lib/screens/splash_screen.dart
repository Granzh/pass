import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/password_repository_service.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNextScreen();
  }

  Future<void> _navigateToNextScreen() async {
    final passwordService = context.read<PasswordRepositoryService>();
    await Future.delayed(const Duration(seconds: 2)); // Splash screen delay

    if (!mounted) return;

    final hasProfiles = passwordService.getProfiles().isNotEmpty;
    
    if (!mounted) return;
    
    Navigator.of(context).pushReplacementNamed(
      hasProfiles ? '/home' : '/onboarding',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            const Icon(
              Icons.lock_outline,
              size: 80,
              color: Colors.purple,
            ),
            const SizedBox(height: 16),
            Text(
              'Pass',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const Spacer(),
            const CircularProgressIndicator(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
