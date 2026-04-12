// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:secret_chat/chat/chat_constants.dart';
import 'package:secret_chat/chat/controllers/direct_chat_controller.dart';
import 'package:secret_chat/chat/controllers/lan_chat_controller.dart';
import 'package:secret_chat/chat/models/network_user_info.dart';
import 'package:secret_chat/chat/models/room_creation_data.dart';
import 'package:secret_chat/chat/models/room_info.dart';
import 'package:secret_chat/platform/hotspot_service.dart';
import 'package:secret_chat/screens/chat_screen.dart';
import 'package:secret_chat/screens/create_room_screen.dart';
import 'package:secret_chat/screens/home_screen.dart';
import 'package:secret_chat/screens/models/active_room_item.dart';
import 'package:secret_chat/screens/models/app_stage.dart';
import 'package:secret_chat/screens/network_overview_screen.dart';
import 'package:secret_chat/screens/rooms_screen.dart';
import 'package:secret_chat/screens/settings_screen.dart';
import 'package:secret_chat/security/app_lock_controller.dart';
import 'package:secret_chat/settings/default_room_listening_controller.dart';
import 'package:secret_chat/settings/network_privacy_controller.dart';
import 'package:secret_chat/settings/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppFlowScreen extends StatefulWidget {
  const AppFlowScreen({
    super.key,
    required this.themeController,
    required this.appLockController,
    required this.defaultRoomListeningController,
    required this.networkPrivacyController,
    this.hotspotService = const MethodChannelHotspotService(),
  });

  final ThemeController themeController;
  final AppLockController appLockController;
  final DefaultRoomListeningController defaultRoomListeningController;
  final NetworkPrivacyController networkPrivacyController;
  final HotspotService hotspotService;

  @override
  State<AppFlowScreen> createState() => _AppFlowScreenState();
}

class _AppFlowScreenState extends State<AppFlowScreen>
    with WidgetsBindingObserver {
  static const String _prefKeyDisplayName = 'user_display_name';

  final LanChatController _discoveryController = LanChatController();
  final Map<String, LanChatController> _roomControllersByKey =
      <String, LanChatController>{};
  final Map<String, VoidCallback> _roomListenerByKey = <String, VoidCallback>{};
  final Map<String, int> _roomUnreadCountByKey = <String, int>{};
  final Map<String, int> _lastIncomingCountByKey = <String, int>{};
  final Map<String, bool> _listenOnLeaveByRoomKey = <String, bool>{};
  final Map<String, String> _roomTitleByKey = <String, String>{};
  final Set<String> _pendingDisposeRoomKeys = <String>{};
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  AppStage _stage = AppStage.home;
  String _userName = '';
  bool _isWifiConnected = false;
  bool _isHostNetworkMode = false;
  bool _lockOverlayVisible = false;
  String? _activeRoomKey;

  bool get _canAccessRooms => _isWifiConnected || _isHostNetworkMode;

  bool _isDirectRoomName(String roomName) {
    return isDirectChatRoomName(roomName);
  }

  String _directPeerToken(String roomName) {
    final String trimmed = roomName.trim();
    if (!_isDirectRoomName(trimmed)) {
      return '';
    }
    return trimmed.substring(directChatRoomPrefix.length).trim();
  }

  String _directRoomNameForUser(NetworkUserInfo user) {
    final String preferredToken = user.userId.trim();
    final String fallbackToken = user.displayName.trim();
    final String token = preferredToken.isNotEmpty
        ? preferredToken
        : fallbackToken;
    return '$directChatRoomPrefix$token';
  }

  String? _directRoomTitle(RoomInfo room, {String? preferredTitle}) {
    final String preferred = preferredTitle?.trim() ?? '';
    if (preferred.isNotEmpty) {
      return preferred;
    }
    if (!_isDirectRoomName(room.roomName)) {
      return null;
    }

    final String host = room.hostName.trim();
    if (host.isNotEmpty &&
        host.toLowerCase() != _userName.trim().toLowerCase()) {
      return host;
    }

    final String token = _directPeerToken(room.roomName);
    return token.isEmpty ? null : token;
  }

  List<ActiveRoomItem> get _overviewActiveRooms {
    return _activeRooms
        .where((ActiveRoomItem room) => !_isDirectRoomName(room.roomName))
        .toList();
  }

  List<ActiveRoomItem> get _overviewUserChats {
    final List<ActiveRoomItem> chats =
        _activeRooms
            .where((ActiveRoomItem room) => _isDirectRoomName(room.roomName))
            .map((ActiveRoomItem room) {
              final String preferredTitle =
                  _roomTitleByKey[room.key]?.trim() ?? '';
              final String token = _directPeerToken(room.roomName);
              final String title = preferredTitle.isNotEmpty
                  ? preferredTitle
                  : (token.isNotEmpty ? token : room.roomName);
              return ActiveRoomItem(
                key: room.key,
                roomName: title,
                unreadCount: room.unreadCount,
                listenOnLeave: room.listenOnLeave,
              );
            })
            .toList()
          ..sort(
            (a, b) =>
                a.roomName.toLowerCase().compareTo(b.roomName.toLowerCase()),
          );
    return chats;
  }

  List<ActiveRoomItem> get _roomsActiveRooms => _overviewActiveRooms;

  List<NetworkUserInfo> get _networkUsers {
    final String localId = _discoveryController.localUserId ?? '';
    final Map<String, NetworkUserInfo> usersById = <String, NetworkUserInfo>{};
    final Set<String> pendingDirectSenderIds = <String>{};
    final Map<String, Set<String>> directRoomKeysBySenderId =
        <String, Set<String>>{};

    for (final RoomInfo room in _discoveryController.discoveredRooms) {
      if (!isDirectChatRoomTargetedToUser(
        room,
        localUserId: localId,
        localUserName: _userName,
      )) {
        continue;
      }

      final String senderId = room.hostUserId.trim().isNotEmpty
          ? room.hostUserId.trim()
          : '${room.hostAddress.address}:${room.hostName}';
      final String senderKey = senderId.toLowerCase();
      pendingDirectSenderIds.add(senderKey);
      directRoomKeysBySenderId
          .putIfAbsent(senderKey, () => <String>{})
          .add(room.key.toLowerCase());
    }

    for (final RoomInfo room in _discoveryController.discoveredRooms) {
      final String userId = room.hostUserId.trim().isEmpty
          ? '${room.hostAddress.address}:${room.hostName}'
          : room.hostUserId.trim();
      final String userKey = userId.toLowerCase();
      final Set<String> knownDirectRoomKeys =
          directRoomKeysBySenderId[userKey] ?? <String>{};

      final List<ActiveRoomItem> directRoomsForUser = _activeRooms.where((
        ActiveRoomItem active,
      ) {
        if (!_isDirectRoomName(active.roomName)) {
          return false;
        }
        // Joining sender-hosted pending rooms keeps the discovery room key,
        // so key match is required to clear dot state after opening chat.
        if (knownDirectRoomKeys.contains(active.key.toLowerCase())) {
          return true;
        }
        final String token = _directPeerToken(active.roomName).toLowerCase();
        return token == userKey || token == room.hostName.toLowerCase();
      }).toList();

      final int pendingCount = directRoomsForUser.fold<int>(
        0,
        (int total, ActiveRoomItem active) => total + active.unreadCount,
      );

      if (directRoomsForUser.isNotEmpty) {
        // Active direct chats are shown in a dedicated section above the
        // network user list and should not be duplicated below.
        continue;
      }

      final bool hasPending =
          pendingDirectSenderIds.contains(userKey) &&
              directRoomsForUser.isEmpty ||
          pendingCount > 0;

      usersById[userId] = NetworkUserInfo(
        userId: userId,
        displayName: room.hostName,
        hostAddress: room.hostAddress.address,
        hiddenFromNetwork: room.hostHiddenFromNetwork,
        allowsIdChat: room.hostAllowsIdChat,
        isCurrentUser: localId.isNotEmpty && userId == localId,
        hasPendingMessages: hasPending,
        pendingMessageCount: pendingCount,
      );
    }

    final List<NetworkUserInfo> users = usersById.values.toList()
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );

    return users.where((NetworkUserInfo user) => !user.isCurrentUser).toList();
  }

  LanChatController? get _activeRoomController =>
      _activeRoomKey == null ? null : _roomControllersByKey[_activeRoomKey!];

  List<ActiveRoomItem> get _activeRooms {
    final List<ActiveRoomItem> result = <ActiveRoomItem>[];
    for (final MapEntry<String, LanChatController> entry
        in _roomControllersByKey.entries) {
      final LanChatController controller = entry.value;
      if (controller.mode != ChatMode.hosting &&
          controller.mode != ChatMode.connected) {
        continue;
      }
      result.add(
        ActiveRoomItem(
          key: entry.key,
          roomName: controller.roomName ?? 'Room',
          unreadCount: _roomUnreadCountByKey[entry.key] ?? 0,
          listenOnLeave: _listenOnLeaveByRoomKey[entry.key] ?? false,
        ),
      );
    }
    return result;
  }

  List<RoomInfo> get _visibleDiscoveredRooms {
    final Set<String> activeRoomNames = _roomControllersByKey.values
        .where((LanChatController controller) {
          return controller.mode == ChatMode.hosting ||
              controller.mode == ChatMode.connected;
        })
        .map(
          (LanChatController controller) =>
              (controller.roomName ?? '').trim().toLowerCase(),
        )
        .where((String name) => name.isNotEmpty)
        .toSet();

    return _discoveryController.visibleRooms.where((RoomInfo room) {
      return !activeRoomNames.contains(room.roomName.trim().toLowerCase()) &&
          !_isDirectRoomName(room.roomName);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.appLockController.addListener(_onAppLockChanged);
    widget.defaultRoomListeningController.addListener(_onControllersChanged);
    widget.networkPrivacyController.addListener(_onControllersChanged);
    _discoveryController.addListener(_onControllersChanged);
    widget.appLockController.init().then((_) => _enforceAppLock());
    widget.defaultRoomListeningController.init();
    widget.networkPrivacyController.init();
    _loadDisplayName();
    unawaited(_discoveryController.ensureLocalUserId());
    _initConnectivity();
    _discoveryController.setStatus(
      'Choose Host Network or Use Wi-Fi to continue.',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.appLockController.removeListener(_onAppLockChanged);
    widget.defaultRoomListeningController.removeListener(_onControllersChanged);
    widget.networkPrivacyController.removeListener(_onControllersChanged);
    _connectivitySubscription?.cancel();
    _discoveryController.removeListener(_onControllersChanged);
    _discoveryController.dispose();
    for (final String roomKey in _roomControllersByKey.keys.toList()) {
      final LanChatController? controller = _roomControllersByKey[roomKey];
      final VoidCallback? listener = _roomListenerByKey[roomKey];
      if (controller != null && listener != null) {
        controller.removeListener(listener);
      }
      controller?.dispose();
    }
    _roomListenerByKey.clear();
    _roomUnreadCountByKey.clear();
    _lastIncomingCountByKey.clear();
    _listenOnLeaveByRoomKey.clear();
    _pendingDisposeRoomKeys.clear();
    _roomControllersByKey.clear();
    super.dispose();
  }

  int _incomingMessageCount(LanChatController controller) {
    final String? localId = controller.localUserId;
    return controller.messages
        .where((message) => !message.system && message.senderId != localId)
        .length;
  }

  void _attachRoomController({
    required String roomKey,
    required LanChatController controller,
  }) {
    _roomControllersByKey[roomKey] = controller;
    _roomUnreadCountByKey.putIfAbsent(roomKey, () => 0);
    _lastIncomingCountByKey[roomKey] = _incomingMessageCount(controller);
    _listenOnLeaveByRoomKey.putIfAbsent(roomKey, () => false);

    void listener() {
      _onRoomControllerChanged(roomKey);
    }

    _roomListenerByKey[roomKey] = listener;
    controller.addListener(listener);
  }

  bool _defaultListenOnLeave() {
    return widget.defaultRoomListeningController.enabled;
  }

  void _onRoomControllerChanged(String roomKey) {
    final LanChatController? controller = _roomControllersByKey[roomKey];
    if (controller == null) {
      return;
    }

    if (controller.mode == ChatMode.idle) {
      _scheduleRoomDisposal(roomKey);
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final int currentIncoming = _incomingMessageCount(controller);
    final int previousIncoming =
        _lastIncomingCountByKey[roomKey] ?? currentIncoming;
    if (currentIncoming > previousIncoming) {
      final bool isRoomVisible =
          _stage == AppStage.chat && _activeRoomKey == roomKey;
      if (!isRoomVisible) {
        _roomUnreadCountByKey[roomKey] =
            (_roomUnreadCountByKey[roomKey] ?? 0) +
            (currentIncoming - previousIncoming);
      }
    }
    _lastIncomingCountByKey[roomKey] = currentIncoming;

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _syncNetworkPresence() async {
    final bool canBroadcast = _isWifiConnected || _isHostNetworkMode;
    final bool hiddenFromNetwork =
        widget.networkPrivacyController.hideFromNetwork;
    final bool allowsIdChat = hiddenFromNetwork
        ? !widget.networkPrivacyController.blockIdChatWhenHidden
        : true;

    await _discoveryController.updatePresenceAnnouncement(
      userName: canBroadcast && !hiddenFromNetwork ? _userName : '',
      hiddenFromNetwork: !canBroadcast || hiddenFromNetwork,
      allowsIdChat: allowsIdChat,
    );
  }

  void _openRoom(String roomKey) {
    if (!_roomControllersByKey.containsKey(roomKey)) {
      return;
    }
    _roomUnreadCountByKey[roomKey] = 0;
    _activeRoomKey = roomKey;
    _stage = AppStage.chat;
  }

  void _scheduleRoomDisposal(String roomKey) {
    if (_pendingDisposeRoomKeys.contains(roomKey)) {
      return;
    }
    _pendingDisposeRoomKeys.add(roomKey);
    Future<void>.microtask(() {
      _pendingDisposeRoomKeys.remove(roomKey);
      _disposeRoomController(roomKey);
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _disposeRoomController(String roomKey) {
    final LanChatController? controller = _roomControllersByKey.remove(roomKey);
    if (controller == null) {
      return;
    }

    final VoidCallback? listener = _roomListenerByKey.remove(roomKey);
    if (listener != null) {
      controller.removeListener(listener);
    }
    controller.dispose();
    _roomUnreadCountByKey.remove(roomKey);
    _lastIncomingCountByKey.remove(roomKey);
    _listenOnLeaveByRoomKey.remove(roomKey);
    _roomTitleByKey.remove(roomKey);
    if (_activeRoomKey == roomKey) {
      _activeRoomKey = null;
    }
  }

  void _onAppLockChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onControllersChanged() {
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
      _discoveryController.startDiscovery();
      if (!_isHostNetworkMode) {
        _discoveryController.setStatus(
          'Connected to Wi-Fi. You can create or join rooms.',
        );
      }
    } else if (!_isHostNetworkMode) {
      _discoveryController.setStatus(
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
          defaultRoomListeningController: widget.defaultRoomListeningController,
          networkPrivacyController: widget.networkPrivacyController,
          onOpenNetworkOverview: _openNetworkOverviewFromBottomNav,
          onOpenRooms: _openRoomsFromBottomNav,
          onOpenSettings: () {},
        ),
      ),
    );
  }

  Future<void> _loadDisplayName() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String value = (prefs.getString(_prefKeyDisplayName) ?? '').trim();
      if (!mounted || value.isEmpty) {
        return;
      }
      setState(() {
        _userName = value;
      });
      unawaited(_syncNetworkPresence());
    } catch (_) {
      // Ignore persistence errors and keep runtime defaults.
    }
  }

  Future<void> _saveDisplayName(String value) async {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyDisplayName, trimmed);
    } catch (_) {
      // Ignore persistence failures.
    }
  }

  Future<void> _onHostNetworkSelected(String userName) async {
    _userName = userName;
    await _saveDisplayName(userName);
    final bool openedHotspotSettings = await widget.hotspotService
        .openHotspotSettings();

    if (!mounted) {
      return;
    }

    setState(() {
      _isHostNetworkMode = true;
      _stage = AppStage.networkOverview;
    });
    _discoveryController.setStatus(
      openedHotspotSettings
          ? 'Hotspot settings opened. Turn on your hotspot, then create a room.'
          : 'Open mobile hotspot settings and turn it on, then create a room.',
    );
    await _discoveryController.startDiscovery();
    await _syncNetworkPresence();
  }

  Future<void> _onUseWifiSelected(String userName) async {
    _userName = userName;
    await _saveDisplayName(userName);
    setState(() {
      _isHostNetworkMode = false;
      _stage = AppStage.networkOverview;
    });

    final List<ConnectivityResult> results = await _connectivity
        .checkConnectivity();
    _applyConnectivity(results);
    await _syncNetworkPresence();
  }

  void _openRoomsFromOverview() {
    setState(() {
      _stage = AppStage.rooms;
      unawaited(_syncNetworkPresence());
    });
  }

  void _openNetworkOverviewFromBottomNav() {
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = AppStage.networkOverview;
    });
  }

  void _openRoomsFromBottomNav() {
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = AppStage.rooms;
    });
  }

  void _openUserChatsFromOverview() {
    if (_overviewUserChats.isNotEmpty) {
      setState(() {
        _openRoom(_overviewUserChats.first.key);
      });
      return;
    }

    if (_networkUsers.isNotEmpty) {
      unawaited(_openUserChat(_networkUsers.first));
      return;
    }

    _showSnack('No users available for direct chat yet.');
  }

  Future<void> _openUserChat(NetworkUserInfo user) async {
    if (!_canAccessRooms) {
      _showSnack('Connect to Wi-Fi or use Host Network first.');
      return;
    }

    final String intendedRoomName = _directRoomNameForUser(user);
    final String hostedRoomKey =
        'host:${intendedRoomName.trim().toLowerCase()}';

    final LanChatController? localDirectController =
        _roomControllersByKey[hostedRoomKey];
    if (localDirectController != null &&
        localDirectController.mode != ChatMode.idle) {
      setState(() {
        _roomTitleByKey[hostedRoomKey] = user.displayName;
        _openRoom(hostedRoomKey);
      });
      return;
    }

    RoomInfo? directRoom;
    for (final RoomInfo room in _discoveryController.discoveredRooms) {
      if (!room.hidden) {
        continue;
      }
      if (!_isDirectRoomName(room.roomName)) {
        continue;
      }
      if (room.hostUserId != user.userId && room.hostName != user.displayName) {
        continue;
      }
      directRoom = room;
      break;
    }

    if (directRoom != null) {
      await _joinRoom(directRoom, null, preferredTitle: user.displayName);
      return;
    }

    // Fallback: host a hidden direct room so chat can start immediately.
    final DirectChatController roomController = DirectChatController();
    final bool hosted = await roomController.hostRoom(
      yourName: _userName,
      room: intendedRoomName,
      hidden: true,
      historyEnabled: true,
    );

    if (!mounted) {
      return;
    }

    if (!hosted) {
      _showSnack(roomController.status ?? 'Unable to start direct chat.');
      roomController.dispose();
      return;
    }

    setState(() {
      _attachRoomController(roomKey: hostedRoomKey, controller: roomController);
      _roomTitleByKey[hostedRoomKey] = user.displayName;
      _listenOnLeaveByRoomKey[hostedRoomKey] = _defaultListenOnLeave();
      _openRoom(hostedRoomKey);
    });
    _showSnack(
      'Direct chat started. Messages will sync when ${user.displayName} joins.',
    );
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

    if (_discoveryController.isRoomNameTaken(data.roomName)) {
      _showSnack('Room name already exists. Choose a different name.');
      return;
    }

    final String roomKey = 'host:${data.roomName.trim().toLowerCase()}';
    if (_roomControllersByKey.containsKey(roomKey)) {
      setState(() {
        _openRoom(roomKey);
      });
      return;
    }

    final LanChatController roomController = LanChatController();

    final bool hosted = await roomController.hostRoom(
      yourName: _userName,
      room: data.roomName,
      hidden: data.hidden,
      historyEnabled: data.historyEnabled,
      securityType: data.securityType,
      securityValue: data.securityValue,
    );

    if (!mounted) {
      return;
    }

    if (hosted) {
      setState(() {
        _attachRoomController(roomKey: roomKey, controller: roomController);
        _listenOnLeaveByRoomKey[roomKey] = _defaultListenOnLeave();
        _openRoom(roomKey);
      });
    } else {
      _showSnack(roomController.status ?? 'Unable to create room.');
      roomController.dispose();
    }
  }

  Future<void> _joinRoom(
    RoomInfo room,
    String? securityValue, {
    String? preferredTitle,
  }) async {
    if (!_canAccessRooms) {
      _showSnack('Connect to Wi-Fi or use Host Network first.');
      return;
    }

    final String roomKey = room.key;
    final String? roomTitle = _directRoomTitle(
      room,
      preferredTitle: preferredTitle,
    );
    final LanChatController? existing = _roomControllersByKey[roomKey];
    if (existing != null && existing.mode != ChatMode.idle) {
      setState(() {
        if (roomTitle != null) {
          _roomTitleByKey[roomKey] = roomTitle;
        }
        _openRoom(roomKey);
      });
      return;
    }

    final bool isDirectChat = _isDirectRoomName(room.roomName);
    final LanChatController roomController = isDirectChat
        ? DirectChatController()
        : LanChatController();

    final bool joined = await roomController.joinRoom(
      room: room,
      yourName: _userName,
      securityValue: securityValue,
    );

    if (!mounted) {
      return;
    }

    if (joined) {
      setState(() {
        _attachRoomController(roomKey: roomKey, controller: roomController);
        if (roomTitle != null) {
          _roomTitleByKey[roomKey] = roomTitle;
        }
        _listenOnLeaveByRoomKey[roomKey] = _defaultListenOnLeave();
        // Intentional UX: secured joins stay on Rooms until host admission is
        // confirmed. This prevents revealing whether a credential guess worked.
        if (!room.requiresSecurity || isDirectChat) {
          _openRoom(roomKey);
        }
      });
    } else {
      _showSnack(roomController.status ?? 'Unable to join room.');
      roomController.dispose();
    }
  }

  Future<void> _leaveChat() async {
    final String? roomKey = _activeRoomKey;
    final LanChatController? controller = _activeRoomController;
    final bool isDirectChat =
        controller != null && _isDirectRoomName(controller.roomName ?? '');
    if (roomKey == null || controller == null) {
      setState(() {
        _stage = isDirectChat ? AppStage.networkOverview : AppStage.rooms;
      });
      return;
    }

    if (_listenOnLeaveByRoomKey[roomKey] == true) {
      if (!mounted) {
        return;
      }
      setState(() {
        _stage = isDirectChat ? AppStage.networkOverview : AppStage.rooms;
      });
      _showSnack('Listening in background. Open room again to resume chat.');
      return;
    }

    await _disconnectRoom(roomKey, showSnack: false);
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = isDirectChat ? AppStage.networkOverview : AppStage.rooms;
    });
  }

  Future<void> _disconnectRoom(String roomKey, {bool showSnack = true}) async {
    final LanChatController? controller = _roomControllersByKey[roomKey];
    if (controller == null) {
      return;
    }

    await controller.disconnect();
    _scheduleRoomDisposal(roomKey);

    if (_activeRoomKey == roomKey) {
      _activeRoomKey = null;
    }

    if (!mounted) {
      return;
    }
    setState(() {});
    if (showSnack) {
      _showSnack('Disconnected from room.');
    }
  }

  Future<void> _disconnectActiveRoomFromRooms(String roomKey) async {
    await _disconnectRoom(roomKey);
    if (!mounted) {
      return;
    }
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
          _stage = AppStage.networkOverview;
        });
        break;
      case AppStage.networkOverview:
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
    Widget screen;
    switch (_stage) {
      case AppStage.home:
        screen = HomeScreen(
          onHostPressed: _onHostNetworkSelected,
          onWifiPressed: _onUseWifiSelected,
          // Intentionally disabled on first screen until host/wifi mode is chosen.
          // This avoids entering user/room flows before network mode is established.
          onOpenNetworkOverview: null,
          onOpenRooms: null,
          onOpenSettings: _openSettings,
          initialDisplayName: _userName,
          onDisplayNameChanged: (String value) {
            _userName = value.trim();
            _saveDisplayName(value);
            unawaited(_syncNetworkPresence());
          },
        );
        break;
      case AppStage.networkOverview:
        screen = NetworkOverviewScreen(
          userName: _userName,
          isHostNetworkMode: _isHostNetworkMode,
          status: _discoveryController.status,
          activeRooms: _overviewActiveRooms,
          activeUserChats: _overviewUserChats,
          discoveredRooms: _visibleDiscoveredRooms,
          networkUsers: _networkUsers,
          onOpenNetworkOverview: _openNetworkOverviewFromBottomNav,
          onOpenRooms: _openRoomsFromOverview,
          onOpenSettings: _openSettings,
          onOpenActiveRoom: (ActiveRoomItem room) {
            _openRoom(room.key);
          },
          onOpenUserChat: _openUserChat,
        );
        break;
      case AppStage.rooms:
        screen = RoomsScreen(
          rooms: _visibleDiscoveredRooms,
          userName: _userName,
          isHostNetworkMode: _isHostNetworkMode,
          canAccessRooms: _canAccessRooms,
          status: _discoveryController.status,
          activeRooms: _roomsActiveRooms,
          activeRoomKey: _activeRoomKey,
          onResumeActiveRoom: (String roomKey) {
            if (!_roomControllersByKey.containsKey(roomKey)) {
              return;
            }
            setState(() {
              _openRoom(roomKey);
            });
          },
          onDisconnectActiveRoom: _disconnectActiveRoomFromRooms,
          onOpenNetworkOverview: _openNetworkOverviewFromBottomNav,
          onOpenRooms: _openRoomsFromBottomNav,
          onOpenSettings: _openSettings,
          onRefresh: _discoveryController.startDiscovery,
          onCreateRoom: _createRoom,
          onFindRoomByName: (String name) {
            if (_isDirectRoomName(name)) {
              return null;
            }
            return _discoveryController.findRoomByName(
              name,
              includeHidden: true,
            );
          },
          onJoinRoom: (RoomInfo room, String? securityValue) =>
              _joinRoom(room, securityValue),
        );
        break;
      case AppStage.chat:
        final LanChatController? controller = _activeRoomController;
        if (controller == null) {
          screen = RoomsScreen(
            rooms: _visibleDiscoveredRooms,
            userName: _userName,
            isHostNetworkMode: _isHostNetworkMode,
            canAccessRooms: _canAccessRooms,
            status: _discoveryController.status,
            activeRooms: _roomsActiveRooms,
            activeRoomKey: _activeRoomKey,
            onResumeActiveRoom: (String roomKey) {
              if (!_roomControllersByKey.containsKey(roomKey)) {
                return;
              }
              setState(() {
                _openRoom(roomKey);
              });
            },
            onDisconnectActiveRoom: _disconnectActiveRoomFromRooms,
            onOpenNetworkOverview: _openNetworkOverviewFromBottomNav,
            onOpenRooms: _openRoomsFromBottomNav,
            onOpenSettings: _openSettings,
            onRefresh: _discoveryController.startDiscovery,
            onCreateRoom: _createRoom,
            onFindRoomByName: (String name) {
              if (_isDirectRoomName(name)) {
                return null;
              }
              return _discoveryController.findRoomByName(
                name,
                includeHidden: true,
              );
            },
            onJoinRoom: (RoomInfo room, String? securityValue) =>
                _joinRoom(room, securityValue),
          );
        } else {
          screen = ChatScreen(
            controller: controller,
            title: _roomTitleByKey[_activeRoomKey!],
            listenOnLeave: _listenOnLeaveByRoomKey[_activeRoomKey!] ?? false,
            onListenOnLeaveChanged: (bool enabled) {
              final String? roomKey = _activeRoomKey;
              if (roomKey == null) {
                return;
              }
              setState(() {
                _listenOnLeaveByRoomKey[roomKey] = enabled;
              });
            },
            onLeave: _leaveChat,
            onOpenNetworkOverview: _openNetworkOverviewFromBottomNav,
            onOpenRooms: _openRoomsFromBottomNav,
            onOpenSettings: _openSettings,
          );
        }
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
  }
}
