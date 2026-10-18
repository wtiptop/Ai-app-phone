import 'package:sqflite/sqflite.dart';
import 'memory_store.dart';
import 'vault_bridge.dart';

class VaultImportProgress {
  const VaultImportProgress(
      this.processed, this.failed, this.status, this.cursor);
  final int processed, failed;
  final String status;
  final String? cursor;
}

/// Jedna strona katalogu i jeden plik w RAM; checkpoint po każdym pliku.
class VaultImporter {
  VaultImporter(this.memory, this.gateway);
  final MemoryStore memory;
  final VaultGateway gateway;
  bool _cancelled = false, _running = false;
  Future<void> cancel(MemoryCollection collection) async {
    _cancelled = true;
    if (collection.vaultId != null) await gateway.cancel(collection.vaultId!);
  }

  Future<VaultImportProgress?> progress(MemoryCollection collection) async {
    await memory.collection(collection.id, ownerId: collection.ownerId);
    final rows = await memory.store.db.query('memory_import_jobs',
        where: 'collection_id=?', whereArgs: [collection.id], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.single;
    return VaultImportProgress(
        r['processed'] as int,
        r['failed'] as int,
        r['status'] as String,
        r['cursor'] == null
            ? null
            : await memory.store.cipher.open(r['cursor'] as String));
  }

  Stream<VaultImportProgress> run(MemoryCollection collection,
      {bool restart = false, int maxFiles = 2000}) async* {
    if (_running) throw StateError('Import już trwa.');
    if (maxFiles < 1 || maxFiles > 10000 || collection.vaultId == null) {
      throw StateError('Połącz lokalny vault.');
    }
    await memory.collection(collection.id, ownerId: collection.ownerId);
    _running = true;
    _cancelled = false;
    String? cursor;
    var offset = 0, processed = 0, failed = 0, runCount = 0;
    Future<void> save(String status) async {
      await memory.store.db.insert(
          'memory_import_jobs',
          {
            'collection_id': collection.id,
            'cursor':
                cursor == null ? null : await memory.store.cipher.seal(cursor),
            'page_offset': offset,
            'processed': processed,
            'failed': failed,
            'status': status,
            'updated': DateTime.now().millisecondsSinceEpoch
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    try {
      final rows = await memory.store.db.query('memory_import_jobs',
          where: 'collection_id=?', whereArgs: [collection.id], limit: 1);
      if (!restart && rows.isNotEmpty) {
        final r = rows.single;
        if (r['status'] == 'completed') {
          yield VaultImportProgress(
              r['processed'] as int, r['failed'] as int, 'completed', null);
          return;
        }
        cursor = r['cursor'] == null
            ? null
            : await memory.store.cipher.open(r['cursor'] as String);
        offset = r['page_offset'] as int;
        processed = r['processed'] as int;
        failed = r['failed'] as int;
      }
      await save('running');
      var cursorReset = false;
      while (!_cancelled && runCount < maxFiles) {
        VaultListing page;
        try {
          page = await gateway.list(collection.vaultId!,
              cursor: cursor, limit: 100);
        } on VaultException catch (e) {
          if (e.code == 'invalid_cursor' && !cursorReset) {
            cursor = null;
            offset = 0;
            cursorReset = true;
            await save('running');
            continue;
          }
          rethrow;
        }
        for (var i = offset; i < page.items.length; i++) {
          if (_cancelled || runCount >= maxFiles) break;
          final file = page.items[i];
          try {
            if (file.bytes > MemoryStore.maxFileBytes) {
              failed++;
            } else {
              final content = await gateway.read(collection.vaultId!, file.id);
              if (_cancelled) break;
              await memory.ingest(collection.id, file.path, content,
                  ownerId: collection.ownerId);
              processed++;
            }
          } on VaultException catch (e) {
            if (e.code == 'cancelled') {
              _cancelled = true;
              break;
            }
            if (e.code == 'permission' || e.code == 'revoked') rethrow;
            failed++;
          } on ArgumentError {
            failed++;
          }
          offset = i + 1;
          runCount++;
          await save('running');
          yield VaultImportProgress(processed, failed, 'running', cursor);
        }
        if (_cancelled || runCount >= maxFiles) break;
        cursor = page.nextCursor;
        offset = 0;
        if (cursor == null) {
          await save('completed');
          yield VaultImportProgress(processed, failed, 'completed', null);
          return;
        }
        await save('running');
      }
      await save('paused');
      yield VaultImportProgress(processed, failed, 'paused', cursor);
    } catch (_) {
      await save('paused');
      rethrow;
    } finally {
      _running = false;
    }
  }
}
