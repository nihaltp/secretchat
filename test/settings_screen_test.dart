// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_chat/security/app_lock_controller.dart';
import 'package:secret_chat/security/app_lock_service.dart';
import 'package:secret_chat/screens/settings_screen.dart';
import 'package:secret_chat/settings/theme_controller.dart';

class _FakeAppLockService implements AppLockService {
  @override
  Future<bool> authenticate({required String reason}) async => true;
}

void main() {
  testWidgets('Settings toggle switches to light mode', (
    WidgetTester tester,
  ) async {
    final ThemeController controller = ThemeController();
    final AppLockController appLockController = AppLockController(
      service: _FakeAppLockService(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          themeController: controller,
          appLockController: appLockController,
        ),
      ),
    );

    expect(controller.themeMode, ThemeMode.dark);
    expect(find.text('Dark theme'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dark_theme_switch')));
    await tester.pumpAndSettle();

    expect(controller.themeMode, ThemeMode.light);

    await tester.tap(find.byKey(const Key('app_lock_switch')));
    await tester.pump();
    expect(find.byKey(const Key('app_lock_switch')), findsOneWidget);
  });
}
