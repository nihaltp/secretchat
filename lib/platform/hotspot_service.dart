// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class HotspotService {
  Future<bool> openHotspotSettings();
}

class MethodChannelHotspotService implements HotspotService {
  const MethodChannelHotspotService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('secret_chat/hotspot');

  final MethodChannel _channel;

  @override
  Future<bool> openHotspotSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      final bool? opened = await _channel.invokeMethod<bool>(
        'openHotspotSettings',
      );
      return opened ?? false;
    } catch (_) {
      return false;
    }
  }
}