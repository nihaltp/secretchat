// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_lock_service.dart';

class AppLockController extends ChangeNotifier {
  AppLockController({AppLockService? service})
    : _service = service ?? LocalAuthAppLockService();

  static const String _prefKeyEnabled = 'app_lock_enabled';

  final AppLockService _service;

  bool _initialized = false;
  bool _enabled = false;
  bool _unlocked = true;

  bool get initialized => _initialized;
  bool get enabled => _enabled;
  bool get isLocked => _enabled && !_unlocked;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefKeyEnabled) ?? false;
      _unlocked = !_enabled;
    } catch (_) {
      _enabled = false;
      _unlocked = true;
    }

    _initialized = true;
    notifyListeners();
  }

  Future<bool> setEnabled(bool value) async {
    if (!_initialized) {
      await init();
    }

    if (value) {
      final bool authenticated = await _service.authenticate(
        reason: 'Authenticate to enable app lock',
      );
      if (!authenticated) {
        return false;
      }
      _enabled = true;
      _unlocked = true;
    } else {
      _enabled = false;
      _unlocked = true;
    }

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyEnabled, _enabled);
    } catch (_) {
      // Ignore persistence failures; keep runtime state.
    }

    notifyListeners();
    return true;
  }

  Future<bool> ensureUnlocked({String reason = 'Unlock to continue'}) async {
    if (!_initialized) {
      await init();
    }

    if (!_enabled || _unlocked) {
      return true;
    }

    final bool authenticated = await _service.authenticate(reason: reason);
    if (authenticated) {
      _unlocked = true;
      notifyListeners();
      return true;
    }

    _unlocked = false;
    notifyListeners();
    return false;
  }

  void markLocked() {
    if (_enabled) {
      _unlocked = false;
      notifyListeners();
    }
  }
}
