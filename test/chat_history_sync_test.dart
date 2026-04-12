// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secret_chat/chat/chat_constants.dart';
import 'package:secret_chat/chat/controllers/lan_chat_controller.dart';
import 'package:secret_chat/chat/models/room_info.dart';

Future<void> _settle([int milliseconds = 300]) async {
  await Future<void>.delayed(Duration(milliseconds: milliseconds));
}

void main() {
  test('History-enabled room restores only messages from user presence windows', () async {
    const int testChatPort = 48751;
    const int testDiscoveryPort = 48750;

    final LanChatController host = LanChatController(
      batteryLevelProvider: () async => 60,
      localUserIdProvider: () async => 'history-host',
      chatPortOverride: testChatPort,
      discoveryPortOverride: testDiscoveryPort,
    );
    final LanChatController client = LanChatController(
      batteryLevelProvider: () async => 55,
      localUserIdProvider: () async => 'history-client',
      chatPortOverride: testChatPort,
      discoveryPortOverride: testDiscoveryPort,
    );

    try {
      final bool hosted = await host.hostRoom(
        yourName: 'Host',
        room: 'HistoryRoom',
        historyEnabled: true,
      );
      expect(hosted, isTrue);

      final RoomInfo room = RoomInfo(
        hostAddress: InternetAddress.loopbackIPv4,
        hostName: 'Host',
        roomName: 'HistoryRoom',
        port: testChatPort,
        lastSeen: DateTime.now(),
        historyEnabled: true,
      );

      final bool joinedFirst = await client.joinRoom(room: room, yourName: 'Alice');
      expect(joinedFirst, isTrue);
      await _settle();

      await client.sendMessage('m1-present');
      await _settle();
      await host.sendMessage('m2-present');
      await _settle();

      await client.disconnect();
      await _settle();

      await host.sendMessage('m3-away');
      await _settle();

      final bool joinedAgain = await client.joinRoom(room: room, yourName: 'Alice');
      expect(joinedAgain, isTrue);
      await _settle(500);

      final List<String> texts = client.messages
          .where((message) => !message.system)
          .map((message) => message.text)
          .toList();

      expect(texts, contains('m2-present'));
      expect(texts, isNot(contains('m1-present')));
      expect(texts, isNot(contains('m3-away')));
    } finally {
      await client.disconnect();
      await host.disconnect();
      host.dispose();
      client.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 25)));

  test('Hidden direct chat replays pending sender messages on first open', () async {
    const int testChatPort = userChatPort;
    const int testDiscoveryPort = userDiscoveryPort;
    const String directRoomName = '${directChatRoomPrefix}direct-client';

    final LanChatController host = LanChatController(
      batteryLevelProvider: () async => 70,
      localUserIdProvider: () async => 'direct-host',
      chatPortOverride: testChatPort,
      discoveryPortOverride: testDiscoveryPort,
    );
    final LanChatController client = LanChatController(
      batteryLevelProvider: () async => 65,
      localUserIdProvider: () async => 'direct-client',
      chatPortOverride: testChatPort,
      discoveryPortOverride: testDiscoveryPort,
    );

    try {
      final bool hosted = await host.hostRoom(
        yourName: 'Host',
        room: directRoomName,
        hidden: true,
        historyEnabled: true,
      );
      expect(hosted, isTrue);

      await host.sendMessage('pending-before-open');
      await _settle();

      final RoomInfo room = RoomInfo(
        hostAddress: InternetAddress.loopbackIPv4,
        hostName: 'Host',
        hostUserId: 'direct-host',
        roomName: directRoomName,
        port: testChatPort,
        lastSeen: DateTime.now(),
        hidden: true,
        historyEnabled: true,
      );

      final bool joined = await client.joinRoom(room: room, yourName: 'Client');
      expect(joined, isTrue);
      await _settle(500);

      final List<String> texts = client.messages
          .where((message) => !message.system)
          .map((message) => message.text)
          .toList();

      expect(texts, contains('pending-before-open'));
    } finally {
      await client.disconnect();
      await host.disconnect();
      host.dispose();
      client.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 25)));
}
