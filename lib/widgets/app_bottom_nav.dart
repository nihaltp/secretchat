// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    this.onOpenUsers,
    this.onOpenRooms,
    this.onOpenSettings,
  });

  final VoidCallback? onOpenUsers;
  final VoidCallback? onOpenRooms;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            // Intentionally icon-only: labels are omitted to avoid crowding
            // on narrow screens while keeping primary navigation accessible.
            child: FilledButton(
              key: const Key('bottom_nav_user_button'),
              onPressed: onOpenUsers,
              child: const Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.tonal(
              key: const Key('bottom_nav_room_button'),
              onPressed: onOpenRooms,
              child: const Icon(Icons.meeting_room),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.tonal(
              key: const Key('bottom_nav_settings_button'),
              onPressed: onOpenSettings,
              child: const Icon(Icons.settings),
            ),
          ),
        ],
      ),
    );
  }
}
