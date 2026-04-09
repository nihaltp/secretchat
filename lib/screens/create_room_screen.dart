// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';

import '../chat/models/room_creation_data.dart';
import '../chat/models/room_info.dart';
import '../widgets/app_logo_title.dart';
import 'pattern_lock_screen.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final TextEditingController _roomNameController = TextEditingController();
  final TextEditingController _securityController = TextEditingController();

  bool _hidden = false;
  RoomSecurityType _securityType = RoomSecurityType.none;
  String? _patternValue;

  @override
  void dispose() {
    _roomNameController.dispose();
    _securityController.dispose();
    super.dispose();
  }

  String get _securityLabel {
    switch (_securityType) {
      case RoomSecurityType.password:
        return 'Password';
      case RoomSecurityType.pin:
        return 'PIN';
      case RoomSecurityType.pattern:
        return 'Pattern (example: 1-2-3-6)';
      case RoomSecurityType.none:
        return '';
    }
  }

  void _submit() {
    final String roomName = _roomNameController.text.trim();
    final String securityValue = _securityController.text.trim();

    if (roomName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Room name is required.')));
      return;
    }

    if (_securityType != RoomSecurityType.none &&
        _securityType != RoomSecurityType.pattern &&
        securityValue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter security value for this room.')),
      );
      return;
    }

    if (_securityType == RoomSecurityType.pattern &&
        (_patternValue == null || _patternValue!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a pattern before creating room.')),
      );
      return;
    }

    Navigator.of(context).pop(
      RoomCreationData(
        roomName: roomName,
        hidden: _hidden,
        securityType: _securityType,
        securityValue: _securityType == RoomSecurityType.none
            ? null
            : _securityType == RoomSecurityType.pattern
            ? _patternValue
            : securityValue,
      ),
    );
  }

  Future<void> _setupPattern() async {
    final String? pattern = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const PatternLockScreen.setup(),
      ),
    );

    if (pattern == null || !mounted) {
      return;
    }

    setState(() {
      _patternValue = pattern;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppLogoTitle('Create Room')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              key: const Key('room_name_field'),
              controller: _roomNameController,
              decoration: const InputDecoration(
                labelText: 'Room name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const Key('hidden_room_switch'),
              value: _hidden,
              onChanged: (bool v) {
                setState(() {
                  _hidden = v;
                });
              },
              title: const Text('Hide room from list'),
              subtitle: const Text(
                'Hidden rooms are not listed. Users can join by room name and security value.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<RoomSecurityType>(
              key: const Key('security_type_dropdown'),
              initialValue: _securityType,
              items: const [
                DropdownMenuItem(
                  value: RoomSecurityType.none,
                  child: Text('No security'),
                ),
                DropdownMenuItem(
                  value: RoomSecurityType.password,
                  child: Text('Password'),
                ),
                DropdownMenuItem(
                  value: RoomSecurityType.pin,
                  child: Text('PIN'),
                ),
                DropdownMenuItem(
                  value: RoomSecurityType.pattern,
                  child: Text('Pattern'),
                ),
              ],
              onChanged: (RoomSecurityType? value) {
                setState(() {
                  _securityType = value ?? RoomSecurityType.none;
                  if (_securityType == RoomSecurityType.none) {
                    _securityController.clear();
                    _patternValue = null;
                  }
                });
              },
              decoration: const InputDecoration(
                labelText: 'Security',
                border: OutlineInputBorder(),
              ),
            ),
            if (_securityType != RoomSecurityType.none) ...[
              const SizedBox(height: 12),
              if (_securityType == RoomSecurityType.pattern)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilledButton.tonalIcon(
                      key: const Key('setup_pattern_button'),
                      onPressed: _setupPattern,
                      icon: const Icon(Icons.pattern),
                      label: Text(
                        _patternValue == null ? 'Set Pattern' : 'Reset Pattern',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _patternValue == null
                          ? 'No pattern set'
                          : 'Pattern is set',
                    ),
                  ],
                )
              else
                TextField(
                  key: const Key('security_value_field'),
                  controller: _securityController,
                  obscureText: _securityType == RoomSecurityType.password,
                  keyboardType: _securityType == RoomSecurityType.pin
                      ? TextInputType.number
                      : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: _securityLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('create_room_submit_button'),
              onPressed: _submit,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create Room'),
            ),
          ],
        ),
      ),
    );
  }
}
