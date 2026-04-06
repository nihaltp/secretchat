import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

const int discoveryPort = 48650;
const int chatPort = 48651;

void main() {
  runApp(const SecretChatApp());
}

class SecretChatApp extends StatelessWidget {
  const SecretChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secret Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF007A5E)),
        useMaterial3: true,
      ),
      home: const ChatHomePage(),
    );
  }
}

enum ChatMode { idle, hosting, connected }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.system = false,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final bool system;
}

class RoomInfo {
  RoomInfo({
    required this.hostAddress,
    required this.hostName,
    required this.roomName,
    required this.port,
    required this.lastSeen,
  });

  final InternetAddress hostAddress;
  final String hostName;
  final String roomName;
  final int port;
  DateTime lastSeen;

  String get key => '${hostAddress.address}:$port';
}

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

  Future<void> hostRoom({
    required String yourName,
    required String room,
  }) async {
    await disconnect();
    await startDiscovery();

    try {
      localUserName = yourName;
      localUserId = _generateId();
      roomName = room;
      mode = ChatMode.hosting;
      status = 'Hosting on local network';

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
    } catch (e) {
      status = 'Host failed: $e';
      mode = ChatMode.idle;
      _notify();
    }
  }

  Future<void> joinRoom({
    required RoomInfo room,
    required String yourName,
  }) async {
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
    } catch (e) {
      status = 'Join failed: $e';
      mode = ChatMode.idle;
      _notify();
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

class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key});

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> {
  final LanChatController controller = LanChatController();
  final TextEditingController nameController = TextEditingController(
    text: 'User${Random().nextInt(900) + 100}',
  );
  final TextEditingController roomController = TextEditingController(
    text: 'My Room',
  );
  final TextEditingController messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller.startDiscovery();
    controller.status = 'Ready';
  }

  @override
  void dispose() {
    controller.dispose();
    nameController.dispose();
    roomController.dispose();
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Secret Chat LAN'),
            actions: [
              IconButton(
                tooltip: 'Disconnect',
                onPressed: controller.mode == ChatMode.idle
                    ? null
                    : () => controller.disconnect(),
                icon: const Icon(Icons.link_off),
              ),
            ],
          ),
          body: SafeArea(
            child: controller.mode == ChatMode.idle
                ? _buildLobby()
                : _buildChat(),
          ),
        );
      },
    );
  }

  Widget _buildLobby() {
    final List<RoomInfo> rooms = controller.discoveredRooms;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Your display name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: roomController,
            decoration: const InputDecoration(
              labelText: 'Room name (when hosting)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    final String name = nameController.text.trim();
                    final String room = roomController.text.trim();
                    if (name.isEmpty || room.isEmpty) {
                      return;
                    }
                    await controller.hostRoom(yourName: name, room: room);
                  },
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Host Room'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh',
                onPressed: controller.startDiscovery,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Available rooms on this network',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: rooms.isEmpty
                ? const Center(child: Text('No rooms found yet.'))
                : ListView.separated(
                    itemCount: rooms.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final RoomInfo room = rooms[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.wifi),
                          title: Text(room.roomName),
                          subtitle: Text(
                            '${room.hostName} • ${room.hostAddress.address}:${room.port}',
                          ),
                          trailing: FilledButton(
                            onPressed: () async {
                              final String name = nameController.text.trim();
                              if (name.isEmpty) {
                                return;
                              }
                              await controller.joinRoom(
                                room: room,
                                yourName: name,
                              );
                            },
                            child: const Text('Join'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (controller.status != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(controller.status!),
          ],
        ],
      ),
    );
  }

  Widget _buildChat() {
    final bool isHost = controller.mode == ChatMode.hosting;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    isHost ? Icons.wifi_tethering : Icons.wifi,
                    size: 18,
                  ),
                  label: Text(
                    isHost
                        ? 'Hosting: ${controller.roomName}'
                        : 'Connected: ${controller.roomName}',
                  ),
                ),
                for (final String name in controller.participants)
                  Chip(label: Text(name)),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: controller.messages.length,
            itemBuilder: (BuildContext context, int i) {
              final ChatMessage msg =
                  controller.messages[controller.messages.length - 1 - i];
              final bool mine = msg.senderId == controller.localUserId;
              if (msg.system) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Center(
                    child: Text(
                      msg.text,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                    ),
                  ),
                );
              }
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  constraints: const BoxConstraints(maxWidth: 320),
                  decoration: BoxDecoration(
                    color: mine
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: mine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg.senderName,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(msg.text),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: messageController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submitMessage(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _submitMessage,
                icon: const Icon(Icons.send),
                label: const Text('Send'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _submitMessage() async {
    final String text = messageController.text;
    messageController.clear();
    await controller.sendMessage(text);
  }
}
