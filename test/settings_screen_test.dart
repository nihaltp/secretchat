// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_chat/screens/settings_screen.dart';
import 'package:secret_chat/security/app_lock_controller.dart';
import 'package:secret_chat/security/app_lock_service.dart';
import 'package:secret_chat/settings/default_room_listening_controller.dart';
import 'package:secret_chat/settings/network_privacy_controller.dart';
import 'package:secret_chat/settings/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAppLockService implements AppLockService {
  @override
  Future<bool> authenticate({required String reason}) async => true;
}

void main() {
  testWidgets('Settings toggle switches to light mode', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final ThemeController controller = ThemeController();
    final AppLockController appLockController = AppLockController(
      service: _FakeAppLockService(),
    );
    final DefaultRoomListeningController defaultRoomListeningController =
        DefaultRoomListeningController();
    final NetworkPrivacyController networkPrivacyController =
        NetworkPrivacyController();

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          themeController: controller,
          appLockController: appLockController,
          defaultRoomListeningController: defaultRoomListeningController,
          networkPrivacyController: networkPrivacyController,
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

    await tester.tap(find.byKey(const Key('default_room_listening_switch')));
    await tester.pump();
    expect(
      find.byKey(const Key('default_room_listening_switch')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('network_hide_from_network_switch')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('network_block_chat_by_id_switch')),
      findsOneWidget,
    );
  });
}
