import 'package:flutter/material.dart';
import 'package:pass/services/gpg_key_service.dart';
import 'package:pass/services/password_repository_service.dart';
import 'package:provider/provider.dart';

import 'ui/screens/profile_list_screen.dart';

void main() {
  final passwordRepositoryService = PasswordRepositoryService();
  final gpgService = GPGService();

  runApp(
    MultiProvider(
      providers: [
        Provider<PasswordRepositoryService>.value(value: passwordRepositoryService),
        Provider<GPGService>.value(value: gpgService),
      ],
      child: const MyApp(),
    )
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Password Manager",
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const ProfileListScreen(),
    );
  }
}