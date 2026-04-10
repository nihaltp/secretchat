// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

part of 'lan_chat_controller.dart';

/// History synchronization and replay logic for decentralized message management.
extension on LanChatController {
  /// Initiates history synchronization for a newly joined peer.
  /// Requests local history from self and other peers to replay messages
  /// that the peer was present for.
  void _requestHistorySyncForPeer(_ClientPeer peer) {
    final String requestId = _generateId();
    final String targetUserId = peer.userId ?? peer.id;
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
      if (otherPeer.id == peer.id) {
        continue;
      }
      _sendLine(otherPeer.socket, <String, dynamic>{
        'type': 'historySyncRequest',
        'requestId': requestId,
        'targetUserId': targetUserId,
      });
    }
  }

  /// Sends local sent messages to a target peer for replay on join.
  /// Filters messages by presence window to ensure peer only receives
  /// messages they were present for.
  void _sendLocalHistorySync({
    required String requestId,
    required String targetUserId,
    required _ClientPeer targetPeer,
  }) {
    _sendLine(targetPeer.socket, <String, dynamic>{
      'type': 'historySyncData',
      'requestId': requestId,
      'messages': _buildLocalHistoryMessagesForTarget(targetUserId),
    });
  }

  /// Builds a list of locally sent messages that a target user should receive.
  /// Only includes messages sent while the target user was present in the room.
  List<Map<String, dynamic>> _buildLocalHistoryMessagesForTarget(
    String targetUserId,
  ) {
    final List<_PresenceWindow> windows =
        _presenceWindowsByUser[targetUserId] ?? <_PresenceWindow>[];
    if (windows.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final List<_HistoryEntry> visible = _localSentEntries.where((entry) {
      return _canUserAccessMessage(entry.timestamp, windows);
    }).toList();
    visible.sort((a, b) => a.sequence.compareTo(b.sequence));
    return visible.map((entry) => entry.toPacket()).toList();
  }

  /// Applies history sync data received from peers to the local message store.
  void _applyHistorySyncData(Map<String, dynamic> packet) {
    final dynamic rawMessages = packet['messages'];
    if (rawMessages is! List) {
      return;
    }

    for (final dynamic raw in rawMessages) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      _appendChatFromPacket(raw);
    }
  }

  /// Sends a page of history to a client during catch-up, respecting
  /// the client's presence window to ensure they only see messages
  /// they were present for.
  void _sendHistoryPage(
    _ClientPeer peer, {
    required String requestId,
    required int? beforeSequence,
    required int limit,
  }) {
    final String effectiveUserId = peer.userId ?? peer.id;
    final List<_PresenceWindow> windows =
        _presenceWindowsByUser[effectiveUserId] ?? <_PresenceWindow>[];

    if (!_hostHistoryEnabled || windows.isEmpty) {
      _sendLine(peer.socket, <String, dynamic>{
        'type': 'historyPage',
        'requestId': requestId,
        'messages': const <Map<String, dynamic>>[],
        'hasMore': false,
        'nextBeforeSequence': null,
      });
      return;
    }

    final int normalizedLimit = limit.clamp(1, 100);
    final Iterable<_HistoryEntry> visible = _historyEntries.where(
      (_HistoryEntry entry) => _canUserAccessMessage(entry.timestamp, windows),
    );

    final Iterable<_HistoryEntry> eligible = beforeSequence == null
        ? visible
        : visible.where((entry) => entry.sequence < beforeSequence);
    final List<_HistoryEntry> eligibleList = eligible.toList();

    final int startIndex = eligibleList.length > normalizedLimit
        ? eligibleList.length - normalizedLimit
        : 0;
    final List<_HistoryEntry> page = eligibleList.sublist(startIndex);
    final bool hasMore = startIndex > 0;
    final int? nextBeforeSequence = hasMore ? page.first.sequence : null;

    _sendLine(peer.socket, <String, dynamic>{
      'type': 'historyPage',
      'requestId': requestId,
      'messages': page.map((entry) => entry.toPacket()).toList(),
      'hasMore': hasMore,
      'nextBeforeSequence': nextBeforeSequence,
    });
  }

  /// Applies a page of history received from the host to the local message store.
  void _applyHistoryPage(Map<String, dynamic> packet) {
    final String requestId = (packet['requestId'] ?? '').toString();
    final dynamic rawMessages = packet['messages'];
    final bool hasMore = packet['hasMore'] == true;
    final int? nextBeforeSequence = packet['nextBeforeSequence'] is int
        ? packet['nextBeforeSequence'] as int
        : int.tryParse((packet['nextBeforeSequence'] ?? '').toString());

    final List<ChatMessage> pageMessages = <ChatMessage>[];
    if (rawMessages is List) {
      for (final dynamic raw in rawMessages) {
        if (raw is! Map<String, dynamic>) {
          continue;
        }

        final String text = (raw['text'] ?? '').toString().trim();
        if (text.isEmpty) {
          continue;
        }

        final String messageId = (raw['messageId'] ?? _generateId()).toString();
        if (_messageIds.contains(messageId)) {
          continue;
        }

        final DateTime timestamp =
            DateTime.tryParse((raw['timestamp'] ?? '').toString()) ??
            DateTime.now();
        pageMessages.add(
          ChatMessage(
            id: messageId,
            senderId: (raw['senderId'] ?? '').toString(),
            senderName: (raw['senderName'] ?? 'Unknown').toString(),
            text: text,
            timestamp: timestamp,
            sequence: raw['sequence'] is int
                ? raw['sequence'] as int
                : int.tryParse((raw['sequence'] ?? '').toString()),
          ),
        );
        _messageIds.add(messageId);
      }
    }

    messages.insertAll(0, pageMessages);
    _historyHasMore = hasMore;
    _historyCursorBeforeSequence = nextBeforeSequence;
    _historyLoading = false;

    final Completer<void>? completer = _pendingHistoryRequests.remove(requestId);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _notify();
  }
}
