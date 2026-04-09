// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter_test/flutter_test.dart';
import 'package:secret_chat/security/app_lock_controller.dart';
import 'package:secret_chat/security/app_lock_service.dart';

class _FakeAppLockService implements AppLockService {
  _FakeAppLockService({this.result = true});

  final bool result;

  @override
  Future<bool> authenticate({required String reason}) async => result;
}

void main() {
  test('App lock can be enabled with successful authentication', () async {
    final AppLockController controller = AppLockController(
      service: _FakeAppLockService(result: true),
    );

    final bool ok = await controller.setEnabled(true);

    expect(ok, isTrue);
    expect(controller.enabled, isTrue);
    expect(controller.isLocked, isFalse);
  });

  test('App lock remains disabled when authentication fails', () async {
    final AppLockController controller = AppLockController(
      service: _FakeAppLockService(result: false),
    );

    final bool ok = await controller.setEnabled(true);

    expect(ok, isFalse);
    expect(controller.enabled, isFalse);
  });
}
