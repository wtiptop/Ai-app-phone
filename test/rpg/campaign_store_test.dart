import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/rpg/campaign.dart';
import 'package:scalajaca/rpg/campaign_schema.dart';
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
          String owner = 'owner',
          AccessRole role = AccessRole.gameMaster,
          bool secret = true,
          String? project}) =>
      AccessContext(
          principalId: owner,
          role: role,
          campaignId: id ?? campaign.id,
          allowGmSecretContext: secret,
          projectId: project);
  CampaignRecord fact(String id, String text,
          {bool secret = false,
          CampaignRecordKind kind = CampaignRecordKind.canon,
          LoreAuthority authority = LoreAuthority.approvedCampaignCanon,
          String edition = 'Własna edycja',
          String? page = 'wpis 1',
          bool verified = true}) =>
      CampaignRecord(
          id: id,
          campaignId: campaign.id,
          title: 'Tytuł $id',
          content: text,
          kind: kind,
          visibility:
              secret ? MemoryVisibility.gmSecret : MemoryVisibility.campaign,
          citation: LoreCitation(
              sourceId: 'manual/$id',
              title: 'Własny kanon',
              authority: authority,
              edition: edition,
              page: page,
              userVerified: verified));
  Future<void> open() async {
    database = await AppDatabase.open(ContentCipher(secrets),
        factory: databaseFactoryFfi, path: p.join(scratch.path, 'rpg.db'));
    opened.add(database);
    await CampaignSchema.create(database.db);
    store = CampaignStore(database);
  }

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    secrets = MemorySecrets();
    opened.clear();
    final parent = await Directory(
            p.join(Directory.current.path, 'work', 'campaign-tests'))
        .create(recursive: true);
    scratch = await parent.createTemp('run-');
    await open();
    campaign = await store.create(
        name: 'Własny świat testowy',
        edition: 'Własna edycja',
        ownerId: 'owner');
  });
  tearDown(() async {
    for (final db in opened) {
      if (db.db.isOpen) await db.close();
    }
    final parent =
        p.absolute(p.join(Directory.current.path, 'work', 'campaign-tests'));
    if (!p.isWithin(parent, p.absolute(scratch.path))) {
      throw StateError('Niebezpieczne sprzątanie.');
    }
    await scratch.delete(recursive: true);
  });

  test('Nowa kampania jest pusta; żaden cudzy kanon nie jest tworzony',
      () async {
    expect(campaign.revision, 0);
    expect(await store.listRecords(scope()), isEmpty);
    expect(await store.audit(scope()), isEmpty);
    expect((await store.listCampaigns(ownerId: 'owner')).single.name,
        'Własny świat testowy');
    expect(await store.listCampaigns(ownerId: 'other'), isEmpty);
  });

  test('Restart zachowuje zaszyfrowany kanon, wiedzę, audyt i pełny checkpoint',
      () async {
    await store.putRecord(
        fact('gate', 'Tylko północna brama jest otwarta.'), scope(),
        expectedRevision: 0, userApproved: true);
    await store.saveCheckpoint(
        const CampaignCheckpoint(
            goal: 'Znajdź posłańca',
            scene: 'Brama',
            openThreads: 'Zaginiona pieczęć',
            party: 'Własne postacie',
            worldClock: 'Dzień 3, wieczór'),
        scope(),
        expectedRevision: 1);
    final raw = await database.db.query('rpg_records');
    expect(raw.map((r) => r['payload']).join(), isNot(contains('północna')));
    expect(raw.map((r) => r['payload']).join(), isNot(contains('posłańca')));
    await database.close();
    await open();
    expect((await store.readCampaign(campaign.id, scope())).revision, 2);
    final restored = await store.readCheckpoint(scope());
    expect(restored!.goal, 'Znajdź posłańca');
    expect(restored.worldClock, 'Dzień 3, wieczór');
    expect(restored.openThreads, 'Zaginiona pieczęć');
    expect(restored.scene, 'Brama');
    expect(restored.party, 'Własne postacie');
    expect(await store.audit(scope()), hasLength(2));
    expect(
        (await store.listRecords(scope()))
            .singleWhere((r) => r.id == 'gate')
            .content,
        'Tylko północna brama jest otwarta.');
  });

  test('Obcy właściciel, projekt, rola i kampania nie uzyskują dostępu',
      () async {
    await store.putRecord(
        fact('secret', 'Ukryta informacja', secret: true), scope(),
        expectedRevision: 0, userApproved: true);
    for (final context in [
      scope(owner: 'other'),
      scope(project: 'other'),
      scope(id: 'unknown'),
      scope(role: AccessRole.owner),
      scope(role: AccessRole.guest)
    ]) {
      await expectLater(store.listRecords(context), throwsStateError);
      await expectLater(store.contextPack(context), throwsStateError);
    }
    await expectLater(store.readCampaign('other', scope()), throwsStateError);
    await expectLater(
        store.putRecord(
            fact('x', 'Inny wpis'), scope(role: AccessRole.rpgPlayer),
            expectedRevision: 1, userApproved: true),
        throwsStateError);
  });

  test('Widok gracza nigdy nie odszyfrowuje sekretów ani stanu świata',
      () async {
    var revision = 0;
    for (final record in [
      fact('canon', 'Jawny kanon'),
      fact('secret', 'SEKRET_MG', secret: true),
      fact('world', 'Ukryta prawda świata',
          kind: CampaignRecordKind.worldEntity),
      fact('known', 'Gracz widział bramę',
          kind: CampaignRecordKind.playerKnowledge)
    ]) {
      revision = await store.putRecord(record, scope(),
          expectedRevision: revision, userApproved: true);
    }
    // Niepoprawny szyfrogram sekretu jest pułapką na odszyfrowanie przed filtrem.
    await database.db.update(
        'rpg_records', {'payload': 'nie jest szyfrogramem'},
        where: 'record_id=?', whereArgs: ['secret']);
    for (final purpose in MemoryPurpose.values) {
      final records = await store.listRecords(scope(role: AccessRole.rpgPlayer),
          purpose: purpose);
      expect(records.map((r) => r.id).toSet(), {'canon', 'known'});
      final pack = await store.contextPack(scope(role: AccessRole.rpgPlayer),
          purpose: purpose);
      expect(pack.text, isNot(contains('SEKRET_MG')));
      expect(pack.text, isNot(contains('Ukryta prawda')));
    }
  });

  test('Sekret wymaga jawnego scope MG, nigdy eksportu, indeksu ani recenzji',
      () async {
    await store.putRecord(fact('secret', 'SEKRET_MG', secret: true), scope(),
        expectedRevision: 0, userApproved: true);
    expect(await store.listRecords(scope(secret: false)), isEmpty);
    expect(
        (await store.contextPack(scope())).text, isNot(contains('SEKRET_MG')));
    expect(
        (await store.contextPack(scope(), selectedRecordIds: ['secret'])).text,
        contains('SEKRET_MG'));
    for (final purpose in [
      MemoryPurpose.export,
      MemoryPurpose.retrievalIndex,
      MemoryPurpose.reviewerContext
    ]) {
      expect(await store.listRecords(scope(), purpose: purpose), isEmpty);
      expect((await store.contextPack(scope(), purpose: purpose)).text,
          isNot(contains('SEKRET_MG')));
    }
  });

  test('Pending nie jest wiedzą gracza ani zatwierdzonym kontekstem modelu',
      () async {
    await store.putRecord(fact('pending', 'Szkic hipotezy'), scope(),
        expectedRevision: 0, userApproved: false);
    expect(await store.listRecords(scope()), hasLength(1));
    expect(await store.listRecords(scope(role: AccessRole.rpgPlayer)), isEmpty);
    expect((await store.contextPack(scope())).recordIds, isEmpty);
    expect((await store.audit(scope())).single.kind, 'recordSaved');
  });

  test('Bez strony fakt jest oznaczony NIEZWERYFIKOWANE; zła edycja odrzucona',
      () async {
    await store.putRecord(fact('unverified', 'Hipoteza', page: null), scope(),
        expectedRevision: 0, userApproved: true);
    final pack = await store.contextPack(scope());
    expect(pack.text, contains('NIEZWERYFIKOWANE'));
    expect(pack.text, contains('strona/wpis: BRAK'));
    await expectLater(
        store.putRecord(
            fact('wrong', 'Obca mechanika',
                authority: LoreAuthority.officialEdition,
                edition: 'Inna edycja'),
            scope(),
            expectedRevision: 1,
            userApproved: true),
        throwsStateError);
    expect((await store.readCampaign(campaign.id, scope())).revision, 1);
  });

  test('Hierarchia źródeł i budżet pakietu są jawne i ograniczone', () async {
    var revision = 0;
    for (final record in [
      fact('z-canon', 'Kanon'),
      fact('a-supplement', 'Pomocnicze',
          authority: LoreAuthority.supplementary),
      fact('b-official', 'Oficjalne', authority: LoreAuthority.officialEdition)
    ]) {
      revision = await store.putRecord(record, scope(),
          expectedRevision: revision, userApproved: true);
    }
    final pack = await store.contextPack(scope(), maxRecords: 2);
    expect(pack.recordIds, ['z-canon', 'b-official']);
    expect(pack.limited, isTrue);
    expect(pack.campaignId, campaign.id);
    expect(pack.revision, 3);
    expect(pack.fingerprint, isNotEmpty);
    expect(() => pack.recordIds.add('tampered'), throwsUnsupportedError);
    final small = await store.contextPack(scope(), maxCharacters: 256);
    expect(small.text.length, lessThanOrEqualTo(256));
    expect(small.limited, isTrue);
  });

  test('Cofnięcie i kolejne gałęzie nie wskrzeszają odrzuconych rekordów',
      () async {
    await store.putRecord(fact('a', 'Stan A1'), scope(),
        expectedRevision: 0, userApproved: true);
    await store.putRecord(fact('b', 'Stan B2'), scope(),
        expectedRevision: 1, userApproved: true);
    await store.rollback(1, scope(), expectedRevision: 2); // r3: tylko A
    await store.putRecord(fact('c', 'Stan C4'), scope(),
        expectedRevision: 3, userApproved: true);
    await store.rollback(3, scope(), expectedRevision: 4); // r5: tylko A
    expect((await store.listRecords(scope())).map((r) => r.id), ['a']);
    await store.rollback(2, scope(), expectedRevision: 5); // stare r2 ma A+B
    expect((await store.listRecords(scope())).map((r) => r.id).toSet(),
        {'a', 'b'});
    await store.rollback(0, scope(), expectedRevision: 6);
    await store.putRecord(fact('d', 'Stan D8'), scope(),
        expectedRevision: 7, userApproved: true);
    await store.rollback(7, scope(), expectedRevision: 8); // pusta baseline
    expect(await store.listRecords(scope()), isEmpty);
    expect(await store.audit(scope()), hasLength(9));
  });

  test('Zapis i rollback wymagają aktualnej rewizji; konflikt nic nie dopisuje',
      () async {
    await store.putRecord(fact('a', 'Pierwszy'), scope(),
        expectedRevision: 0, userApproved: true);
    await expectLater(
        store.putRecord(fact('b', 'Nieaktualny'), scope(),
            expectedRevision: 0, userApproved: true),
        throwsStateError);
    await expectLater(
        store.rollback(0, scope(), expectedRevision: 0), throwsStateError);
    expect(await store.audit(scope()), hasLength(1));
    expect(await database.db.query('rpg_versions'), hasLength(1));
  });

  test('SQL blokuje zmianę i skasowanie historycznych wersji i zdarzeń',
      () async {
    await store.putRecord(fact('a', 'Treść'), scope(),
        expectedRevision: 0, userApproved: true);
    for (final table in ['rpg_versions', 'rpg_events']) {
      await expectLater(database.db.update(table, {'revision': 10}),
          throwsA(isA<DatabaseException>()));
      await expectLater(
          database.db.delete(table), throwsA(isA<DatabaseException>()));
      expect(await database.db.query(table), hasLength(1));
    }
  });

  test('Checkpoint jest tylko MG i cofany razem z kanonem', () async {
    await store.saveCheckpoint(
        const CampaignCheckpoint(
            goal: 'Cel pierwszy',
            scene: 'Scena A',
            openThreads: 'Wątek',
            party: 'Drużyna',
            worldClock: 'Dzień 1'),
        scope(),
        expectedRevision: 0);
    await store.saveCheckpoint(
        const CampaignCheckpoint(
            goal: 'Cel drugi',
            scene: 'Scena B',
            openThreads: '',
            party: '',
            worldClock: 'Dzień 2'),
        scope(),
        expectedRevision: 1);
    await store.rollback(1, scope(), expectedRevision: 2);
    expect((await store.readCheckpoint(scope()))!.goal, 'Cel pierwszy');
    await expectLater(store.readCheckpoint(scope(role: AccessRole.rpgPlayer)),
        throwsStateError);
    await expectLater(
        store.readCheckpoint(scope(secret: false)), throwsStateError);
    expect(
        (await store.contextPack(scope(role: AccessRole.rpgPlayer))).recordIds,
        isEmpty);
  });

  test('Paginacja nie pobiera całego świata i nie miesza kampanii', () async {
    var revision = 0;
    for (var i = 0; i < 7; i++) {
      revision = await store.putRecord(fact('r$i', 'Fakt $i'), scope(),
          expectedRevision: revision, userApproved: true);
    }
    final other = await store.create(
        name: 'Druga kampania', edition: 'Inna', ownerId: 'owner');
    expect(await store.listRecords(scope(id: other.id)), isEmpty);
    expect(
        (await store.listRecords(scope(), limit: 2, offset: 4))
            .map((r) => r.id),
        ['r4', 'r5']);
    await expectLater(
        store.listRecords(scope(), limit: 101), throwsArgumentError);
    await expectLater(
        store.listRecords(scope(), offset: -1), throwsArgumentError);
  });

  test(
      'HMAC wyszukuje właściwy kanon bez jawnych słów i bez indeksowania sekretów',
      () async {
    await store.putRecord(
        fact('gate', 'Północna brama przyjmuje posłańców.'), scope(),
        expectedRevision: 0, userApproved: true);
    await store.putRecord(
        fact('hidden', 'Tajemnicza wskazówka posłańców', secret: true), scope(),
        expectedRevision: 1, userApproved: true);
    await store.putRecord(fact('pending', 'Posłańców szkic'), scope(),
        expectedRevision: 2, userApproved: false);
    final terms = await database.db.query('rpg_terms');
    expect(terms.every((row) => row['record_id'] == 'gate'), isTrue);
    expect(terms.map((row) => row['term']).join(), isNot(contains('brama')));
    final pack = await store.contextPack(scope(), query: 'brama');
    expect(pack.recordIds, ['gate']);
    expect((await store.contextPack(scope(), query: 'tajemnicza')).recordIds,
        isEmpty);
    expect((await store.contextPack(scope(), query: 'nieobecnesłowo')).text,
        contains('Brak dopasowanych źródeł'));
    await expectLater(
        store.contextPack(scope(role: AccessRole.rpgPlayer),
            selectedRecordIds: ['hidden']),
        throwsStateError);
  });

  test(
      'Zmiana treści i rollback atomowo zmieniają indeks; kanon wyprzedza checkpoint',
      () async {
    await store.putRecord(fact('gate', 'Stara brama'), scope(),
        expectedRevision: 0, userApproved: true);
    await store.putRecord(fact('gate', 'Nowy port'), scope(),
        expectedRevision: 1, userApproved: true);
    expect(
        (await store.contextPack(scope(), query: 'brama')).recordIds, isEmpty);
    await store.rollback(1, scope(), expectedRevision: 2);
    expect(
        (await store.contextPack(scope(), query: 'brama')).recordIds, ['gate']);
    expect(
        (await store.contextPack(scope(), query: 'port')).recordIds, isEmpty);
    await store.saveCheckpoint(
        const CampaignCheckpoint(
            goal: 'Powrót',
            scene: 'Brama',
            openThreads: '',
            party: '',
            worldClock: 'Świt'),
        scope(),
        expectedRevision: 3);
    final pack = await store.contextPack(scope(), query: 'brama');
    expect(pack.recordIds, ['gate', 'active-session']);
    expect(
        (await store.contextPack(scope(role: AccessRole.rpgPlayer),
                query: 'brama'))
            .recordIds,
        ['gate']);
    await store.putRecord(fact('gate', 'Stara brama', secret: true), scope(),
        expectedRevision: 4, userApproved: true);
    expect(await database.db.query('rpg_terms'), isEmpty);
  });
}
