import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecretStore {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
  Future<void> delete(String name);
}

/// Android: implementacja pluginu korzystająca z Android Keystore.
class KeystoreSecrets implements SecretStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String name) => _storage.read(key: name);
  @override
  Future<void> write(String name, String value) =>
      _storage.write(key: name, value: value);
  @override
  Future<void> delete(String name) => _storage.delete(key: name);
}

class MemorySecrets implements SecretStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String name) async => _values[name];
  @override
  Future<void> write(String name, String value) async => _values[name] = value;
  @override
  Future<void> delete(String name) async => _values.remove(name);
}

/// Szyfruje treść, tytuły, szkice i notatki; metadane SQLite pozostają jawne.
class ContentCipher {
  ContentCipher(this.secrets);
  final SecretStore secrets;
  final _aes = AesGcm.with256bits();
  SecretKey? _key;
  Future<void> initialize({bool requireExisting = false}) async {
    var raw = await secrets.read('local_content_key_v1');
    if (raw == null) {
      if (requireExisting) {
        throw StateError(
            'Brak klucza istniejącej bazy. Przywróć zaszyfrowaną kopię.');
      }
      raw = base64Encode(
        List.generate(32, (_) => Random.secure().nextInt(256)),
      );
      await secrets.write('local_content_key_v1', raw);
    }
    final bytes = base64Decode(raw);
    if (bytes.length != 32) {
      throw StateError('Nieprawidłowy klucz lokalnej pamięci.');
    }
    _key = SecretKey(bytes);
  }

  Future<String> seal(String value) async {
    final box = await _aes.encrypt(utf8.encode(value), secretKey: _key!);
    return jsonEncode({
      'v': 1,
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    });
  }

  Future<String> open(String value) async {
    final data = jsonDecode(value) as Map<String, dynamic>;
    if (data['v'] != 1) {
      throw const FormatException('Nieobsługiwana wersja szyfrowania.');
    }
    final box = SecretBox(
      base64Decode(data['c'] as String),
      nonce: base64Decode(data['n'] as String),
      mac: Mac(base64Decode(data['m'] as String)),
    );
    return utf8.decode(await _aes.decrypt(box, secretKey: _key!));
  }

  /// Indeks słów nie zapisuje ich jawnie; domena oddziela MAC od szyfrowania.
  Future<String> indexToken(String value) async => base64UrlEncode(
        (await Hmac.sha256().calculateMac(
          utf8.encode('scalajaca.index.v1\u0000$value'),
          secretKey: _key!,
        ))
            .bytes,
      );
}
