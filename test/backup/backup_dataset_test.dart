import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/backup/backup_dataset.dart';
import 'package:scalajaca/memory/context_packet.dart';
import 'package:scalajaca/memory/memory_store.dart';
import 'package:scalajaca/rpg/campaign.dart';
import 'package:scalajaca/rpg/campaign_store.dart';
import 'package:scalajaca/security/memory_access.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:scalajaca/storage/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Snapshot {
  _Snapshot(this.counts, this.rows);
  final Map<String, int> counts;
  final List<Map<String, Object?>> rows;
  _Snapshot copy() => _Snapshot(Map.of(counts), [
        for (final envelope in rows)
          {
            'table': envelope['table'],
            'row': Map<String, Object?>.from(envelope['row'] as Map)
          }
      ]);
  Map<String, Object?> first(String table,
          {bool Function(Map<String, Object?> row)? where}) =>
      rows
          .where((e) => e['table'] == table)
          .map((e) => e['row'] as Map<String, Object?>)
          .firstWhere(where ?? (_) => true);
  void removeTable(String table) {
    rows.removeWhere((e) => e['table'] == table);
    counts[table] = 0;
  }
}

void main() {
  late AppDatabase source, target;
  late _Snapshot snapshot;
  late String collectionId, campaignId, canonicalId, secretId;
  late String originalEvidence, originalDigest;
  final opened = <AppDatabase>[];
  Future<AppDatabase> open() async {
    final db = await AppDatabase.open(ContentCipher(MemorySecrets()),
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    opened.add(db);
    return db;
  }

  Future<_Snapshot> take(AppDatabase db) => BackupDataset(db).exportSnapshot(
      (counts, rows) async => _Snapshot(counts, await rows.toList()));
  Future<void> restore(_Snapshot fixture, {bool Function()? cancel}) =>
      BackupDataset(target).restore(
          Stream.fromIterable(fixture.rows), fixture.counts,
          isCancelled: cancel);
  Future<void> expectEmptyTarget() async {
    for (final table in BackupDataset.tables) {
      expect(await target.db.query(table), isEmpty,
          reason: 'Pozostały częściowe dane: $table');
    }
    expect(await target.setting('destinationSetting', ''), 'zachowane');
  }

  Future<void> populate() async {
    final memory = MemoryStore(source);
    final collection = await memory.createCollection(
        name: 'Projekt badawczy', vaultId: 'source-vault-capability');
    collectionId = collection.id;
    var doc = await memory.ingest(collection.id, 'badania/brama.md',
        'Bursztynowa brama.\r\nPierwsza wersja');
    await memory.approve(doc.id, doc.revision);
    doc = await memory.ingest(collection.id, 'badania/brama.md',
        'Bursztynowa brama.\nDruga wersja.\n');
    await memory.approve(doc.id, doc.revision);
    await memory.ingest(
        collection.id, 'RPG/sekret.md', 'SEKRET_MG tylko w odrębnej kampanii.');
    await memory.ingest(
        collection.id, 'badania/szkic.md', 'Niezatwierdzony bursztyn.');
    final removed = await memory.ingest(
        collection.id, 'badania/usunięte.md', 'Historyczny dokument.');
    await memory.approve(removed.id, removed.revision);
    final historical = await memory.retrieve(collection.id, 'historyczny');
    await memory.revoke(removed.id, remove: true);
    await memory.saveCheckpoint(collection.id,
        goal: 'Porównaj wersje',
        findings: 'Ustalony fakt',
        nextStep: 'Sprawdź źródło',
        sources: historical.text);
    await source.db.insert('memory_import_jobs', {
      'collection_id': collection.id,
      'cursor': await source.cipher.seal('content://private-source-cursor'),
      'page_offset': 17,
      'processed': 123,
      'failed': 2,
      'status': 'running',
      'updated': 777
    });
    final campaigns = CampaignStore(source);
    final campaign = await campaigns.create(
        name: 'Własna kampania testowa',
        edition: 'Własna edycja',
        ownerId: 'local-owner');
    campaignId = campaign.id;
    canonicalId = 'gate';
    secretId = 'gm-secret';
    final context = AccessContext(
        principalId: 'local-owner',
        role: AccessRole.gameMaster,
        campaignId: campaign.id,
        allowGmSecretContext: true);
    CampaignRecord record(String id, String text,
            {bool secret = false,
            CampaignRecordKind kind = CampaignRecordKind.canon}) =>
        CampaignRecord(
            id: id,
            campaignId: campaign.id,
            title: 'Tytuł $id',
            content: text,
            kind: kind,
            visibility:
                secret ? MemoryVisibility.gmSecret : MemoryVisibility.campaign,
            citation: LoreCitation(
                sourceId: 'own/$id',
                title: 'Własny kanon',
                authority: LoreAuthority.approvedCampaignCanon,
                edition: campaign.edition,
                page: 'wpis 1',
                userVerified: true));
    await campaigns.putRecord(record(canonicalId, 'Stara brama'), context,
        expectedRevision: 0, userApproved: true);
    await campaigns.putRecord(
        record(canonicalId, 'Nowa bursztynowa brama'), context,
        expectedRevision: 1, userApproved: true);
    await campaigns.putRecord(
        record(secretId, 'SEKRET_MG ukryty cel', secret: true), context,
        expectedRevision: 2, userApproved: true);
    await campaigns.saveCheckpoint(
        const CampaignCheckpoint(
            goal: 'Stary cel',
            scene: 'Stara scena',
            openThreads: 'Wątek A',
            party: 'Własne postacie',
            worldClock: 'Dzień 1'),
        context,
        expectedRevision: 3);
    await campaigns.rollback(2, context, expectedRevision: 4);
    await campaigns.saveCheckpoint(
        const CampaignCheckpoint(
            goal: 'Odnajdź posłańca',
            scene: 'Bursztynowa brama',
            openThreads: 'Zaginiona pieczęć',
            party: 'Własne postacie',
            worldClock: 'Dzień 2'),
        context,
        expectedRevision: 5);
    await campaigns.putRecord(
        record(secretId, 'SEKRET_MG przywrócony', secret: true), context,
        expectedRevision: 6, userApproved: true);
    await campaigns.putRecord(
        record('known', 'Gracz widział bramę',
            kind: CampaignRecordKind.playerKnowledge),
        context,
        expectedRevision: 7,
        userApproved: true);
    final gmConversation = await source.createConversation('Rozmowa MG');
    final projectConversation =
        await source.createConversation('Analiza źródła');
    final playerConversation =
        await source.createConversation('Rozmowa gracza');
    await source.draft(projectConversation.id, 'Szkic pozostaje zapisany');
    await source.pin(projectConversation.id, true);
    for (final item in [
      (gmConversation, 'rpg:${campaign.id}:gameMaster', 1),
      (projectConversation, 'project:${collection.id}', 0),
      (playerConversation, 'rpg:${campaign.id}:rpgPlayer', 0)
    ]) {
      await source.db.insert('chat_scopes', {
        'conversation_id': item.$1.id,
        'scope_key': item.$2,
        'confidential': item.$3
      });
      await source.saveMessage(Message(
          id: 'user-${item.$1.id}',
          conversationId: item.$1.id,
          role: 'user',
          text: 'Pytanie'));
      await source.saveMessage(Message(
          id: 'answer-${item.$1.id}',
          conversationId: item.$1.id,
          role: 'assistant',
          text: item.$3 == 1 ? 'SEKRET_MG odpowiedź' : 'Jawna odpowiedź',
          status: item.$3 == 1
              ? 'streaming'
              : item.$2.endsWith(':rpgPlayer')
                  ? 'pending'
                  : 'complete',
          inputTokens: 21,
          outputTokens: 3));
    }
    originalDigest =
        await contentDigest('Niezmienny historyczny pakiet wejściowy');
    originalEvidence = jsonEncode({
      'format': 'scalajaca.context-receipt.v1',
      'digest': originalDigest,
      'omittedMessages': 2,
      'attachment': {
        'collectionId': collection.id,
        'sources': [for (final e in historical.excerpts) e.toJson()]
      },
      'sourceSnapshot': historical.text
    });
    await source.db.insert('chat_context_receipts', {
      'message_id': 'answer-${projectConversation.id}',
      'digest': originalDigest,
      'evidence': await source.cipher.seal(originalEvidence),
      'omitted': 2,
      'created': 888
    });
    final gmDigest = await contentDigest('GM input snapshot');
    final gmEvidence = jsonEncode({
      'format': 'scalajaca.context-receipt.v1',
      'digest': gmDigest,
      'omittedMessages': 0,
      'attachment': {
        'campaignId': campaign.id,
        'role': 'gameMaster',
        'revision': 8,
        'records': ['active-session', secretId],
        'fingerprint': await contentDigest('RPG frozen fingerprint')
      },
      'sourceSnapshot': 'SEKRET_MG historyczny tekst, bez zmiany ID'
    });
    await source.db.insert('chat_context_receipts', {
      'message_id': 'answer-${gmConversation.id}',
      'digest': gmDigest,
      'evidence': await source.cipher.seal(gmEvidence),
      'omitted': 0,
      'created': 889
    });
    await source.saveNote(
        'Notatka szyfrowana', 'Treść notatki po polsku', 'PERSONAL');
    await source.db.insert('tasks', {
      'id': 'task-preserved-id',
      'title': await source.cipher.seal('Wróć do analizy'),
      'done': 1,
      'created': 555
    });
    await source.setSetting('sourceOnly', 'nie przenoś');
    await source.db.insert('cost_reservations', {
      'id': 'no-cost-copy',
      'amount': 0.02,
      'created': 1,
      'provider': 'demo'
    });
  }

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    opened.clear();
    source = await open();
    target = await open();
    await target.setSetting('destinationSetting', 'zachowane');
    await populate();
    snapshot = await take(source);
  });
  tearDown(() async {
    for (final db in opened) {
      if (db.db.isOpen) await db.close();
    }
  });

  test(
      '16 tabel przechodzi do innego szyfru z ID, historią, checkpointem i dowodami',
      () async {
    expect(snapshot.counts.keys.toList(), BackupDataset.tables);
    expect(snapshot.counts.values, everyElement(greaterThan(0)));
    expect(snapshot.first('memory_collections')['vault_id'], isNull);
    final job = snapshot.first('memory_import_jobs');
    expect(job['cursor'], isNull);
    expect(job['page_offset'], 0);
    expect(job['status'], 'paused');
    expect(job['processed'], 123);
    expect(job['failed'], 2);
    expect(job['updated'], 777);
    await restore(snapshot);
    final restored = await take(target);
    expect(restored.counts, snapshot.counts);
    for (final table in BackupDataset.tables) {
      final before = snapshot.rows
          .where((r) => r['table'] == table)
          .map((r) => Map<String, Object?>.from(r['row'] as Map))
          .toList();
      final after = restored.rows
          .where((r) => r['table'] == table)
          .map((r) => r['row'])
          .toList();
      if (table == 'memory_documents') {
        for (var i = 0; i < before.length; i++) {
          before[i]['source_key'] = (after[i] as Map)['source_key'];
        }
      }
      if (table == 'messages') {
        for (final row in before) {
          if (['streaming', 'pending'].contains(row['status'])) {
            row['status'] = 'interrupted';
          }
        }
      }
      expect(after, before, reason: table);
    }
    final evidence = (await target.db.query('chat_context_receipts',
            where: 'digest=?', whereArgs: [originalDigest]))
        .single;
    expect(await target.cipher.open(evidence['evidence'] as String),
        originalEvidence);
    final historical =
        jsonDecode(originalEvidence)['attachment']['sources'][0] as Map;
    expect(
        await target.db.query('memory_documents',
            where: 'id=?', whereArgs: [historical['document']]),
        isEmpty);
    final context = AccessContext(
        principalId: 'local-owner',
        role: AccessRole.gameMaster,
        campaignId: campaignId,
        allowGmSecretContext: true);
    expect((await CampaignStore(target).readCheckpoint(context))!.goal,
        'Odnajdź posłańca');
    expect((await CampaignStore(target).audit(context)).map((e) => e.kind),
        contains('rollback'));
    expect(await target.setting('sourceOnly', 'brak'), 'brak');
    expect(await target.setting('destinationSetting', ''), 'zachowane');
    expect(await target.db.query('cost_reservations'), isEmpty);
    final sourceRaw = (await source.db.query('notes')).single['content'];
    final targetRaw = (await target.db.query('notes')).single['content'];
    expect(targetRaw, isNot(sourceRaw));
    expect(targetRaw, isNot(contains('Treść')));
    expect((await source.db.query('memory_collections')).single['vault_id'],
        'source-vault-capability');
    expect((await source.db.query('memory_import_jobs')).single['status'],
        'running');
  });

  test(
      'Indeksy i source_key są przeliczane kluczem celu tylko dla zatwierdzonego current state',
      () async {
    await restore(snapshot);
    final doc = (await target.db.query('memory_documents',
            where: 'approval=?', whereArgs: ['approved']))
        .single;
    final sourceDoc =
        snapshot.first('memory_documents', where: (r) => r['id'] == doc['id']);
    expect(doc['source_key'],
        await target.cipher.indexToken('path:badania/brama.md'));
    expect(doc['source_key'], isNot(sourceDoc['source_key']));
    final packet =
        await MemoryStore(target).retrieve(collectionId, 'bursztynowa');
    expect(packet.excerpts, isNotEmpty);
    expect(packet.excerpts.every((e) => e.revision == 2), isTrue);
    expect(
        (await MemoryStore(target).retrieve(collectionId, 'sekret')).excerpts,
        isEmpty);
    expect(
        (await MemoryStore(target).retrieve(collectionId, 'niezatwierdzony'))
            .excerpts,
        isEmpty);
    final gm = AccessContext(
        principalId: 'local-owner',
        role: AccessRole.gameMaster,
        campaignId: campaignId,
        allowGmSecretContext: true);
    final player = AccessContext(
        principalId: 'local-owner',
        role: AccessRole.rpgPlayer,
        campaignId: campaignId);
    expect(
        (await CampaignStore(target).contextPack(player, query: 'bursztynowa'))
            .recordIds,
        [canonicalId]);
    expect(
        (await CampaignStore(target).contextPack(gm, query: 'ukryty'))
            .recordIds,
        ['active-session']);
    expect(
        (await CampaignStore(target)
                .contextPack(gm, selectedRecordIds: [secretId]))
            .text,
        contains('SEKRET_MG'));
    expect(
        (await target.db
            .query('rpg_terms', where: 'record_id=?', whereArgs: [secretId])),
        isEmpty);
    expect(
        await target.db.query('rpg_terms',
            where: 'record_id=?', whereArgs: ['active-session']),
        isEmpty);
  });

  test('Błąd footera po ostatnim wierszu i anulowanie cofają wszystkie inserty',
      () async {
    Stream<Map<String, Object?>> broken() async* {
      yield* Stream.fromIterable(snapshot.rows);
      throw const FormatException('Niepoprawny footer GCM / brak EOF');
    }

    await expectLater(BackupDataset(target).restore(broken(), snapshot.counts),
        throwsFormatException);
    await expectEmptyTarget();
    var seen = 0;
    Stream<Map<String, Object?>> cancelled() async* {
      for (final row in snapshot.rows) {
        seen++;
        yield row;
      }
    }

    await expectLater(
        BackupDataset(target).restore(cancelled(), snapshot.counts,
            isCancelled: () => seen > 10),
        throwsStateError);
    await expectEmptyTarget();
    await restore(
        snapshot); // TEMP metadata zostały posprzątane po obu błędach.
  });

  test('Kolizja po wielu insertach odrzuca całość, nie nadpisuje celu',
      () async {
    final existing = Map<String, Object?>.from(snapshot.first('rpg_campaigns'));
    existing['name'] = await target.cipher.seal('Istniejąca kampania');
    existing['revision'] = 0;
    await target.db.insert('rpg_campaigns', existing);
    await expectLater(restore(snapshot), throwsA(isA<DatabaseException>()));
    expect(await target.db.query('memory_collections'), isEmpty);
    final preserved = (await target.db.query('rpg_campaigns')).single;
    expect(await target.cipher.open(preserved['name'] as String),
        'Istniejąca kampania');
    expect(await target.db.query('rpg_versions'), isEmpty);
    expect(await target.setting('destinationSetting', ''), 'zachowane');
  });

  test(
      'Child nie może zostać dopięty do istniejącego parenta pominiętego w kopii',
      () async {
    final existing =
        Map<String, Object?>.from(snapshot.first('memory_collections'));
    existing['name'] = await target.cipher.seal('Już istniejący projekt');
    await target.db.insert('memory_collections', existing);
    final forged = snapshot.copy()..removeTable('memory_collections');
    await expectLater(restore(forged), throwsFormatException);
    expect(await target.db.query('memory_documents'), isEmpty);
    expect((await target.db.query('memory_collections')).single['id'],
        collectionId);
  });

  test('Błędne role, GM flags i role dowodu nie przechodzą walidacji',
      () async {
    final role = snapshot.copy();
    role.first('messages')['role'] = 'system';
    await expectLater(restore(role), throwsFormatException);
    await expectEmptyTarget();
    final flags = snapshot.copy();
    flags.first('chat_scopes',
        where: (r) => (r['scope_key'] as String)
            .endsWith(':gameMaster'))['confidential'] = 0;
    await expectLater(restore(flags), throwsFormatException);
    await expectEmptyTarget();
    final downgrade = snapshot.copy();
    final scope = downgrade.first('chat_scopes',
        where: (r) => (r['scope_key'] as String).endsWith(':gameMaster'));
    scope['scope_key'] = 'rpg:$campaignId:rpgPlayer';
    scope['confidential'] = 0;
    await expectLater(restore(downgrade), throwsFormatException);
    await expectEmptyTarget();
  });

  test('Osierocony chunk, niezgodny current RPG i niepełny audyt cofają całość',
      () async {
    final orphan = snapshot.copy();
    orphan.first('memory_chunks')['revision'] = 99;
    await expectLater(restore(orphan), throwsFormatException);
    await expectEmptyTarget();
    final mismatched = snapshot.copy();
    final record = mismatched.first('rpg_records',
        where: (r) => r['record_id'] == canonicalId);
    final payload =
        jsonDecode(record['payload'] as String) as Map<String, dynamic>;
    payload['content'] = 'Treść niezgodna z historyczną wersją';
    record['payload'] = jsonEncode(payload);
    await expectLater(restore(mismatched), throwsFormatException);
    await expectEmptyTarget();
    final gap = snapshot.copy();
    gap.rows.removeWhere((r) =>
        r['table'] == 'rpg_events' && (r['row'] as Map)['revision'] == 2);
    gap.counts['rpg_events'] = gap.counts['rpg_events']! - 1;
    await expectLater(restore(gap), throwsFormatException);
    await expectEmptyTarget();
  });

  test(
      'Ścieżka traversal i obniżenie sekretu także w starej wersji są odrzucane',
      () async {
    final path = snapshot.copy();
    path.first('memory_documents')['path'] = '../spoza-vault.md';
    await expectLater(restore(path), throwsFormatException);
    await expectEmptyTarget();
    final secret = snapshot.copy();
    final oldChunk =
        secret.first('memory_chunks', where: (r) => r['revision'] == 1);
    oldChunk['body'] = 'GM_SECRET${(oldChunk['body'] as String).substring(9)}';
    await expectLater(restore(secret), throwsFormatException);
    await expectEmptyTarget();
    final active = snapshot.copy();
    active.first('rpg_versions',
            where: (r) => r['record_id'] == 'active-session')['visibility'] =
        'campaign';
    await expectLater(restore(active), throwsFormatException);
    await expectEmptyTarget();
  });

  test(
      'Strict columns, types, manifest i kolejność nie dopuszczają częściowego restore',
      () async {
    final extra = snapshot.copy();
    extra.first('memory_collections')['admin'] = true;
    await expectLater(restore(extra), throwsFormatException);
    await expectEmptyTarget();
    final typed = snapshot.copy();
    typed.first('memory_documents')['restricted'] = false;
    await expectLater(restore(typed), throwsFormatException);
    await expectEmptyTarget();
    final short = snapshot.copy();
    short.counts['tasks'] = short.counts['tasks']! + 1;
    await expectLater(restore(short), throwsFormatException);
    await expectEmptyTarget();
    final order = snapshot.copy();
    final last = order.rows.removeLast();
    order.rows.insert(0, last);
    await expectLater(restore(order), throwsFormatException);
    await expectEmptyTarget();
    final oversized = snapshot.copy();
    oversized.counts['tasks'] = BackupDataset.maxRows + 1;
    await expectLater(restore(oversized), throwsFormatException);
    await expectEmptyTarget();
  });

  test('Obcy owner jest odrzucany zarówno przez eksport, jak i restore',
      () async {
    final foreign = snapshot.copy();
    foreign.first('memory_collections')['owner_id'] = 'other-owner';
    await expectLater(restore(foreign), throwsFormatException);
    await expectEmptyTarget();
    await MemoryStore(source)
        .createCollection(name: 'Obcy projekt', ownerId: 'other-owner');
    await expectLater(take(source), throwsStateError);
  });

  test('Odbiorca musi odczytać cały snapshot zanim zwolni transakcję eksportu',
      () async {
    await expectLater(
        BackupDataset(source).exportSnapshot((counts, rows) async => 7),
        throwsStateError);
    final complete = await take(source);
    expect(complete.counts, snapshot.counts);
  });

  test(
      'Przywrócenie nie usuwa istniejących dokumentów, ustawień i ich indeksów',
      () async {
    final memory = MemoryStore(target);
    final project = await memory.createCollection(name: 'Istniejące dane');
    final doc =
        await memory.ingest(project.id, 'stare.md', 'Zachowany heliotrop');
    await memory.approve(doc.id, doc.revision);
    final indexBefore =
        await target.db.query('memory_terms', orderBy: 'term,chunk_id');
    await restore(snapshot);
    final oldChunks = (await target.db.query('memory_chunks',
            where: 'document_id=?', whereArgs: [doc.id]))
        .map((r) => r['id'])
        .toSet();
    final indexAfter =
        (await target.db.query('memory_terms', orderBy: 'term,chunk_id'))
            .where((r) => oldChunks.contains(r['chunk_id']))
            .toList();
    expect(indexAfter, indexBefore);
    expect(
        (await memory.retrieve(project.id, 'heliotrop')).excerpts, isNotEmpty);
    expect(await target.setting('destinationSetting', ''), 'zachowane');
  });

  test(
      'Legalne CRLF, CR, puste pliki, Unicode i długie linie zachowują kompletną historię',
      () async {
    final memory = MemoryStore(source);
    final collection =
        await memory.createCollection(name: 'Granice normalizacji');
    final contents = <String>[
      '',
      '\n',
      '\r\n',
      '\r',
      'Pierwsza\r\nDruga',
      'Pierwsza\rDruga\r',
      'Pierwsza\nDruga\r\nTrzecia\rCzwarta\n',
      List.filled(2701, 'a').join(),
      List.filled(1800, '😀').join(),
      'Start\r\n${List.filled(1801, 'ż').join()}\r\nKoniec'
    ];
    for (var i = 0; i < contents.length; i++) {
      await memory.ingest(collection.id, 'format-$i.md', contents[i]);
    }
    final extended = await take(source);
    await restore(extended);
    final docs = await MemoryStore(target).documents(collection.id, limit: 30);
    expect(docs, hasLength(contents.length));
    for (final document in docs) {
      final i = int.parse(document.path.substring(7, document.path.length - 3));
      expect(document.bytes, utf8.encode(contents[i]).length);
      expect(document.hash, await contentDigest(contents[i]));
    }
  });

  test(
      'Brak fragmentów niepustej wersji i nieciągłe linie odrzucają cały restore',
      () async {
    final missing = snapshot.copy();
    final chunk =
        missing.first('memory_chunks', where: (r) => r['revision'] == 1);
    final docId = chunk['document_id'];
    final prior = missing.rows.length;
    missing.rows.removeWhere((e) =>
        e['table'] == 'memory_chunks' &&
        (e['row'] as Map)['document_id'] == docId &&
        (e['row'] as Map)['revision'] == 1);
    missing.counts['memory_chunks'] =
        missing.counts['memory_chunks']! - (prior - missing.rows.length);
    await expectLater(restore(missing), throwsFormatException);
    await expectEmptyTarget();
    final gap = snapshot.copy();
    final changed = gap.first('memory_chunks');
    changed['start_line'] = (changed['start_line'] as int) + 1;
    changed['end_line'] = (changed['end_line'] as int) + 1;
    await expectLater(restore(gap), throwsFormatException);
    await expectEmptyTarget();
  });

  test(
      'Historyczny checkbox cytacji bez źródła jest zachowany jako NIEZWERYFIKOWANE',
      () async {
    final legacy = snapshot.copy();
    for (final envelope in legacy.rows
        .where((e) => ['rpg_versions', 'rpg_records'].contains(e['table']))) {
      final row = envelope['row'] as Map<String, Object?>;
      if (row['record_id'] != canonicalId) continue;
      final payload =
          jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      payload['citation'] = {
        'sourceId': '',
        'title': '',
        'page': '',
        'userVerified': true
      };
      row['payload'] = jsonEncode(payload);
    }
    await restore(legacy);
    final gm = AccessContext(
        principalId: 'local-owner',
        role: AccessRole.gameMaster,
        campaignId: campaignId,
        allowGmSecretContext: true);
    final pack =
        await CampaignStore(target).contextPack(gm, query: 'bursztynowa');
    expect(pack.text, contains('NIEZWERYFIKOWANE'));
    final returned = await take(target);
    expect(
        returned.first('rpg_records',
            where: (r) => r['record_id'] == canonicalId)['payload'],
        legacy.first('rpg_records',
            where: (r) => r['record_id'] == canonicalId)['payload']);
  });

  test('Ponowne połączenie vaultu odmawia obcemu ownerowi i nie zmienia stanu',
      () async {
    await restore(snapshot);
    final before = await target.db.query('memory_import_jobs');
    await expectLater(
        MemoryStore(target).reconnectVault(collectionId, 'unauthorized-handle',
            ownerId: 'other-owner'),
        throwsStateError);
    expect((await target.db.query('memory_collections')).single['vault_id'],
        isNull);
    expect(await target.db.query('memory_import_jobs'), before);
  });

  test(
      'Nowe SAF resetuje stary kursor, zachowując dokumenty, wersje i checkpoint analizy',
      () async {
    await restore(snapshot);
    final memory = MemoryStore(target);
    final documents = await target.db.query('memory_documents', orderBy: 'id');
    final versions = await target.db
        .query('memory_versions', orderBy: 'document_id,revision');
    final chunks = await target.db.query('memory_chunks', orderBy: 'id');
    final checkpoints = await target.db.query('analysis_checkpoints');
    await target.db.update('memory_collections', {'vault_id': 'old-grant'},
        where: 'id=?', whereArgs: [collectionId]);
    await target.db.update(
        'memory_import_jobs',
        {
          'cursor': await target.cipher.seal('content://old-tree'),
          'page_offset': 27,
          'status': 'running',
          'processed': 55,
          'failed': 3
        },
        where: 'collection_id=?',
        whereArgs: [collectionId]);
    await memory.reconnectVault(collectionId, 'new-explicit-SAF-grant');
    expect((await memory.collection(collectionId)).vaultId,
        'new-explicit-SAF-grant');
    final job = (await target.db.query('memory_import_jobs')).single;
    expect(job['cursor'], isNull);
    expect(job['page_offset'], 0);
    expect(job['status'], 'paused');
    expect(job['processed'], 0);
    expect(job['failed'], 0);
    expect(await target.db.query('memory_documents', orderBy: 'id'), documents);
    expect(
        await target.db
            .query('memory_versions', orderBy: 'document_id,revision'),
        versions);
    expect(await target.db.query('memory_chunks', orderBy: 'id'), chunks);
    expect(await target.db.query('analysis_checkpoints'), checkpoints);
  });
}
