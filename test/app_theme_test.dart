// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_chat/main.dart';

void main() {
  testWidgets('App defaults to dark theme mode', (WidgetTester tester) async {
    await tester.pumpWidget(const SecretChatApp());
    await tester.pump();

    final MaterialApp app = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    expect(app.themeMode, ThemeMode.dark);
  });
}
