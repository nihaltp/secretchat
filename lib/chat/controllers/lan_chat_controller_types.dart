// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

part of 'lan_chat_controller.dart';

enum ChatMode { idle, connecting, hosting, connected }

class _ClientPeer {
  _ClientPeer({required this.socket, required this.id, required this.name});

  final Socket socket;
  final String id;
  String name;
  String? userId;
  int batteryLevel = 50;
}

class _HistorySyncTarget {
  _HistorySyncTarget({required this.requestId, required this.targetUserId});

  final String requestId;
  final String targetUserId;
}

class _FailoverLatencyReport {
  _FailoverLatencyReport({
    required this.userId,
    required this.averageRttMs,
    required this.successfulProbes,
    required this.totalProbes,
  });

  final String userId;
  final int? averageRttMs;
  final int successfulProbes;
  final int totalProbes;
}

class _ParticipantState {
  _ParticipantState({
    required this.userId,
    required this.name,
    required this.batteryLevel,
    required this.joinedAt,
  });

  final String userId;
  String name;
  int batteryLevel;
  final DateTime joinedAt;
  DateTime? leftAt;
}

class _PresenceWindow {
  _PresenceWindow({required this.start});

  final DateTime start;
  DateTime? end;

  bool contains(DateTime timestamp) {
    if (timestamp.isBefore(start)) {
      return false;
    }
    if (end != null && timestamp.isAfter(end!)) {
      return false;
    }
    return true;
  }
}

class _HistoryEntry {
  _HistoryEntry({
    required this.sequence,
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
  });

  final int sequence;
  final String messageId;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime timestamp;

  Map<String, dynamic> toPacket() {
    return <String, dynamic>{
      'type': 'chat',
      'sequence': sequence,
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
