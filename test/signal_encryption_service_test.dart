import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secret_chat/security/signal_encryption_service.dart';

void main() {
  group('SignalEncryptionService', () {
    late SignalEncryptionService alice;
    late SignalEncryptionService bob;

    setUp(() async {
      alice = SignalEncryptionService();
      bob = SignalEncryptionService();

      await alice.initialize(localUserId: 'alice');
      await bob.initialize(localUserId: 'bob');

      alice.registerPeerBundle('bob', bob.exportPreKeyBundle());
      bob.registerPeerBundle('alice', alice.exportPreKeyBundle());
    });

    tearDown(() async {
      await alice.endSession();
      await bob.endSession();
    });

    test('encrypt/decrypt performs initial X3DH handshake', () async {
      final String encrypted = await alice.encryptMessage('hello bob', 'bob');
      final String decrypted = await bob.decryptMessage(encrypted, 'alice');

      expect(decrypted, 'hello bob');
      expect(encrypted.contains('x3dh'), isTrue);
      expect(encrypted.contains('"port":48653'), isTrue);
    });

    test(
      'double ratchet derives distinct ciphertext for repeated plaintext',
      () async {
        final String first = await alice.encryptMessage('same text', 'bob');
        final String second = await alice.encryptMessage('same text', 'bob');

        expect(first, isNot(second));

        final String firstDecrypted = await bob.decryptMessage(first, 'alice');
        final String secondDecrypted = await bob.decryptMessage(
          second,
          'alice',
        );

        expect(firstDecrypted, 'same text');
        expect(secondDecrypted, 'same text');
      },
    );

    test('bidirectional messages decrypt after ratchet updates', () async {
      final String toBob = await alice.encryptMessage('msg-1', 'bob');
      final String fromAlice = await bob.decryptMessage(toBob, 'alice');
      expect(fromAlice, 'msg-1');

      final String toAlice = await bob.encryptMessage('reply-1', 'alice');
      final String fromBob = await alice.decryptMessage(toAlice, 'bob');
      expect(fromBob, 'reply-1');

      final String toBob2 = await alice.encryptMessage('msg-2', 'bob');
      final String fromAlice2 = await bob.decryptMessage(toBob2, 'alice');
      expect(fromAlice2, 'msg-2');
    });

    test('clearing sessions prevents decrypting new messages', () async {
      final String encrypted = await alice.encryptMessage(
        'before clear',
        'bob',
      );
      final String decrypted = await bob.decryptMessage(encrypted, 'alice');
      expect(decrypted, 'before clear');

      bob.clearSession('alice');
      final String nextCipher = await alice.encryptMessage(
        'after clear',
        'bob',
      );

      expect(
        () => bob.decryptMessage(nextCipher, 'alice'),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'encrypted envelope keeps direct-port metadata and one-time handshake',
      () async {
        final String firstCipher = await alice.encryptMessage('first', 'bob');
        final Map<String, dynamic> first =
            jsonDecode(firstCipher) as Map<String, dynamic>;

        expect(first['alg'], 'signal-x3dh-double-ratchet-aes256gcm');
        expect(first['port'], 48653);
        expect(first.containsKey('x3dh'), isTrue);
        expect(first['header'], isA<Map<String, dynamic>>());
        expect(first['nonce'], isA<String>());
        expect(first['ct'], isA<String>());
        expect(first['mac'], isA<String>());

        final String secondCipher = await alice.encryptMessage('second', 'bob');
        final Map<String, dynamic> second =
            jsonDecode(secondCipher) as Map<String, dynamic>;

        // The initial X3DH bootstrap data should only be included once per session.
        expect(second.containsKey('x3dh'), isFalse);

        expect(await bob.decryptMessage(firstCipher, 'alice'), 'first');
        expect(await bob.decryptMessage(secondCipher, 'alice'), 'second');
      },
    );
  });
}
