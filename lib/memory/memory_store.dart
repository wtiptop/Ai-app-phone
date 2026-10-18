import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../storage/app_database.dart';
import '../storage/models.dart';
import 'context_packet.dart';

class MemoryCollection {
  const MemoryCollection(this.id, this.name, this.ownerId, this.vaultId);
  final String id, name, ownerId;
  final String? vaultId;
}

class MemoryDocument {
  const MemoryDocument(
      {required this.id,
      required this.collectionId,
      required this.path,
      required this.hash,
      required this.revision,
      required this.approval,
      required this.restricted,
      required this.bytes});
  final String id, collectionId, path, hash, approval;
  final int revision, bytes;
  final bool restricted;
}

class AnalysisCheckpoint {
  const AnalysisCheckpoint(
      {required this.id,
      required this.collectionId,
      required this.revision,
      required this.goal,
      required this.findings,
      required this.nextStep,
      required this.sources});
  final String id, collectionId, goal, findings, nextStep, sources;
  final int revision;
}

class MemoryStore {
  MemoryStore(this.store);
  final AppDatabase store;
  static const maxFileBytes = 1024 * 1024;
  static const maxChunkCharacters = 900;
  static Iterable<String> words(String text) =>
      RegExp(r'[a-z0-9ąćęłńóśźżäöüß]{2,48}')
          .allMatches(text.toLowerCase())
          .map((m) => m.group(0)!);

  Future<MemoryCollection> createCollection(
      {required String name,
      String ownerId = 'local-owner',
      String? vaultId}) async {
    if (name.trim().isEmpty || name.length > 160 || ownerId.isEmpty) {
      throw ArgumentError('Nieprawidłowy projekt pamięci.');
    }
    final id = newId();
    await store.db.insert('memory_collections', {
      'id': id,
      'owner_id': ownerId,
      'name': await store.cipher.seal(name.trim()),
      'vault_id': vaultId,
      'created': DateTime.now().millisecondsSinceEpoch
    });
    return MemoryCollection(id, name.trim(), ownerId, vaultId);
  }

  Future<MemoryCollection> collection(String id,
      {String ownerId = 'local-owner'}) async {
    final rows = await store.db.query('memory_collections',
        where: 'id=? AND owner_id=?', whereArgs: [id, ownerId], limit: 1);
    if (rows.isEmpty) throw StateError('Brak dostępu do projektu pamięci.');
    final r = rows.single;
    return MemoryCollection(id, await store.cipher.open(r['name'] as String),
        ownerId, r['vault_id'] as String?);
  }

  Future<List<MemoryCollection>> collections(
      {String ownerId = 'local-owner', int offset = 0}) async {
    final rows = await store.db.query('memory_collections',
        where: 'owner_id=?',
        whereArgs: [ownerId],
        limit: 50,
        offset: offset,
        orderBy: 'created DESC');
    return [
      for (final r in rows)
        MemoryCollection(
            r['id'] as String,
            await store.cipher.open(r['name'] as String),
            ownerId,
            r['vault_id'] as String?)
    ];
  }

  bool restrictedSource(String path, String content) {
    final p = path.replaceAll('\\', '/').toUpperCase().split('/');
    return p.any((s) => [
              'RPG',
              'GM_SECRET',
              'GM',
              'SECRETS',
              '.OBSIDIAN',
              '.GIT'
            ].contains(s)) ||
        RegExp(r'(^|/)(gm[_ -]?secret|secrets?|sekrety|gm)([^a-z0-9]|$)',
                caseSensitive: false)
            .hasMatch(path) ||
        RegExp(r'GM[_ -]?SECRET|visibility\s*:\s*(secret|private_gm)|campaign[_ -]?id\s*:',
                caseSensitive: false)
            .hasMatch(content);
  }

  void _path(String path) {
    if (path.isEmpty ||
        path.length > 1024 ||
        path.startsWith('/') ||
        path.contains('\\') ||
        RegExp(r'[\x00-\x1f:]').hasMatch(path) ||
        path.split('/').any(
            (s) => s.isEmpty || s == '.' || s == '..' || s.startsWith('.')) ||
        !(path.toLowerCase().endsWith('.md') ||
            path.toLowerCase().endsWith('.markdown'))) {
      throw ArgumentError('Nieprawidłowa ścieżka Markdown.');
    }
  }

  Future<MemoryDocument> ingest(
      String collectionId, String path, String content,
      {String ownerId = 'local-owner'}) async {
    await collection(collectionId, ownerId: ownerId);
    _path(path);
    final bytes = utf8.encode(content).length;
    if (bytes > maxFileBytes) throw ArgumentError('Plik przekracza 1 MiB.');
    final hash = await contentDigest(content),
        sourceKey = await store.cipher.indexToken('path:$path');
    final restricted = restrictedSource(path, content);
    final encodedPath = await store.cipher.seal(path);
    final chunks = <_Chunk>[];
    final lines = const LineSplitter().convert(content);
    var buffer = StringBuffer(), start = 1, end = 1;
    void flush() {
      if (buffer.isNotEmpty) chunks.add(_Chunk(start, end, buffer.toString()));
      buffer = StringBuffer();
    }

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (buffer.isNotEmpty &&
          buffer.length + line.length + 1 > maxChunkCharacters) {
        flush();
      }
      while (line.length > maxChunkCharacters) {
        flush();
        final part = utf8Prefix(line, maxChunkCharacters);
        chunks.add(_Chunk(i + 1, i + 1, part));
        line = line.substring(part.length);
      }
      if (buffer.isEmpty) start = i + 1;
      end = i + 1;
      buffer.writeln(line);
    }
    flush();
    if (chunks.length > 4096) throw ArgumentError('Za dużo fragmentów pliku.');
    final encrypted = [for (final c in chunks) await store.cipher.seal(c.text)];
    late String id;
    await store.db.transaction((tx) async {
      final prior = await tx.query('memory_documents',
          where: 'collection_id=? AND source_key=?',
          whereArgs: [collectionId, sourceKey],
          limit: 1);
      if (prior.isNotEmpty && prior.single['hash'] == hash) {
        id = prior.single['id'] as String;
        return;
      }
      id = prior.isEmpty ? newId() : prior.single['id'] as String;
      final revision =
          prior.isEmpty ? 1 : (prior.single['revision'] as int) + 1;
      if (prior.isNotEmpty) {
        await tx.rawDelete(
            'DELETE FROM memory_terms WHERE chunk_id IN (SELECT id FROM memory_chunks WHERE document_id=?)',
            [id]);
      }
      final data = {
        'id': id,
        'collection_id': collectionId,
        'source_key': sourceKey,
        'path': encodedPath,
        'hash': hash,
        'revision': revision,
        'approval': 'pending',
        'restricted': restricted ? 1 : 0,
        'bytes': bytes,
        'updated': DateTime.now().millisecondsSinceEpoch
      };
      if (prior.isEmpty) {
        await tx.insert('memory_documents', data);
      } else {
        await tx
            .update('memory_documents', data, where: 'id=?', whereArgs: [id]);
      }
      await tx.insert('memory_versions', {
        'document_id': id,
        'revision': revision,
        'hash': hash,
        'path': encodedPath,
        'restricted': restricted ? 1 : 0,
        'bytes': bytes,
        'created': DateTime.now().millisecondsSinceEpoch
      });
      for (var i = 0; i < chunks.length; i++) {
        await tx.insert('memory_chunks', {
          'id': newId(),
          'document_id': id,
          'revision': revision,
          'ordinal': i,
          'start_line': chunks[i].start,
          'end_line': chunks[i].end,
          'body': encrypted[i]
        });
      }
    });
    return document(id, ownerId: ownerId);
  }

  Future<MemoryDocument> _document(Map<String, Object?> r) async =>
      MemoryDocument(
          id: r['id'] as String,
          collectionId: r['collection_id'] as String,
          path: await store.cipher.open(r['path'] as String),
          hash: r['hash'] as String,
          revision: r['revision'] as int,
          approval: r['approval'] as String,
          restricted: r['restricted'] == 1,
          bytes: r['bytes'] as int);
  Future<MemoryDocument> document(String id,
      {String ownerId = 'local-owner'}) async {
    final rows = await store.db.rawQuery(
        'SELECT d.* FROM memory_documents d JOIN memory_collections c ON c.id=d.collection_id WHERE d.id=? AND c.owner_id=? LIMIT 1',
        [id, ownerId]);
    if (rows.isEmpty) throw StateError('Dokument niedostępny.');
    return _document(rows.single);
  }

  Future<List<MemoryDocument>> documents(String collectionId,
      {String ownerId = 'local-owner', int limit = 30, int offset = 0}) async {
    await collection(collectionId, ownerId: ownerId);
    if (limit < 1 || limit > 100 || offset < 0) {
      throw ArgumentError('Nieprawidłowa strona.');
    }
    return [
      for (final r in await store.db.query('memory_documents',
          where: 'collection_id=?',
          whereArgs: [collectionId],
          orderBy: 'updated DESC,id',
          limit: limit,
          offset: offset))
        await _document(r)
    ];
  }

  Future<String> preview(String id,
      {String ownerId = 'local-owner',
      int maxBytes = 8192,
      int? revision}) async {
    final doc = await document(id, ownerId: ownerId);
    final rows = await store.db.query('memory_chunks',
        where: 'document_id=? AND revision=?',
        whereArgs: [id, revision ?? doc.revision],
        orderBy: 'ordinal',
        limit: 16);
    final result = StringBuffer();
    for (final r in rows) {
      final text = await store.cipher.open(r['body'] as String);
      final remaining = maxBytes - utf8.encode(result.toString()).length;
      result.write(utf8Prefix(text, remaining));
      if (remaining <= utf8.encode(text).length) break;
    }
    return result.toString();
  }

  Future<void> approve(String id, int expectedRevision,
      {String ownerId = 'local-owner'}) async {
    final doc = await document(id, ownerId: ownerId);
    if (doc.restricted) {
      throw StateError(
          'Treść kampanii lub sekret MG nie może trafić do ogólnego indeksu. Użyj odrębnej kampanii RPG.');
    }
    await store.db.transaction((tx) async {
      final current = await tx.query('memory_documents',
          where: 'id=? AND revision=?',
          whereArgs: [id, expectedRevision],
          limit: 1);
      if (current.isEmpty || current.single['restricted'] == 1) {
        throw StateError('Dokument zmienił się; otwórz podgląd ponownie.');
      }
      await tx.rawDelete(
          'DELETE FROM memory_terms WHERE chunk_id IN (SELECT id FROM memory_chunks WHERE document_id=?)',
          [id]);
      // Jedna strona naraz również dla długiego dokumentu.
      var offset = 0;
      while (true) {
        final rows = await tx.query('memory_chunks',
            where: 'document_id=? AND revision=?',
            whereArgs: [id, expectedRevision],
            limit: 32,
            offset: offset,
            orderBy: 'ordinal');
        if (rows.isEmpty) break;
        for (final r in rows) {
          final body = await store.cipher.open(r['body'] as String);
          for (final word in words(body).toSet()) {
            await tx.insert(
                'memory_terms',
                {
                  'term': await store.cipher.indexToken(word),
                  'chunk_id': r['id']
                },
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        offset += rows.length;
      }
      await tx.update('memory_documents', {'approval': 'approved'},
          where: 'id=?', whereArgs: [id]);
    });
  }

  Future<void> revoke(String id,
      {String ownerId = 'local-owner', bool remove = false}) async {
    await document(id, ownerId: ownerId);
    await store.db.transaction((tx) async {
      await tx.rawDelete(
          'DELETE FROM memory_terms WHERE chunk_id IN (SELECT id FROM memory_chunks WHERE document_id=?)',
          [id]);
      if (remove) {
        await tx.delete('memory_documents', where: 'id=?', whereArgs: [id]);
      } else {
        await tx.update('memory_documents', {'approval': 'pending'},
            where: 'id=?', whereArgs: [id]);
      }
    });
  }

  Future<ContextPacket> retrieve(String collectionId, String query,
      {String ownerId = 'local-owner',
      int maxBytes = 2200,
      int maxChunks = 6}) async {
    await collection(collectionId, ownerId: ownerId);
    if (maxBytes < 256 || maxBytes > 24000 || maxChunks < 1 || maxChunks > 20) {
      throw ArgumentError('Nieprawidłowy budżet kontekstu.');
    }
    final terms = [
      for (final word in words(query).toSet().take(12))
        await store.cipher.indexToken(word)
    ];
    if (terms.isEmpty) {
      return ContextPacket(
          collectionId: collectionId, ownerId: ownerId, excerpts: const []);
    }
    final marks = List.filled(terms.length, '?').join(',');
    final rows = await store.db.rawQuery(
        'SELECT k.*,d.path,d.hash,d.revision,COUNT(t.term) AS score FROM memory_terms t JOIN memory_chunks k ON k.id=t.chunk_id JOIN memory_documents d ON d.id=k.document_id JOIN memory_collections c ON c.id=d.collection_id WHERE d.collection_id=? AND c.owner_id=? AND k.revision=d.revision AND d.approval=\'approved\' AND d.restricted=0 AND t.term IN ($marks) GROUP BY k.id ORDER BY score DESC,d.updated DESC,k.ordinal LIMIT 64',
        [collectionId, ownerId, ...terms]);
    final excerpts = <SourceExcerpt>[];
    var limited = false;
    for (final r in rows) {
      if (excerpts.length >= maxChunks) {
        limited = true;
        break;
      }
      final body = await store.cipher.open(r['body'] as String);
      final path = await store.cipher.open(r['path'] as String);
      final base = ContextPacket(
              collectionId: collectionId, ownerId: ownerId, excerpts: excerpts)
          .bytes;
      var candidate = SourceExcerpt(
          documentId: r['document_id'] as String,
          chunkId: r['id'] as String,
          revision: r['revision'] as int,
          hash: r['hash'] as String,
          path: path,
          startLine: r['start_line'] as int,
          endLine: r['end_line'] as int,
          text: body);
      var next = ContextPacket(
          collectionId: collectionId,
          ownerId: ownerId,
          excerpts: [...excerpts, candidate]);
      if (next.bytes > maxBytes) {
        final cut =
            utf8Prefix(body, maxBytes - base - 320 - utf8.encode(path).length);
        if (cut.isEmpty) {
          limited = true;
          continue;
        }
        final last = candidate.startLine +
            '\n'.allMatches(cut).length -
            (cut.endsWith('\n') ? 1 : 0);
        candidate = SourceExcerpt(
            documentId: candidate.documentId,
            chunkId: candidate.chunkId,
            revision: candidate.revision,
            hash: candidate.hash,
            path: path,
            startLine: candidate.startLine,
            endLine: last > candidate.endLine ? candidate.endLine : last,
            text: cut);
        next = ContextPacket(
            collectionId: collectionId,
            ownerId: ownerId,
            excerpts: [...excerpts, candidate]);
        limited = true;
      }
      if (next.bytes <= maxBytes) excerpts.add(candidate);
    }
    return ContextPacket(
        collectionId: collectionId,
        ownerId: ownerId,
        excerpts: excerpts,
        limited: limited);
  }

  Future<void> validate(ContextPacket packet) async {
    await collection(packet.collectionId, ownerId: packet.ownerId);
    for (final e in packet.excerpts) {
      final doc = await document(e.documentId, ownerId: packet.ownerId);
      if (doc.collectionId != packet.collectionId ||
          doc.revision != e.revision ||
          doc.hash != e.hash ||
          doc.approval != 'approved' ||
          doc.restricted) {
        throw StateError(
            'Źródła zmieniły się lub cofnięto zgodę. Wybierz kontekst ponownie.');
      }
      final chunks = await store.db.query('memory_chunks',
          where: 'id=? AND document_id=? AND revision=?',
          whereArgs: [e.chunkId, e.documentId, e.revision],
          limit: 1);
      if (chunks.isEmpty ||
          e.path != doc.path ||
          e.text.isEmpty ||
          chunks.single['start_line'] != e.startLine ||
          e.endLine < e.startLine ||
          e.endLine > (chunks.single['end_line'] as int) ||
          !(await store.cipher.open(chunks.single['body'] as String))
              .startsWith(e.text)) {
        throw StateError(
            'Pakiet źródeł jest nieprawidłowy. Wybierz go ponownie.');
      }
      final last = e.startLine +
          '\n'.allMatches(e.text).length -
          (e.text.endsWith('\n') ? 1 : 0);
      if (e.endLine != last) {
        throw StateError('Nieprawidłowy zakres cytowania.');
      }
    }
  }

  Future<List<int>> versions(String id,
      {String ownerId = 'local-owner'}) async {
    await document(id, ownerId: ownerId);
    return [
      for (final r in await store.db.query('memory_versions',
          columns: ['revision'],
          where: 'document_id=?',
          whereArgs: [id],
          orderBy: 'revision DESC',
          limit: 100))
        r['revision'] as int
    ];
  }

  Future<AnalysisCheckpoint> saveCheckpoint(String collectionId,
      {required String goal,
      required String findings,
      required String nextStep,
      required String sources,
      String? id,
      int? expectedRevision,
      String ownerId = 'local-owner'}) async {
    await collection(collectionId, ownerId: ownerId);
    if (goal.trim().isEmpty ||
        [goal, findings, nextStep, sources]
            .any((s) => utf8.encode(s).length > 32000)) {
      throw ArgumentError('Nieprawidłowy punkt wznowienia.');
    }
    final key = id ?? newId();
    final encrypted = [
      for (final s in [goal, findings, nextStep, sources])
        await store.cipher.seal(s)
    ];
    var revision = 1;
    await store.db.transaction((tx) async {
      final old = await tx.query('analysis_checkpoints',
          where: 'id=? AND collection_id=?',
          whereArgs: [key, collectionId],
          limit: 1);
      if (id != null &&
          (old.isEmpty || old.single['revision'] != expectedRevision)) {
        throw StateError('Konflikt punktu wznowienia.');
      }
      if (old.isNotEmpty) revision = (old.single['revision'] as int) + 1;
      final value = {
        'id': key,
        'collection_id': collectionId,
        'revision': revision,
        'goal': encrypted[0],
        'findings': encrypted[1],
        'next_step': encrypted[2],
        'sources': encrypted[3],
        'updated': DateTime.now().millisecondsSinceEpoch
      };
      if (old.isEmpty) {
        await tx.insert('analysis_checkpoints', value);
      } else {
        await tx.update('analysis_checkpoints', value,
            where: 'id=?', whereArgs: [key]);
      }
    });
    return AnalysisCheckpoint(
        id: key,
        collectionId: collectionId,
        revision: revision,
        goal: goal,
        findings: findings,
        nextStep: nextStep,
        sources: sources);
  }

  Future<List<AnalysisCheckpoint>> checkpoints(String collectionId,
      {String ownerId = 'local-owner'}) async {
    await collection(collectionId, ownerId: ownerId);
    return [
      for (final r in await store.db.query('analysis_checkpoints',
          where: 'collection_id=?',
          whereArgs: [collectionId],
          orderBy: 'updated DESC',
          limit: 30))
        AnalysisCheckpoint(
            id: r['id'] as String,
            collectionId: collectionId,
            revision: r['revision'] as int,
            goal: await store.cipher.open(r['goal'] as String),
            findings: await store.cipher.open(r['findings'] as String),
            nextStep: await store.cipher.open(r['next_step'] as String),
            sources: await store.cipher.open(r['sources'] as String))
    ];
  }
}

class _Chunk {
  const _Chunk(this.start, this.end, this.text);
  final int start, end;
  final String text;
}
