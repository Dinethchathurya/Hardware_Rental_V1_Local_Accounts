import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

typedef PasswordRecord = ({String salt, String hash, int iterations});

const _iterations = 600000;

Future<PasswordRecord> createPassword(String password) async {
  if (password.length < 12 || password.length > 128) {
    throw StateError('Use a password between 12 and 128 characters.');
  }
  final random = Random.secure();
  final salt = List.generate(16, (_) => random.nextInt(256));
  final hash = await derivePassword(password, salt, _iterations);
  return (
    salt: base64Encode(salt),
    hash: base64Encode(hash),
    iterations: _iterations,
  );
}

Future<bool> verifyPassword(String password, PasswordRecord stored) async {
  if (password.length > 128) return false;
  final expected = base64Decode(stored.hash);
  final actual = await derivePassword(
    password,
    base64Decode(stored.salt),
    stored.iterations,
  );
  if (expected.length != actual.length) return false;
  var difference = 0;
  for (var i = 0; i < expected.length; i++) {
    difference |= expected[i] ^ actual[i];
  }
  return difference == 0;
}

Future<Uint8List> derivePassword(
  String password,
  List<int> salt,
  int iterations,
) async {
  final hmac = Hmac(sha256, utf8.encode(password));
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final digest = Uint8List.fromList(block);
  for (var round = 1; round < iterations; round++) {
    if (round % 4096 == 0) await Future<void>.delayed(Duration.zero);
    block = hmac.convert(block).bytes;
    for (var index = 0; index < digest.length; index++) {
      digest[index] ^= block[index];
    }
  }
  return digest;
}
