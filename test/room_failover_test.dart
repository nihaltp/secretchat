// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:secret_chat/chat/controllers/lan_chat_controller.dart';
import 'package:secret_chat/chat/models/room_info.dart';

Future<void> _waitFor(bool Function() predicate, {Duration timeout = const Duration(seconds: 12)}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  fail('Timed out waiting for condition.');
}

void main() {
  test('highest-battery device takes over when host leaves and host can rejoin with prior history', () async {
    final int basePort = 50000 + Random.secure().nextInt(1000) * 2;
    final int testDiscoveryPort = basePort;
    final int testChatPort = basePort + 1;

    final LanChatController host = LanChatController(
      batteryLevelProvider: () async => 20,
      localUserIdProvider: () async => 'host-device',
      chatPortOverride: testChatPort,
      discoveryPortOverride: testDiscoveryPort,
    );
    final LanChatController alice = LanChatController(
      batteryLevelProvider: () async => 90,
      localUserIdProvider: () async => 'alice-device',
      chatPortOverride: testChatPort,
      discoveryPortOverride: testDiscoveryPort,
    );
    final LanChatController bob = LanChatController(
      batteryLevelProvider: () async => 40,
      localUserIdProvider: () async => 'bob-device',
      chatPortOverride: testChatPort,
      discoveryPortOverride: testDiscoveryPort,
    );

    try {
      final bool hosted = await host.hostRoom(
        yourName: 'Host',
        room: 'FailoverRoom',
        historyEnabled: true,
      );
      expect(hosted, isTrue);

      final RoomInfo room = RoomInfo(
        hostAddress: InternetAddress.loopbackIPv4,
        hostName: 'Host',
        roomName: 'FailoverRoom',
        port: testChatPort,
        lastSeen: DateTime.now(),
        historyEnabled: true,
      );

      expect(await alice.joinRoom(room: room, yourName: 'Alice'), isTrue);
      expect(await bob.joinRoom(room: room, yourName: 'Bob'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      await host.sendMessage('before-leave');
      await Future<void>.delayed(const Duration(milliseconds: 400));

      await host.disconnect();
      await _waitFor(() => alice.mode == ChatMode.hosting);
      await Future<void>.delayed(const Duration(seconds: 1));

      await alice.sendMessage('during-failover');
      await Future<void>.delayed(const Duration(milliseconds: 700));

      final LanChatController hostRejoin = LanChatController(
        batteryLevelProvider: () async => 20,
        localUserIdProvider: () async => 'host-device',
        chatPortOverride: testChatPort,
        discoveryPortOverride: testDiscoveryPort,
      );
      try {
        final RoomInfo? discovered = alice.findRoomByName(
          'FailoverRoom',
          includeHidden: true,
        );
        expect(discovered, isNotNull);

        final bool rejoined = await hostRejoin.joinRoom(
          room: discovered!,
          yourName: 'Host',
        );
        expect(rejoined, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 800));

        final List<String> hostMessages = hostRejoin.messages
            .where((message) => !message.system)
            .map((message) => message.text)
            .toList();

        expect(hostMessages, isNot(contains('before-leave')));
        expect(hostMessages, isNot(contains('during-failover')));
      } finally {
        await hostRejoin.disconnect();
        hostRejoin.dispose();
      }
    } finally {
      await bob.disconnect();
      await alice.disconnect();
      await host.disconnect();
      bob.dispose();
      alice.dispose();
      host.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 45)));
}
