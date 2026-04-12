// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';
import 'package:secret_chat/chat/models/room_info.dart';
import 'package:secret_chat/screens/models/active_room_item.dart';
import 'package:secret_chat/screens/pattern_lock_screen.dart';
import 'package:secret_chat/widgets/app_bottom_nav.dart';
import 'package:secret_chat/widgets/app_logo_title.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({
    super.key,
    required this.rooms,
    required this.userName,
    required this.isHostNetworkMode,
    required this.canAccessRooms,
    required this.status,
    this.activeRooms = const <ActiveRoomItem>[],
    this.activeRoomKey,
    required this.onResumeActiveRoom,
    required this.onDisconnectActiveRoom,
    this.onOpenNetworkOverview,
    this.onOpenRooms,
    this.onOpenSettings,
    required this.onRefresh,
    required this.onCreateRoom,
    required this.onFindRoomByName,
    required this.onJoinRoom,
  });

  final List<RoomInfo> rooms;
  final String userName;
  final bool isHostNetworkMode;
  final bool canAccessRooms;
  final String? status;
  final List<ActiveRoomItem> activeRooms;
  final String? activeRoomKey;

  final ValueChanged<String> onResumeActiveRoom;
  final Future<void> Function(String roomKey) onDisconnectActiveRoom;
  final VoidCallback? onOpenNetworkOverview;
  final VoidCallback? onOpenRooms;
  final VoidCallback? onOpenSettings;
  final VoidCallback onRefresh;
  final VoidCallback onCreateRoom;
  final RoomInfo? Function(String roomName) onFindRoomByName;
  final Future<void> Function(RoomInfo room, String? securityValue) onJoinRoom;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RoomInfo> get _filteredRooms {
    final String q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) {
      return widget.rooms;
    }
    return widget.rooms
        .where((RoomInfo r) => r.roomName.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _joinRoom(RoomInfo room) async {
    String? securityValue;
    if (room.requiresSecurity) {
      if (room.securityType == RoomSecurityType.pattern) {
        securityValue = await Navigator.of(context).push<String>(
          MaterialPageRoute<String>(
            builder: (_) => PatternLockScreen.verify(
              existingPattern: room.securityValue,
              title: 'Draw Pattern for ${room.roomName}',
            ),
          ),
        );
      } else {
        securityValue = await _askSecurityValue(
          title: 'Room Security',
          message:
              'Enter ${roomSecurityTypeToWire(room.securityType)} for ${room.roomName}',
        );
      }

      if (securityValue == null) {
        return;
      }
    }
    await widget.onJoinRoom(room, securityValue);
  }

  Future<String?> _askSecurityValue({
    required String title,
    required String message,
  }) async {
    final TextEditingController securityController = TextEditingController();
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: 10),
              TextField(
                controller: securityController,
                decoration: const InputDecoration(
                  labelText: 'Security value',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(securityController.text.trim()),
              child: const Text('Join'),
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<void> _joinByRoomName() async {
    final TextEditingController roomController = TextEditingController();

    final String? roomName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Join by Room Name'),
          content: TextField(
            controller: roomController,
            decoration: const InputDecoration(
              labelText: 'Room name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(roomController.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (roomName == null || roomName.isEmpty) {
      return;
    }

    final RoomInfo? room = widget.onFindRoomByName(roomName);
    if (room == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Room does not exist.')));
      return;
    }

    await _joinRoom(room);
  }

  @override
  Widget build(BuildContext context) {
    final List<RoomInfo> rooms = _filteredRooms;
    return Scaffold(
      appBar: AppBar(title: const AppLogoTitle('Rooms')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('User: ${widget.userName}'),
            const SizedBox(height: 4),
            Text(
              widget.isHostNetworkMode
                  ? 'Network Mode: Host'
                  : 'Network Mode: Wi-Fi',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('create_room_button'),
                    onPressed: widget.canAccessRooms
                        ? widget.onCreateRoom
                        : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Room'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const Key('join_by_name_button'),
                  onPressed: widget.canAccessRooms ? _joinByRoomName : null,
                  icon: const Icon(Icons.search),
                  label: const Text('Join by name'),
                ),
                IconButton(
                  key: const Key('refresh_rooms_button'),
                  onPressed: widget.canAccessRooms ? widget.onRefresh : null,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('room_search_field'),
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Search visible rooms',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            if (widget.activeRooms.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Rooms listening to'),
                      const SizedBox(height: 8),
                      Column(
                        children: [
                          for (int i = 0; i < widget.activeRooms.length; i++)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: i == widget.activeRooms.length - 1
                                    ? 0
                                    : 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(widget.activeRooms[i].roomName),
                                  ),
                                  if (widget.activeRooms[i].unreadCount > 0)
                                    Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        '${widget.activeRooms[i].unreadCount}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                    ),
                                  FilledButton.icon(
                                    key: Key(
                                      'resume_active_room_button_${widget.activeRooms[i].key}',
                                    ),
                                    onPressed: () => widget.onResumeActiveRoom(
                                      widget.activeRooms[i].key,
                                    ),
                                    icon: const Icon(Icons.chat),
                                    label: const Text('Resume'),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    key: Key(
                                      'disconnect_active_room_button_${widget.activeRooms[i].key}',
                                    ),
                                    onPressed: () async {
                                      await widget.onDisconnectActiveRoom(
                                        widget.activeRooms[i].key,
                                      );
                                    },
                                    icon: const Icon(Icons.link_off),
                                    label: const Text('Leave'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (widget.status != null)
              Text(
                widget.status!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 6),
            Expanded(
              child: rooms.isEmpty
                  ? const Center(child: Text('No visible rooms found.'))
                  : ListView.separated(
                      itemCount: rooms.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final RoomInfo room = rooms[index];
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              room.requiresSecurity
                                  ? Icons.lock
                                  : Icons.meeting_room,
                            ),
                            title: Text(room.roomName),
                            subtitle: Text(
                              '${room.hostName} • ${room.hostAddress.address}:${room.port}',
                            ),
                            trailing: FilledButton(
                              key: Key('join_room_button_$index'),
                              onPressed: widget.canAccessRooms
                                  ? () => _joinRoom(room)
                                  : null,
                              child: const Text('Join'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        activeItem: AppBottomNavItem.room,
        onOpenUsers: widget.onOpenNetworkOverview,
        onOpenRooms: widget.onOpenRooms,
        onOpenSettings: widget.onOpenSettings,
      ),
    );
  }
}
