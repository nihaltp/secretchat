import 'package:flutter/material.dart';

import 'screens/app_flow_screen.dart';
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

  @override
  void dispose() {
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
          home: AppFlowScreen(themeController: _themeController),
        );
      },
    );
  }
}
