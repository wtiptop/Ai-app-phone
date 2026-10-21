import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/rpg/campaign.dart';
import 'package:scalajaca/rpg/campaign_store.dart';
import 'package:scalajaca/security/memory_access.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase database;
  late CampaignStore store;
  late StoredCampaign campaign;
  late MemorySecrets secrets;
  late Directory scratch;
  final opened = <AppDatabase>[];
  AccessContext scope(
          {String? id,
          String owner = 'local-owner',
          AccessRole role = AccessRole.gameMaster,
          bool secret = true,
          String? project}) =>
      AccessContext(
          principalId: owner,
          role: role,
          campaignId: id ?? campaign.id,
          allowGmSecretContext: secret,
          projectId: project);
  CampaignCheckpoint point(String goal) => CampaignCheckpoint(
      goal: goal,
      scene: 'Scena $goal',
      openThreads: 'Wątek $goal',
      party: 'Własne postacie',
      worldClock: 'Zegar $goal');
  CampaignRecord lore(String text, {bool secret = false}) => CampaignRecord(
      id: 'gate',
      campaignId: campaign.id,
      title: 'Brama',
      content: text,
      kind: CampaignRecordKind.canon,
      visibility:
          secret ? MemoryVisibility.gmSecret : MemoryVisibility.campaign,
      citation: LoreCitation(
          sourceId: 'own/gate',
          title: 'Własny kanon',
          authority: LoreAuthority.approvedCampaignCanon,
          edition: 'Własna edycja',
          page: 'wpis 1',
          userVerified: true));
  Future<void> open() async {
    database = await AppDatabase.open(ContentCipher(secrets),
        factory: databaseFactoryFfi, path: p.join(scratch.path, 'history.db'));
    opened.add(database);
    store = CampaignStore(database);
  }

  Future<void> seed() async {
    await store.putRecord(lore('Brama otwarta'), scope(),
        expectedRevision: 0, userApproved: true);
    await store.saveCheckpoint(point('Dawny cel'), scope(),
        expectedRevision: 1);
    await store.putRecord(
        lore('Brama zamknięta po bieżących wydarzeniach'), scope(),
        expectedRevision: 2, userApproved: true);
    await store.saveCheckpoint(point('Najnowszy cel'), scope(),
        expectedRevision: 3);
  }

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    secrets = MemorySecrets();
    opened.clear();
    final parent = await Directory(
            p.join(Directory.current.path, 'work', 'campaign-history-tests'))
        .create(recursive: true);
    scratch = await parent.createTemp('run-');
    await open();
    campaign = await store.create(
        name: 'Własna kampania historii',
        edition: 'Własna edycja',
        ownerId: 'local-owner');
  });
  tearDown(() async {
    for (final db in opened) {
      if (db.db.isOpen) {
        await db.close();
      }
    }
    final parent = p.absolute(
        p.join(Directory.current.path, 'work', 'campaign-history-tests'));
    if (!p.isWithin(parent, p.absolute(scratch.path))) {
      throw StateError('Sprzątanie poza katalogiem testów.');
    }
    await scratch.delete(recursive: true);
  });

  test(
      'Historia sesji i wersji lore przeżywa restart, sam odczyt niczego nie dopisuje',
      () async {
    await seed();
    final versions =
        await database.db.query('rpg_versions', orderBy: 'revision,record_id');
    final events = await database.db.query('rpg_events', orderBy: 'revision');
    await database.close();
    await open();
    final history = await store.checkpointHistory(scope());
    expect(history.map((e) => e.record.revision), [4, 2]);
    expect(
        history.map((e) => e.checkpoint.goal), ['Najnowszy cel', 'Dawny cel']);
    expect(history.first.isCurrent, isTrue);
    expect(history.last.isCurrent, isFalse);
    expect(history.every((e) => e.eventKind == 'checkpointSaved'), isTrue);
    expect(
        (await store.recordHistory('gate', scope()))
            .map((e) => e.record.content),
        ['Brama zamknięta po bieżących wydarzeniach', 'Brama otwarta']);
    expect(
        await database.db.query('rpg_versions', orderBy: 'revision,record_id'),
        versions);
    expect(await database.db.query('rpg_events', orderBy: 'revision'), events);
    expect((await store.readCampaign(campaign.id, scope())).revision, 4);
    expect(() => history.add(history.first), throwsUnsupportedError);
  });

  test(
      'Keyset stronicuje duże archiwum bez pominięcia po dopisaniu nowej sesji',
      () async {
    for (var i = 0; i < 27; i++) {
      await store.saveCheckpoint(point('Sesja ${i + 1}'), scope(),
          expectedRevision: i);
    }
    final first = await store.checkpointHistory(scope(), limit: 10);
    await store.saveCheckpoint(point('Dopisano między stronami'), scope(),
        expectedRevision: 27);
    final second = await store.checkpointHistory(scope(),
        limit: 10, beforeRevision: first.last.record.revision);
    final third = await store.checkpointHistory(scope(),
        limit: 10, beforeRevision: second.last.record.revision);
    final revisions =
        [...first, ...second, ...third].map((e) => e.record.revision).toList();
    expect(revisions, List.generate(27, (i) => 27 - i));
    expect(revisions.toSet(), hasLength(27));
    expect(
        (await store.checkpointHistory(scope(), limit: 1))
            .single
            .record
            .revision,
        28);
    await expectLater(
        store.checkpointHistory(scope(), limit: 101), throwsArgumentError);
    await expectLater(store.recordHistory('gate', scope(), beforeRevision: 0),
        throwsArgumentError);
  });

  test(
      'Wznowienie dopisuje tylko nowy checkpoint, zachowując świat i historyczne szyfrogramy',
      () async {
    await seed();
    final old =
        await database.db.query('rpg_versions', orderBy: 'revision,record_id');
    final currentLore = (await database.db
            .query('rpg_records', where: 'record_id=?', whereArgs: ['gate']))
        .single;
    final terms = await database.db.query('rpg_terms', orderBy: 'term');
    expect(await store.resumeCheckpoint(2, scope(), expectedRevision: 4), 5);
    expect((await store.readCheckpoint(scope()))!.goal, 'Dawny cel');
    expect(
        (await database.db.query('rpg_records',
                where: 'record_id=?', whereArgs: ['gate']))
            .single,
        currentLore);
    expect(
        await database.db.query('rpg_versions',
            where: 'revision<=4', orderBy: 'revision,record_id'),
        old);
    expect(await database.db.query('rpg_terms', orderBy: 'term'), terms);
    final current = (await store.listRecords(scope()))
        .firstWhere((r) => r.id == 'active-session');
    expect(current.citation.sourceId, 'history-checkpoint:2');
    expect(current.citation.page, contains('zapis jako rewizja 5'));
    expect(current.title, contains('bez zmiany kanonu'));
    final pack = await store.contextPack(scope(), query: 'brama');
    expect(pack.recordIds, ['gate', 'active-session']);
    expect(pack.text.indexOf('Brama zamknięta po bieżących wydarzeniach'),
        lessThan(pack.text.indexOf('Dawny cel')));
    expect(pack.text, contains('rewizja zapisu notatki r5'));
    expect(pack.text,
        contains('poziom: notatka MG, nie ustala bieżącego kanonu świata'));
    expect(pack.text, contains('Tytuł wpisu: Brama\nTreść:\n'));
    final sessionText =
        pack.text.substring(pack.text.indexOf('[active-session;'));
    expect(sessionText, isNot(contains('poziom: approvedCampaignCanon')));
    expect((await store.audit(scope())).first.kind, 'checkpointSaved');
    final history = await store.checkpointHistory(scope());
    expect(history.map((e) => e.record.revision), [5, 4, 2]);
    expect(history.first.isCurrent, isTrue);
    expect(
        await database.db.query('rpg_terms',
            where: 'record_id=?', whereArgs: ['active-session']),
        isEmpty);
  });

  test(
      'Historia i wznowienie wymagają właściwej kampanii, właściciela oraz jawnego MG',
      () async {
    await seed();
    final other = await store.create(
        name: 'Druga pusta kampania', edition: 'Inna', ownerId: 'local-owner');
    expect(await store.checkpointHistory(scope(id: other.id)), isEmpty);
    await expectLater(
        store.compareRecordVersion('gate', 1, scope(id: other.id)),
        throwsStateError);
    for (final access in [
      scope(owner: 'other-owner'),
      scope(role: AccessRole.rpgPlayer),
      scope(role: AccessRole.owner),
      scope(secret: false),
      scope(project: 'wrong-project')
    ]) {
      await expectLater(store.checkpointHistory(access), throwsStateError);
      await expectLater(store.recordHistory('gate', access), throwsStateError);
      await expectLater(
          store.compareRecordVersion('gate', 1, access), throwsStateError);
      await expectLater(store.resumeCheckpoint(2, access, expectedRevision: 4),
          throwsStateError);
    }
    expect((await store.readCampaign(campaign.id, scope())).revision, 4);
  });

  test(
      'Niepoprawny szyfrogram dawnego sekretu nie jest odszyfrowany bez autoryzacji',
      () async {
    await seed();
    await database.db.insert('rpg_versions', {
      'campaign_id': campaign.id,
      'record_id': 'poison',
      'revision': 1,
      'kind': 'canon',
      'visibility': 'gmSecret',
      'approved': 1,
      'authority': 0,
      'edition': 'Własna edycja',
      'payload': 'to nie jest zaszyfrowana treść'
    });
    for (final access in [
      scope(role: AccessRole.rpgPlayer),
      scope(secret: false),
      scope(owner: 'other')
    ]) {
      await expectLater(
          store.recordHistory('poison', access), throwsStateError);
      await expectLater(
          store.compareRecordVersion('poison', 1, access), throwsStateError);
    }
    await expectLater(
        store.recordHistory('poison', scope(), purpose: MemoryPurpose.export),
        throwsStateError);
  });

  test(
      'Archiwum nie jest automatycznym źródłem modelu, indeksu, recenzji ani eksportu',
      () async {
    await seed();
    for (final purpose
        in MemoryPurpose.values.where((p) => p != MemoryPurpose.localView)) {
      await expectLater(
          store.checkpointHistory(scope(), purpose: purpose), throwsStateError);
      await expectLater(store.recordHistory('gate', scope(), purpose: purpose),
          throwsStateError);
      await expectLater(
          store.compareRecordVersion('gate', 1, scope(), purpose: purpose),
          throwsStateError);
      await expectLater(
          store.resumeCheckpoint(2, scope(),
              expectedRevision: 4, purpose: purpose),
          throwsStateError);
    }
    final player = scope(role: AccessRole.rpgPlayer);
    expect(
        (await store.contextPack(player, query: 'otwarta')).recordIds, isEmpty);
    expect((await store.contextPack(player, query: 'zamknięta')).recordIds,
        ['gate']);
    expect(
        (await store.contextPack(player)).text, isNot(contains('Dawny cel')));
  });

  test(
      'Konflikt rewizji nie dopisuje niczego, równoległe wznowienia mają jednego zwycięzcę',
      () async {
    await seed();
    final before =
        await database.db.query('rpg_versions', orderBy: 'revision,record_id');
    await expectLater(store.resumeCheckpoint(2, scope(), expectedRevision: 3),
        throwsStateError);
    expect(
        await database.db.query('rpg_versions', orderBy: 'revision,record_id'),
        before);
    Future<Object> resume(int revision) async {
      try {
        return await store.resumeCheckpoint(revision, scope(),
            expectedRevision: 4);
      } catch (e) {
        return e;
      }
    }

    final result = await Future.wait([resume(2), resume(4)]);
    expect(result.whereType<int>(), [5]);
    expect(result.whereType<StateError>(), hasLength(1));
    expect((await store.audit(scope())).length, 5);
  });

  test(
      'Wznowienie odrzuca rewizję lore, przyszłą, zerową i zakres innej kampanii',
      () async {
    await seed();
    await expectLater(store.resumeCheckpoint(1, scope(), expectedRevision: 4),
        throwsStateError);
    await expectLater(store.resumeCheckpoint(0, scope(), expectedRevision: 4),
        throwsRangeError);
    await expectLater(store.resumeCheckpoint(99, scope(), expectedRevision: 4),
        throwsRangeError);
    expect((await store.readCampaign(campaign.id, scope())).revision, 4);
  });

  test(
      'Rollback zachowuje archiwum; wznowienie nie odwraca późniejszego rollbacku świata',
      () async {
    await seed();
    await store.rollback(2, scope(), expectedRevision: 4);
    final history = await store.checkpointHistory(scope());
    expect(history.map((e) => e.record.revision), [5, 4, 2]);
    expect(history.first.eventKind, 'rollback');
    expect(history.first.isCurrent, isTrue);
    expect(history.first.checkpoint.goal, 'Dawny cel');
    await store.resumeCheckpoint(4, scope(), expectedRevision: 5);
    expect((await store.readCheckpoint(scope()))!.goal, 'Najnowszy cel');
    final loreRecord =
        (await store.listRecords(scope())).firstWhere((r) => r.id == 'gate');
    expect(loreRecord.content, 'Brama otwarta');
    expect(loreRecord.revision, 5);
    await store.rollback(0, scope(), expectedRevision: 6);
    final absent = await store.compareRecordVersion('gate', 1, scope());
    expect(absent.current, isNull);
    expect(absent.changedFields,
        contains('Wpis nie występuje w bieżącym stanie świata'));
    expect((await store.checkpointHistory(scope())).every((e) => !e.isCurrent),
        isTrue);
    await store.resumeCheckpoint(2, scope(), expectedRevision: 7);
    expect((await store.listRecords(scope())).map((r) => r.id),
        ['active-session']);
  });

  test('Podgląd zmian zachowuje dawny sekret po publicznej edycji tylko dla MG',
      () async {
    await store.putRecord(
        lore('SEKRET_MG bursztynowiec', secret: true), scope(),
        expectedRevision: 0, userApproved: true);
    await store.putRecord(lore('Jawna brama'), scope(),
        expectedRevision: 1, userApproved: true);
    final diff = await store.compareRecordVersion('gate', 1, scope());
    expect(diff.historical.visibility, MemoryVisibility.gmSecret);
    expect(diff.current!.content, 'Jawna brama');
    expect(diff.changedFields, containsAll(['Treść', 'Widoczność']));
    expect(() => diff.changedFields.add('fałsz'), throwsUnsupportedError);
    final player = scope(role: AccessRole.rpgPlayer);
    expect((await store.listRecords(player)).single.content, 'Jawna brama');
    expect((await store.contextPack(player, query: 'bursztynowiec')).recordIds,
        isEmpty);
    await expectLater(store.recordHistory('gate', player), throwsStateError);
    await expectLater(
        store.compareRecordVersion('gate', 1, player), throwsStateError);
    final history = await store.recordHistory('gate', scope());
    expect(() => history.first.checkpoint, throwsStateError);
  });

  test(
      'Białe znaki w identyfikatorze, tytule lub stronie nie nadają weryfikacji lore',
      () {
    for (final values in [
      [' ', 'Źródło', '1'],
      ['source', '\t', '1'],
      ['source', 'Źródło', '\n']
    ]) {
      final citation = LoreCitation(
          sourceId: values[0],
          title: values[1],
          page: values[2],
          authority: LoreAuthority.approvedCampaignCanon,
          edition: 'Własna edycja',
          userVerified: true);
      expect(citation.verification, LoreVerification.unverified);
      expect(
          const LorePolicy().prioritize([citation], edition: 'Własna edycja'),
          isEmpty);
    }
  });
}
