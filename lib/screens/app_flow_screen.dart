import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../chat/controllers/lan_chat_controller.dart';
import '../chat/models/room_creation_data.dart';
import '../chat/models/room_info.dart';
import '../settings/theme_controller.dart';
import 'chat_screen.dart';
import 'create_room_screen.dart';
import 'home_screen.dart';
import 'rooms_screen.dart';
import 'settings_screen.dart';

enum AppStage { home, rooms, chat }

class AppFlowScreen extends StatefulWidget {
  const AppFlowScreen({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  State<AppFlowScreen> createState() => _AppFlowScreenState();
}

class _AppFlowScreenState extends State<AppFlowScreen> {
  final LanChatController _controller = LanChatController();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  AppStage _stage = AppStage.home;
  String _userName = '';
  bool _isWifiConnected = false;
  bool _isHostNetworkMode = false;

  bool get _canAccessRooms => _isWifiConnected || _isHostNetworkMode;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _controller.setStatus('Choose Host Network or Use Wi-Fi to continue.');
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    final List<ConnectivityResult> results = await _connectivity
        .checkConnectivity();
    _applyConnectivity(results);

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _applyConnectivity,
    );
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    final bool connected =
        results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);

    if (!mounted) {
      return;
    }

    setState(() {
      _isWifiConnected = connected;
    });

    if (connected) {
      _controller.startDiscovery();
      if (!_isHostNetworkMode) {
        _controller.setStatus(
          'Connected to Wi-Fi. You can create or join rooms.',
        );
      }
    } else if (!_isHostNetworkMode) {
      _controller.setStatus(
        'No Wi-Fi connection. Use Host Network or connect to Wi-Fi.',
      );
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(themeController: widget.themeController),
      ),
    );
  }

  Future<void> _onHostNetworkSelected(String userName) async {
    _userName = userName;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Turn On Hotspot'),
          content: const Text(
            'Enable your phone hotspot from system settings, then tap Continue.\n\n'
            'After that, you will be taken to Rooms.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isHostNetworkMode = true;
      _stage = AppStage.rooms;
    });
    _controller.setStatus(
      'Host network mode active. Create a room for users connected to your hotspot.',
    );
    await _controller.startDiscovery();
  }

  Future<void> _onUseWifiSelected(String userName) async {
    _userName = userName;
    setState(() {
      _isHostNetworkMode = false;
      _stage = AppStage.rooms;
    });

    final List<ConnectivityResult> results = await _connectivity
        .checkConnectivity();
    _applyConnectivity(results);
  }

  Future<void> _createRoom() async {
    if (!_canAccessRooms) {
      _showSnack('Connect to Wi-Fi or use Host Network first.');
      return;
    }

    final RoomCreationData? data = await Navigator.of(context)
        .push<RoomCreationData>(
          MaterialPageRoute<RoomCreationData>(
            builder: (_) => const CreateRoomScreen(),
          ),
        );

    if (data == null) {
      return;
    }

    if (_controller.isRoomNameTaken(data.roomName)) {
      _showSnack('Room name already exists. Choose a different name.');
      return;
    }

    final bool hosted = await _controller.hostRoom(
      yourName: _userName,
      room: data.roomName,
      hidden: data.hidden,
      securityType: data.securityType,
      securityValue: data.securityValue,
    );

    if (!mounted) {
      return;
    }

    if (hosted) {
      setState(() {
        _stage = AppStage.chat;
      });
    } else {
      _showSnack(_controller.status ?? 'Unable to create room.');
    }
  }

  Future<void> _joinRoom(RoomInfo room, String? securityValue) async {
    if (!_canAccessRooms) {
      _showSnack('Connect to Wi-Fi or use Host Network first.');
      return;
    }

    final bool joined = await _controller.joinRoom(
      room: room,
      yourName: _userName,
      securityValue: securityValue,
    );

    if (!mounted) {
      return;
    }

    if (joined) {
      setState(() {
        _stage = AppStage.chat;
      });
    } else {
      _showSnack(_controller.status ?? 'Unable to join room.');
    }
  }

  Future<void> _joinByName(String roomName, String? securityValue) async {
    final RoomInfo? room = _controller.findRoomByName(
      roomName,
      includeHidden: true,
    );

    if (room == null) {
      _showSnack('Room not found. Check name and try again.');
      return;
    }

    await _joinRoom(room, securityValue);
  }

  Future<void> _leaveChat() async {
    await _controller.disconnect();
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = AppStage.rooms;
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        switch (_stage) {
          case AppStage.home:
            return HomeScreen(
              onHostPressed: _onHostNetworkSelected,
              onWifiPressed: _onUseWifiSelected,
              onOpenSettings: _openSettings,
            );
          case AppStage.rooms:
            return RoomsScreen(
              rooms: _controller.visibleRooms,
              userName: _userName,
              isHostNetworkMode: _isHostNetworkMode,
              canAccessRooms: _canAccessRooms,
              status: _controller.status,
              onBack: () {
                setState(() {
                  _stage = AppStage.home;
                });
              },
              onOpenSettings: _openSettings,
              onRefresh: _controller.startDiscovery,
              onCreateRoom: _createRoom,
              onJoinRoom: _joinRoom,
              onJoinByName: _joinByName,
            );
          case AppStage.chat:
            return ChatScreen(
              controller: _controller,
              onLeave: _leaveChat,
              onOpenSettings: _openSettings,
            );
        }
      },
    );
  }
}
