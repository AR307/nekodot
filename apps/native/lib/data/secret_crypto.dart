import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Relay sees only this envelope. The destination Node holds the Bot private key.
Future<Map<String, dynamic>> encryptSecretDelivery({
  required String nodeId,
  required String botId,
  required String requestId,
  required String publicKey,
  required Map<String, String> fields,
}) async {
  final exchange = X25519();
  final pair = await exchange.newKeyPair();
  final peer = SimplePublicKey(
    base64Decode(publicKey),
    type: KeyPairType.x25519,
  );
  final shared = await exchange.sharedSecretKey(
    keyPair: pair,
    remotePublicKey: peer,
  );
  final random = Random.secure();
  final salt = List<int>.generate(32, (_) => random.nextInt(256));
  final context = utf8.encode(
    jsonEncode(['nekodot-secret-v1', nodeId, botId, requestId]),
  );
  final key = await Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  ).deriveKey(secretKey: shared, nonce: salt, info: context);
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(jsonEncode(fields)),
    secretKey: key,
    aad: context,
  );
  final localPublic = await pair.extractPublicKey();
  return {
    'version': 1,
    'publicKey': base64Encode(localPublic.bytes),
    'salt': base64Encode(salt),
    'nonce': base64Encode(box.nonce),
    'ciphertext': base64Encode(box.cipherText),
    'tag': base64Encode(box.mac.bytes),
  };
}
