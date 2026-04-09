import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';

import '../chat/controllers/lan_chat_controller.dart';
import '../chat/models/room_creation_data.dart';
import '../chat/models/room_info.dart';
import '../platform/hotspot_service.dart';
import '../security/app_lock_controller.dart';
import '../settings/theme_controller.dart';
import 'chat_screen.dart';
import 'create_room_screen.dart';
import 'home_screen.dart';
import 'rooms_screen.dart';
import 'settings_screen.dart';

enum AppStage { home, rooms, chat }

class AppFlowScreen extends StatefulWidget {
  const AppFlowScreen({
    super.key,
    required this.themeController,
    required this.appLockController,
    this.hotspotService = const MethodChannelHotspotService(),
  });

  final ThemeController themeController;
  final AppLockController appLockController;
  final HotspotService hotspotService;

  @override
  State<AppFlowScreen> createState() => _AppFlowScreenState();
}

class _AppFlowScreenState extends State<AppFlowScreen>
    with WidgetsBindingObserver {
  final LanChatController _controller = LanChatController();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  AppStage _stage = AppStage.home;
  String _userName = '';
  bool _isWifiConnected = false;
  bool _isHostNetworkMode = false;
  bool _lockOverlayVisible = false;

  bool get _canAccessRooms => _isWifiConnected || _isHostNetworkMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.appLockController.addListener(_onAppLockChanged);
    widget.appLockController.init().then((_) => _enforceAppLock());
    _initConnectivity();
    _controller.setStatus('Choose Host Network or Use Wi-Fi to continue.');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.appLockController.removeListener(_onAppLockChanged);
    _connectivitySubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onAppLockChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      widget.appLockController.markLocked();
      if (widget.appLockController.enabled && mounted) {
        setState(() {
          _lockOverlayVisible = true;
        });
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _enforceAppLock();
    }
  }

  Future<void> _enforceAppLock() async {
    final bool unlocked = await widget.appLockController.ensureUnlocked(
      reason: 'Unlock Secret Chat',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _lockOverlayVisible = !unlocked;
    });
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
        builder: (_) => SettingsScreen(
          themeController: widget.themeController,
          appLockController: widget.appLockController,
        ),
      ),
    );
  }

  Future<void> _onHostNetworkSelected(String userName) async {
    _userName = userName;
    final bool openedHotspotSettings = await widget.hotspotService
        .openHotspotSettings();

    if (!mounted) {
      return;
    }

    setState(() {
      _isHostNetworkMode = true;
      _stage = AppStage.rooms;
    });
    _controller.setStatus(
      openedHotspotSettings
          ? 'Hotspot settings opened. Turn on your hotspot, then create a room.'
          : 'Open mobile hotspot settings and turn it on, then create a room.',
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

  Future<void> _handleSystemBack() async {
    switch (_stage) {
      case AppStage.chat:
        await _leaveChat();
        break;
      case AppStage.rooms:
        if (!mounted) {
          return;
        }
        setState(() {
          _stage = AppStage.home;
        });
        break;
      case AppStage.home:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        Widget screen;
        switch (_stage) {
          case AppStage.home:
            screen = HomeScreen(
              onHostPressed: _onHostNetworkSelected,
              onWifiPressed: _onUseWifiSelected,
              onOpenSettings: _openSettings,
            );
            break;
          case AppStage.rooms:
            screen = RoomsScreen(
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
              onFindRoomByName: (String name) =>
                  _controller.findRoomByName(name, includeHidden: true),
              onJoinRoom: _joinRoom,
            );
            break;
          case AppStage.chat:
            screen = ChatScreen(
              controller: _controller,
              onLeave: _leaveChat,
              onOpenSettings: _openSettings,
            );
            break;
        }

        final bool lockVisible =
            _lockOverlayVisible || widget.appLockController.isLocked;
        final Widget content;
        if (!lockVisible) {
          content = screen;
        } else {
          content = Stack(
          children: [
            screen,
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.96),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock, size: 40),
                            const SizedBox(height: 10),
                            const Text(
                              'App is locked',
                              style: TextStyle(fontSize: 18),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Use biometric authentication or your screen lock to continue.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              key: const Key('unlock_app_button'),
                              onPressed: _enforceAppLock,
                              icon: const Icon(Icons.fingerprint),
                              label: const Text('Unlock'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          );
        }

        return PopScope<void>(
          canPop: _stage == AppStage.home,
          onPopInvokedWithResult: (bool didPop, void _) {
            if (didPop) {
              return;
            }
            _handleSystemBack();
          },
          child: content,
        );
      },
    );
  }
}
