// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';

import '../chat/models/network_user_info.dart';
import '../chat/models/room_info.dart';
import 'models/active_room_item.dart';
import '../widgets/app_logo_title.dart';

class NetworkOverviewScreen extends StatelessWidget {
  const NetworkOverviewScreen({
    super.key,
    required this.userName,
    required this.isHostNetworkMode,
    required this.status,
    required this.activeRooms,
    required this.activeUserChats,
    required this.discoveredRooms,
    required this.networkUsers,
    required this.onBack,
    required this.onOpenSettings,
    required this.onOpenRooms,
    required this.onOpenActiveRoom,
    required this.onOpenUserChat,
  });

  final String userName;
  final bool isHostNetworkMode;
  final String? status;
  final List<ActiveRoomItem> activeRooms;
  final List<ActiveRoomItem> activeUserChats;
  final List<RoomInfo> discoveredRooms;
  final List<NetworkUserInfo> networkUsers;
  final VoidCallback onBack;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenRooms;
  final ValueChanged<ActiveRoomItem> onOpenActiveRoom;
  final ValueChanged<NetworkUserInfo> onOpenUserChat;

  Widget _unreadBadge(BuildContext context, int count) {
    final String label = count > 99 ? '99+' : '$count';
    return Container(
      width: label.length > 2 ? 34 : 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.green,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppLogoTitle('Network Overview'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('User: $userName'),
          const SizedBox(height: 4),
          Text(
            isHostNetworkMode ? 'Network Mode: Host' : 'Network Mode: Wi-Fi',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              key: const Key('open_rooms_button'),
              onPressed: onOpenRooms,
              icon: const Icon(Icons.meeting_room),
              label: const Text('Open Rooms'),
            ),
          ),
          if (status != null) ...[
            const SizedBox(height: 10),
            Text(status!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          Text(
            'Rooms you are in',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (activeRooms.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('You are not currently in any rooms.'),
              ),
            )
          else
            ...activeRooms.map(
              (ActiveRoomItem room) => Card(
                child: ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(room.roomName),
                  trailing: room.unreadCount > 0
                      ? _unreadBadge(context, room.unreadCount)
                      : null,
                  onTap: () => onOpenActiveRoom(room),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Chats with users',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (activeUserChats.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('No active user chats.'),
              ),
            )
          else
            ...activeUserChats.map(
              (ActiveRoomItem chat) => Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(chat.roomName),
                  trailing: chat.unreadCount > 0
                      ? _unreadBadge(context, chat.unreadCount)
                      : null,
                  onTap: () => onOpenActiveRoom(chat),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Users currently on network',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (networkUsers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('No users discovered on the network.'),
              ),
            )
          else
            ...networkUsers.map(
              (NetworkUserInfo user) => Card(
                child: ListTile(
                  leading: Icon(
                    user.isCurrentUser ? Icons.person : Icons.person_outline,
                  ),
                  title: Text(user.displayName),
                  subtitle: Text(
                    'ID: ${user.userId}${user.hostAddress == null ? '' : '\nHost: ${user.hostAddress}'}',
                  ),
                  isThreeLine: user.hostAddress != null,
                  trailing: user.pendingMessageCount > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${user.pendingMessageCount}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : user.hasPendingMessages
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        )
                      : (user.allowsIdChat
                            ? const Chip(label: Text('ID chat on'))
                            : const Chip(label: Text('ID chat off'))),
                  onTap: () => onOpenUserChat(user),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
