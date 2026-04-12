// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secret_chat/chat/chat_constants.dart';
import 'package:secret_chat/chat/models/room_info.dart';

void main() {
  test('Direct user chat port is distinct from room and discovery ports', () {
    expect(userChatPort, isNot(equals(roomChatPort)));
    expect(userChatPort, isNot(equals(roomDiscoveryPort)));
    expect(userChatPort, isNot(equals(userDiscoveryPort)));
  });

  test('Direct chat room names are identified separately from rooms', () {
    expect(isDirectChatRoomName('__direct_chat__abc123'), isTrue);
    expect(isDirectChatRoomName('  __direct_chat__alice  '), isTrue);
    expect(isDirectChatRoomName('General'), isFalse);
  });

  test('Hidden direct rooms are detected for the local user', () {
    final RoomInfo room = RoomInfo(
      hostAddress: InternetAddress.loopbackIPv4,
      hostName: 'Bob',
      hostUserId: 'u-bob',
      roomName: '__direct_chat__u-alice',
      port: userChatPort,
      lastSeen: DateTime.now(),
      hidden: true,
    );

    expect(
      isDirectChatRoomTargetedToUser(
        room,
        localUserId: 'u-alice',
        localUserName: 'Alice',
      ),
      isTrue,
    );

    expect(
      isDirectChatRoomTargetedToUser(
        room,
        localUserId: 'u-other',
        localUserName: 'Other',
      ),
      isFalse,
    );
  });

  test('Hidden direct chats defer announcements until first message', () {
    expect(
      shouldDeferDirectChatAnnouncements(chatPort: userChatPort, hidden: true),
      isTrue,
    );
    expect(
      shouldDeferDirectChatAnnouncements(chatPort: roomChatPort, hidden: true),
      isFalse,
    );
    expect(
      shouldDeferDirectChatAnnouncements(chatPort: userChatPort, hidden: false),
      isFalse,
    );
  });
}
