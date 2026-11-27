import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// The shared secret of a household. Generated on the first phone and
/// handed to the second in person, inside the pairing QR code; it never
/// goes through the sync backend.
class HouseholdKey {
  final Uint8List bytes;

  HouseholdKey(this.bytes) : assert(bytes.length == 32);

  factory HouseholdKey.generate() {
    final random = Random.secure();
    return HouseholdKey(
      Uint8List.fromList(List.generate(32, (_) => random.nextInt(256))),
    );
  }

  String toBase64() => base64UrlEncode(bytes).replaceAll('=', '');

  static HouseholdKey? fromBase64(String text) {
    try {
      final padded = text.padRight((text.length + 3) ~/ 4 * 4, '=');
      final bytes = base64Url.decode(padded);
      return bytes.length == 32 ? HouseholdKey(bytes) : null;
    } on FormatException {
      return null;
    }
  }
}

/// Raised when a blob cannot be decrypted: wrong key, tampered data, or a
/// blob from another household.
class HouseholdDecryptionException implements Exception {
  @override
  String toString() => 'HouseholdDecryptionException';
}

/// AES-256-GCM encryption of household blobs.
///
/// Layout: version byte (1) | 12-byte nonce | ciphertext | 16-byte tag.
/// The household id is authenticated as associated data, so a blob copied
/// from another household fails to open even with the same key.
class HouseholdCrypto {
  static const _version = 1;
  static final _cipher = AesGcm.with256bits();

  static Future<Uint8List> encrypt(
    Uint8List plain,
    HouseholdKey key,
    String householdId,
  ) async {
    final box = await _cipher.encrypt(
      plain,
      secretKey: SecretKey(key.bytes),
      nonce: _cipher.newNonce(),
      aad: utf8.encode(householdId),
    );
    return Uint8List.fromList([
      _version,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  static Future<Uint8List> decrypt(
    Uint8List blob,
    HouseholdKey key,
    String householdId,
  ) async {
    const nonceLength = 12;
    const macLength = 16;
    if (blob.length < 1 + nonceLength + macLength || blob[0] != _version) {
      throw HouseholdDecryptionException();
    }
    final nonce = blob.sublist(1, 1 + nonceLength);
    final cipherText = blob.sublist(1 + nonceLength, blob.length - macLength);
    final mac = Mac(blob.sublist(blob.length - macLength));
    try {
      final plain = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: SecretKey(key.bytes),
        aad: utf8.encode(householdId),
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw HouseholdDecryptionException();
    }
  }

  static Future<Uint8List> encryptJson(
    Map<String, dynamic> json,
    HouseholdKey key,
    String householdId,
  ) => encrypt(
    Uint8List.fromList(utf8.encode(jsonEncode(json))),
    key,
    householdId,
  );

  static Future<Map<String, dynamic>> decryptJson(
    Uint8List blob,
    HouseholdKey key,
    String householdId,
  ) async {
    final plain = await decrypt(blob, key, householdId);
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! Map<String, dynamic>) {
      throw HouseholdDecryptionException();
    }
    return decoded;
  }
}
