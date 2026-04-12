// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

part of 'lan_chat_controller.dart';

Future<InternetAddress?> _findLocalIPv4() async {
  final List<NetworkInterface> interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
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
