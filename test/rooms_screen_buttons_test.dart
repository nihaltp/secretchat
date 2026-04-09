// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_chat/chat/models/room_info.dart';
import 'package:secret_chat/screens/rooms_screen.dart';

void main() {
  testWidgets('Rooms screen create/refresh/join buttons trigger callbacks', (
    WidgetTester tester,
  ) async {
    bool createTapped = false;
    bool refreshTapped = false;
    bool joinTapped = false;

    final RoomInfo room = RoomInfo(
      hostAddress: InternetAddress.loopbackIPv4,
      hostName: 'HostOne',
      roomName: 'General',
      port: 48651,
      lastSeen: DateTime.now(),
      hidden: false,
      securityType: RoomSecurityType.none,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RoomsScreen(
          rooms: <RoomInfo>[room],
          userName: 'Alice',
          isHostNetworkMode: false,
          canAccessRooms: true,
          status: 'Ready',
          onBack: () {},
          onOpenSettings: () {},
          onRefresh: () {
            refreshTapped = true;
          },
          onCreateRoom: () {
            createTapped = true;
          },
          onFindRoomByName: (String roomName) => room,
          onJoinRoom: (RoomInfo roomArg, String? securityArg) async {
            joinTapped = true;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('create_room_button')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('refresh_rooms_button')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('join_room_button_0')));
    await tester.pump();

    expect(createTapped, isTrue);
    expect(refreshTapped, isTrue);
    expect(joinTapped, isTrue);
  });

  testWidgets('Rooms screen buttons are disabled when network is unavailable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RoomsScreen(
          rooms: const <RoomInfo>[],
          userName: 'Alice',
          isHostNetworkMode: false,
          canAccessRooms: false,
          status: 'No network',
          onBack: () {},
          onOpenSettings: () {},
          onRefresh: () {},
          onCreateRoom: () {},
          onFindRoomByName: (String roomName) => null,
          onJoinRoom: (RoomInfo roomArg, String? securityArg) async {},
        ),
      ),
    );

    final FilledButton createButton = tester.widget<FilledButton>(
      find.byKey(const Key('create_room_button')),
    );
    expect(createButton.onPressed, isNull);
  });
}
