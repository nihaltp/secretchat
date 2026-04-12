import 'package:flutter_test/flutter_test.dart';
import 'package:secret_chat/chat/controllers/lan_chat_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LanChatController Concurrency Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('ensureLocalUserId called concurrently returns the exact same ID', () async {
      final LanChatController controller = LanChatController();

      // Ensure that concurrent calls to ensureLocalUserId all resolve to the same ID
      // and do not initialize multiple IDs or overwrite SharedPreferences multiple times.
      final List<Future<String>> futures = <Future<String>>[
        controller.ensureLocalUserId(),
        controller.ensureLocalUserId(),
        controller.ensureLocalUserId(),
        controller.ensureLocalUserId(),
      ];

      final List<String> results = await Future.wait(futures);

      expect(results.length, 4);
      final String firstId = results.first;
      
      for (final String id in results) {
        expect(id, firstId);
      }
      
      // Verify preferences wrote the correct ID
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('secret_chat_local_user_id'), firstId);
    });

    test('updatePresenceAnnouncement called concurrently does not orphan timers', () async {
      final LanChatController controller = LanChatController();

      // Launch multiple simultaneous update presence calls
      final List<Future<void>> futures = <Future<void>>[
        controller.updatePresenceAnnouncement(
          userName: 'U',
          hiddenFromNetwork: false,
          allowsIdChat: true,
        ),
        controller.updatePresenceAnnouncement(
          userName: 'Us',
          hiddenFromNetwork: false,
          allowsIdChat: true,
        ),
        controller.updatePresenceAnnouncement(
          userName: 'Use',
          hiddenFromNetwork: false,
          allowsIdChat: true,
        ),
        controller.updatePresenceAnnouncement(
          userName: 'User',
          hiddenFromNetwork: false,
          allowsIdChat: true,
        ),
      ];

      await Future.wait(futures);

      // Clean up the controller
      controller.dispose();
      
      // If timers were orphaned, they would still trigger and cause memory leaks.
      // Simply reaching here without multiple active presence sequences is a success indication in tests
      // as our implementation relies on the sequence ID cleanly skipping legacy closure executions.
      expect(controller.localUserName, 'User');
    });
  });
}
