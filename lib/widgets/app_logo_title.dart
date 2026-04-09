// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'package:flutter/material.dart';

class AppLogoTitle extends StatelessWidget {
  const AppLogoTitle(this.title, {super.key, this.logoSize = 24});

  final String title;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/branding/app_logo.jpg',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 8),
        Text(title),
      ],
    );
  }
}
