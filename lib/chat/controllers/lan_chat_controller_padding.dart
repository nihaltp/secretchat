// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

part of 'lan_chat_controller.dart';

extension on LanChatController {
  String _generateJunkText(int length) {
    if (length <= 0) return '';
    const String chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final Random rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
      ),
    );
  }

  List<String> _chunkAndPadMessage(String text) {
    final List<String> parts = <String>[];
    int start = 0;
    while (start < text.length) {
      int end = start + messageLengthLimit;
      if (end > text.length) {
        end = text.length;
      }
      parts.add(text.substring(start, end));
      start = end;
    }

    final List<String> result = <String>[];
    for (final String part in parts) {
      String paddedPart = part;
      if (paddedPart.length < messageLengthLimit) {
        paddedPart +=
            '\u0000${_generateJunkText(messageLengthLimit - paddedPart.length - 1)}';
      }
      result.add(paddedPart);
    }
    return result;
  }
}
