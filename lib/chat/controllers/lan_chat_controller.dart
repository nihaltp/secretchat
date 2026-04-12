// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat_constants.dart';
import '../models/chat_message.dart';
import '../models/room_info.dart';

part 'lan_chat_controller_types.dart';
part 'lan_chat_controller_network.dart';
part 'lan_chat_controller_history_sync.dart';
part 'lan_chat_controller_message_store.dart';

class LanChatController extends ChangeNotifier {
  static const int _historyPageSize = 25;
  static const String _prefKeyLocalUserId = 'secret_chat_local_user_id';

  LanChatController({
    Future<int> Function()? batteryLevelProvider,
    Future<String> Function()? localUserIdProvider,
    int? chatPortOverride,
    int? discoveryPortOverride,
  }) : _batteryLevelProvider = batteryLevelProvider ?? _defaultBatteryLevel,
       _localUserIdProvider = localUserIdProvider,
       _chatPort = chatPortOverride ?? roomChatPort,
       _discoveryPort = discoveryPortOverride ?? roomDiscoveryPort;

  final List<ChatMessage> messages = <ChatMessage>[];
  final List<String> participants = <String>[];
  final Map<String, RoomInfo> _roomsByKey = <String, RoomInfo>{};
  final Set<String> _messageIds = <String>{};
  final List<_HistoryEntry> _historyEntries = <_HistoryEntry>[];
  final List<_HistoryEntry> _localSentEntries = <_HistoryEntry>[];
  final Map<String, List<_PresenceWindow>> _presenceWindowsByUser =
      <String, List<_PresenceWindow>>{};
  final Map<String, _ParticipantState> _participantsById =
      <String, _ParticipantState>{};
  final Map<String, Completer<void>> _pendingHistoryRequests =
      <String, Completer<void>>{};
  final Future<int> Function() _batteryLevelProvider;
  final Future<String> Function()? _localUserIdProvider;
  final int _chatPort;
  final int _discoveryPort;

  ChatMode mode = ChatMode.idle;
  String? roomName;
  String? localUserName;
  String? localUserId;
  String? status;
  String? hostAddress;
  bool _hostHidden = false;
  bool _hostHistoryEnabled = false;
  bool _joinedRoomHistoryEnabled = false;
  bool _awaitingFailover = false;
  RoomSecurityType _hostSecurityType = RoomSecurityType.none;
  String? _hostSecurityValue;
  bool _roomHidden = false;
  bool _roomHistoryEnabled = false;
  RoomSecurityType _roomSecurityType = RoomSecurityType.none;
  String? _roomSecurityValue;
  int _nextHistorySequence = 1;
  int? _historyCursorBeforeSequence;
  int _historyRequestCounter = 0;
  bool _historyHasMore = false;
  bool _historyLoading = false;
  Timer? _batteryUpdateTimer;
  final Map<String, Timer> _ephemeralMessageTimers = <String, Timer>{};
  bool _deferAnnouncementsUntilFirstMessage = false;

  RawDatagramSocket? _discoveryListener;
  RawDatagramSocket? _alternateDiscoveryListener;
  ServerSocket? _serverSocket;
  Socket? _serverConnection;
  Timer? _announcementTimer;
  Timer? _presenceAnnouncementTimer;
  Timer? _roomsCleanupTimer;
  final Map<String, _ClientPeer> _clients = <String, _ClientPeer>{};
  final Map<String, _HistorySyncTarget> _historySyncTargetsByRequest =
      <String, _HistorySyncTarget>{};
  bool _disposed = false;

  bool get historyEnabled => mode == ChatMode.hosting
      ? _hostHistoryEnabled
      : _joinedRoomHistoryEnabled;

  bool get historyLoading => _historyLoading;

  bool get hasMoreHistory => _historyHasMore;

  static Future<int> _defaultBatteryLevel() async {
    final Battery battery = Battery();
    try {
      return await battery.batteryLevel;
    } catch (_) {
      return 50;
    }
  }

  Future<String> _loadOrCreateLocalUserId() async {
    if (_localUserIdProvider != null) {
      return _localUserIdProvider();
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString(_prefKeyLocalUserId);
    if (stored != null && stored.trim().isNotEmpty) {
      return stored;
    }

    final String generated = _generateId();
    await prefs.setString(_prefKeyLocalUserId, generated);
    return generated;
  }

  Future<String> ensureLocalUserId() {
    return _loadOrCreateLocalUserId();
  }

  List<RoomInfo> get discoveredRooms {
    final List<RoomInfo> rooms = _roomsByKey.values.toList();
    rooms.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return rooms;
  }

  List<RoomInfo> get visibleRooms {
    return discoveredRooms.where((RoomInfo room) => !room.hidden).toList();
  }

  void setStatus(String value) {
    status = value;
    _notify();
  }

  bool isRoomNameTaken(String name) {
    final String candidate = name.trim().toLowerCase();
    if (candidate.isEmpty) {
      return false;
    }
    return discoveredRooms.any(
      (RoomInfo room) => room.roomName.trim().toLowerCase() == candidate,
    );
  }

  RoomInfo? findRoomByName(String name, {bool includeHidden = false}) {
    final String candidate = name.trim().toLowerCase();
    if (candidate.isEmpty) {
      return null;
    }

    final List<RoomInfo> source = includeHidden
        ? discoveredRooms
        : visibleRooms;
    for (final RoomInfo room in source) {
      if (room.roomName.trim().toLowerCase() == candidate) {
        return room;
      }
    }
    return null;
  }

  Future<void> startDiscovery() async {
    await _closeDiscovery();

    try {
      final RawDatagramSocket listener = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );

      listener.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        final Datagram? datagram = listener.receive();
        if (datagram == null) {
          return;
        }
        _onDiscoveryPacket(datagram);
      });

      _discoveryListener = listener;

      // If this is the main room discovery controller, also listen on user discovery port
      // to discover direct chats announced by user-mode controllers
      if (_discoveryPort == roomDiscoveryPort) {
        try {
          final RawDatagramSocket altListener = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            userDiscoveryPort,
            reuseAddress: true,
          );
          altListener.listen((RawSocketEvent event) {
            if (event != RawSocketEvent.read) {
              return;
            }
            final Datagram? datagram = altListener.receive();
            if (datagram == null) {
              return;
            }
            _onDiscoveryPacket(datagram);
          });
          _alternateDiscoveryListener = altListener;
        } catch (_) {
          // If alternate discovery listener fails, just continue with primary
        }
      }

      _roomsCleanupTimer?.cancel();
      _roomsCleanupTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        final DateTime cutoff = DateTime.now().subtract(
          const Duration(seconds: 6),
        );
        _roomsByKey.removeWhere((_, room) => room.lastSeen.isBefore(cutoff));
        _notify();
      });
    } catch (e) {
      status = 'Discovery start failed: $e';
      _notify();
    }
  }

  Future<bool> hostRoom({
    required String yourName,
    required String room,
    bool hidden = false,
    bool historyEnabled = false,
    RoomSecurityType securityType = RoomSecurityType.none,
    String? securityValue,
  }) async {
    if (isRoomNameTaken(room)) {
      setStatus('A room with this name already exists. Pick another name.');
      return false;
    }

    await disconnect();
    await startDiscovery();

    try {
      localUserName = yourName;
      localUserId = await _loadOrCreateLocalUserId();
      roomName = room;
      mode = ChatMode.hosting;
      status = 'Hosting on local network';
      _roomHidden = hidden;
      _roomHistoryEnabled = historyEnabled;
      _roomSecurityType = securityType;
      _roomSecurityValue = securityValue?.trim();
      _hostHidden = hidden;
      _hostHistoryEnabled = historyEnabled;
      _joinedRoomHistoryEnabled = false;
      _hostSecurityType = securityType;
      _hostSecurityValue = securityValue?.trim();
      _awaitingFailover = false;
      _nextHistorySequence = 1;
      _historyEntries.clear();
      _localSentEntries.clear();
      _presenceWindowsByUser.clear();
      _historyCursorBeforeSequence = null;
      _historyHasMore = false;
      _historyLoading = false;
      _pendingHistoryRequests.clear();
      _historySyncTargetsByRequest.clear();
      _messageIds.clear();

      if (_hostHistoryEnabled) {
        _markPresenceJoined(localUserId!);
      }

      participants
        ..clear()
        ..add(localUserName!);
      _participantsById.clear();
      _participantsById[localUserId!] = _ParticipantState(
        userId: localUserId!,
        name: localUserName!,
        batteryLevel: await _readBatteryLevel(),
        joinedAt: DateTime.now(),
      );

      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _chatPort,
        shared: true,
      );

      _serverSocket!.listen(_onClientConnected);
      _startBatteryUpdates();
      _deferAnnouncementsUntilFirstMessage = shouldDeferDirectChatAnnouncements(
        chatPort: _chatPort,
        hidden: hidden,
      );
      if (!_deferAnnouncementsUntilFirstMessage) {
        _startAnnouncements();
      }
      _addSystemMessage('Room "$roomName" created.');
      _notify();
      return true;
    } catch (e) {
      status = 'Host failed: $e';
      mode = ChatMode.idle;
      _notify();
      return false;
    }
  }

  Future<bool> joinRoom({
    required RoomInfo room,
    required String yourName,
    String? securityValue,
    bool preserveLocalState = false,
  }) async {
    if (room.requiresSecurity) {
      final String provided = securityValue?.trim() ?? '';
      final String expected = room.securityValue?.trim() ?? '';
      if (provided.isEmpty || provided != expected) {
        setStatus('Security check failed. Wrong password/PIN/pattern.');
        return false;
      }
    }

    if (!preserveLocalState) {
      await disconnect();
    }
    await startDiscovery();

    localUserName = yourName;
    localUserId = await _loadOrCreateLocalUserId();
    roomName = room.roomName;
    hostAddress = room.hostAddress.address;
    _roomHidden = room.hidden;
    _roomHistoryEnabled = room.historyEnabled;
    _roomSecurityType = room.securityType;
    _roomSecurityValue = room.securityValue;
    _joinedRoomHistoryEnabled = room.historyEnabled;
    _hostHistoryEnabled = false;
    _awaitingFailover = false;
    _historyCursorBeforeSequence = null;
    _historyHasMore = false;
    _historyLoading = false;
    _historyRequestCounter = 0;
    _pendingHistoryRequests.clear();
    if (!preserveLocalState) {
      _messageIds.clear();
      _participantsById.clear();
    }
    status = 'Connecting to ${room.hostAddress.address}:${room.port}';
    _notify();

    try {
      final Socket socket = await Socket.connect(room.hostAddress, room.port);
      _serverConnection = socket;
      mode = ChatMode.connected;
      if (!preserveLocalState) {
        _participantsById.clear();
      }
      _participantsById[localUserId!] = _ParticipantState(
        userId: localUserId!,
        name: localUserName!,
        batteryLevel: await _readBatteryLevel(),
        joinedAt: DateTime.now(),
      );
      if (!preserveLocalState) {
        participants
          ..clear()
          ..add(localUserName!);
      } else if (!participants.contains(localUserName)) {
        participants.add(localUserName!);
      }

      _sendLine(socket, <String, dynamic>{
        'type': 'join',
        'senderId': localUserId,
        'name': localUserName,
        'batteryLevel': await _readBatteryLevel(),
        'eventTimestamp': DateTime.now().toIso8601String(),
      });

      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onServerLine,
            onDone: () {
              unawaited(_handleHostDisconnected());
            },
            onError: (Object error) {
              unawaited(
                _handleHostDisconnected(reason: 'Socket error: $error'),
              );
            },
          );

      _startBatteryUpdates();
      _addSystemMessage('Connected to room "$roomName".');
      _notify();
      return true;
    } catch (e) {
      status = 'Join failed: $e';
      mode = ChatMode.idle;
      _notify();
      return false;
    }
  }

  Future<void> sendMessage(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || localUserId == null || localUserName == null) {
      return;
    }

    if (mode == ChatMode.hosting) {
      if (_deferAnnouncementsUntilFirstMessage) {
        _deferAnnouncementsUntilFirstMessage = false;
        await _startAnnouncements();
      }
      final Map<String, dynamic> packet = _buildHostChatPacket(
        senderId: localUserId!,
        senderName: localUserName!,
        text: trimmed,
      );
      _appendChatFromPacket(packet);
      _broadcast(packet);
      return;
    }

    if (mode == ChatMode.connected && _serverConnection != null) {
      _sendLine(_serverConnection!, <String, dynamic>{
        'type': 'chat',
        'text': trimmed,
      });
    }
  }

  Future<void> disconnect() async {
    for (final Timer timer in _ephemeralMessageTimers.values) {
      timer.cancel();
    }
    _ephemeralMessageTimers.clear();

    _batteryUpdateTimer?.cancel();
    _batteryUpdateTimer = null;
    _announcementTimer?.cancel();
    _announcementTimer = null;

    if (mode == ChatMode.connected &&
        _serverConnection != null &&
        localUserId != null) {
      try {
        _sendLine(_serverConnection!, <String, dynamic>{
          'type': 'leave',
          'senderId': localUserId,
          'eventTimestamp': DateTime.now().toIso8601String(),
        });
      } catch (_) {
        // Ignore send errors during teardown.
      }
    }

    if (mode == ChatMode.hosting && localUserId != null) {
      final DateTime eventTime = DateTime.now();
      _broadcastSystemEvent(
        event: 'leave',
        userId: localUserId!,
        name: localUserName ?? 'Host',
        eventTimestamp: eventTime,
      );
      _addSystemMessage(
        '${localUserName ?? 'Host'} left the room.',
        event: 'leave',
        userId: localUserId,
        name: localUserName ?? 'Host',
        eventTimestamp: eventTime,
        ephemeralDuration: const Duration(seconds: 5),
      );
    }

    await _closeDiscovery();

    for (final _ClientPeer peer in _clients.values.toList()) {
      await peer.socket.close();
    }
    _clients.clear();

    await _serverSocket?.close();
    _serverSocket = null;

    await _serverConnection?.close();
    _serverConnection = null;

    if (_hostHistoryEnabled && localUserId != null) {
      _markPresenceLeft(localUserId!);
    }

    participants.clear();
    messages.clear();
    _messageIds.clear();
    _historyEntries.clear();
    _localSentEntries.clear();
    _presenceWindowsByUser.clear();
    _participantsById.clear();
    _historySyncTargetsByRequest.clear();
    _nextHistorySequence = 1;
    _historyCursorBeforeSequence = null;
    _historyHasMore = false;
    _historyLoading = false;
    _historyRequestCounter = 0;
    _awaitingFailover = false;
    for (final Completer<void> completer in _pendingHistoryRequests.values) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _pendingHistoryRequests.clear();
    mode = ChatMode.idle;
    roomName = null;
    hostAddress = null;
    _hostHidden = false;
    _hostHistoryEnabled = false;
    _joinedRoomHistoryEnabled = false;
    _roomHidden = false;
    _roomHistoryEnabled = false;
    _deferAnnouncementsUntilFirstMessage = false;
    _roomSecurityType = RoomSecurityType.none;
    _roomSecurityValue = null;
    _hostSecurityType = RoomSecurityType.none;
    _hostSecurityValue = null;
    status = 'Ready';
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    super.dispose();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _closeDiscovery() async {
    _roomsCleanupTimer?.cancel();
    _roomsCleanupTimer = null;
    _discoveryListener?.close();
    _discoveryListener = null;
    _alternateDiscoveryListener?.close();
    _alternateDiscoveryListener = null;
    _presenceAnnouncementTimer?.cancel();
    _presenceAnnouncementTimer = null;
    _roomsByKey.clear();
  }

  Future<void> updatePresenceAnnouncement({
    required String userName,
    required bool hiddenFromNetwork,
    required bool allowsIdChat,
  }) async {
    final String trimmedName = userName.trim();
    if (trimmedName.isEmpty || hiddenFromNetwork) {
      _presenceAnnouncementTimer?.cancel();
      _presenceAnnouncementTimer = null;
      return;
    }

    localUserName = trimmedName;
    localUserId ??= await _loadOrCreateLocalUserId();

    _presenceAnnouncementTimer?.cancel();

    Future<void> announce() async {
      try {
        final RawDatagramSocket sender = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
        );
        sender.broadcastEnabled = true;
        final List<int> bytes = utf8.encode(
          jsonEncode(<String, dynamic>{
            'type': 'announce',
            'roomName': '__presence__${localUserId ?? trimmedName}',
            'hostName': trimmedName,
            'hostUserId': localUserId,
            'port': userChatPort,
            'hostIp': hostAddress,
            'hidden': true,
            'hostHiddenFromNetwork': hiddenFromNetwork,
            'hostAllowsIdChat': allowsIdChat,
            'historyEnabled': false,
            'securityType': roomSecurityTypeToWire(RoomSecurityType.none),
            'securityValue': null,
          }),
        );
        sender.send(
          bytes,
          InternetAddress('255.255.255.255'),
          userDiscoveryPort,
        );
        sender.close();
      } catch (_) {
        // Ignore transient broadcast errors.
      }
    }

    await announce();
    _presenceAnnouncementTimer = Timer.periodic(const Duration(seconds: 2), (
      _,
    ) {
      announce();
    });
  }

  void _onDiscoveryPacket(Datagram datagram) {
    try {
      final dynamic decoded = jsonDecode(utf8.decode(datagram.data));
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      if (decoded['type'] != 'announce') {
        return;
      }
      final int port = decoded['port'] is int
          ? decoded['port'] as int
          : _chatPort;
      final RoomInfo room = RoomInfo(
        hostAddress: datagram.address,
        hostName: (decoded['hostName'] ?? 'Host').toString(),
        hostUserId: (decoded['hostUserId'] ?? '').toString(),
        roomName: (decoded['roomName'] ?? 'Secret Chat').toString(),
        port: port,
        lastSeen: DateTime.now(),
        hidden: decoded['hidden'] == true,
        historyEnabled: decoded['historyEnabled'] == true,
        securityType: roomSecurityTypeFromString(
          (decoded['securityType'] ?? 'none').toString(),
        ),
        securityValue:
            (decoded['securityValue'] ?? '').toString().trim().isEmpty
            ? null
            : (decoded['securityValue'] ?? '').toString(),
        hostHiddenFromNetwork: decoded['hostHiddenFromNetwork'] == true,
        hostAllowsIdChat: decoded['hostAllowsIdChat'] != false,
      );
      _roomsByKey[room.key] = room;
      _notify();

      if (_awaitingFailover &&
          mode == ChatMode.connected &&
          _serverConnection == null &&
          room.roomName.trim().toLowerCase() ==
              (roomName ?? '').trim().toLowerCase() &&
          room.hostAddress.address != hostAddress) {
        unawaited(
          joinRoom(
            room: room,
            yourName: localUserName ?? 'Guest',
            securityValue: _roomSecurityValue,
            preserveLocalState: true,
          ),
        );
      }
    } catch (_) {
      // Ignore malformed packets from other apps on the LAN.
    }
  }

  Future<void> _startAnnouncements() async {
    _announcementTimer?.cancel();

    final InternetAddress? localIp = await _findLocalIPv4();
    hostAddress = localIp?.address;

    Future<void> announce() async {
      try {
        final RawDatagramSocket sender = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
        );
        sender.broadcastEnabled = true;
        final List<int> bytes = utf8.encode(
          jsonEncode(<String, dynamic>{
            'type': 'announce',
            'roomName': roomName,
            'hostName': localUserName,
            'hostUserId': localUserId,
            'port': _chatPort,
            'hostIp': hostAddress,
            'hidden': _hostHidden,
            'hostHiddenFromNetwork': false,
            'hostAllowsIdChat': true,
            'historyEnabled': _hostHistoryEnabled,
            'securityType': roomSecurityTypeToWire(_hostSecurityType),
            'securityValue': _hostSecurityType == RoomSecurityType.none
                ? null
                : _hostSecurityValue,
          }),
        );
        sender.send(bytes, InternetAddress('255.255.255.255'), _discoveryPort);
        sender.close();
      } catch (_) {
        // Ignore transient broadcast errors.
      }
    }

    await announce();
    _announcementTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      announce();
    });
  }

  void _onClientConnected(Socket socket) {
    final String peerId = _generateId();
    final _ClientPeer peer = _ClientPeer(
      socket: socket,
      id: peerId,
      name: 'Guest',
    );
    _clients[peerId] = peer;

    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (String line) {
            _onClientLine(peerId, line);
          },
          onDone: () {
            _removePeer(peerId);
          },
          onError: (_) {
            _removePeer(peerId);
          },
        );
  }

  void _onClientLine(String peerId, String line) {
    final _ClientPeer? peer = _clients[peerId];
    if (peer == null) {
      return;
    }

    try {
      final dynamic decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final String type = (decoded['type'] ?? '').toString();
      if (type == 'join') {
        final DateTime eventTime =
            DateTime.tryParse((decoded['eventTimestamp'] ?? '').toString()) ??
            DateTime.now();
        peer.name = (decoded['name'] ?? 'Guest').toString();
        peer.userId = (decoded['senderId'] ?? '').toString().trim().isEmpty
            ? peer.id
            : (decoded['senderId'] ?? '').toString();
        peer.batteryLevel = decoded['batteryLevel'] is int
            ? decoded['batteryLevel'] as int
            : int.tryParse((decoded['batteryLevel'] ?? '').toString()) ?? 50;
        participants.remove(peer.name);
        participants.add(peer.name);
        _participantsById[peer.userId!] = _ParticipantState(
          userId: peer.userId!,
          name: peer.name,
          batteryLevel: peer.batteryLevel,
          joinedAt: eventTime,
        );
        if (_hostHistoryEnabled) {
          _markPresenceJoined(peer.userId!, at: eventTime);
          _requestHistorySyncForPeer(peer);
        }
        _broadcastParticipants();
        final DateTime systemEventTime = DateTime.now();
        _broadcastSystemEvent(
          event: 'join',
          userId: peer.userId!,
          name: peer.name,
          eventTimestamp: systemEventTime,
        );
        _addSystemMessage(
          '${peer.name} joined the room.',
          event: 'join',
          userId: peer.userId,
          name: peer.name,
          eventTimestamp: systemEventTime,
          ephemeralDuration: const Duration(seconds: 5),
        );
        _notify();
        return;
      }

      if (type == 'leave') {
        final DateTime eventTime =
            DateTime.tryParse((decoded['eventTimestamp'] ?? '').toString()) ??
            DateTime.now();
        if (peer.userId != null) {
          final _ParticipantState? state = _participantsById[peer.userId];
          if (state != null) {
            state.leftAt = eventTime;
          }
        }
        if (_hostHistoryEnabled && peer.userId != null) {
          _markPresenceLeft(peer.userId!, at: eventTime);
        }
        final DateTime systemEventTime = DateTime.now();
        _broadcastSystemEvent(
          event: 'leave',
          userId: peer.userId ?? peer.id,
          name: peer.name,
          eventTimestamp: systemEventTime,
        );
        _addSystemMessage(
          '${peer.name} left the room.',
          event: 'leave',
          userId: peer.userId,
          name: peer.name,
          eventTimestamp: systemEventTime,
          ephemeralDuration: const Duration(seconds: 5),
        );
        return;
      }

      if (type == 'chat') {
        final Map<String, dynamic> packet = _buildHostChatPacket(
          senderId: peer.userId ?? peer.id,
          senderName: peer.name,
          text: (decoded['text'] ?? '').toString(),
        );
        _appendChatFromPacket(packet);
        _broadcast(packet);
        return;
      }

      if (type == 'batteryUpdate') {
        if (peer.userId != null) {
          final int batteryLevel = decoded['batteryLevel'] is int
              ? decoded['batteryLevel'] as int
              : int.tryParse((decoded['batteryLevel'] ?? '').toString()) ??
                    peer.batteryLevel;
          peer.batteryLevel = batteryLevel;
          final _ParticipantState? state = _participantsById[peer.userId];
          if (state != null) {
            state.batteryLevel = batteryLevel;
          }
        }
        return;
      }

      if (type == 'historyRequest') {
        final String requestId = (decoded['requestId'] ?? '').toString();
        final String targetUserId =
            (decoded['targetUserId'] ?? peer.userId ?? '').toString();
        if (requestId.isEmpty || targetUserId.isEmpty) {
          return;
        }

        _historySyncTargetsByRequest[requestId] = _HistorySyncTarget(
          requestId: requestId,
          targetUserId: targetUserId,
        );

        _sendLocalHistorySync(
          requestId: requestId,
          targetUserId: targetUserId,
          targetPeer: peer,
        );

        for (final _ClientPeer otherPeer in _clients.values) {
          if (otherPeer.id == peerId) {
            continue;
          }
          _sendLine(otherPeer.socket, <String, dynamic>{
            'type': 'historySyncRequest',
            'requestId': requestId,
            'targetUserId': targetUserId,
          });
        }
        return;
      }

      if (type == 'historySyncResponse') {
        final String requestId = (decoded['requestId'] ?? '').toString();
        final _HistorySyncTarget? target =
            _historySyncTargetsByRequest[requestId];
        if (target == null) {
          return;
        }

        _ClientPeer? targetPeer;
        for (final _ClientPeer candidate in _clients.values) {
          if (candidate.userId == target.targetUserId) {
            targetPeer = candidate;
            break;
          }
        }
        if (targetPeer == null) {
          return;
        }

        _sendLine(targetPeer.socket, <String, dynamic>{
          'type': 'historySyncData',
          'requestId': requestId,
          'messages': decoded['messages'] ?? const <Map<String, dynamic>>[],
        });
        return;
      }
    } catch (_) {
      // Ignore invalid client payloads.
    }
  }

  void _onServerLine(String line) {
    try {
      final dynamic decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final String type = (decoded['type'] ?? '').toString();
      if (type == 'chat') {
        _appendChatFromPacket(decoded);
        return;
      }
      if (type == 'participants') {
        final dynamic names = decoded['names'];
        if (names is List) {
          participants
            ..clear()
            ..addAll(names.map((dynamic e) => e.toString()));
          _notify();
        }
        final dynamic members = decoded['members'];
        if (members is List) {
          _participantsById.clear();
          for (final dynamic member in members) {
            if (member is! Map<String, dynamic>) {
              continue;
            }
            final String userId = (member['userId'] ?? '').toString();
            if (userId.isEmpty) {
              continue;
            }
            final _ParticipantState state = _ParticipantState(
              userId: userId,
              name: (member['name'] ?? 'Guest').toString(),
              batteryLevel: member['batteryLevel'] is int
                  ? member['batteryLevel'] as int
                  : int.tryParse((member['batteryLevel'] ?? '').toString()) ??
                        50,
              joinedAt:
                  DateTime.tryParse((member['joinedAt'] ?? '').toString()) ??
                  DateTime.now(),
            );
            if (member['leftAt'] != null &&
                member['leftAt'].toString().trim().isNotEmpty) {
              state.leftAt =
                  DateTime.tryParse(member['leftAt'].toString()) ??
                  DateTime.now();
            }
            _participantsById[userId] = state;
            _syncPresenceFromParticipant(state);
          }
        }
        return;
      }
      if (type == 'historyPage') {
        _applyHistoryPage(decoded);
        return;
      }
      if (type == 'historySyncRequest') {
        final String requestId = (decoded['requestId'] ?? '').toString();
        final String targetUserId = (decoded['targetUserId'] ?? '').toString();
        if (requestId.isEmpty || targetUserId.isEmpty) {
          return;
        }
        _sendLine(_serverConnection!, <String, dynamic>{
          'type': 'historySyncResponse',
          'requestId': requestId,
          'messages': _buildLocalHistoryMessagesForTarget(targetUserId),
        });
        return;
      }
      if (type == 'historySyncData') {
        _applyHistorySyncData(decoded);
        return;
      }
      if (type == 'system') {
        _applyPresenceEvent(decoded);
        final String event = (decoded['event'] ?? '').toString();
        _addSystemMessage(
          (decoded['text'] ?? '').toString(),
          ephemeralDuration: event == 'join' || event == 'leave'
              ? const Duration(seconds: 5)
              : null,
        );
      }
    } catch (_) {
      // Ignore malformed host messages.
    }
  }

  void _removePeer(String peerId) {
    final _ClientPeer? peer = _clients.remove(peerId);
    if (peer == null) {
      return;
    }
    participants.remove(peer.name);
    if (_hostHistoryEnabled && peer.userId != null) {
      _markPresenceLeft(peer.userId!);
    }
    _participantsById.remove(peer.userId);
    _broadcastParticipants();
    final DateTime eventTime = DateTime.now();
    _broadcastSystemEvent(
      event: 'leave',
      userId: peer.userId ?? peer.id,
      name: peer.name,
      eventTimestamp: eventTime,
    );
    _addSystemMessage(
      '${peer.name} left the room.',
      event: 'leave',
      userId: peer.userId,
      name: peer.name,
      eventTimestamp: eventTime,
      ephemeralDuration: const Duration(seconds: 5),
    );
    _notify();
  }

  void _broadcastParticipants() {
    final List<String> allNames = <String>[
      localUserName ?? 'Host',
      ...participants.where((String p) => p != localUserName),
    ];
    final Map<String, dynamic> packet = <String, dynamic>{
      'type': 'participants',
      'names': allNames,
      'members': _participantsById.values
          .map(
            (_ParticipantState member) => <String, dynamic>{
              'userId': member.userId,
              'name': member.name,
              'batteryLevel': member.batteryLevel,
              'joinedAt': member.joinedAt.toIso8601String(),
              'leftAt': member.leftAt?.toIso8601String(),
            },
          )
          .toList(),
    };
    _broadcast(packet);
  }

  void _broadcastSystemEvent({
    required String event,
    required String userId,
    required String name,
    required DateTime eventTimestamp,
  }) {
    _broadcast(<String, dynamic>{
      'type': 'system',
      'event': event,
      'userId': userId,
      'name': name,
      'eventTimestamp': eventTimestamp.toIso8601String(),
      'text': event == 'join'
          ? '$name joined the room.'
          : '$name left the room.',
    });
  }

  void _broadcast(Map<String, dynamic> packet) {
    for (final _ClientPeer peer in _clients.values) {
      try {
        _sendLine(peer.socket, packet);
      } catch (_) {
        // Ignore peers that are already tearing down.
      }
    }
  }

  Map<String, dynamic> _buildHostChatPacket({
    required String senderId,
    required String senderName,
    required String text,
  }) {
    final DateTime now = DateTime.now();
    final String messageId = _generateId();
    final Map<String, dynamic> packet = <String, dynamic>{
      'type': 'chat',
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'timestamp': now.toIso8601String(),
    };

    if (_hostHistoryEnabled) {
      final int sequence = _nextHistorySequence++;
      packet['sequence'] = sequence;
    }

    return packet;
  }

  void _markPresenceJoined(String userId, {DateTime? at}) {
    final List<_PresenceWindow> windows = _presenceWindowsByUser.putIfAbsent(
      userId,
      () => <_PresenceWindow>[],
    );
    if (windows.isNotEmpty && windows.last.end == null) {
      return;
    }
    windows.add(_PresenceWindow(start: at ?? DateTime.now()));
  }

  void _markPresenceLeft(String userId, {DateTime? at}) {
    final List<_PresenceWindow>? windows = _presenceWindowsByUser[userId];
    if (windows == null || windows.isEmpty) {
      return;
    }
    if (windows.last.end == null) {
      windows.last.end = at ?? DateTime.now();
    }
  }

  bool _canUserAccessMessage(
    DateTime timestamp,
    List<_PresenceWindow> windows,
  ) {
    for (final _PresenceWindow window in windows) {
      if (window.contains(timestamp)) {
        return true;
      }
    }
    return false;
  }

  Future<void> loadOlderMessages() async {
    if (!_joinedRoomHistoryEnabled ||
        mode != ChatMode.connected ||
        _serverConnection == null ||
        _historyLoading ||
        !_historyHasMore) {
      return;
    }

    _historyLoading = true;
    _notify();

    final String requestId = 'history-${++_historyRequestCounter}';
    final Completer<void> completer = Completer<void>();
    _pendingHistoryRequests[requestId] = completer;

    _sendLine(_serverConnection!, <String, dynamic>{
      'type': 'historyRequest',
      'requestId': requestId,
      'beforeSequence': _historyCursorBeforeSequence,
      'limit': _historyPageSize,
    });

    try {
      await completer.future.timeout(const Duration(seconds: 3));
    } catch (_) {
      if (_pendingHistoryRequests.remove(requestId) != null) {
        _historyLoading = false;
        _notify();
      }
    }
  }

  Future<void> _handleHostDisconnected({String? reason}) async {
    if (mode != ChatMode.connected) {
      return;
    }

    _serverConnection = null;
    _awaitingFailover = true;
    _historyLoading = false;
    status = reason ?? 'Host disconnected. Looking for failover host.';

    final _ParticipantState? leader = _selectHostCandidate();
    if (leader != null && leader.userId == localUserId) {
      await _promoteToHost();
      return;
    }

    _notify();
  }

  _ParticipantState? _selectHostCandidate() {
    final List<_ParticipantState> candidates = _participantsById.values
        .where((member) => member.leftAt == null)
        .toList();

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((a, b) {
      final int batteryCompare = b.batteryLevel.compareTo(a.batteryLevel);
      if (batteryCompare != 0) {
        return batteryCompare;
      }
      final int joinCompare = a.joinedAt.compareTo(b.joinedAt);
      if (joinCompare != 0) {
        return joinCompare;
      }
      return a.userId.compareTo(b.userId);
    });
    return candidates.first;
  }

  Future<void> _promoteToHost() async {
    if (roomName == null) {
      return;
    }

    _awaitingFailover = false;
    mode = ChatMode.hosting;
    _hostHidden = _roomHidden;
    _hostHistoryEnabled = _roomHistoryEnabled;
    _joinedRoomHistoryEnabled = false;
    _hostSecurityType = _roomSecurityType;
    _hostSecurityValue = _roomSecurityValue;
    _historyEntries.clear();
    _messageIds.clear();

    int nextSequence = 1;
    for (final ChatMessage message in messages.where((msg) => !msg.system)) {
      final int sequence = message.sequence ?? nextSequence;
      if (sequence >= nextSequence) {
        nextSequence = sequence + 1;
      }
      _messageIds.add(message.id);
    }
    _nextHistorySequence = nextSequence;

    participants.removeWhere((String name) => name.isEmpty);
    if (localUserName != null && !participants.contains(localUserName)) {
      participants.insert(0, localUserName!);
    }

    _participantsById[localUserId!] = _ParticipantState(
      userId: localUserId!,
      name: localUserName ?? 'Host',
      batteryLevel: await _readBatteryLevel(),
      joinedAt: _participantsById[localUserId!]?.joinedAt ?? DateTime.now(),
    );

    _serverSocket = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      _chatPort,
      shared: true,
    );
    _serverSocket!.listen(_onClientConnected);
    _startBatteryUpdates();
    _startAnnouncements();
    status = 'Hosting recovered room on local network';
    _notify();
  }

  void _applyPresenceEvent(Map<String, dynamic> packet) {
    final String event = (packet['event'] ?? '').toString();
    final String userId = (packet['userId'] ?? '').toString();
    if (userId.isEmpty) {
      return;
    }

    final DateTime eventTime =
        DateTime.tryParse((packet['eventTimestamp'] ?? '').toString()) ??
        DateTime.now();

    if (event == 'join') {
      _markPresenceJoined(userId, at: eventTime);
      _participantsById.putIfAbsent(
        userId,
        () => _ParticipantState(
          userId: userId,
          name: (packet['name'] ?? 'Guest').toString(),
          batteryLevel: 50,
          joinedAt: eventTime,
        ),
      );
      return;
    }

    if (event == 'leave') {
      _markPresenceLeft(userId, at: eventTime);
      final _ParticipantState? state = _participantsById[userId];
      if (state != null) {
        state.leftAt = eventTime;
      }
      _removeMessagesFromSender(userId);
    }
  }

  void _syncPresenceFromParticipant(_ParticipantState state) {
    final List<_PresenceWindow> windows = _presenceWindowsByUser.putIfAbsent(
      state.userId,
      () => <_PresenceWindow>[],
    );
    if (windows.isEmpty) {
      windows.add(_PresenceWindow(start: state.joinedAt));
    }
    if (state.leftAt != null && windows.last.end == null) {
      windows.last.end = state.leftAt;
    }
  }

  Future<int> _readBatteryLevel() async {
    try {
      return await _batteryLevelProvider();
    } catch (_) {
      return 50;
    }
  }

  void _startBatteryUpdates() {
    _batteryUpdateTimer?.cancel();
    _batteryUpdateTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_sendBatteryUpdate());
    });
    unawaited(_sendBatteryUpdate());
  }

  Future<void> _sendBatteryUpdate() async {
    final int batteryLevel = await _readBatteryLevel();
    if (localUserId == null) {
      return;
    }

    final _ParticipantState? state = _participantsById[localUserId!];
    if (state != null) {
      state.batteryLevel = batteryLevel;
    } else {
      _participantsById[localUserId!] = _ParticipantState(
        userId: localUserId!,
        name: localUserName ?? 'Guest',
        batteryLevel: batteryLevel,
        joinedAt: DateTime.now(),
      );
    }

    if (mode == ChatMode.hosting) {
      _broadcastParticipants();
      return;
    }

    if (mode == ChatMode.connected && _serverConnection != null) {
      _sendLine(_serverConnection!, <String, dynamic>{
        'type': 'batteryUpdate',
        'senderId': localUserId,
        'batteryLevel': batteryLevel,
      });
    }
  }

  String _generateId() {
    final Random r = Random.secure();
    return '${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(1 << 32)}';
  }

  void _sendLine(Socket socket, Map<String, dynamic> payload) {
    socket.write('${jsonEncode(payload)}\n');
  }
}
