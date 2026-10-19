import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/backup/backup_coordinator.dart';
import 'package:scalajaca/backup/backup_files.dart';
import 'package:scalajaca/backup/encrypted_archive.dart';
import 'package:scalajaca/security/encrypted_backup.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:scalajaca/storage/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Files implements BackupFilesGateway {
  final output = BytesBuilder();
  Uint8List? input;
  int offset = 0, closed = 0, saved = 0;
  bool failWrite = false;
  void Function()? duringSave;
  @override
  Future<String> create() async => 'stage';
  @override
  Future<void> write(String id, Uint8List bytes) async {
    expect(bytes.length, lessThanOrEqualTo(262144));
    if (failWrite) throw StateError('test IO');
    output.add(bytes);
  }

  @override
  Future<bool> save(String id, String filename) async {
    expect(filename, endsWith('.scalabackup'));
    saved++;
    duringSave?.call();
    return true;
  }

  @override
  Future<String?> open() async {
    offset = 0;
    return input == null ? null : 'read';
  }

  @override
  Future<Uint8List> read(String id, {int maxBytes = 65536}) async {
    final bytes = input!;
    final end = (offset + maxBytes).clamp(0, bytes.length);
    final result = Uint8List.sublistView(bytes, offset, end);
    offset = end;
    return result;
  }

  @override
  Future<void> close(String id) async {
    closed++;
  }
}

void main() {
  const pass = 'silne hasło testowe 2026';
  late AppDatabase source, target;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    source = await AppDatabase.open(ContentCipher(MemorySecrets()),
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    target = await AppDatabase.open(ContentCipher(MemorySecrets()),
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    await source.db.insert('notes', {
      'id': 'backup-note',
      'title': await source.cipher.seal('Dowód kopii'),
      'content': await source.cipher.seal('SECRET_BACKUP_TEST'),
      'folder': memoryFolders.first,
      'updated': 1
    });
  });
  tearDown(() async {
    await source.close();
    await target.close();
  });

  test(
      'Cały przepływ przez most plikowy zmienia szyfr urządzenia i zachowuje dane',
      () async {
    final files = Files();
    expect(await BackupCoordinator(source, files: files).create(pass), isTrue);
    expect(files.saved, 1);
    files.input = files.output.takeBytes();
    expect(String.fromCharCodes(files.input!),
        isNot(contains('SECRET_BACKUP_TEST')));
    var confirmed = false;
    expect(
        await BackupCoordinator(target, files: files).restore(pass,
            confirm: (m) async {
          confirmed = true;
          expect(m.counts['notes'], 1);
          return true;
        }),
        isTrue);
    expect(confirmed, isTrue);
    final restored = (await target.db.query('notes')).single;
    expect(await target.cipher.open(restored['content'] as String),
        'SECRET_BACKUP_TEST');
    expect(restored['content'],
        isNot((await source.db.query('notes')).single['content']));
    expect(files.closed, 2);
  });

  test('Odmowa podglądu manifestu nie zapisuje danych', () async {
    final files = Files();
    await BackupCoordinator(source, files: files).create(pass);
    files.input = files.output.takeBytes();
    expect(
        await BackupCoordinator(target, files: files)
            .restore(pass, confirm: (_) async => false),
        isFalse);
    expect(await target.db.query('notes'), isEmpty);
    expect(files.closed, 2);
  });

  test('Błąd ostatniego tagu po emisji danych wycofuje transakcję', () async {
    final files = Files();
    await BackupCoordinator(source, files: files).create(pass);
    files.input = files.output.takeBytes();
    files.input![files.input!.length - 1] ^= 1;
    await expectLater(
        BackupCoordinator(target, files: files)
            .restore(pass, confirm: (_) async => true),
        throwsA(isA<BackupException>()));
    expect(await target.db.query('notes'), isEmpty);
    expect(files.closed, 2);
  });

  test('Błąd zapisu usuwa staging i nie otwiera systemowego eksportu',
      () async {
    final files = Files()..failWrite = true;
    await expectLater(
        BackupCoordinator(source, files: files).create(pass), throwsStateError);
    expect(files.saved, 0);
    expect(files.closed, 1);
  });

  test('Anulowanie po manifeście nie zapisuje danych', () async {
    final files = Files();
    await BackupCoordinator(source, files: files).create(pass);
    files.input = files.output.takeBytes();
    final coordinator = BackupCoordinator(target, files: files);
    await expectLater(
        coordinator.restore(pass, confirm: (_) async {
          coordinator.cancel();
          return true;
        }),
        throwsA(isA<BackupCancelled>()));
    expect(await target.db.query('notes'), isEmpty);
  });

  test(
      'Anulowanie podczas końcowego zapisu zamyka uchwyt i nie zgłasza sukcesu',
      () async {
    final files = Files();
    final coordinator = BackupCoordinator(source, files: files);
    files.duringSave = coordinator.cancel;
    await expectLater(
        coordinator.create(pass), throwsA(isA<BackupCancelled>()));
    expect(files.closed, greaterThanOrEqualTo(1));
  });
}
