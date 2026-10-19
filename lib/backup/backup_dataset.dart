import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../memory/memory_store.dart';
import '../storage/app_database.dart';
import '../storage/models.dart';

/// Logiczny strumień wyłącznie wewnątrz szyfrowanego kontenera backupu.
/// Nie wolno zapisywać plaintextu tego API do pliku ani logu.
class BackupDataset {
  BackupDataset(this.store);
  final AppDatabase store;

  static const tables = <String>[
    'memory_collections',
    'memory_documents',
    'memory_versions',
    'memory_chunks',
    'analysis_checkpoints',
    'memory_import_jobs',
    'rpg_campaigns',
    'rpg_versions',
    'rpg_records',
    'rpg_events',
    'conversations',
    'messages',
    'chat_scopes',
    'chat_context_receipts',
    'notes',
    'tasks',
  ];
  static const maxRows = 2000000, maxRowBytes = 32 * 1024 * 1024;
  static const _members = 'scalajaca_backup_members';
  static const _protected = <String, List<String>>{
    'memory_collections': ['name'],
    'memory_documents': ['path'],
    'memory_versions': ['path'],
    'memory_chunks': ['body'],
    'analysis_checkpoints': ['goal', 'findings', 'next_step', 'sources'],
    'rpg_campaigns': ['name'],
    'rpg_versions': ['payload'],
    'rpg_records': ['payload'],
    'rpg_events': ['payload'],
    'conversations': ['title', 'draft'],
    'messages': ['content'],
    'chat_context_receipts': ['evidence'],
    'notes': ['title', 'content'],
    'tasks': ['title'],
  };
  // i = integer, s = string, ? = nullable. Pełna lista odrzuca ukryte kolumny.
  static const _columns = <String, Map<String, String>>{
    'memory_collections': {
      'id': 's',
      'owner_id': 's',
      'name': 's',
      'vault_id': 's?',
      'created': 'i'
    },
    'memory_documents': {
      'id': 's',
      'collection_id': 's',
      'source_key': 's',
      'path': 's',
      'hash': 's',
      'revision': 'i',
      'approval': 's',
      'restricted': 'i',
      'bytes': 'i',
      'updated': 'i'
    },
    'memory_versions': {
      'document_id': 's',
      'revision': 'i',
      'hash': 's',
      'path': 's',
      'restricted': 'i',
      'bytes': 'i',
      'created': 'i'
    },
    'memory_chunks': {
      'id': 's',
      'document_id': 's',
      'revision': 'i',
      'ordinal': 'i',
      'start_line': 'i',
      'end_line': 'i',
      'body': 's'
    },
    'analysis_checkpoints': {
      'id': 's',
      'collection_id': 's',
      'revision': 'i',
      'goal': 's',
      'findings': 's',
      'next_step': 's',
      'sources': 's',
      'updated': 'i'
    },
    'memory_import_jobs': {
      'collection_id': 's',
      'cursor': 's?',
      'page_offset': 'i',
      'processed': 'i',
      'failed': 'i',
      'status': 's',
      'updated': 'i'
    },
    'rpg_campaigns': {
      'id': 's',
      'owner_id': 's',
      'edition': 's',
      'name': 's',
      'revision': 'i',
      'created': 'i',
      'updated': 'i'
    },
    'rpg_versions': {
      'campaign_id': 's',
      'record_id': 's',
      'revision': 'i',
      'kind': 's',
      'visibility': 's',
      'approved': 'i',
      'authority': 'i',
      'edition': 's',
      'payload': 's'
    },
    'rpg_records': {
      'campaign_id': 's',
      'record_id': 's',
      'revision': 'i',
      'kind': 's',
      'visibility': 's',
      'approved': 'i',
      'authority': 'i',
      'edition': 's',
      'payload': 's'
    },
    'rpg_events': {
      'campaign_id': 's',
      'revision': 'i',
      'kind': 's',
      'created': 'i',
      'payload': 's'
    },
    'conversations': {
      'id': 's',
      'title': 's',
      'draft': 's',
      'updated': 'i',
      'pinned': 'i'
    },
    'messages': {
      'id': 's',
      'conversation_id': 's',
      'role': 's',
      'content': 's',
      'provider': 's',
      'model': 's',
      'status': 's',
      'created': 'i',
      'input_tokens': 'i?',
      'output_tokens': 'i?'
    },
    'chat_scopes': {
      'conversation_id': 's',
      'scope_key': 's',
      'confidential': 'i'
    },
    'chat_context_receipts': {
      'message_id': 's',
      'digest': 's',
      'evidence': 's',
      'omitted': 'i',
      'created': 'i'
    },
    'notes': {
      'id': 's',
      'title': 's',
      'content': 's',
      'folder': 's',
      'updated': 'i'
    },
    'tasks': {'id': 's', 'title': 's', 'done': 'i', 'created': 'i'},
  };

  Map<String, int> _counts(Map<String, int> counts) {
    if (counts.length != tables.length ||
        tables.any((t) => !counts.containsKey(t)) ||
        counts.values.any((v) => v < 0 || v > maxRows) ||
        counts.values.fold<int>(0, (sum, v) => sum + v) > maxRows) {
      throw const FormatException(
          'Nieprawidłowy spis tabel lub limit liczby wierszy.');
    }
    return Map.unmodifiable(counts);
  }

  /// Czytelnik musi zużyć cały stream przed powrotem. Jedna transakcja snapshotu
  /// obejmuje manifest, wszystkie strony i czas zapisu kontenera.
  Future<T> exportSnapshot<T>(
          Future<T> Function(
                  Map<String, int> counts, Stream<Map<String, Object?>> rows)
              consume) =>
      store.db.transaction((tx) async {
        for (final table in ['memory_collections', 'rpg_campaigns']) {
          if ((await tx.query(table,
                  columns: ['id'],
                  where: 'owner_id != ?',
                  whereArgs: ['local-owner'],
                  limit: 1))
              .isNotEmpty) {
            throw StateError('Kopia zawiera dane obcego właściciela.');
          }
        }
        final counts = <String, int>{};
        for (final table in tables) {
          counts[table] = Sqflite.firstIntValue(
              await tx.rawQuery('SELECT COUNT(*) FROM $table'))!;
        }
        final manifest = _counts(counts);
        var completed = false;
        Stream<Map<String, Object?>> records() async* {
          for (final table in tables) {
            var actual = 0;
            await for (final row in _pages(tx, table)) {
              final logical = Map<String, Object?>.from(row);
              for (final column in _protected[table] ?? const <String>[]) {
                logical[column] =
                    await store.cipher.open(logical[column] as String);
              }
              _sanitize(table, logical);
              _validateRow(table, logical);
              actual++;
              yield {'table': table, 'row': logical};
            }
            if (actual != manifest[table]) {
              throw StateError('Snapshot zmienił liczbę wierszy.');
            }
          }
          completed = true;
        }

        final result = await consume(manifest, records());
        if (!completed) {
          throw StateError('Eksport nie odczytał całego snapshotu.');
        }
        return result;
      });

  Stream<Map<String, Object?>> _pages(DatabaseExecutor tx, String table,
      {String? where, List<Object?> args = const []}) async* {
    int? after;
    // Treści tych tabel mogą zajmować cały limit 32 MiB. Nie pobieramy 50
    // dużych szyfrogramów naraz (base64 zwiększa ich rozmiar jeszcze bardziej).
    final pageSize = const {
      'conversations',
      'messages',
      'notes',
      'chat_context_receipts',
      'tasks'
    }.contains(table)
        ? 1
        : 50;
    while (true) {
      final conditions = [
        if (where != null) '($where)',
        if (after != null) 'rowid > ?'
      ];
      final rows = await tx.rawQuery(
          'SELECT rowid AS __backup_rowid, * FROM $table'
          '${conditions.isEmpty ? '' : ' WHERE ${conditions.join(' AND ')}'} ORDER BY rowid LIMIT $pageSize',
          [...args, if (after != null) after]);
      if (rows.isEmpty) return;
      for (final row in rows) {
        after = row['__backup_rowid'] as int;
        final data = Map<String, Object?>.from(row)..remove('__backup_rowid');
        yield data;
      }
    }
  }

  void _sanitize(String table, Map<String, Object?> row) {
    if (table == 'memory_collections') row['vault_id'] = null;
    if (table == 'memory_import_jobs') {
      row['cursor'] = null;
      row['page_offset'] = 0;
      row['status'] = 'paused';
    }
  }

  /// Stream musi zakończyć się dopiero po uwierzytelnieniu footera i EOF.
  /// Każdy błąd, anulowanie, kolizja lub błąd walidacji cofa całą transakcję.
  Future<void> restore(
      Stream<Map<String, Object?>> rows, Map<String, int> counts,
      {bool Function()? isCancelled}) async {
    final manifest = _counts(counts);
    void checkCancel() {
      if (isCancelled?.call() ?? false) {
        throw StateError('Przywracanie anulowano.');
      }
    }

    checkCancel();
    await store.db.transaction((tx) async {
      await tx.execute(
          'CREATE TEMP TABLE $_members(t TEXT NOT NULL,k1 TEXT NOT NULL,'
          "k2 TEXT NOT NULL DEFAULT '',revision INTEGER NOT NULL DEFAULT 0,"
          'PRIMARY KEY(t,k1,k2,revision)) WITHOUT ROWID');
      try {
        final seen = {for (final table in tables) table: 0};
        var lastTable = -1, total = 0;
        await for (final envelope in rows) {
          checkCancel();
          if (envelope.length != 2 ||
              envelope['table'] is! String ||
              envelope['row'] is! Map) {
            throw const FormatException('Nieprawidłowy wiersz kontenera.');
          }
          final table = envelope['table'] as String;
          final index = tables.indexOf(table);
          if (index < lastTable ||
              index < 0 ||
              ++total > maxRows ||
              seen[table]! >= manifest[table]!) {
            throw const FormatException(
                'Kolejność, liczba lub nazwa tabeli jest nieprawidłowa.');
          }
          lastTable = index;
          final raw = envelope['row'] as Map;
          if (raw.keys.any((key) => key is! String)) {
            throw const FormatException('Nieprawidłowa kolumna.');
          }
          final logical = Map<String, Object?>.from(raw);
          _validateRow(table, logical);
          _sanitize(table, logical);
          await _parents(tx, table, logical);
          final encoded = Map<String, Object?>.from(logical);
          if (table == 'memory_documents') {
            encoded['source_key'] =
                await store.cipher.indexToken('path:${logical['path']}');
          }
          if (table == 'messages' &&
              ['streaming', 'pending'].contains(logical['status'])) {
            encoded['status'] = 'interrupted';
          }
          for (final column in _protected[table] ?? const <String>[]) {
            encoded[column] =
                await store.cipher.seal(logical[column] as String);
          }
          // Żadnych IGNORE, REPLACE, remapowania ID ani łączenia z istniejącą rodziną.
          checkCancel();
          await tx.insert(table, encoded);
          checkCancel();
          await _addMember(tx, table, logical);
          seen[table] = seen[table]! + 1;
        }
        checkCancel();
        if (tables.any((table) => seen[table] != manifest[table])) {
          throw const FormatException(
              'Strumień nie zawiera zadeklarowanych wierszy.');
        }
        await _validateRelations(tx, checkCancel);
        await _rebuildIndexes(tx, checkCancel);
        checkCancel();
      } finally {
        await tx.execute('DROP TABLE $_members');
      }
    });
  }

  void _validateRow(String table, Map<String, Object?> row) {
    final schema = _columns[table];
    if (schema == null ||
        row.length != schema.length ||
        schema.keys.any((key) => !row.containsKey(key))) {
      throw const FormatException('Nieznane lub brakujące kolumny.');
    }
    for (final entry in schema.entries) {
      final value = row[entry.key], type = entry.value;
      if (value == null && type.endsWith('?')) continue;
      if ((type.startsWith('s') && value is! String) ||
          (type.startsWith('i') &&
              (value is! int || value < 0 || value > 9007199254740991))) {
        throw const FormatException('Nieprawidłowy typ lub zakres kolumny.');
      }
      if ((entry.key == 'id' ||
              entry.key.endsWith('_id') ||
              entry.key == 'record_id') &&
          value != null &&
          (value is! String ||
              value.isEmpty ||
              value.length > 1024 ||
              RegExp(r'[\x00-\x1f]').hasMatch(value))) {
        throw const FormatException('Nieprawidłowy identyfikator.');
      }
    }
    if (utf8.encode(jsonEncode({'table': table, 'row': row})).length >
        maxRowBytes) {
      throw const FormatException('Wiersz przekracza 32 MiB.');
    }
    for (final flag in [
      'restricted',
      'approved',
      'confidential',
      'pinned',
      'done'
    ]) {
      if (row.containsKey(flag) && row[flag] != 0 && row[flag] != 1) {
        throw const FormatException('Nieprawidłowa flaga.');
      }
    }
    if (row.containsKey('owner_id') && row['owner_id'] != 'local-owner') {
      throw const FormatException(
          'Nie można przywrócić danych obcego właściciela.');
    }
    if (table == 'memory_collections' &&
        ((row['name'] as String).trim().isEmpty ||
            (row['name'] as String).length > 160)) {
      throw const FormatException('Nieprawidłowa nazwa projektu.');
    }
    if (table == 'memory_documents' || table == 'memory_versions') {
      _path(row['path'] as String);
      _digest(row['hash']);
      if ((row['revision'] as int) < 1 ||
          (row['bytes'] as int) > MemoryStore.maxFileBytes) {
        throw const FormatException(
            'Nieprawidłowa wersja lub rozmiar dokumentu.');
      }
      if (MemoryStore(store).restrictedSource(row['path'] as String, '') &&
          row['restricted'] != 1) {
        throw const FormatException(
            'Ścieżka sekretu nie może utracić ograniczenia.');
      }
      if (table == 'memory_documents' &&
          !['pending', 'approved', 'rejected'].contains(row['approval'])) {
        throw const FormatException('Nieprawidłowy stan zatwierdzenia.');
      }
    }
    if (table == 'memory_chunks' &&
        ((row['revision'] as int) < 1 ||
            (row['ordinal'] as int) > 4095 ||
            (row['start_line'] as int) < 1 ||
            (row['end_line'] as int) < (row['start_line'] as int) ||
            (row['body'] as String).isEmpty ||
            (row['body'] as String).length > 901)) {
      throw const FormatException('Nieprawidłowy fragment dokumentu.');
    }
    if (table == 'memory_chunks') {
      final body = row['body'] as String;
      final last = (row['start_line'] as int) +
          '\n'.allMatches(body).length -
          (body.endsWith('\n') ? 1 : 0);
      if (last != row['end_line']) {
        throw const FormatException(
            'Zakres linii nie odpowiada treści fragmentu.');
      }
    }
    if (table == 'analysis_checkpoints') {
      if ((row['revision'] as int) < 1 ||
          (row['goal'] as String).trim().isEmpty ||
          ['goal', 'findings', 'next_step', 'sources']
              .any((key) => utf8.encode(row[key] as String).length > 32000)) {
        throw const FormatException('Nieprawidłowy checkpoint analizy.');
      }
    }
    if (table == 'memory_import_jobs' &&
        !['running', 'paused', 'completed'].contains(row['status'])) {
      throw const FormatException('Nieprawidłowy stan importu.');
    }
    if (table == 'rpg_campaigns' &&
        ((row['name'] as String).trim().isEmpty ||
            (row['name'] as String).length > 200 ||
            (row['edition'] as String).trim().isEmpty ||
            (row['edition'] as String).length > 100)) {
      throw const FormatException('Nieprawidłowa kampania.');
    }
    if (table == 'rpg_records' || table == 'rpg_versions') _rpgRecord(row);
    if (table == 'rpg_events') _rpgEvent(row);
    if (table == 'messages' &&
        (!['user', 'assistant'].contains(row['role']) ||
            ![
              'complete',
              'streaming',
              'pending',
              'cancelled',
              'interrupted',
              'error'
            ].contains(row['status']) ||
            (row['provider'] as String).length > 200 ||
            (row['model'] as String).length > 500)) {
      throw const FormatException('Nieprawidłowa rola lub stan wiadomości.');
    }
    if (table == 'chat_scopes') {
      _scope(row['scope_key'] as String, row['confidential'] as int);
    }
    if (table == 'chat_context_receipts') {
      _digest(row['digest']);
      final receipt = _jsonObject(row['evidence'] as String, [
        'format',
        'digest',
        'omittedMessages',
        'attachment',
        'sourceSnapshot'
      ]);
      if (receipt['format'] != 'scalajaca.context-receipt.v1' ||
          receipt['digest'] != row['digest'] ||
          receipt['omittedMessages'] is! int ||
          receipt['omittedMessages'] != row['omitted'] ||
          (receipt['sourceSnapshot'] != null &&
              receipt['sourceSnapshot'] is! String) ||
          (receipt['attachment'] != null && receipt['attachment'] is! Map)) {
        throw const FormatException('Nieprawidłowy dowód kontekstu.');
      }
    }
    if (table == 'notes' && !memoryFolders.contains(row['folder'])) {
      throw const FormatException('Nieprawidłowy katalog notatki.');
    }
  }

  void _path(String path) {
    if (path.isEmpty ||
        path.length > 1024 ||
        path.startsWith('/') ||
        path.contains('\\') ||
        RegExp(r'[\x00-\x1f:]').hasMatch(path) ||
        path.split('/').any((part) =>
            part.isEmpty ||
            part == '.' ||
            part == '..' ||
            part.startsWith('.')) ||
        !(path.toLowerCase().endsWith('.md') ||
            path.toLowerCase().endsWith('.markdown'))) {
      throw const FormatException('Nieprawidłowa ścieżka źródła Markdown.');
    }
  }

  void _digest(Object? value) {
    try {
      if (value is! String || base64Url.decode(value).length != 32) {
        throw const FormatException();
      }
    } on FormatException {
      throw const FormatException('Nieprawidłowy SHA-256.');
    }
  }

  Map<String, dynamic> _jsonObject(String text, List<String> keys) {
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic> ||
        value.length != keys.length ||
        keys.any((key) => !value.containsKey(key))) {
      throw const FormatException(
          'Nieprawidłowa struktura danych chronionych.');
    }
    return value;
  }

  void _rpgRecord(Map<String, Object?> row) {
    if ((row['revision'] as int) < 1 ||
        !['canon', 'worldEntity', 'playerKnowledge', 'sessionCheckpoint']
            .contains(row['kind']) ||
        !['campaign', 'gmSecret'].contains(row['visibility']) ||
        (row['authority'] as int) > 2 ||
        (row['edition'] as String).length > 100 ||
        (row['record_id'] as String).length > 200 ||
        (row['kind'] == 'playerKnowledge' && row['visibility'] != 'campaign') ||
        ((row['record_id'] == 'active-session' ||
                row['kind'] == 'sessionCheckpoint') &&
            (row['record_id'] != 'active-session' ||
                row['kind'] != 'sessionCheckpoint' ||
                row['visibility'] != 'gmSecret' ||
                row['approved'] != 1 ||
                row['authority'] != 0))) {
      throw const FormatException('Nieprawidłowy zakres wpisu RPG.');
    }
    final payload =
        _jsonObject(row['payload'] as String, ['title', 'content', 'citation']);
    if (payload['title'] is! String ||
        (payload['title'] as String).trim().isEmpty ||
        (payload['title'] as String).length > 300 ||
        payload['content'] is! String ||
        (payload['content'] as String).trim().isEmpty ||
        (payload['content'] as String).length > 100000 ||
        payload['citation'] is! Map<String, dynamic>) {
      throw const FormatException('Nieprawidłowa treść RPG.');
    }
    final citation = payload['citation'] as Map<String, dynamic>;
    if (citation.length != 4 ||
        !['sourceId', 'title', 'page', 'userVerified']
            .every(citation.containsKey) ||
        citation['sourceId'] is! String ||
        (citation['sourceId'] as String).length > 1000 ||
        citation['title'] is! String ||
        (citation['title'] as String).length > 1000 ||
        (citation['page'] != null &&
            (citation['page'] is! String ||
                (citation['page'] as String).length > 500)) ||
        citation['userVerified'] is! bool) {
      throw const FormatException('Nieprawidłowe źródło lore.');
    }
    // Starsze wersje aplikacji mogły zapisać checkbox=true bez kompletnej
    // cytacji. Zachowujemy historyczny payload; LoreCitation.verification
    // nadal oznacza taki wpis jako niezweryfikowany, bez nadawania autorytetu.
    if (row['record_id'] == 'active-session') {
      final checkpoint = _jsonObject(payload['content'] as String,
          ['goal', 'scene', 'openThreads', 'party', 'worldClock']);
      if (checkpoint.values.any((v) => v is! String)) {
        throw const FormatException('Nieprawidłowy checkpoint sesji.');
      }
    }
  }

  void _rpgEvent(Map<String, Object?> row) {
    if ((row['revision'] as int) < 1 ||
        !['recordApproved', 'recordSaved', 'checkpointSaved', 'rollback']
            .contains(row['kind'])) {
      throw const FormatException('Nieprawidłowe zdarzenie RPG.');
    }
    if (row['kind'] == 'rollback') {
      final payload = _jsonObject(row['payload'] as String, ['targetRevision']);
      if (payload['targetRevision'] is! int ||
          (payload['targetRevision'] as int) < 0 ||
          (payload['targetRevision'] as int) >= (row['revision'] as int)) {
        throw const FormatException('Nieprawidłowy cel cofnięcia.');
      }
    } else {
      final payload = _jsonObject(row['payload'] as String, ['recordId']);
      if (payload['recordId'] is! String ||
          (payload['recordId'] as String).isEmpty ||
          (payload['recordId'] as String).length > 200 ||
          (row['kind'] == 'checkpointSaved' &&
              payload['recordId'] != 'active-session')) {
        throw const FormatException('Nieprawidłowe powiązanie zdarzenia.');
      }
    }
  }

  (String, String) _scope(String key, int confidential) {
    if (key.startsWith('project:')) {
      final id = key.substring(8);
      if (id.isNotEmpty && id.length <= 1024 && confidential == 0) {
        return ('project', id);
      }
    } else if (key.startsWith('rpg:')) {
      final end = key.lastIndexOf(':');
      if (end > 4) {
        final id = key.substring(4, end), role = key.substring(end + 1);
        if (id.length <= 1024 &&
            ((role == 'gameMaster' && confidential == 1) ||
                (role == 'rpgPlayer' && confidential == 0))) {
          return (role, id);
        }
      }
    }
    throw const FormatException('Nieprawidłowy lub obniżony zakres rozmowy.');
  }

  Future<void> _addMember(
      Transaction tx, String table, Map<String, Object?> row) async {
    final (k1, k2, revision) = _key(table, row);
    await tx.insert(
        _members, {'t': table, 'k1': k1, 'k2': k2, 'revision': revision});
  }

  (String, String, int) _key(String table, Map<String, Object?> row) {
    if (table == 'memory_versions') {
      return (row['document_id'] as String, '', row['revision'] as int);
    }
    if (table == 'rpg_versions' || table == 'rpg_records') {
      return (
        row['campaign_id'] as String,
        row['record_id'] as String,
        table == 'rpg_versions' ? row['revision'] as int : 0
      );
    }
    if (table == 'rpg_events') {
      return (row['campaign_id'] as String, '', row['revision'] as int);
    }
    final key = table == 'memory_import_jobs'
        ? 'collection_id'
        : table == 'chat_scopes'
            ? 'conversation_id'
            : table == 'chat_context_receipts'
                ? 'message_id'
                : 'id';
    return (row[key] as String, '', 0);
  }

  Future<void> _member(Transaction tx, String table, String k1,
      {String k2 = '', int revision = 0}) async {
    if ((await tx.query(_members,
            columns: ['k1'],
            where: 't=? AND k1=? AND k2=? AND revision=?',
            whereArgs: [table, k1, k2, revision],
            limit: 1))
        .isEmpty) {
      throw const FormatException('Rodzic rekordu nie należy do tej kopii.');
    }
  }

  Future<void> _parents(
      Transaction tx, String table, Map<String, Object?> row) async {
    if (['memory_documents', 'analysis_checkpoints', 'memory_import_jobs']
        .contains(table)) {
      await _member(tx, 'memory_collections', row['collection_id'] as String);
    }
    if (table == 'memory_versions' || table == 'memory_chunks') {
      await _member(tx, 'memory_documents', row['document_id'] as String);
      if (table == 'memory_chunks') {
        await _member(tx, 'memory_versions', row['document_id'] as String,
            revision: row['revision'] as int);
      }
    }
    if (table.startsWith('rpg_') && table != 'rpg_campaigns') {
      await _member(tx, 'rpg_campaigns', row['campaign_id'] as String);
      final campaign = (await tx.query('rpg_campaigns',
              where: 'id=?', whereArgs: [row['campaign_id']], limit: 1))
          .single;
      if ((row['revision'] as int) > (campaign['revision'] as int) ||
          ((table == 'rpg_records' || table == 'rpg_versions') &&
              row['authority'] == 1 &&
              row['edition'] != campaign['edition'])) {
        throw const FormatException(
            'Rewizja lub edycja nie odpowiada kampanii.');
      }
      if (table == 'rpg_records') {
        await _member(tx, 'rpg_versions', row['campaign_id'] as String,
            k2: row['record_id'] as String, revision: row['revision'] as int);
      }
    }
    if (table == 'messages' || table == 'chat_scopes') {
      await _member(tx, 'conversations', row['conversation_id'] as String);
    }
    if (table == 'chat_scopes') {
      final (kind, id) =
          _scope(row['scope_key'] as String, row['confidential'] as int);
      await _member(
          tx, kind == 'project' ? 'memory_collections' : 'rpg_campaigns', id);
    }
    if (table == 'chat_context_receipts') {
      await _member(tx, 'messages', row['message_id'] as String);
      await _receipt(tx, row);
    }
  }

  Future<void> _receipt(Transaction tx, Map<String, Object?> row) async {
    final message = (await tx.query('messages',
            where: 'id=?', whereArgs: [row['message_id']], limit: 1))
        .single;
    if (message['role'] != 'assistant') {
      throw const FormatException('Dowód musi dotyczyć odpowiedzi asystenta.');
    }
    final scopes = await tx.query('chat_scopes',
        where: 'conversation_id=?',
        whereArgs: [message['conversation_id']],
        limit: 1);
    final receipt = _jsonObject(row['evidence'] as String, [
      'format',
      'digest',
      'omittedMessages',
      'attachment',
      'sourceSnapshot'
    ]);
    final attachment = receipt['attachment'];
    if (attachment == null) {
      if (receipt['sourceSnapshot'] != null) {
        throw const FormatException('Snapshot bez określonego zakresu źródeł.');
      }
      return;
    }
    if (attachment is! Map<String, dynamic> ||
        receipt['sourceSnapshot'] is! String ||
        scopes.isEmpty) {
      throw const FormatException('Dowód źródeł wymaga zakresu rozmowy.');
    }
    await _member(tx, 'chat_scopes', message['conversation_id'] as String);
    final scope = scopes.single;
    final (kind, id) =
        _scope(scope['scope_key'] as String, scope['confidential'] as int);
    if (attachment.containsKey('campaignId')) {
      if (attachment.length != 5 ||
          !['campaignId', 'role', 'revision', 'records', 'fingerprint']
              .every(attachment.containsKey) ||
          attachment['campaignId'] != id ||
          attachment['role'] != kind ||
          !['gameMaster', 'rpgPlayer'].contains(attachment['role']) ||
          attachment['revision'] is! int ||
          (attachment['revision'] as int) < 0 ||
          attachment['records'] is! List ||
          (attachment['records'] as List).length > 100 ||
          (attachment['records'] as List)
              .any((v) => v is! String || v.isEmpty || v.length > 200)) {
        throw const FormatException(
            'Dowód RPG ma niezgodną kampanię lub rolę.');
      }
      _digest(attachment['fingerprint']);
      final campaign = (await tx.query('rpg_campaigns',
              where: 'id=?', whereArgs: [id], limit: 1))
          .single;
      if ((attachment['revision'] as int) > (campaign['revision'] as int)) {
        throw const FormatException('Dowód wskazuje przyszłą rewizję.');
      }
    } else {
      if (kind != 'project' ||
          attachment.length != 2 ||
          attachment['collectionId'] != id ||
          attachment['sources'] is! List) {
        throw const FormatException('Dowód projektu ma niezgodny zakres.');
      }
      if ((attachment['sources'] as List).length > 20) {
        throw const FormatException('Za dużo historycznych cytatów.');
      }
      for (final source in attachment['sources'] as List) {
        if (source is! Map<String, dynamic> ||
            source.length != 7 ||
            !['document', 'chunk', 'version', 'sha256', 'path', 'lines', 'text']
                .every(source.containsKey)) {
          throw const FormatException('Nieprawidłowy historyczny cytat.');
        }
        if (source['document'] is! String ||
            (source['document'] as String).isEmpty ||
            source['chunk'] is! String ||
            (source['chunk'] as String).isEmpty ||
            source['version'] is! int ||
            (source['version'] as int) < 1 ||
            source['path'] is! String ||
            source['text'] is! String ||
            source['lines'] is! List ||
            (source['lines'] as List).length != 2 ||
            (source['lines'] as List).any((v) => v is! int || v < 1) ||
            (source['lines'] as List)[1] < (source['lines'] as List)[0]) {
          throw const FormatException(
              'Nieprawidłowy historyczny zakres cytowania.');
        }
        _path(source['path'] as String);
        _digest(source['sha256']);
      }
      // Historyczne źródła mogą zostać usunięte: nie sprawdzamy ich istnienia.
    }
  }

  Future<void> _validateRelations(
      Transaction tx, void Function() checkCancel) async {
    final invalidDoc = await tx.rawQuery('''SELECT d.id FROM memory_documents d
      JOIN $_members m ON m.t='memory_documents' AND m.k1=d.id
      LEFT JOIN memory_versions v ON v.document_id=d.id AND v.revision=d.revision
      WHERE v.document_id IS NULL OR d.hash!=v.hash OR d.restricted!=v.restricted
      OR d.bytes!=v.bytes LIMIT 1''');
    if (invalidDoc.isNotEmpty) {
      throw const FormatException(
          'Bieżący dokument nie odpowiada zapisanej wersji.');
    }
    await for (final doc in _importedPages(tx, 'memory_documents')) {
      checkCancel();
      final version = (await tx.query('memory_versions',
              where: 'document_id=? AND revision=?',
              whereArgs: [doc['id'], doc['revision']],
              limit: 1))
          .single;
      if (await store.cipher.open(doc['path'] as String) !=
          await store.cipher.open(version['path'] as String)) {
        throw const FormatException(
            'Ścieżka bieżącego dokumentu nie odpowiada wersji.');
      }
      final stats = (await tx.rawQuery(
              'SELECT MIN(revision) AS lo,MAX(revision) AS hi,COUNT(*) AS n '
              'FROM memory_versions WHERE document_id=?',
              [doc['id']]))
          .single;
      if (stats['lo'] != 1 ||
          stats['hi'] != doc['revision'] ||
          stats['n'] != doc['revision']) {
        throw const FormatException('Nieciągła historia wersji dokumentu.');
      }
    }
    await for (final version in _importedPages(tx, 'memory_versions')) {
      checkCancel();
      final content = StringBuffer();
      var ordinal = 0, nextLine = 1;
      await for (final chunk in _versionChunks(
          tx, version['document_id'] as String, version['revision'] as int)) {
        checkCancel();
        if (chunk['ordinal'] != ordinal++ || chunk['start_line'] != nextLine) {
          throw const FormatException('Nieciągła kolejność fragmentów.');
        }
        final body = await store.cipher.open(chunk['body'] as String);
        nextLine = (chunk['end_line'] as int) + (body.endsWith('\n') ? 1 : 0);
        content.write(body);
        if (content.length > MemoryStore.maxFileBytes + 1 || ordinal > 4096) {
          throw const FormatException(
              'Treść wersji przekracza limit dokumentu.');
        }
      }
      final text = content.toString(), originalBytes = version['bytes'] as int;
      final normalizedBytes = utf8.encode(text).length;
      // Importer zapisuje znormalizowane końce linii i może dodać finalny LF.
      // Nie udajemy ponownego wyliczenia oryginalnego SHA z tej reprezentacji.
      if ((originalBytes == 0) != (ordinal == 0) ||
          originalBytes < normalizedBytes - 1 ||
          originalBytes > normalizedBytes + '\n'.allMatches(text).length) {
        throw const FormatException(
            'Rozmiar i kompletność fragmentów nie odpowiadają wersji.');
      }
      final path = await store.cipher.open(version['path'] as String);
      if (MemoryStore(store).restrictedSource(path, text) &&
          version['restricted'] != 1) {
        throw const FormatException(
            'Sekret nie może zostać obniżony do jawnej pamięci.');
      }
    }
    await for (final campaign in _importedPages(tx, 'rpg_campaigns')) {
      checkCancel();
      final stats = (await tx.rawQuery(
              'SELECT MIN(revision) AS lo,MAX(revision) AS hi,COUNT(*) AS n '
              'FROM rpg_events WHERE campaign_id=?',
              [campaign['id']]))
          .single;
      final revision = campaign['revision'] as int;
      if (stats['n'] != revision ||
          (revision > 0 && (stats['lo'] != 1 || stats['hi'] != revision))) {
        throw const FormatException(
            'Rewizja kampanii nie odpowiada pełnemu audytowi.');
      }
    }
    await for (final version in _importedPages(tx, 'rpg_versions')) {
      await _member(tx, 'rpg_events', version['campaign_id'] as String,
          revision: version['revision'] as int);
    }
    await for (final record in _importedPages(tx, 'rpg_records')) {
      checkCancel();
      final version = (await tx.query('rpg_versions',
              where: 'campaign_id=? AND record_id=? AND revision=?',
              whereArgs: [
                record['campaign_id'],
                record['record_id'],
                record['revision']
              ],
              limit: 1))
          .single;
      if (['kind', 'visibility', 'approved', 'authority', 'edition']
              .any((key) => record[key] != version[key]) ||
          await store.cipher.open(record['payload'] as String) !=
              await store.cipher.open(version['payload'] as String)) {
        throw const FormatException(
            'Bieżący stan RPG nie odpowiada wersji historycznej.');
      }
    }
    await for (final event in _importedPages(tx, 'rpg_events')) {
      checkCancel();
      if (event['kind'] == 'rollback') continue;
      final payload =
          jsonDecode(await store.cipher.open(event['payload'] as String))
              as Map<String, dynamic>;
      await _member(tx, 'rpg_versions', event['campaign_id'] as String,
          k2: payload['recordId'] as String,
          revision: event['revision'] as int);
      final version = (await tx.query('rpg_versions',
              where: 'campaign_id=? AND record_id=? AND revision=?',
              whereArgs: [
                event['campaign_id'],
                payload['recordId'],
                event['revision']
              ],
              limit: 1))
          .single;
      if ((event['kind'] == 'recordSaved' && version['approved'] != 0) ||
          (event['kind'] != 'recordSaved' && version['approved'] != 1)) {
        throw const FormatException(
            'Zdarzenie ma niezgodny stan zatwierdzenia.');
      }
    }
    if ((await tx.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw const FormatException('Niespójne klucze obce po przywróceniu.');
    }
  }

  Stream<
      Map<String,
          Object?>> _importedPages(Transaction tx, String table) => _pages(
      tx, table,
      where:
          'EXISTS(SELECT 1 FROM $_members m WHERE m.t=? AND ${_memberJoin(table)})',
      args: [table]);
  String _memberJoin(String table) {
    if (table == 'memory_versions') {
      return 'm.k1=$table.document_id AND m.revision=$table.revision';
    }
    if (table == 'rpg_versions' || table == 'rpg_records') {
      return 'm.k1=$table.campaign_id AND m.k2=$table.record_id'
          '${table == 'rpg_versions' ? ' AND m.revision=$table.revision' : ''}';
    }
    if (table == 'rpg_events') {
      return 'm.k1=$table.campaign_id AND m.revision=$table.revision';
    }
    final key = table == 'memory_import_jobs'
        ? 'collection_id'
        : table == 'chat_scopes'
            ? 'conversation_id'
            : table == 'chat_context_receipts'
                ? 'message_id'
                : 'id';
    return 'm.k1=$table.$key';
  }

  Stream<Map<String, Object?>> _versionChunks(
      Transaction tx, String documentId, int revision) async* {
    var after = -1;
    while (true) {
      final page = await tx.query('memory_chunks',
          where: 'document_id=? AND revision=? AND ordinal>?',
          whereArgs: [documentId, revision, after],
          orderBy: 'ordinal',
          limit: 50);
      if (page.isEmpty) return;
      for (final row in page) {
        after = row['ordinal'] as int;
        yield row;
      }
    }
  }

  Future<void> _rebuildIndexes(
      Transaction tx, void Function() checkCancel) async {
    await for (final chunk in _importedPages(tx, 'memory_chunks')) {
      checkCancel();
      final doc = (await tx.query('memory_documents',
          where: 'id=? AND revision=? AND approval=? AND restricted=0',
          whereArgs: [chunk['document_id'], chunk['revision'], 'approved'],
          limit: 1));
      if (doc.isEmpty) continue;
      final body = await store.cipher.open(chunk['body'] as String);
      for (final word in MemoryStore.words(body).toSet()) {
        checkCancel();
        final token = await store.cipher.indexToken(word);
        checkCancel();
        await tx
            .insert('memory_terms', {'chunk_id': chunk['id'], 'term': token});
      }
    }
    await for (final record in _importedPages(tx, 'rpg_records')) {
      checkCancel();
      if (record['approved'] != 1 || record['visibility'] != 'campaign') {
        continue;
      }
      final payload =
          jsonDecode(await store.cipher.open(record['payload'] as String))
              as Map<String, dynamic>;
      for (final word
          in MemoryStore.words('${payload['title']}\n${payload['content']}')
              .toSet()) {
        checkCancel();
        final token = await store.cipher.indexToken('rpg:$word');
        checkCancel();
        await tx.insert('rpg_terms', {
          'campaign_id': record['campaign_id'],
          'record_id': record['record_id'],
          'term': token
        });
      }
    }
  }
}
