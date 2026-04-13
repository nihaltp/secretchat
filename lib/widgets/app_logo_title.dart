// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLogoTitle extends StatelessWidget {
  const AppLogoTitle(this.title, {super.key, this.logoSize = 24});

  final String title;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    final String logoAssetPath = kDebugMode
        ? 'assets/branding/app_logo_debug.png'
        : 'assets/branding/app_logo.jpg';

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            logoAssetPath,
            width: logoSize,
            height: logoSize,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
