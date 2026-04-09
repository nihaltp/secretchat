// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:local_auth/local_auth.dart';

abstract class AppLockService {
  Future<bool> authenticate({required String reason});
}

class LocalAuthAppLockService implements AppLockService {
  LocalAuthAppLockService({LocalAuthentication? localAuthentication})
    : _localAuth = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      final bool deviceSupported = await _localAuth.isDeviceSupported();
      final bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!deviceSupported && !canCheckBiometrics) {
        return false;
      }

      return _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
