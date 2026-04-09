// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../chat_constants.dart';
import '../models/chat_message.dart';
import '../models/room_info.dart';

enum ChatMode { idle, hosting, connected }

class _ClientPeer {
  _ClientPeer({required this.socket, required this.id, required this.name});

  final Socket socket;
  final String id;
  String name;
}

class LanChatController extends ChangeNotifier {
  final List<ChatMessage> messages = <ChatMessage>[];
  final List<String> participants = <String>[];
  final Map<String, RoomInfo> _roomsByKey = <String, RoomInfo>{};

  ChatMode mode = ChatMode.idle;
  String? roomName;
  String? localUserName;
  String? localUserId;
  String? status;
  String? hostAddress;
  bool _hostHidden = false;
  RoomSecurityType _hostSecurityType = RoomSecurityType.none;
  String? _hostSecurityValue;

  RawDatagramSocket? _discoveryListener;
  ServerSocket? _serverSocket;
  Socket? _serverConnection;
  Timer? _announcementTimer;
  Timer? _roomsCleanupTimer;
  final Map<String, _ClientPeer> _clients = <String, _ClientPeer>{};
  bool _disposed = false;

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
        discoveryPort,
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
      localUserId = _generateId();
      roomName = room;
      mode = ChatMode.hosting;
      status = 'Hosting on local network';
      _hostHidden = hidden;
      _hostSecurityType = securityType;
      _hostSecurityValue = securityValue?.trim();

      participants
        ..clear()
        ..add(localUserName!);

      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        chatPort,
        shared: true,
      );

      _serverSocket!.listen(_onClientConnected);
      _startAnnouncements();
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
  }) async {
    if (room.requiresSecurity) {
      final String provided = securityValue?.trim() ?? '';
      final String expected = room.securityValue?.trim() ?? '';
      if (provided.isEmpty || provided != expected) {
        setStatus('Security check failed. Wrong password/PIN/pattern.');
        return false;
      }
    }

    await disconnect();
    await startDiscovery();

    localUserName = yourName;
    localUserId = _generateId();
    roomName = room.roomName;
    hostAddress = room.hostAddress.address;
    status = 'Connecting to ${room.hostAddress.address}:${room.port}';
    _notify();

    try {
      final Socket socket = await Socket.connect(room.hostAddress, room.port);
      _serverConnection = socket;
      mode = ChatMode.connected;
      participants
        ..clear()
        ..add(localUserName!);

      _sendLine(socket, <String, dynamic>{
        'type': 'join',
        'senderId': localUserId,
        'name': localUserName,
      });

      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onServerLine,
            onDone: () {
              status = 'Disconnected from host';
              mode = ChatMode.idle;
              _notify();
            },
            onError: (Object error) {
              status = 'Socket error: $error';
              mode = ChatMode.idle;
              _notify();
            },
          );

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
      final Map<String, dynamic> packet = <String, dynamic>{
        'type': 'chat',
        'messageId': _generateId(),
        'senderId': localUserId,
        'senderName': localUserName,
        'text': trimmed,
        'timestamp': DateTime.now().toIso8601String(),
      };
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
    _announcementTimer?.cancel();
    _announcementTimer = null;

    await _closeDiscovery();

    for (final _ClientPeer peer in _clients.values) {
      await peer.socket.close();
    }
    _clients.clear();

    await _serverSocket?.close();
    _serverSocket = null;

    await _serverConnection?.close();
    _serverConnection = null;

    participants.clear();
    messages.clear();
    mode = ChatMode.idle;
    roomName = null;
    hostAddress = null;
    _hostHidden = false;
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
    _roomsByKey.clear();
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
          : chatPort;
      final RoomInfo room = RoomInfo(
        hostAddress: datagram.address,
        hostName: (decoded['hostName'] ?? 'Host').toString(),
        roomName: (decoded['roomName'] ?? 'Secret Chat').toString(),
        port: port,
        lastSeen: DateTime.now(),
        hidden: decoded['hidden'] == true,
        securityType: roomSecurityTypeFromString(
          (decoded['securityType'] ?? 'none').toString(),
        ),
        securityValue:
            (decoded['securityValue'] ?? '').toString().trim().isEmpty
            ? null
            : (decoded['securityValue'] ?? '').toString(),
      );
      _roomsByKey[room.key] = room;
      _notify();
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
            'port': chatPort,
            'hostIp': hostAddress,
            'hidden': _hostHidden,
            'securityType': roomSecurityTypeToWire(_hostSecurityType),
            'securityValue': _hostSecurityType == RoomSecurityType.none
                ? null
                : _hostSecurityValue,
          }),
        );
        sender.send(bytes, InternetAddress('255.255.255.255'), discoveryPort);
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
        peer.name = (decoded['name'] ?? 'Guest').toString();
        participants.remove(peer.name);
        participants.add(peer.name);
        _broadcastParticipants();
        _broadcast(<String, dynamic>{
          'type': 'system',
          'text': '${peer.name} joined the room.',
        });
        _addSystemMessage('${peer.name} joined the room.');
        _notify();
        return;
      }

      if (type == 'chat') {
        final Map<String, dynamic> packet = <String, dynamic>{
          'type': 'chat',
          'messageId': _generateId(),
          'senderId': peer.id,
          'senderName': peer.name,
          'text': (decoded['text'] ?? '').toString(),
          'timestamp': DateTime.now().toIso8601String(),
        };
        _appendChatFromPacket(packet);
        _broadcast(packet);
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
        return;
      }
      if (type == 'system') {
        _addSystemMessage((decoded['text'] ?? '').toString());
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
    _broadcastParticipants();
    _broadcast(<String, dynamic>{
      'type': 'system',
      'text': '${peer.name} left the room.',
    });
    _addSystemMessage('${peer.name} left the room.');
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
    };
    _broadcast(packet);
  }

  void _broadcast(Map<String, dynamic> packet) {
    for (final _ClientPeer peer in _clients.values) {
      _sendLine(peer.socket, packet);
    }
  }

  void _appendChatFromPacket(Map<String, dynamic> packet) {
    final String text = (packet['text'] ?? '').toString().trim();
    if (text.isEmpty) {
      return;
    }
    final DateTime timestamp =
        DateTime.tryParse((packet['timestamp'] ?? '').toString()) ??
        DateTime.now();
    messages.add(
      ChatMessage(
        id: (packet['messageId'] ?? _generateId()).toString(),
        senderId: (packet['senderId'] ?? '').toString(),
        senderName: (packet['senderName'] ?? 'Unknown').toString(),
        text: text,
        timestamp: timestamp,
      ),
    );
    _notify();
  }

  void _addSystemMessage(String text) {
    messages.add(
      ChatMessage(
        id: _generateId(),
        senderId: 'system',
        senderName: 'System',
        text: text,
        timestamp: DateTime.now(),
        system: true,
      ),
    );
    _notify();
  }

  String _generateId() {
    final Random r = Random.secure();
    return '${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(1 << 32)}';
  }

  void _sendLine(Socket socket, Map<String, dynamic> payload) {
    socket.write('${jsonEncode(payload)}\n');
  }
}

Future<InternetAddress?> _findLocalIPv4() async {
  final List<NetworkInterface> interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLinkLocal: false,
  );
  for (final NetworkInterface iface in interfaces) {
    for (final InternetAddress addr in iface.addresses) {
      if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
        return addr;
      }
    }
  }
  return null;
}
