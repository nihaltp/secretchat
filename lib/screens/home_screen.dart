// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';

import 'package:secret_chat/widgets/app_logo_title.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onHostPressed,
    required this.onWifiPressed,
    this.onOpenNetworkOverview,
    this.onOpenRooms,
    this.onOpenSettings,
    this.initialDisplayName,
    this.onDisplayNameChanged,
  });

  final ValueChanged<String> onHostPressed;
  final ValueChanged<String> onWifiPressed;
  final VoidCallback? onOpenNetworkOverview;
  final VoidCallback? onOpenRooms;
  final VoidCallback? onOpenSettings;
  final String? initialDisplayName;
  final ValueChanged<String>? onDisplayNameChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final String seeded = widget.initialDisplayName?.trim() ?? '';
    _nameController.text = seeded.isEmpty
        ? 'User${DateTime.now().millisecond % 900 + 100}'
        : seeded;
    _nameController.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    widget.onDisplayNameChanged?.call(_nameController.text);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  void _run(ValueChanged<String> callback) {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your display name first.')),
      );
      return;
    }
    callback(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppLogoTitle('Secret Chat')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 32).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Start by choosing network mode',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          key: const Key('display_name_field'),
                          controller: _nameController,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            labelText: 'Your display name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 64,
                          child: FilledButton.icon(
                            key: const Key('host_network_button'),
                            onPressed: () => _run(widget.onHostPressed),
                            icon: const Icon(Icons.wifi_tethering, size: 28),
                            label: const Text('Host Network'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 64,
                          child: OutlinedButton.icon(
                            key: const Key('use_wifi_button'),
                            onPressed: () => _run(widget.onWifiPressed),
                            icon: const Icon(Icons.wifi, size: 28),
                            label: const Text('Use Wi-Fi'),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Host Network: Open hotspot settings, then create rooms.\n'
                          'Use Wi-Fi: Join your existing LAN and discover rooms.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              // Intentionally icon-only: labels are omitted to avoid crowding
              // on narrow screens while keeping primary navigation accessible.
              child: FilledButton(
                key: const Key('bottom_nav_user_button'),
                onPressed: widget.onOpenNetworkOverview,
                child: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonal(
                key: const Key('bottom_nav_room_button'),
                onPressed: widget.onOpenRooms,
                child: const Icon(Icons.meeting_room),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonal(
                key: const Key('bottom_nav_settings_button'),
                onPressed: widget.onOpenSettings,
                child: const Icon(Icons.settings),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
