// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_chat/chat/models/network_user_info.dart';
import 'package:secret_chat/chat/models/room_info.dart';
import 'package:secret_chat/screens/models/active_room_item.dart';
import 'package:secret_chat/screens/network_overview_screen.dart';

void main() {
  testWidgets(
    'Network Overview shows pending count and opens user chat on tap',
    (WidgetTester tester) async {
      NetworkUserInfo? tappedUser;
      ActiveRoomItem? tappedRoom;
      const NetworkUserInfo pendingUser = NetworkUserInfo(
        userId: 'u-2',
        displayName: 'Bob',
        hostAddress: '192.168.1.50',
        hasPendingMessages: true,
        pendingMessageCount: 2,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NetworkOverviewScreen(
            userName: 'Alice',
            isHostNetworkMode: false,
            status: 'Connected',
            activeRooms: const <ActiveRoomItem>[
              ActiveRoomItem(
                key: 'room-1',
                roomName: 'General',
                unreadCount: 1,
              ),
            ],
            activeUserChats: const <ActiveRoomItem>[
              ActiveRoomItem(
                key: 'chat-1',
                roomName: 'Charlie',
              ),
            ],
            discoveredRooms: const <RoomInfo>[],
            networkUsers: const <NetworkUserInfo>[pendingUser],
            onBack: () {},
            onOpenSettings: () {},
            onOpenRooms: () {},
            onOpenActiveRoom: (ActiveRoomItem room) {
              tappedRoom = room;
            },
            onOpenUserChat: (NetworkUserInfo user) {
              tappedUser = user;
            },
          ),
        ),
      );

      expect(find.text('Users currently on network'), findsOneWidget);
      expect(find.text('Chats with users'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Unread messages: 1'), findsNothing);

      await tester.tap(find.text('Bob'));
      await tester.pump();

      expect(tappedUser?.userId, 'u-2');

      await tester.tap(find.text('General'));
      await tester.pump();

      expect(tappedRoom?.key, 'room-1');
    },
  );

  testWidgets('Network Overview shows pending dot indicator', (
    WidgetTester tester,
  ) async {
    const NetworkUserInfo pendingDotUser = NetworkUserInfo(
      userId: 'u-3',
      displayName: 'Carol',
      hasPendingMessages: true,
      allowsIdChat: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NetworkOverviewScreen(
          userName: 'Alice',
          isHostNetworkMode: true,
          status: null,
          activeRooms: const <ActiveRoomItem>[],
          activeUserChats: const <ActiveRoomItem>[],
          discoveredRooms: const <RoomInfo>[],
          networkUsers: const <NetworkUserInfo>[pendingDotUser],
          onBack: () {},
          onOpenSettings: () {},
          onOpenRooms: () {},
          onOpenActiveRoom: (_) {},
          onOpenUserChat: (_) {},
        ),
      ),
    );

    expect(find.text('Carol'), findsOneWidget);
    expect(find.text('ID chat off'), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets(
    'Network Overview keeps active-chat users out of network users list',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkOverviewScreen(
            userName: 'Alice',
            isHostNetworkMode: false,
            status: 'Connected',
            activeRooms: const <ActiveRoomItem>[],
            activeUserChats: const <ActiveRoomItem>[
              ActiveRoomItem(
                key: 'chat-1',
                roomName: 'Bob',
                unreadCount: 3,
              ),
            ],
            discoveredRooms: const <RoomInfo>[],
            networkUsers: const <NetworkUserInfo>[
              NetworkUserInfo(
                userId: 'u-3',
                displayName: 'Carol',
              ),
            ],
            onBack: () {},
            onOpenSettings: () {},
            onOpenRooms: () {},
            onOpenActiveRoom: (_) {},
            onOpenUserChat: (_) {},
          ),
        ),
      );

      // Bob appears in active chats only, while the network users list
      // contains Carol.
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    },
  );
}
