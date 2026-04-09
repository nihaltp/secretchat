// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_chat/screens/home_screen.dart';

void main() {
  testWidgets('Home screen host and wifi buttons trigger callbacks', (
    WidgetTester tester,
  ) async {
    String hostName = '';
    String wifiName = '';
    bool settingsOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          onHostPressed: (String name) {
            hostName = name;
          },
          onWifiPressed: (String name) {
            wifiName = name;
          },
          onOpenSettings: () {
            settingsOpened = true;
          },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('display_name_field')),
      'Alice',
    );

    await tester.tap(find.byKey(const Key('host_network_button')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('use_wifi_button')));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();

    expect(hostName, 'Alice');
    expect(wifiName, 'Alice');
    expect(settingsOpened, isTrue);
  });
}
