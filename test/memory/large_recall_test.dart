// ignore_for_file: avoid_print
// Metryki wyłącznie syntetycznego korpusu w raporcie testów hosta.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/memory/context_packet.dart';
import 'package:scalajaca/memory/memory_store.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _CountingCipher extends ContentCipher {
  _CountingCipher() : super(MemorySecrets());
  int opens = 0;
  @override
  Future<String> open(String value) {
    opens++;
    return super.open(value);
  }
}

void main() {
  late AppDatabase database;
  late _CountingCipher cipher;
  late MemoryStore memory;
  late MemoryCollection corpus;
  const noiseDocuments = 1200, twinChunks = 1000;
  const documentCount = noiseDocuments + 2,
      chunkCount = noiseDocuments + 1 + twinChunks;
  const lateFact = 'RIVERLIGHT_LATE_1200';

  setUpAll(() async {
    sqfliteFfiInit();
    cipher = _CountingCipher();
    database = await AppDatabase.open(cipher,
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    memory = MemoryStore(database);
    corpus =
        await memory.createCollection(name: 'Duży syntetyczny korpus recall');
    final timer = Stopwatch()..start();
    // Fixture indeksu: identyczne HMAC jak approve()/odbudowa backupu, realne
    // AES-GCM i SQLite. Jedna partia <=50 dokumentów; korpus powstaje raz.
    const noise =
        'Archiwum archive zawiera zwykły wpis. Jest to the is and placeholder.\n';
    const fact = 'Klucz archiwum to $lateFact. Archive key $lateFact.\n';
    const twin =
        'Klucz archiwum i archive key są wspomniane w powtarzalnej kronice.\n';
    final bodyCipher = {
      for (final body in [noise, fact, twin]) body: await cipher.seal(body)
    };
    final bodyTerms = <String, List<String>>{};
    for (final body in bodyCipher.keys) {
      bodyTerms[body] = [
        for (final word in MemoryStore.words(body).toSet())
          await cipher.indexToken(word)
      ];
    }
    await database.db.transaction((tx) async {
      var batch = tx.batch(), buffered = 0;
      Future<void> insertDocument(
          String id, String path, String body, int chunks, int updated) async {
        final encodedPath = await cipher.seal(path);
        final hash = await contentDigest(body * chunks);
        final size = utf8.encode(body).length * chunks;
        batch.insert('memory_documents', {
          'id': id,
          'collection_id': corpus.id,
          'source_key': await cipher.indexToken('path:$path'),
          'path': encodedPath,
          'hash': hash,
          'revision': 1,
          'approval': 'approved',
          'restricted': 0,
          'bytes': size,
          'updated': updated
        });
        batch.insert('memory_versions', {
          'document_id': id,
          'revision': 1,
          'hash': hash,
          'path': encodedPath,
          'restricted': 0,
          'bytes': size,
          'created': updated
        });
        for (var ordinal = 0; ordinal < chunks; ordinal++) {
          final chunkId = '$id-chunk-${ordinal.toString().padLeft(4, '0')}';
          batch.insert('memory_chunks', {
            'id': chunkId,
            'document_id': id,
            'revision': 1,
            'ordinal': ordinal,
            'start_line': ordinal + 1,
            'end_line': ordinal + 1,
            'body': bodyCipher[body]
          });
          for (final token in bodyTerms[body]!) {
            batch.insert('memory_terms', {'term': token, 'chunk_id': chunkId});
          }
        }
        if (++buffered == 50) {
          await batch.commit(noResult: true);
          batch = tx.batch();
          buffered = 0;
        }
      }

      for (var i = 0; i < noiseDocuments; i++) {
        final suffix = i.toString().padLeft(4, '0');
        await insertDocument(
            'corpus-$suffix', 'Archive/file-$suffix.md', noise, 1, 2);
      }
      // Stary ORDER BY updated + LIMIT64 tonął w 1000 bliźniaczych fragmentów.
      await insertDocument('corpus-last', 'Archive/last-fact.md', fact, 1, 1);
      await insertDocument(
          'corpus-twins', 'Archive/repetitive.md', twin, twinChunks, 9999999);
      await batch.commit(noResult: true);
    });
    timer.stop();
    print(
        'HOST_SYNTHETIC_RECALL seedMs=${timer.elapsedMilliseconds} documents=$documentCount chunks=$chunkCount; SQLite/AES-GCM, nie pomiar Pixela ani korpusu GB.');
  });
  tearDownAll(() async => database.close());

  Future<MemoryDocument> accepted(
      String project, String path, String text) async {
    final doc = await memory.ingest(project, path, text);
    await memory.approve(doc.id, doc.revision);
    return doc;
  }

  test(
      '1202 dokumenty i 2201 fragmentów: późny fakt, coverage i bounded decrypt',
      () async {
    cipher.opens = 0;
    final timer = Stopwatch()..start();
    final page =
        await memory.search(corpus.id, 'jaki jest klucz archiwum', limit: 10);
    timer.stop();
    final opens = cipher.opens;
    print(
        'HOST_SYNTHETIC_RECALL queryMs=${timer.elapsedMilliseconds} total=${page.total} returned=${page.excerpts.length} decrypts=$opens documents=$documentCount chunks=$chunkCount.');
    expect(page.total, chunkCount);
    expect(page.excerpts, hasLength(10));
    expect(page.excerpts.map((e) => e.documentId).toSet(), hasLength(10));
    expect(page.excerpts.take(2).any((e) => e.text.contains(lateFact)), isTrue);
    expect(opens, lessThanOrEqualTo(21),
        reason: '1 nazwa projektu +2 pola tylko zwróconej strony.');
    expect(page.hasMore, isTrue);
    expect(page.queryLimited, isFalse);
    final automatic = await memory
        .retrieve(corpus.id, 'jaki jest klucz archiwum', maxBytes: 2200);
    expect(automatic.text, contains(lateFact));
    expect(automatic.limited, isTrue);
    await memory.validate(automatic);
  });

  test('stabilne strony bez powtórzeń i daleka ostatnia strona', () async {
    final first = await memory.search(corpus.id, 'archiwum klucz', limit: 10);
    final repeat = await memory.search(corpus.id, 'archiwum klucz', limit: 10);
    final second =
        await memory.search(corpus.id, 'archiwum klucz', limit: 10, offset: 10);
    expect(repeat.excerpts.map((e) => e.chunkId),
        first.excerpts.map((e) => e.chunkId));
    expect(
        first.excerpts
            .map((e) => e.chunkId)
            .toSet()
            .intersection(second.excerpts.map((e) => e.chunkId).toSet()),
        isEmpty);
    cipher.opens = 0;
    final last = await memory.search(corpus.id, 'archiwum klucz',
        limit: 30, offset: chunkCount - 11);
    expect(last.excerpts, hasLength(11));
    expect(last.hasMore, isFalse);
    expect(last.total, chunkCount);
    expect(cipher.opens, lessThanOrEqualTo(23));
    final empty =
        await memory.search(corpus.id, 'archiwum', offset: chunkCount);
    expect(empty.excerpts, isEmpty);
    expect(empty.hasMore, isFalse);
  });

  test('PL/EN stoplista i jawne ograniczenie 12 słów nie zmieniają indeksu',
      () async {
    final english = await memory.search(corpus.id, 'what is the archive key');
    expect(
        english.excerpts.take(2).any((e) => e.text.contains(lateFact)), isTrue);
    cipher.opens = 0;
    final empty = await memory.search(corpus.id, 'jaki jest oraz the is and');
    expect(empty.total, 0);
    expect(cipher.opens, 1);
    final limited = await memory.search(
        corpus.id, 'archiwum ${List.generate(15, (i) => 'wyraz$i').join(' ')}');
    expect(limited.queryLimited, isTrue);
    final tokens =
        await database.db.query('memory_terms', columns: ['term'], limit: 20);
    expect(
        tokens.every(
            (row) => !['archiwum', 'klucz', 'the'].contains(row['term'])),
        isTrue);
    await expectLater(
        memory.search(corpus.id, 'x' * 2049), throwsArgumentError);
    await expectLater(
        memory.search(corpus.id, 'archiwum', limit: 31), throwsArgumentError);
    await expectLater(
        memory.search(corpus.id, 'archiwum', offset: -1), throwsArgumentError);
  });

  test('modern i wymuszony legacy SQL dają identyczny ranking', () async {
    final timer = Stopwatch()..start();
    final legacy = await MemoryStore(database, forceLegacySearch: true)
        .search(corpus.id, 'klucz archiwum', limit: 30);
    timer.stop();
    final modern = await memory.search(corpus.id, 'klucz archiwum', limit: 30);
    print(
        'HOST_SYNTHETIC_RECALL legacyQueryMs=${timer.elapsedMilliseconds} repetitiveFileChunks=$twinChunks returned=${legacy.excerpts.length}.');
    expect(legacy.total, modern.total);
    expect(legacy.excerpts.map((e) => e.chunkId),
        modern.excerpts.map((e) => e.chunkId));
  });

  test('ręczna selekcja przestrzega UTF-8/JSON i limitu wszystkich metadanych',
      () async {
    final project =
        await memory.createCollection(name: 'Escapowanie i Unicode');
    await accepted(project.id, 'Ścieżka/"cytat".md',
        'needle ${'"żółć 😀\t' * 80}\nDruga linia.');
    final hits = await memory.search(project.id, 'needle');
    final ids = hits.excerpts.map((e) => e.chunkId).toList();
    final packet = await memory.retrieveSelected(project.id, ids,
        maxBytes: 900, maxChunks: 20);
    expect(packet.bytes, lessThanOrEqualTo(900));
    expect(packet.excerpts, isNotEmpty);
    expect(packet.limited, isTrue);
    expect(packet.text, isNot(contains('\uFFFD')));
    await memory.validate(packet);
    final tiny = await memory.retrieveSelected(project.id, ids, maxBytes: 256);
    expect(tiny.bytes, lessThanOrEqualTo(256));
    expect(tiny.excerpts, isEmpty);
    expect(tiny.limited, isTrue);
  });

  test(
      'selekcja odrzuca obcy projekt/owner, wszystkie stale/revoked ID przed budżetem',
      () async {
    final a = await memory.createCollection(name: 'Izolacja A');
    final b = await memory.createCollection(name: 'Izolacja B');
    final first = await accepted(a.id, 'first.md', 'needle stale_version_one');
    final revoked = await accepted(a.id, 'second.md', 'needle revoked_version');
    await accepted(b.id, 'other.md', 'needle foreign_project');
    final aHits = await memory.search(a.id, 'needle');
    final bId = (await memory.search(b.id, 'needle')).excerpts.single.chunkId;
    final firstId =
        aHits.excerpts.firstWhere((e) => e.documentId == first.id).chunkId;
    final revokedId =
        aHits.excerpts.firstWhere((e) => e.documentId == revoked.id).chunkId;
    await expectLater(
        memory.retrieveSelected(a.id, [firstId, bId]), throwsStateError);
    await expectLater(
        memory.retrieveSelected(a.id, [firstId], ownerId: 'other-owner'),
        throwsStateError);
    await memory.revoke(revoked.id);
    await expectLater(
        memory.retrieveSelected(a.id, [firstId, revokedId],
            maxBytes: 256, maxChunks: 1),
        throwsStateError);
    final updated =
        await memory.ingest(a.id, 'first.md', 'needle current_version_two');
    await memory.approve(updated.id, updated.revision);
    await expectLater(
        memory.retrieveSelected(a.id, [firstId]), throwsStateError);
    final current = await memory.search(a.id, 'needle');
    expect(current.total, 1);
    expect(current.excerpts.single.text, contains('current_version_two'));
    expect(current.excerpts.single.text, isNot(contains('stale_version_one')));
    await memory.validate(
        await memory.retrieveSelected(a.id, [current.excerpts.single.chunkId]));
    await expectLater(
        memory.retrieveSelected(a.id,
            [current.excerpts.single.chunkId, current.excerpts.single.chunkId]),
        throwsArgumentError);
  });

  test('checkpointy po stronach i dokładny odczyt pilnują projektu/właściciela',
      () async {
    final a = await memory.createCollection(name: 'Checkpointy A');
    final b = await memory.createCollection(name: 'Checkpointy B');
    for (var i = 0; i < 35; i++) {
      await memory.saveCheckpoint(a.id,
          goal: 'Cel $i',
          findings: 'Ustalenia $i',
          nextStep: 'Następny krok $i',
          sources: 'source.md w1');
    }
    await database.db.update('analysis_checkpoints', {'updated': 1000},
        where: 'collection_id=?', whereArgs: [a.id]);
    final first = await memory.checkpoints(a.id, limit: 30);
    final second = await memory.checkpoints(a.id, limit: 30, offset: 30);
    expect(first, hasLength(30));
    expect(second, hasLength(5));
    expect(
        {...first.map((c) => c.id), ...second.map((c) => c.id)}, hasLength(35));
    final exact = await memory.checkpoint(a.id, second.last.id);
    expect(exact.goal, second.last.goal);
    expect(exact.nextStep, second.last.nextStep);
    await expectLater(memory.checkpoint(b.id, exact.id), throwsStateError);
    await expectLater(memory.checkpoint(a.id, exact.id, ownerId: 'other-owner'),
        throwsStateError);
    await expectLater(
        memory.checkpoints(a.id, limit: 101), throwsArgumentError);
    await expectLater(
        memory.checkpoints(a.id, offset: -1), throwsArgumentError);
  });
}
