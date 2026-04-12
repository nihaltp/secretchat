// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:secret_chat/chat/chat_constants.dart';
import 'package:secret_chat/chat/controllers/lan_chat_controller.dart';

/// DirectChatController extends LanChatController with userChatPort and userDiscoveryPort
/// for isolated direct peer-to-peer communication separate from room chat.
///
/// When hosting or joining a direct chat, use this controller instead of LanChatController
/// to ensure messages are sent/received on userChatPort (48653) and discoveries on
/// userDiscoveryPort (48652), avoiding conflicts with room-based chat traffic.
class DirectChatController extends LanChatController {
  DirectChatController({super.batteryLevelProvider, super.localUserIdProvider})
    : super(
        chatPortOverride: userChatPort,
        discoveryPortOverride: userDiscoveryPort,
      );
}
