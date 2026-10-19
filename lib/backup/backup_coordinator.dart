import 'dart:async';
import 'dart:typed_data';

import '../storage/app_database.dart';
import 'backup_dataset.dart';
import 'backup_files.dart';
import 'encrypted_archive.dart';

/// Jedna operacja; plaintext trafia wyłącznie do transakcji i szyfratora w RAM.
class BackupCoordinator {
  BackupCoordinator(AppDatabase store, {BackupFilesGateway? files})
      : dataset = BackupDataset(store),
        files = files ?? BackupFilesBridge();
  final BackupDataset dataset;
  final BackupFilesGateway files;
  bool _busy = false, _cancelled = false;
  String? _active;
  void cancel() {
    _cancelled = true;
    unawaited(_close(_active));
  }

  bool get cancelled => _cancelled;

  Future<void> _close(String? id) async {
    if (id == null) return;
    try {
      await files.close(id);
    } catch (_) {/* pierwotny wynik jest ważniejszy */}
  }

  Future<bool> create(String passphrase,
      {void Function(int records, int total)? onProgress}) async {
    if (_busy) throw StateError('Operacja kopii już trwa.');
    _busy = true;
    _cancelled = false;
    String? id;
    try {
      EncryptedArchive.validatePassphrase(passphrase);
      id = await files.create();
      _active = id;
      final handle = id;
      await dataset.exportSnapshot((counts, rows) => EncryptedArchive().write(
          rows, counts, passphrase, (bytes) => files.write(handle, bytes),
          isCancelled: () => _cancelled, onProgress: onProgress));
      EncryptedArchive.checkCancelled(() => _cancelled);
      final date =
          DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
      final saved = await files.save(handle, 'scalajaca-$date.scalabackup');
      EncryptedArchive.checkCancelled(() => _cancelled);
      return saved;
    } finally {
      await _close(id);
      _active = null;
      _busy = false;
    }
  }

  Future<bool> restore(String passphrase,
      {required Future<bool> Function(ArchiveManifest manifest) confirm,
      void Function(int records, int total)? onProgress}) async {
    if (_busy) throw StateError('Operacja kopii już trwa.');
    _busy = true;
    _cancelled = false;
    String? id;
    ArchiveReader? reader;
    try {
      EncryptedArchive.validatePassphrase(passphrase);
      id = await files.open();
      _active = id;
      if (id == null) return false;
      final handle = id;
      Stream<Uint8List> input() async* {
        while (true) {
          EncryptedArchive.checkCancelled(() => _cancelled);
          final bytes = await files.read(handle);
          if (bytes.isEmpty) return;
          yield bytes;
        }
      }

      reader = await EncryptedArchive().open(input(), passphrase,
          isCancelled: () => _cancelled, onProgress: onProgress);
      if (!await confirm(reader.manifest)) return false;
      EncryptedArchive.checkCancelled(() => _cancelled);
      // records() kończy się dopiero po poprawnej stopce i EOF. Błąd wycofuje tx.
      await dataset.restore(reader.records(), reader.manifest.counts,
          isCancelled: () => _cancelled);
      return true;
    } finally {
      try {
        await reader?.close();
      } finally {
        await _close(id);
        _active = null;
        _busy = false;
      }
    }
  }
}
