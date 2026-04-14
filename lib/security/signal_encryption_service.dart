// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:secret_chat/chat/chat_constants.dart';

class SignalPreKeyBundle {
  SignalPreKeyBundle({
    required this.userId,
    required this.identityKey,
    required this.signedPreKey,
    required this.signedPreKeySignature,
    this.oneTimePreKey,
    this.oneTimePreKeyId,
  });

  final String userId;
  final SimplePublicKey identityKey;
  final SimplePublicKey signedPreKey;
  final List<int> signedPreKeySignature;
  final SimplePublicKey? oneTimePreKey;
  final int? oneTimePreKeyId;
}

class SignalEncryptionService {
  SignalEncryptionService({Random? random})
    : _random = random ?? Random.secure();

  static const int _kdfSize = 32;

  final Random _random;

  late final AesGcm _aesGcm = AesGcm.with256bits();
  late final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: _kdfSize * 2);
  late final Ed25519 _ed25519 = Ed25519();
  late final X25519 _x25519 = X25519();

  String? _localUserId;
  SimpleKeyPair? _identityKeyPair;
  SimplePublicKey? _identityPublicKey;
  SimpleKeyPair? _signedPreKeyPair;
  SimplePublicKey? _signedPreKeyPublic;
  List<int>? _signedPreKeySignature;

  final Map<int, SimpleKeyPair> _oneTimePreKeysById = <int, SimpleKeyPair>{};
  final Map<int, SimplePublicKey> _oneTimePreKeyPublicById =
      <int, SimplePublicKey>{};
  final Map<String, SignalPreKeyBundle> _peerBundlesByUserId =
      <String, SignalPreKeyBundle>{};
  final Map<String, _SessionState> _sessionsByPeerId =
      <String, _SessionState>{};

  bool get isInitialized =>
      _identityKeyPair != null && _signedPreKeyPair != null;

  Future<void> initialize({
    required String localUserId,
    int oneTimePreKeyCount = 10,
  }) async {
    clearAllSessions();

    _localUserId = localUserId.trim();
    if (_localUserId!.isEmpty) {
      throw ArgumentError('localUserId must not be empty.');
    }

    _identityKeyPair = await _ed25519.newKeyPair();
    _identityPublicKey = await _identityKeyPair!.extractPublicKey();

    _signedPreKeyPair = await _x25519.newKeyPair();
    _signedPreKeyPublic = await _signedPreKeyPair!.extractPublicKey();
    final List<int> preKeyBytes = _signedPreKeyPublic!.bytes;
    final Signature signature = await _ed25519.sign(
      preKeyBytes,
      keyPair: _identityKeyPair!,
    );
    _signedPreKeySignature = List<int>.from(signature.bytes);

    _oneTimePreKeysById.clear();
    _oneTimePreKeyPublicById.clear();
    final int normalizedPreKeyCount = oneTimePreKeyCount < 0
        ? 0
        : oneTimePreKeyCount;
    for (int i = 0; i < normalizedPreKeyCount; i++) {
      final int id = i + 1;
      final SimpleKeyPair keyPair = await _x25519.newKeyPair();
      final SimplePublicKey publicKey = await keyPair.extractPublicKey();
      _oneTimePreKeysById[id] = keyPair;
      _oneTimePreKeyPublicById[id] = publicKey;
    }
  }

  SignalPreKeyBundle exportPreKeyBundle() {
    _requireInitialized();

    final int? oneTimeId = _oneTimePreKeysById.keys.isEmpty
        ? null
        : _oneTimePreKeysById.keys.first;
    return SignalPreKeyBundle(
      userId: _localUserId!,
      identityKey: _identityPublicKey!,
      signedPreKey: _signedPreKeyPublic!,
      signedPreKeySignature: List<int>.from(_signedPreKeySignature!),
      oneTimePreKey: oneTimeId == null
          ? null
          : _oneTimePreKeyPublicById[oneTimeId],
      oneTimePreKeyId: oneTimeId,
    );
  }

  void registerPeerBundle(String peerId, SignalPreKeyBundle bundle) {
    _requireInitialized();

    final String normalizedPeer = peerId.trim();
    if (normalizedPeer.isEmpty) {
      throw ArgumentError('peerId must not be empty.');
    }

    if (bundle.userId.trim() != normalizedPeer) {
      throw ArgumentError('bundle.userId must match peerId.');
    }

    _peerBundlesByUserId[normalizedPeer] = bundle;
  }

  Future<String> encryptMessage(String plainText, String recipientId) async {
    _requireInitialized();

    final String normalizedRecipient = recipientId.trim();
    if (normalizedRecipient.isEmpty) {
      throw ArgumentError('recipientId must not be empty.');
    }

    final String trimmed = plainText.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('plainText must not be empty.');
    }

    final _SessionState session =
        _sessionsByPeerId[normalizedRecipient] ??
        await _createInitiatorSession(normalizedRecipient);

    final _ChainStep sendStep = await _deriveChainStep(
      session.sendingChainKey!,
    );
    session.sendingChainKey = sendStep.nextChainKey;

    final List<int> nonce = _randomBytes(12);
    final List<int> associatedData = _buildAssociatedData(
      senderId: _localUserId!,
      recipientId: normalizedRecipient,
      dhPublicKey: session.localRatchetPublic,
      messageIndex: session.sendCount,
      previousChainLength: session.previousChainLength,
    );

    final SecretBox encrypted = await _aesGcm.encrypt(
      utf8.encode(trimmed),
      secretKey: SecretKey(sendStep.messageKey),
      nonce: nonce,
      aad: associatedData,
    );

    final Map<String, dynamic> payload = <String, dynamic>{
      'v': 1,
      'alg': 'signal-x3dh-double-ratchet-aes256gcm',
      'port': userChatPort,
      'header': <String, dynamic>{
        'senderId': _localUserId,
        'recipientId': normalizedRecipient,
        'dh': _b64Encode(session.localRatchetPublic.bytes),
        'pn': session.previousChainLength,
        'n': session.sendCount,
      },
      'nonce': _b64Encode(encrypted.nonce),
      'ct': _b64Encode(encrypted.cipherText),
      'mac': _b64Encode(encrypted.mac.bytes),
    };

    if (session.pendingHandshake != null) {
      payload['x3dh'] = session.pendingHandshake;
      session.pendingHandshake = null;
    }

    session.sendCount += 1;
    _sessionsByPeerId[normalizedRecipient] = session;
    return jsonEncode(payload);
  }

  Future<String> decryptMessage(String cipherText, String senderId) async {
    _requireInitialized();

    final String normalizedSender = senderId.trim();
    if (normalizedSender.isEmpty) {
      throw ArgumentError('senderId must not be empty.');
    }

    final dynamic decoded = jsonDecode(cipherText);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('cipherText is not a valid encrypted payload.');
    }

    final Map<String, dynamic> header =
        (decoded['header'] as Map<String, dynamic>? ?? <String, dynamic>{});
    final String dhB64 = (header['dh'] ?? '').toString();
    if (dhB64.isEmpty) {
      throw StateError('Encrypted payload missing ratchet public key.');
    }

    final _SessionState session =
        _sessionsByPeerId[normalizedSender] ??
        await _createResponderSession(normalizedSender, decoded);

    final List<int> remoteRatchetBytes = _b64Decode(dhB64);
    final SimplePublicKey remoteRatchetPublic = SimplePublicKey(
      remoteRatchetBytes,
      type: KeyPairType.x25519,
    );

    if (!_bytesEqual(session.remoteRatchetPublic.bytes, remoteRatchetBytes)) {
      await _applyDhRatchetStep(session, remoteRatchetPublic);
    }

    final int messageIndex = header['n'] is int
        ? header['n'] as int
        : int.tryParse((header['n'] ?? '').toString()) ?? 0;
    if (messageIndex < session.receiveCount) {
      throw StateError(
        'Out-of-order or replayed message is not supported in this build.',
      );
    }

    List<int>? messageKey;
    while (session.receiveCount <= messageIndex) {
      final _ChainStep step = await _deriveChainStep(
        session.receivingChainKey!,
      );
      session.receivingChainKey = step.nextChainKey;
      messageKey = step.messageKey;
      session.receiveCount += 1;
    }

    final List<int> associatedData = _buildAssociatedData(
      senderId: normalizedSender,
      recipientId: _localUserId!,
      dhPublicKey: remoteRatchetPublic,
      messageIndex: messageIndex,
      previousChainLength: header['pn'] is int
          ? header['pn'] as int
          : int.tryParse((header['pn'] ?? '').toString()) ?? 0,
    );

    final SecretBox box = SecretBox(
      _b64Decode((decoded['ct'] ?? '').toString()),
      nonce: _b64Decode((decoded['nonce'] ?? '').toString()),
      mac: Mac(_b64Decode((decoded['mac'] ?? '').toString())),
    );

    final List<int> clear = await _aesGcm.decrypt(
      box,
      secretKey: SecretKey(messageKey!),
      aad: associatedData,
    );

    _sessionsByPeerId[normalizedSender] = session;
    return utf8.decode(clear);
  }

  void clearSession(String peerId) {
    final String normalizedPeer = peerId.trim();
    if (normalizedPeer.isEmpty) {
      return;
    }

    final _SessionState? session = _sessionsByPeerId.remove(normalizedPeer);
    if (session == null) {
      return;
    }

    _zeroize(session.rootKey);
    _zeroize(session.sendingChainKey);
    _zeroize(session.receivingChainKey);
  }

  void clearAllSessions() {
    for (final String peer in _sessionsByPeerId.keys.toList()) {
      clearSession(peer);
    }
    _sessionsByPeerId.clear();
    _peerBundlesByUserId.clear();
  }

  Future<void> endSession() async {
    clearAllSessions();

    _zeroize(_signedPreKeySignature);
    _signedPreKeySignature = null;

    _identityKeyPair = null;
    _identityPublicKey = null;
    _signedPreKeyPair = null;
    _signedPreKeyPublic = null;

    _oneTimePreKeysById.clear();
    _oneTimePreKeyPublicById.clear();
    _localUserId = null;
  }

  Future<_SessionState> _createInitiatorSession(String recipientId) async {
    final SignalPreKeyBundle? bundle = _peerBundlesByUserId[recipientId];
    if (bundle == null) {
      throw StateError('Missing pre-key bundle for recipient: $recipientId.');
    }

    final bool signatureValid = await _ed25519.verify(
      bundle.signedPreKey.bytes,
      signature: Signature(
        bundle.signedPreKeySignature,
        publicKey: bundle.identityKey,
      ),
    );
    if (!signatureValid) {
      throw StateError('Recipient signed pre-key signature validation failed.');
    }

    final SimpleKeyPair initialRatchetKeyPair = await _x25519.newKeyPair();
    final SimplePublicKey initialRatchetPublic = await initialRatchetKeyPair
        .extractPublicKey();

    final List<int> dhPrimary = await _sharedSecret(
      local: initialRatchetKeyPair,
      remote: bundle.signedPreKey,
    );

    final int? oneTimeId = bundle.oneTimePreKeyId;
    List<int> ikm = dhPrimary;
    if (bundle.oneTimePreKey != null && oneTimeId != null) {
      final List<int> dhOneTime = await _sharedSecret(
        local: initialRatchetKeyPair,
        remote: bundle.oneTimePreKey!,
      );
      ikm = <int>[...ikm, ...dhOneTime];
    }

    final List<int> rootAndChain = await _hkdfMaterial(
      ikm: ikm,
      salt: Uint8List(_kdfSize),
      info: utf8.encode('secret-chat/x3dh/init-v1'),
    );

    final _SessionState session = _SessionState(
      rootKey: rootAndChain.sublist(0, _kdfSize),
      sendingChainKey: rootAndChain.sublist(_kdfSize),
      receivingChainKey: rootAndChain.sublist(_kdfSize),
      localRatchetKeyPair: initialRatchetKeyPair,
      localRatchetPublic: initialRatchetPublic,
      remoteRatchetPublic: bundle.signedPreKey,
      sendCount: 0,
      receiveCount: 0,
      previousChainLength: 0,
      pendingHandshake: <String, dynamic>{
        'ik': _b64Encode(_identityPublicKey!.bytes),
        'ek': _b64Encode(initialRatchetPublic.bytes),
        'spkId': 1,
        'opkId': oneTimeId,
      },
    );

    _sessionsByPeerId[recipientId] = session;
    return session;
  }

  Future<_SessionState> _createResponderSession(
    String senderId,
    Map<String, dynamic> payload,
  ) async {
    final Map<String, dynamic>? x3dh = payload['x3dh'] as Map<String, dynamic>?;
    if (x3dh == null) {
      throw StateError(
        'Missing session and no X3DH data for sender: $senderId.',
      );
    }

    final String ek = (x3dh['ek'] ?? '').toString();
    if (ek.isEmpty) {
      throw StateError('X3DH payload missing initiator ephemeral key.');
    }

    final SimplePublicKey initiatorEphemeral = SimplePublicKey(
      _b64Decode(ek),
      type: KeyPairType.x25519,
    );

    final List<int> dhPrimary = await _sharedSecret(
      local: _signedPreKeyPair!,
      remote: initiatorEphemeral,
    );

    List<int> ikm = dhPrimary;
    final int? oneTimeId = x3dh['opkId'] is int
        ? x3dh['opkId'] as int
        : int.tryParse((x3dh['opkId'] ?? '').toString());

    if (oneTimeId != null) {
      final SimpleKeyPair? oneTimePreKey = _oneTimePreKeysById.remove(
        oneTimeId,
      );
      _oneTimePreKeyPublicById.remove(oneTimeId);
      if (oneTimePreKey != null) {
        final List<int> dhOneTime = await _sharedSecret(
          local: oneTimePreKey,
          remote: initiatorEphemeral,
        );
        ikm = <int>[...ikm, ...dhOneTime];
      }
    }

    final List<int> rootAndChain = await _hkdfMaterial(
      ikm: ikm,
      salt: Uint8List(_kdfSize),
      info: utf8.encode('secret-chat/x3dh/init-v1'),
    );

    final _SessionState session = _SessionState(
      rootKey: rootAndChain.sublist(0, _kdfSize),
      sendingChainKey: rootAndChain.sublist(_kdfSize),
      receivingChainKey: rootAndChain.sublist(_kdfSize),
      localRatchetKeyPair: _signedPreKeyPair!,
      localRatchetPublic: _signedPreKeyPublic!,
      remoteRatchetPublic: initiatorEphemeral,
      sendCount: 0,
      receiveCount: 0,
      previousChainLength: 0,
    );

    _sessionsByPeerId[senderId] = session;
    return session;
  }

  Future<void> _applyDhRatchetStep(
    _SessionState session,
    SimplePublicKey remoteRatchetPublic,
  ) async {
    final List<int> receiveDh = await _sharedSecret(
      local: session.localRatchetKeyPair,
      remote: remoteRatchetPublic,
    );
    final _RootStep receivedStep = await _deriveRootStep(
      rootKey: session.rootKey,
      dhOut: receiveDh,
    );

    session.rootKey = receivedStep.nextRootKey;
    session.receivingChainKey = receivedStep.chainKey;
    session.remoteRatchetPublic = remoteRatchetPublic;
    session.previousChainLength = session.sendCount;
    session.sendCount = 0;
    session.receiveCount = 0;

    session.localRatchetKeyPair = await _x25519.newKeyPair();
    session.localRatchetPublic = await session.localRatchetKeyPair
        .extractPublicKey();

    final List<int> sendDh = await _sharedSecret(
      local: session.localRatchetKeyPair,
      remote: remoteRatchetPublic,
    );
    final _RootStep sendStep = await _deriveRootStep(
      rootKey: session.rootKey,
      dhOut: sendDh,
    );
    session.rootKey = sendStep.nextRootKey;
    session.sendingChainKey = sendStep.chainKey;
  }

  Future<_RootStep> _deriveRootStep({
    required List<int> rootKey,
    required List<int> dhOut,
  }) async {
    final List<int> material = await _hkdfMaterial(
      ikm: dhOut,
      salt: rootKey,
      info: utf8.encode('secret-chat/double-ratchet/root-v1'),
    );
    return _RootStep(
      nextRootKey: material.sublist(0, _kdfSize),
      chainKey: material.sublist(_kdfSize),
    );
  }

  Future<_ChainStep> _deriveChainStep(List<int> chainKey) async {
    final List<int> material = await _hkdfMaterial(
      ikm: chainKey,
      salt: Uint8List(_kdfSize),
      info: utf8.encode('secret-chat/double-ratchet/chain-v1'),
    );
    return _ChainStep(
      nextChainKey: material.sublist(0, _kdfSize),
      messageKey: material.sublist(_kdfSize),
    );
  }

  Future<List<int>> _sharedSecret({
    required SimpleKeyPair local,
    required SimplePublicKey remote,
  }) async {
    final SecretKey secret = await _x25519.sharedSecretKey(
      keyPair: local,
      remotePublicKey: remote,
    );
    return secret.extractBytes();
  }

  Future<List<int>> _hkdfMaterial({
    required List<int> ikm,
    required List<int> salt,
    required List<int> info,
  }) async {
    final SecretKey key = await _hkdf.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: salt,
      info: info,
    );
    return key.extractBytes();
  }

  List<int> _buildAssociatedData({
    required String senderId,
    required String recipientId,
    required SimplePublicKey dhPublicKey,
    required int messageIndex,
    required int previousChainLength,
  }) {
    final String dhEncoded = _b64Encode(dhPublicKey.bytes);
    return utf8.encode(
      '$senderId|$recipientId|$dhEncoded|$messageIndex|$previousChainLength|$userChatPort',
    );
  }

  List<int> _randomBytes(int count) {
    return List<int>.generate(
      count,
      (_) => _random.nextInt(256),
      growable: false,
    );
  }

  String _b64Encode(List<int> bytes) {
    return base64Url.encode(bytes);
  }

  List<int> _b64Decode(String value) {
    return base64Url.decode(value);
  }

  void _zeroize(List<int>? bytes) {
    if (bytes == null) {
      return;
    }
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  void _requireInitialized() {
    if (!isInitialized || _localUserId == null || _localUserId!.isEmpty) {
      throw StateError('SignalEncryptionService is not initialized.');
    }
  }
}

class _SessionState {
  _SessionState({
    required this.rootKey,
    required this.sendingChainKey,
    required this.receivingChainKey,
    required this.localRatchetKeyPair,
    required this.localRatchetPublic,
    required this.remoteRatchetPublic,
    required this.sendCount,
    required this.receiveCount,
    required this.previousChainLength,
    this.pendingHandshake,
  });

  List<int> rootKey;
  List<int>? sendingChainKey;
  List<int>? receivingChainKey;
  SimpleKeyPair localRatchetKeyPair;
  SimplePublicKey localRatchetPublic;
  SimplePublicKey remoteRatchetPublic;
  int sendCount;
  int receiveCount;
  int previousChainLength;
  Map<String, dynamic>? pendingHandshake;
}

class _RootStep {
  _RootStep({required this.nextRootKey, required this.chainKey});

  final List<int> nextRootKey;
  final List<int> chainKey;
}

class _ChainStep {
  _ChainStep({required this.nextChainKey, required this.messageKey});

  final List<int> nextChainKey;
  final List<int> messageKey;
}
