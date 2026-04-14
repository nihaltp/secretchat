// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:secret_chat/chat/chat_constants.dart';
import 'package:secret_chat/security/app_lock_controller.dart';
import 'package:secret_chat/settings/default_room_listening_controller.dart';
import 'package:secret_chat/settings/network_privacy_controller.dart';
import 'package:secret_chat/settings/theme_controller.dart';
import 'package:secret_chat/widgets/app_bottom_nav.dart';
import 'package:secret_chat/widgets/app_logo_title.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.themeController,
    required this.appLockController,
    required this.defaultRoomListeningController,
    required this.networkPrivacyController,
    this.onOpenNetworkOverview,
    this.onOpenRooms,
    this.onOpenSettings,
  });

  final ThemeController themeController;
  final AppLockController appLockController;
  final DefaultRoomListeningController defaultRoomListeningController;
  final NetworkPrivacyController networkPrivacyController;
  final VoidCallback? onOpenNetworkOverview;
  final VoidCallback? onOpenRooms;
  final VoidCallback? onOpenSettings;

  static const String _releaseChannel = String.fromEnvironment(
    'RELEASE_CHANNEL',
    defaultValue: 'unknown',
  );

  Future<({String appVersion, String channel})> _footerMetadata() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    final String installerStore = (info.installerStore ?? '').toLowerCase();
    final String fallbackChannel = installerStore.contains('fdroid')
        ? 'fdroid'
        : installerStore.contains('vending')
        ? 'playstore'
        : 'unknown';
    final String effectiveChannel = _releaseChannel == 'unknown'
        ? fallbackChannel
        : _releaseChannel;
    return (
      appVersion: '${info.version}+${info.buildNumber}',
      channel: effectiveChannel,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (BuildContext context, _) {
        return AnimatedBuilder(
          animation: appLockController,
          builder: (BuildContext context, _) {
            return AnimatedBuilder(
              animation: defaultRoomListeningController,
              builder: (BuildContext context, _) {
                return AnimatedBuilder(
                  animation: networkPrivacyController,
                  builder: (BuildContext context, _) {
                    void openUsers() {
                      Navigator.of(context).pop();
                      onOpenNetworkOverview?.call();
                    }

                    void openRooms() {
                      Navigator.of(context).pop();
                      onOpenRooms?.call();
                    }

                    void openSettings() {
                      onOpenSettings?.call();
                    }

                    return Scaffold(
                      appBar: AppBar(
                        automaticallyImplyLeading: false,
                        title: const AppLogoTitle('Settings'),
                      ),
                      body: Column(
                        children: [
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                SwitchListTile(
                                  key: const Key('dark_theme_switch'),
                                  title: const Text('Dark theme'),
                                  subtitle: const Text(
                                    'Dark is default. Turn off to use light theme.',
                                  ),
                                  value: themeController.isDarkMode,
                                  onChanged: themeController.setDarkMode,
                                ),
                                SwitchListTile(
                                  key: const Key('default_room_listening_switch'),
                                  title: const Text('Default room listening'),
                                  subtitle: const Text(
                                    'When you join a room, start with listening in background turned on.',
                                  ),
                                  value: defaultRoomListeningController.enabled,
                                  onChanged:
                                      defaultRoomListeningController.setEnabled,
                                ),
                                SwitchListTile(
                                  key: const Key('network_hide_from_network_switch'),
                                  title: const Text('Hide me from network'),
                                  subtitle: const Text(
                                    'Do not show your profile in the network user list.',
                                  ),
                                  value: networkPrivacyController.hideFromNetwork,
                                  onChanged: networkPrivacyController
                                      .setHideFromNetwork,
                                ),
                                if (networkPrivacyController.hideFromNetwork)
                                  SwitchListTile(
                                    key: const Key(
                                      'network_block_chat_by_id_switch',
                                    ),
                                    title: const Text('Block chat by network ID'),
                                    subtitle: const Text(
                                      'Prevent users from chatting to you using your network ID.',
                                    ),
                                    value: networkPrivacyController
                                        .blockIdChatWhenHidden,
                                    onChanged: networkPrivacyController
                                        .setBlockIdChatWhenHidden,
                                  ),
                                SwitchListTile(
                                  key: const Key('app_lock_switch'),
                                  title: const Text('App lock'),
                                  subtitle: const Text(
                                    'Use biometric if available, otherwise fallback to device screen lock.',
                                  ),
                                  value: appLockController.enabled,
                                  onChanged: (bool enabled) async {
                                    final bool ok = await appLockController
                                        .setEnabled(enabled);
                                    if (!context.mounted) {
                                      return;
                                    }
                                    if (!ok) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Authentication failed. App lock unchanged.',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                              child: DefaultTextStyle(
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall!
                                    .copyWith(color: Colors.grey.shade600),
                                child: FutureBuilder<({String appVersion, String channel})>(
                                  future: _footerMetadata(),
                                  builder: (
                                    BuildContext context,
                                    AsyncSnapshot<({String appVersion, String channel})> snapshot,
                                  ) {
                                    final String appVersion =
                                        snapshot.data?.appVersion ?? 'loading...';
                                    final String channel =
                                        snapshot.data?.channel ?? 'loading...';
                                    return Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Protocol v$chatProtocolVersion  |  App v$appVersion  |  Channel $channel',
                                          key: const Key('settings_version_footer'),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      bottomNavigationBar: AppBottomNav(
                        activeItem: AppBottomNavItem.settings,
                        onOpenUsers: onOpenNetworkOverview == null
                            ? null
                            : openUsers,
                        onOpenRooms: onOpenRooms == null ? null : openRooms,
                        onOpenSettings: openSettings,
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
