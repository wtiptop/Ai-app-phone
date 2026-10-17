import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => 'BackupException: $message';
}

/// Versioned passphrase backup, separate from SQLite at-rest encryption.
/// No key/passphrase/payload is written to logs or stored by this class.
class EncryptedBackup {
  EncryptedBackup() : _random = Random.secure();

  static const int formatVersion = 1;
  static const int iterations = 600000;
  static const int maxPayloadBytes = 32 * 1024 * 1024;
  static const String _aad = 'Scalajaca|backup|1|PBKDF2-SHA256|AES-256-GCM';
  final Random _random;
  final _cipher = AesGcm.with256bits();

  List<int> _bytes(int length) =>
      List.generate(length, (_) => _random.nextInt(256));

  Future<SecretKey> _key(String passphrase, List<int> salt) => Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);

  void _validatePassphrase(String passphrase) {
    if (passphrase.runes.length < 12 || utf8.encode(passphrase).length > 4096) {
      throw const BackupException(
        'Hasło kopii musi mieć co najmniej 12 znaków.',
      );
    }
  }

  Future<String> encrypt(List<int> plaintext, String passphrase) async {
    _validatePassphrase(passphrase);
    if (plaintext.length > maxPayloadBytes ||
        plaintext.any((byte) => byte < 0 || byte > 255)) {
      throw const BackupException('Nieprawidłowy rozmiar lub dane kopii.');
    }
    final salt = _bytes(16);
    final nonce = _bytes(12);
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: await _key(passphrase, salt),
      nonce: nonce,
      aad: utf8.encode(_aad),
    );
    return jsonEncode({
      'format': 'scalajaca.encrypted-backup',
      'version': formatVersion,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': iterations,
      'cipher': 'AES-256-GCM',
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    });
  }

  Future<List<int>> decrypt(String envelope, String passphrase) async {
    _validatePassphrase(passphrase);
    // Validate bounded parameters BEFORE expensive KDF or allocation.
    if (utf8.encode(envelope).length > maxPayloadBytes * 2) {
      throw const BackupException('Kopia przekracza dozwolony rozmiar.');
    }
    try {
      final value = jsonDecode(envelope);
      if (value is! Map<String, dynamic> ||
          value.length != 9 ||
          value['format'] != 'scalajaca.encrypted-backup' ||
          value['version'] != formatVersion ||
          value['kdf'] != 'PBKDF2-HMAC-SHA256' ||
          value['iterations'] != iterations ||
          value['cipher'] != 'AES-256-GCM') {
        throw const FormatException();
      }
      final salt = base64Decode(value['salt'] as String);
      final nonce = base64Decode(value['nonce'] as String);
      final ciphertext = base64Decode(value['ciphertext'] as String);
      final tag = base64Decode(value['tag'] as String);
      if (salt.length != 16 ||
          nonce.length != 12 ||
          tag.length != 16 ||
          ciphertext.length > maxPayloadBytes) {
        throw const FormatException();
      }
      return await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
        secretKey: await _key(passphrase, salt),
        aad: utf8.encode(_aad),
      );
    } catch (_) {
      // One failure message avoids exposing key or plaintext/authentication details.
      throw const BackupException(
        'Nie można odczytać kopii: złe hasło lub uszkodzone dane.',
      );
    }
  }
}
