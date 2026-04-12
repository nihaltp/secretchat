// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:secret_chat/chat/models/room_info.dart';

class RoomCreationData {
  RoomCreationData({
    required this.roomName,
    required this.hidden,
    required this.historyEnabled,
    required this.securityType,
    this.securityValue,
  });

  final String roomName;
  final bool hidden;
  final bool historyEnabled;
  final RoomSecurityType securityType;
  final String? securityValue;
}
