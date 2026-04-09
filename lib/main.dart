// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';

import 'screens/app_flow_screen.dart';
import 'security/app_lock_controller.dart';
import 'settings/theme_controller.dart';

void main() {
  runApp(const SecretChatApp());
}

class SecretChatApp extends StatefulWidget {
  const SecretChatApp({super.key});

  @override
  State<SecretChatApp> createState() => _SecretChatAppState();
}

class _SecretChatAppState extends State<SecretChatApp> {
  final ThemeController _themeController = ThemeController();
  final AppLockController _appLockController = AppLockController();

  @override
  void dispose() {
    _appLockController.dispose();
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeController,
      builder: (BuildContext context, _) {
        return MaterialApp(
          title: 'Secret Chat',
          themeMode: _themeController.themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF007A5E),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF007A5E),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: AppFlowScreen(
            themeController: _themeController,
            appLockController: _appLockController,
          ),
        );
      },
    );
  }
}
