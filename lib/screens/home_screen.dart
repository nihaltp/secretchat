import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onHostPressed,
    required this.onWifiPressed,
    required this.onOpenSettings,
  });

  final ValueChanged<String> onHostPressed;
  final ValueChanged<String> onWifiPressed;
  final VoidCallback onOpenSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.text = 'User${DateTime.now().millisecond % 900 + 100}';
  }

  @override
  void dispose() {
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
      appBar: AppBar(
        title: const Text('Secret Chat'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Start by choosing network mode',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('display_name_field'),
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Your display name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('host_network_button'),
              onPressed: () => _run(widget.onHostPressed),
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Host Network'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('use_wifi_button'),
              onPressed: () => _run(widget.onWifiPressed),
              icon: const Icon(Icons.wifi),
              label: const Text('Use Wi-Fi'),
            ),
            const SizedBox(height: 12),
            Text(
              'Host Network: Turn on your hotspot, then create rooms.\n'
              'Use Wi-Fi: Join your existing LAN and discover rooms.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
