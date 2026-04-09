// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_chat/settings/theme_controller.dart';

void main() {
  test('ThemeController defaults to dark and toggles to light', () {
    final ThemeController controller = ThemeController();

    expect(controller.themeMode, ThemeMode.dark);
    expect(controller.isDarkMode, isTrue);

    controller.setDarkMode(false);

    expect(controller.themeMode, ThemeMode.light);
    expect(controller.isDarkMode, isFalse);
  });
}
