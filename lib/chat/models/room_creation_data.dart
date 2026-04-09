// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'room_info.dart';

class RoomCreationData {
  RoomCreationData({
    required this.roomName,
    required this.hidden,
    required this.securityType,
    this.securityValue,
  });

  final String roomName;
  final bool hidden;
  final RoomSecurityType securityType;
  final String? securityValue;
}
