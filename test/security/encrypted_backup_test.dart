import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/security/encrypted_backup.dart';

void main() {
  test('Szyfrowana kopia: roundtrip, inne nonce, sabotaż, złe hasło', () async {
    final backup = EncryptedBackup();
    const passphrase = 'Długa tajna fraza 2026!';
    final plaintext = utf8.encode('Prywatna pamięć: zażółć gęślą jaźń.');
    final envelope = await backup.encrypt(plaintext, passphrase);
    expect(envelope.contains('Prywatna'), isFalse);
    expect(await backup.decrypt(envelope, passphrase), plaintext);
    final second = jsonDecode(
      await backup.encrypt(plaintext, passphrase),
    ) as Map<String, dynamic>;
    final first = jsonDecode(envelope) as Map<String, dynamic>;
    expect(second['salt'], isNot(first['salt']));
    expect(second['nonce'], isNot(first['nonce']));
    final ciphertext = base64Decode(first['ciphertext'] as String);
    ciphertext[0] ^= 1;
    first['ciphertext'] = base64Encode(ciphertext);
    await expectLater(
      backup.decrypt(jsonEncode(first), passphrase),
      throwsA(isA<BackupException>()),
    );
    await expectLater(
      backup.decrypt(envelope, 'Inna długa tajna fraza'),
      throwsA(isA<BackupException>()),
    );
  }, timeout: const Timeout(Duration(minutes: 4)));

  test(
    'Odrzuca krótkie hasło, zmienione parametry KDF i nieznaną wersję',
    () async {
      final backup = EncryptedBackup();
      await expectLater(
        backup.encrypt([1, 2, 3], 'krótkie'),
        throwsA(isA<BackupException>()),
      );
      await expectLater(
        backup.decrypt('{"version":99}', 'Dostatecznie długie hasło'),
        throwsA(isA<BackupException>()),
      );
    },
  );
}
