// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';

import 'package:secret_chat/screens/app_flow_screen.dart';
import 'package:secret_chat/security/app_lock_controller.dart';
import 'package:secret_chat/settings/default_room_listening_controller.dart';
import 'package:secret_chat/settings/network_privacy_controller.dart';
import 'package:secret_chat/settings/theme_controller.dart';

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
  final DefaultRoomListeningController _defaultRoomListeningController =
      DefaultRoomListeningController();
  final NetworkPrivacyController _networkPrivacyController =
      NetworkPrivacyController();

  @override
  void initState() {
    super.initState();
    _themeController.init();
  }

  @override
  void dispose() {
    _defaultRoomListeningController.dispose();
    _networkPrivacyController.dispose();
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
            defaultRoomListeningController: _defaultRoomListeningController,
            networkPrivacyController: _networkPrivacyController,
          ),
        );
      },
    );
  }
}
