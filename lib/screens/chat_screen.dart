// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';

import '../chat/controllers/lan_chat_controller.dart';
import '../chat/models/chat_message.dart';
import '../widgets/app_logo_title.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.controller,
    required this.onLeave,
    required this.onOpenSettings,
  });

  final LanChatController controller;
  final VoidCallback onLeave;
  final VoidCallback onOpenSettings;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitMessage() async {
    final String text = _messageController.text;
    _messageController.clear();
    await widget.controller.sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final LanChatController controller = widget.controller;
    final bool isHost = controller.mode == ChatMode.hosting;

    return Scaffold(
      appBar: AppBar(
        title: AppLogoTitle(controller.roomName ?? 'Room Chat'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Leave',
            onPressed: widget.onLeave,
            icon: const Icon(Icons.link_off),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Icon(
                      isHost ? Icons.wifi_tethering : Icons.wifi,
                      size: 18,
                    ),
                    label: Text(isHost ? 'You are host' : 'You joined'),
                  ),
                  for (final String name in controller.participants)
                    Chip(label: Text(name)),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: controller.messages.length,
              itemBuilder: (BuildContext context, int i) {
                final ChatMessage msg =
                    controller.messages[controller.messages.length - 1 - i];
                final bool mine = msg.senderId == controller.localUserId;
                if (msg.system) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Center(
                      child: Text(
                        msg.text,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  );
                }
                return Align(
                  alignment: mine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: mine
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: mine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.senderName,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(msg.text),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('chat_message_field'),
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submitMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('chat_send_button'),
                  onPressed: _submitMessage,
                  icon: const Icon(Icons.send),
                  label: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
