// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';

enum AppBottomNavItem { user, room, settings }

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.activeItem,
    this.onOpenUsers,
    this.onOpenRooms,
    this.onOpenSettings,
  });

  final AppBottomNavItem activeItem;
  final VoidCallback? onOpenUsers;
  final VoidCallback? onOpenRooms;
  final VoidCallback? onOpenSettings;

  Widget _navButton({
    required Key key,
    required IconData icon,
    required VoidCallback? onPressed,
    required bool active,
  }) {
    if (active) {
      return FilledButton(key: key, onPressed: onPressed, child: Icon(icon));
    }
    return FilledButton.tonal(
      key: key,
      onPressed: onPressed,
      child: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            // Intentionally icon-only: labels are omitted to avoid crowding
            // on narrow screens while keeping primary navigation accessible.
            child: _navButton(
              key: const Key('bottom_nav_user_button'),
              icon: Icons.person_outline,
              onPressed: onOpenUsers,
              active: activeItem == AppBottomNavItem.user,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _navButton(
              key: const Key('bottom_nav_room_button'),
              icon: Icons.meeting_room,
              onPressed: onOpenRooms,
              active: activeItem == AppBottomNavItem.room,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _navButton(
              key: const Key('bottom_nav_settings_button'),
              icon: Icons.settings,
              onPressed: onOpenSettings,
              active: activeItem == AppBottomNavItem.settings,
            ),
          ),
        ],
      ),
    );
  }
}
