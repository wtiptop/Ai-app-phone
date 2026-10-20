import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/backup/backup_dataset.dart';
import 'package:scalajaca/memory/memory_store.dart';
import 'package:scalajaca/rpg/campaign.dart';
import 'package:scalajaca/rpg/campaign_store.dart';
import 'package:scalajaca/security/memory_access.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Testy integracyjne małych, wyłącznie fikcyjnych zbiorów. Kontener kryptografii
/// ma osobne testy; tutaj sprawdzamy trwałą semantykę workflow po rekey/restore.
void main() {
  late AppDatabase source, target;
  late _RecordingCipher targetCipher;

  Future<void> copy() => BackupDataset(source).exportSnapshot(
        (counts, rows) => BackupDataset(target).restore(rows, counts),
      );

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    source = await AppDatabase.open(ContentCipher(MemorySecrets()),
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    targetCipher = _RecordingCipher(MemorySecrets());
    target = await AppDatabase.open(targetCipher,
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });
  tearDown(() async {
    await source.close();
    await target.close();
  });

  test('Stronicowany recall i wybór źródeł zachowują zakres po pełnym restore',
      () async {
    final memory = MemoryStore(source);
    final collection = await memory.createCollection(
        name: 'Fikcyjny projekt A', vaultId: 'source-only-SAF-handle');
    final other = await memory.createCollection(name: 'Fikcyjny projekt B');
    final documents = <MemoryDocument>[];
    for (var index = 0; index < 7; index++) {
      final document = await memory.ingest(collection.id, 'notes/$index.md',
          'Bursztynowiec źródło $index CURRENT_$index');
      await memory.approve(document.id, document.revision);
      documents.add(document);
    }
    final foreign = await memory.ingest(
        other.id, 'other.md', 'Bursztynowiec FOREIGN_PROJECT_ONLY');
    await memory.approve(foreign.id, foreign.revision);
    await memory.ingest(
        collection.id, 'pending.md', 'Bursztynowiec UNAPPROVED_ONLY');
    final secret = await memory.ingest(
        collection.id, 'GM_SECRET.md', 'Bursztynowiec GM_VAULT_ONLY');
    final first = await memory.search(collection.id, 'bursztynowiec', limit: 2);
    final second = await memory.search(collection.id, 'bursztynowiec',
        limit: 2, offset: 2);
    expect(first.total, 7);
    expect(first.hasMore, isTrue);
    expect(
        first.excerpts
            .map((e) => e.chunkId)
            .toSet()
            .intersection(second.excerpts.map((e) => e.chunkId).toSet()),
        isEmpty);
    final oldSelection = await memory
        .retrieveSelected(collection.id, [first.excerpts.first.chunkId]);
    await memory.validate(oldSelection);
    final selectedDocument =
        documents.singleWhere((d) => d.id == first.excerpts.first.documentId);
    final revised = await memory.ingest(collection.id, selectedDocument.path,
        'Bursztynowiec NEW_APPROVED_VERSION');
    await memory.approve(revised.id, revised.revision);
    final revokedId = second.excerpts.first.documentId;
    await memory.revoke(revokedId);
    await memory.saveCheckpoint(collection.id,
        goal: 'Fikcyjna długa analiza',
        findings: 'Własne ustalenia użytkownika',
        nextStep: 'Sprawdź aktualną wersję źródła',
        sources: oldSelection.text);
    await copy();

    final restored = MemoryStore(target);
    expect((await restored.collection(collection.id)).vaultId, isNull);
    await expectLater(restored.validate(oldSelection), throwsStateError);
    await expectLater(
        restored
            .retrieveSelected(collection.id, [first.excerpts.first.chunkId]),
        throwsStateError);
    final current =
        await restored.search(collection.id, 'bursztynowiec', limit: 2);
    expect(current.total, 6);
    final all = <String>{};
    for (var offset = 0; offset < current.total; offset += 2) {
      final page = await restored.search(collection.id, 'bursztynowiec',
          limit: 2, offset: offset);
      expect(page.offset, offset);
      for (final excerpt in page.excerpts) {
        expect(all.add(excerpt.chunkId), isTrue,
            reason: 'Stronicowanie nie może powtarzać źródeł.');
        expect(excerpt.text, isNot(contains('FOREIGN_PROJECT_ONLY')));
        expect(excerpt.text, isNot(contains('UNAPPROVED_ONLY')));
        expect(excerpt.text, isNot(contains('GM_VAULT_ONLY')));
      }
    }
    expect(all, hasLength(6));
    final foreignHits = await restored.search(other.id, 'bursztynowiec');
    final secretChunk = (await target.db.query('memory_chunks',
            where: 'document_id=?', whereArgs: [secret.id]))
        .single;
    for (final forbidden in [
      foreignHits.excerpts.single.chunkId,
      secretChunk['id'] as String,
      second.excerpts.first.chunkId,
      'missing-chunk-id',
    ]) {
      await expectLater(
          restored.retrieveSelected(
              collection.id, [current.excerpts.first.chunkId, forbidden]),
          throwsStateError,
          reason: 'Cały wybór ma zostać odrzucony bez częściowego pakietu.');
    }
    final packet = await restored
        .retrieveSelected(collection.id, [current.excerpts.first.chunkId]);
    await restored.validate(packet);
    expect(packet.bytes, lessThanOrEqualTo(2200));
    expect((await restored.checkpoints(collection.id)).single.sources,
        oldSelection.text,
        reason: 'Historyczny checkpoint nie staje się aktualnym źródłem.');
  });

  test('Strony checkpointów i pojedynczy odczyt nie mieszają projektów',
      () async {
    final memory = MemoryStore(source);
    final a = await memory.createCollection(name: 'Analiza A');
    final b = await memory.createCollection(name: 'Analiza B');
    final foreign = await memory.saveCheckpoint(b.id,
        goal: 'OTHER_CHECKPOINT_ONLY', findings: '', nextStep: '', sources: '');
    final ids = <String>{};
    for (var index = 0; index < 35; index++) {
      final checkpoint = await memory.saveCheckpoint(a.id,
          goal: 'Fikcyjna analiza $index',
          findings: 'Własny wynik $index',
          nextStep: 'Krok $index',
          sources: 'Źródło testowe $index');
      ids.add(checkpoint.id);
    }
    await copy();
    final restored = MemoryStore(target);
    final seen = <String>{};
    for (var offset = 0; offset < 35; offset += 5) {
      final page = await restored.checkpoints(a.id, limit: 5, offset: offset);
      expect(page, hasLength(5));
      for (final item in page) {
        expect(seen.add(item.id), isTrue);
        final loaded = await restored.checkpoint(a.id, item.id);
        expect(loaded.goal, item.goal);
        expect(loaded.findings, item.findings);
      }
    }
    expect(seen, ids);
    await expectLater(restored.checkpoint(a.id, foreign.id), throwsStateError);
    await expectLater(
        restored.checkpoint(a.id, ids.first, ownerId: 'foreign-owner'),
        throwsStateError);
    expect(await restored.checkpoints(a.id, limit: 5, offset: 35), isEmpty);
  });

  test('Wznowienie dawnej sesji tworzy nową rewizję i przechodzi backup',
      () async {
    final campaigns = CampaignStore(source);
    final campaign = await campaigns.create(
        name: 'Fikcyjna kampania ciągłości',
        edition: 'Własna edycja testowa',
        ownerId: 'local-owner');
    final gm = AccessContext(
        principalId: 'local-owner',
        role: AccessRole.gameMaster,
        campaignId: campaign.id,
        allowGmSecretContext: true);
    CampaignRecord fact(String text, {bool secret = false}) => CampaignRecord(
        id: 'fixture-lore',
        campaignId: campaign.id,
        title: 'Fikcyjny fakt',
        content: text,
        kind: CampaignRecordKind.canon,
        visibility:
            secret ? MemoryVisibility.gmSecret : MemoryVisibility.campaign,
        citation: const LoreCitation(
            sourceId: 'fixture-source',
            title: 'Własny testowy kanon',
            authority: LoreAuthority.approvedCampaignCanon,
            edition: 'Własna edycja testowa',
            page: 'wpis 1',
            userVerified: true));
    CampaignCheckpoint checkpoint(String scene) => CampaignCheckpoint(
        goal: 'Fikcyjny cel',
        scene: scene,
        openThreads: 'Testowy wątek',
        party: 'Własne testowe postacie',
        worldClock: 'Testowy zegar');
    await campaigns.putRecord(
        fact('OLD_LORE HISTORY_ONLY_NEEDLE', secret: true), gm,
        expectedRevision: 0, userApproved: true);
    await campaigns.saveCheckpoint(checkpoint('OLD_GM_SCENE'), gm,
        expectedRevision: 1);
    await campaigns.putRecord(fact('CURRENT_LORE'), gm,
        expectedRevision: 2, userApproved: true);
    await campaigns.saveCheckpoint(checkpoint('NEW_GM_SCENE'), gm,
        expectedRevision: 3);
    final before =
        await source.db.query('rpg_versions', orderBy: 'record_id,revision');
    expect(await campaigns.resumeCheckpoint(2, gm, expectedRevision: 4), 5);
    expect((await campaigns.readCheckpoint(gm))!.scene, 'OLD_GM_SCENE');
    expect(
        (await campaigns.listRecords(gm))
            .singleWhere((r) => r.id == 'fixture-lore')
            .content,
        'CURRENT_LORE');
    for (final original in before) {
      final after = (await source.db.query('rpg_versions',
              where: 'campaign_id=? AND record_id=? AND revision=?',
              whereArgs: [
            campaign.id,
            original['record_id'],
            original['revision']
          ]))
          .single;
      expect(after, original, reason: 'Historia nie może być nadpisana.');
    }
    await copy();
    final restored = CampaignStore(target);
    expect((await restored.readCampaign(campaign.id, gm)).revision, 5);
    expect((await restored.readCheckpoint(gm))!.scene, 'OLD_GM_SCENE');
    expect((await restored.audit(gm)).first.kind, 'checkpointSaved');
    expect(await restored.resumeCheckpoint(4, gm, expectedRevision: 5), 6);
    expect((await restored.readCheckpoint(gm))!.scene, 'NEW_GM_SCENE');
    expect(
        (await restored.listRecords(gm))
            .singleWhere((r) => r.id == 'fixture-lore')
            .content,
        'CURRENT_LORE');
    final firstPage = await restored.checkpointHistory(gm, limit: 2);
    expect(firstPage.map((e) => e.record.revision), [6, 5]);
    final secondPage =
        await restored.checkpointHistory(gm, limit: 2, beforeRevision: 5);
    expect(secondPage.map((e) => e.record.revision), [4, 2]);
    final comparison =
        await restored.compareRecordVersion('fixture-lore', 1, gm);
    expect(comparison.historical.content, 'OLD_LORE HISTORY_ONLY_NEEDLE');
    expect(comparison.current?.content, 'CURRENT_LORE');
    expect(comparison.changedFields, contains('Treść'));
    expect(comparison.changedFields, contains('Widoczność'));
    final player = AccessContext(
        principalId: 'local-owner',
        role: AccessRole.rpgPlayer,
        campaignId: campaign.id);
    expect((await restored.contextPack(player, query: 'history')).recordIds,
        isEmpty,
        reason:
            'Stara tajna wersja nie zasila indeksu jawnej bieżącej wersji.');
    final head = (await restored.readCampaign(campaign.id, gm)).revision;
    for (final scope in [
      AccessContext(
          principalId: 'local-owner',
          role: AccessRole.rpgPlayer,
          campaignId: campaign.id,
          allowGmSecretContext: true),
      AccessContext(
          principalId: 'local-owner',
          role: AccessRole.gameMaster,
          campaignId: campaign.id),
      AccessContext(
          principalId: 'foreign-owner',
          role: AccessRole.gameMaster,
          campaignId: campaign.id,
          allowGmSecretContext: true),
    ]) {
      for (final action in <Future<void> Function()>[
        () async {
          await restored.checkpointHistory(scope);
        },
        () async {
          await restored.recordHistory('fixture-lore', scope);
        },
        () async {
          await restored.compareRecordVersion('fixture-lore', 1, scope);
        },
        () async {
          await restored.resumeCheckpoint(2, scope, expectedRevision: head);
        },
      ]) {
        targetCipher.opens = 0;
        await expectLater(action(), throwsStateError);
        expect(targetCipher.opens, 0,
            reason: 'Odmowa roli musi poprzedzać odszyfrowanie historii.');
      }
    }
    expect((await restored.readCampaign(campaign.id, gm)).revision, head);
    for (final purpose in MemoryPurpose.values
        .where((purpose) => purpose != MemoryPurpose.localView)) {
      for (final action in <Future<void> Function()>[
        () async {
          await restored.checkpointHistory(gm, purpose: purpose);
        },
        () async {
          await restored.recordHistory('fixture-lore', gm, purpose: purpose);
        },
        () async {
          await restored.compareRecordVersion('fixture-lore', 1, gm,
              purpose: purpose);
        },
      ]) {
        targetCipher.opens = 0;
        await expectLater(action(), throwsStateError);
        expect(targetCipher.opens, 0,
            reason: 'Historia jest tylko lokalnym odczytem, także dla MG.');
      }
    }
    final rawIndex = jsonEncode(await target.db.query('rpg_terms'));
    expect(rawIndex, isNot(contains('GM_SCENE')));
    expect(
        await target.db.query('rpg_terms',
            where: 'record_id=?', whereArgs: ['active-session']),
        isEmpty);
  });
}

class _RecordingCipher extends ContentCipher {
  _RecordingCipher(super.secrets);
  int opens = 0;
  @override
  Future<String> open(String value) {
    opens++;
    return super.open(value);
  }
}
