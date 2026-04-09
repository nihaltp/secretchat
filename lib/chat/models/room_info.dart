// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'dart:io';

enum RoomSecurityType { none, password, pin, pattern }

RoomSecurityType roomSecurityTypeFromString(String? value) {
  switch (value) {
    case 'password':
      return RoomSecurityType.password;
    case 'pin':
      return RoomSecurityType.pin;
    case 'pattern':
      return RoomSecurityType.pattern;
    default:
      return RoomSecurityType.none;
  }
}

String roomSecurityTypeToWire(RoomSecurityType value) {
  switch (value) {
    case RoomSecurityType.password:
      return 'password';
    case RoomSecurityType.pin:
      return 'pin';
    case RoomSecurityType.pattern:
      return 'pattern';
    case RoomSecurityType.none:
      return 'none';
  }
}

class RoomInfo {
  RoomInfo({
    required this.hostAddress,
    required this.hostName,
    required this.roomName,
    required this.port,
    required this.lastSeen,
    this.hidden = false,
    this.securityType = RoomSecurityType.none,
    this.securityValue,
  });

  final InternetAddress hostAddress;
  final String hostName;
  final String roomName;
  final int port;
  DateTime lastSeen;
  final bool hidden;
  final RoomSecurityType securityType;
  final String? securityValue;

  bool get requiresSecurity => securityType != RoomSecurityType.none;

  String get key => '${hostAddress.address}:$port:$roomName';
}
