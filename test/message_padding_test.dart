import 'package:flutter_test/flutter_test.dart';
import 'package:secret_chat/chat/chat_constants.dart';
import 'package:secret_chat/chat/controllers/lan_chat_controller.dart';
import 'package:secret_chat/chat/models/chat_message.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('sendMessage chunks text and strips padding locally', () async {
    // Bind to random ephemeral ports so we don't conflict with other tests
    final LanChatController controller = LanChatController(
      chatPortOverride: 0,
      discoveryPortOverride: 0,
    );

    final bool hosted = await controller.hostRoom(
      yourName: 'Alice',
      room: 'Test Room Padding',
    );
    expect(hosted, isTrue);

    // Wait for the room creation to settle
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Clear system messages like "Room created" to easily check our sent messages
    controller.messages.clear();

    // The limit is exactly messageLengthLimit
    final int extraLength = 15;
    final String longMessage = 'A' * (messageLengthLimit + extraLength);

    await controller.sendMessage(longMessage);

    // Check we have split it into 2 chunks
    // The underlying network packets would be fully padded to messageLengthLimit but locally
    // the junk text and the null termination byte is correctly stripped before presentation.
    expect(controller.messages.length, 2);

    final ChatMessage firstChunk = controller.messages[0];
    final ChatMessage secondChunk = controller.messages[1];

    expect(firstChunk.text.length, messageLengthLimit);
    expect(firstChunk.text, 'A' * messageLengthLimit);

    expect(secondChunk.text.length, extraLength);
    expect(secondChunk.text, 'A' * extraLength);

    // Ensure the message has no null-byte artifacts left
    expect(secondChunk.text.contains('\u0000'), isFalse);

    await controller.disconnect();
    controller.dispose();
  });
}
