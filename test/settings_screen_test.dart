// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:secret_chat/chat/chat_constants.dart';
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

String _readPubspecVersion() {
  final String pubspec = File('pubspec.yaml').readAsStringSync();
  final RegExpMatch? match = RegExp(
    r'^version:\s*([^\s]+)',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw StateError('Could not find version in pubspec.yaml');
  }
  return match.group(1)!;
}

void main() {
  testWidgets('Settings toggle switches to light mode', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final String expectedVersion = _readPubspecVersion();
    final List<String> parts = expectedVersion.split('+');
    final String appVersion = parts.first;
    final String buildNumber = parts.length > 1 ? parts[1] : '0';
    PackageInfo.setMockInitialValues(
      appName: 'secret_chat',
      packageName: 'com.nihaltp.secret_chat',
      version: appVersion,
      buildNumber: buildNumber,
      buildSignature: '',
      installerStore: 'org.fdroid.fdroid',
    );

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
    await tester.pumpAndSettle();

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
    expect(find.byKey(const Key('settings_version_footer')), findsOneWidget);
    expect(
      find.text(
        'Protocol v$chatProtocolVersion  |  App v$expectedVersion  |  Channel fdroid',
      ),
      findsOneWidget,
    );
  });
}
