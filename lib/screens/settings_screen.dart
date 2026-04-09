// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';

import '../security/app_lock_controller.dart';
import '../settings/theme_controller.dart';
import '../widgets/app_logo_title.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.themeController,
    required this.appLockController,
  });

  final ThemeController themeController;
  final AppLockController appLockController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (BuildContext context, _) {
        return AnimatedBuilder(
          animation: appLockController,
          builder: (BuildContext context, _) {
            return Scaffold(
              appBar: AppBar(title: const AppLogoTitle('Settings')),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(
                    key: const Key('dark_theme_switch'),
                    title: const Text('Dark theme'),
                    subtitle: const Text(
                      'Dark is default. Turn off to use light theme.',
                    ),
                    value: themeController.isDarkMode,
                    onChanged: themeController.setDarkMode,
                  ),
                  SwitchListTile(
                    key: const Key('app_lock_switch'),
                    title: const Text('App lock'),
                    subtitle: const Text(
                      'Use biometric if available, otherwise fallback to device screen lock.',
                    ),
                    value: appLockController.enabled,
                    onChanged: (bool enabled) async {
                      final bool ok = await appLockController.setEnabled(
                        enabled,
                      );
                      if (!context.mounted) {
                        return;
                      }
                      if (!ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Authentication failed. App lock unchanged.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
