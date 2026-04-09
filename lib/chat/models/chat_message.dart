// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

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
