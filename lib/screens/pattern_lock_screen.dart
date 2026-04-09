// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';

import '../widgets/app_logo_title.dart';
import '../widgets/pattern_lock_board.dart';

enum PatternLockMode { setup, verify }

class PatternLockScreen extends StatefulWidget {
  const PatternLockScreen.setup({super.key})
    : mode = PatternLockMode.setup,
      existingPattern = null,
      title = 'Set Pattern Lock';

  const PatternLockScreen.verify({
    super.key,
    required this.existingPattern,
    this.title = 'Draw Pattern',
  }) : mode = PatternLockMode.verify;

  final PatternLockMode mode;
  final String? existingPattern;
  final String title;

  @override
  State<PatternLockScreen> createState() => _PatternLockScreenState();
}

class _PatternLockScreenState extends State<PatternLockScreen> {
  String? _firstPattern;
  String get _initialHint {
    if (widget.mode == PatternLockMode.verify) {
      return 'Draw your pattern to unlock room';
    }
    return 'Draw pattern with at least 4 dots';
  }

  String _hint = '';

  @override
  void initState() {
    super.initState();
    _hint = _initialHint;
  }

  void _onPatternComplete(String pattern) {
    if (widget.mode == PatternLockMode.verify) {
      Navigator.of(context).pop(pattern);
      return;
    }

    if (_firstPattern == null) {
      setState(() {
        _firstPattern = pattern;
        _hint = 'Draw pattern again to confirm';
      });
      return;
    }

    if (_firstPattern == pattern) {
      Navigator.of(context).pop(pattern);
      return;
    }

    setState(() {
      _firstPattern = null;
      _hint = 'Patterns did not match. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: AppLogoTitle(widget.title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_hint),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: PatternLockBoard(
                  key: Key('pattern_lock_board'),
                  onCompleted: _onPatternComplete,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Connect dots in one continuous gesture.'),
          ],
        ),
      ),
    );
  }
}
