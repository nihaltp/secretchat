// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

part of 'lan_chat_controller.dart';

/// Message lifecycle management including appending, deletion, and ephemeral cleanup.
extension on LanChatController {
  /// Appends a chat message from a received packet to the local message store.
  /// For messages sent by the local user, tracks them in _localSentEntries
  /// for sender-owned history replay.
  void _appendChatFromPacket(Map<String, dynamic> packet) {
    final String text = (packet['text'] ?? '').toString().trim();
    if (text.isEmpty) {
      return;
    }
    final String messageId = (packet['messageId'] ?? _generateId()).toString();
    if (_messageIds.contains(messageId)) {
      return;
    }
    final DateTime timestamp =
        DateTime.tryParse((packet['timestamp'] ?? '').toString()) ??
        DateTime.now();
    messages.add(
      ChatMessage(
        id: messageId,
        senderId: (packet['senderId'] ?? '').toString(),
        senderName: (packet['senderName'] ?? 'Unknown').toString(),
        text: text,
        timestamp: timestamp,
        sequence: packet['sequence'] is int
            ? packet['sequence'] as int
            : int.tryParse((packet['sequence'] ?? '').toString()),
      ),
    );
    final String senderId = (packet['senderId'] ?? '').toString();
    if (senderId == localUserId) {
      final int sequence = packet['sequence'] is int
          ? packet['sequence'] as int
          : int.tryParse((packet['sequence'] ?? '').toString()) ??
                (_localSentEntries.isEmpty
                    ? 1
                    : _localSentEntries.last.sequence + 1);
      final bool alreadyTracked = _localSentEntries.any(
        (entry) => entry.messageId == messageId,
      );
      if (!alreadyTracked) {
        _localSentEntries.add(
          _HistoryEntry(
            sequence: sequence,
            messageId: messageId,
            senderId: senderId,
            senderName: (packet['senderName'] ?? 'Unknown').toString(),
            text: text,
            timestamp: timestamp,
          ),
        );
      }
    }
    _messageIds.add(messageId);
    _notify();
  }

  /// Adds a system message to the chat and optionally schedules it for removal.
  /// System messages can be ephemeral (e.g., join/leave notifications that
  /// disappear after a short duration) or permanent.
  ///
  /// Can optionally trigger a presence event (join/leave) via the [event],
  /// [userId], and [name] parameters.
  void _addSystemMessage(
    String text, {
    String? event,
    String? userId,
    String? name,
    DateTime? eventTimestamp,
    Duration? ephemeralDuration,
  }) {
    final String id = _generateId();
    messages.add(
      ChatMessage(
        id: id,
        senderId: 'system',
        senderName: 'System',
        text: text,
        timestamp: DateTime.now(),
        system: true,
      ),
    );
    if (event != null && userId != null && name != null) {
      _applyPresenceEvent(<String, dynamic>{
        'event': event,
        'userId': userId,
        'name': name,
        if (eventTimestamp != null)
          'eventTimestamp': eventTimestamp.toIso8601String(),
      });
    }
    if (ephemeralDuration != null) {
      _scheduleEphemeralMessageRemoval(id, ephemeralDuration);
    }
    _messageIds.add(id);
    _notify();
  }

  /// Schedules a message for automatic removal after the specified duration.
  /// Used for ephemeral system messages (join/leave notifications) that
  /// should not persist in the chat history.
  void _scheduleEphemeralMessageRemoval(String messageId, Duration duration) {
    _ephemeralMessageTimers[messageId]?.cancel();
    _ephemeralMessageTimers[messageId] = Timer(duration, () {
      _ephemeralMessageTimers.remove(messageId);
      final int before = messages.length;
      messages.removeWhere((message) => message.id == messageId);
      _messageIds.remove(messageId);
      if (messages.length != before) {
        _notify();
      }
    });
  }

  /// Removes all non-system messages sent by a given user from all stores.
  /// Called when a user leaves to implement the sender-owned history model:
  /// when a sender leaves, all their messages are purged from the room.
  void _removeMessagesFromSender(String senderId) {
    final Set<String> removedIds = messages
        .where((message) => !message.system && message.senderId == senderId)
        .map((message) => message.id)
        .toSet();
    if (removedIds.isEmpty) {
      return;
    }

    messages.removeWhere(
      (message) => !message.system && message.senderId == senderId,
    );
    _messageIds.removeWhere((id) => removedIds.contains(id));
    _historyEntries.removeWhere((entry) => entry.senderId == senderId);
    _localSentEntries.removeWhere((entry) => entry.senderId == senderId);
  }
}
