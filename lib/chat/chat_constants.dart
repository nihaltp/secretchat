// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:secret_chat/chat/models/room_info.dart';

const int roomDiscoveryPort = 48650;
const int roomChatPort = 48651;
const int userDiscoveryPort = 48652;
const int userChatPort = 48653;
const int chatProtocolVersion = 2;

// The default message length limit(characters) for chat messages.
const int messageLengthLimit = 64;

const String directChatRoomPrefix = '__direct_chat__';

bool isDirectChatRoomName(String roomName) {
  return roomName.trim().toLowerCase().startsWith(directChatRoomPrefix);
}

bool shouldDeferDirectChatAnnouncements({
  required int chatPort,
  required bool hidden,
}) {
  return hidden && chatPort == userChatPort;
}

String directChatRoomTargetToken(String roomName) {
  final String trimmed = roomName.trim();
  if (!isDirectChatRoomName(trimmed)) {
    return '';
  }
  return trimmed.substring(directChatRoomPrefix.length).trim();
}

bool isDirectChatRoomTargetedToUser(
  RoomInfo room, {
  required String localUserId,
  required String localUserName,
}) {
  if (!room.hidden || !isDirectChatRoomName(room.roomName)) {
    return false;
  }

  final String token = directChatRoomTargetToken(room.roomName).toLowerCase();
  if (token.isEmpty) {
    return false;
  }

  final String normalizedLocalUserId = localUserId.trim().toLowerCase();
  final String normalizedLocalUserName = localUserName.trim().toLowerCase();
  return token == normalizedLocalUserId || token == normalizedLocalUserName;
}
