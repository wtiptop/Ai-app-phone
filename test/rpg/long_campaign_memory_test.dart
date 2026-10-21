import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/rpg/campaign.dart';
import 'package:scalajaca/rpg/campaign_store.dart';
import 'package:scalajaca/security/memory_access.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Faktyczny store/SQLite/szyfr. To test doboru źródeł, nie jakości narracji LLM.
/// Wyłącznie fikcyjny, własny świat; żaden istniejący kanon nie jest importowany.
void main() {
  late AppDatabase database;
  late CampaignStore store;
  late StoredCampaign campaign;
  late MemorySecrets secrets;
  late Directory scratch;
  late int head;
  final opened = <AppDatabase>[];

  AccessContext access(
          {AccessRole role = AccessRole.gameMaster,
          bool allowSecret = true,
          String owner = 'local-owner',
          String? campaignId,
          String? projectId}) =>
      AccessContext(
          principalId: owner,
          role: role,
          campaignId: campaignId ?? campaign.id,
          allowGmSecretContext: allowSecret,
          projectId: projectId);

  CampaignRecord fact(
    String id,
    String content, {
    LoreAuthority authority = LoreAuthority.approvedCampaignCanon,
    String edition = 'Autorski świat testowy',
    bool secret = false,
    CampaignRecordKind kind = CampaignRecordKind.canon,
    String? campaignId,
  }) =>
      CampaignRecord(
          id: id,
          campaignId: campaignId ?? campaign.id,
          title: 'Własny fakt $id',
          content: content,
          kind: kind,
          visibility:
              secret ? MemoryVisibility.gmSecret : MemoryVisibility.campaign,
          citation: LoreCitation(
              sourceId: 'synthetic/$id',
              title: 'Własny materiał testowy',
              authority: authority,
              edition: edition,
              page: 'wpis $id',
              userVerified: true));

  Future<void> put(CampaignRecord record, {bool approved = true}) async {
    head = await store.putRecord(record, access(),
        expectedRevision: head, userApproved: approved);
  }

  Future<void> open() async {
    database = await AppDatabase.open(ContentCipher(secrets),
        factory: databaseFactoryFfi,
        path: p.join(scratch.path, 'long-campaign.db'));
    opened.add(database);
    store = CampaignStore(database);
  }

  Future<void> restart() async {
    await database.close();
    await open();
    head = (await store.readCampaign(campaign.id, access())).revision;
  }

  Future<void> seedTwentyFourSessions() async {
    await put(fact('old-canon',
        'Od pierwszej sesji obowiązuje przysięga bursztynowiec. Ustalone hasło: LATARNIA.'));
    await put(fact('withdrawn-canon',
        'bursztynowiec WYCOFANY_FAKT nie powinien wrócić po cofnięciu zgody.'));
    await put(fact(
        'gm-secret', 'gmsekretnik TAJEMNICA_MG nie należy do wiedzy gracza.',
        secret: true));
    for (var session = 1; session <= 24; session++) {
      await put(fact(
          'npc-state',
          'Stan karczmarki archiwalnik${session.toString().padLeft(2, '0')}. '
              'Aktualne ustalenie pochodzi z sesji $session.'));
      head = await store.saveCheckpoint(
          CampaignCheckpoint(
              goal: 'Własny cel sesji $session',
              scene: 'Kamienna brama, etap $session',
              openThreads: 'Przysięga i własne zadania drużyny',
              party: 'Postacie stworzone przez użytkownika',
              worldClock: 'Dzień $session, świt'),
          access(),
          expectedRevision: head);
    }
    await put(
        fact('withdrawn-canon',
            'bursztynowiec WYCOFANY_FAKT nie powinien wrócić po cofnięciu zgody.'),
        approved: false);
    await put(
        fact('pending-canon',
            'bursztynowiec SZKIC_NIEZATWIERDZONY nie jest przyjętym faktem.'),
        approved: false);
  }

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    opened.clear();
    secrets = MemorySecrets();
    final parent = await Directory(
            p.join(Directory.current.path, 'work', 'long-campaign-tests'))
        .create(recursive: true);
    scratch = await parent.createTemp('run-');
    await open();
    campaign = await store.create(
        name: 'Własna wielosesyjna kampania testowa',
        edition: 'Autorski świat testowy',
        ownerId: 'local-owner');
    head = 0;
    await seedTwentyFourSessions();
    await restart();
  });
  tearDown(() async {
    for (final db in opened) {
      if (db.db.isOpen) await db.close();
    }
    final parent = p.absolute(
        p.join(Directory.current.path, 'work', 'long-campaign-tests'));
    if (!p.isWithin(parent, p.absolute(scratch.path))) {
      throw StateError('Sprzątanie poza katalogiem testów wielosesyjnych.');
    }
    await scratch.delete(recursive: true);
  });

  test(
      'Po24sesjach i restarcie wraca dawny aktualny fakt, a nie dawna wersja NPC',
      () async {
    final sessions = await store.checkpointHistory(access(), limit: 100);
    final versions =
        await store.recordHistory('npc-state', access(), limit: 100);
    expect(sessions, hasLength(24));
    expect(versions, hasLength(24));
    expect(sessions.first.checkpoint.goal, 'Własny cel sesji 24');
    expect(versions.first.record.content, contains('archiwalnik24'));
    final recalled = await store.contextPack(access(), query: 'bursztynowiec');
    expect(recalled.recordIds, containsAll(['active-session', 'old-canon']));
    expect(recalled.text, contains('LATARNIA'));
    expect(recalled.text, isNot(contains('WYCOFANY_FAKT')));
    expect(recalled.text, isNot(contains('SZKIC_NIEZATWIERDZONY')));
    expect(recalled.revision, head);
    expect(
        (await store.contextPack(access(), query: 'archiwalnik01')).recordIds,
        ['active-session']);
    expect(
        (await store.contextPack(access(), query: 'archiwalnik24')).recordIds,
        contains('npc-state'));
  });

  test(
      'Polskie słowa pospolite nie wypychają istotnego późnego rzeczownika poza12terminów',
      () async {
    // Grzecznościowy wstęp zajmuje pierwszych12terminów. Istotna przysięga
    // i hasło pojawiają się później w rzeczywistym polskim pytaniu.
    final pack = await store.contextPack(access(),
        query:
            'Czy możesz mi proszę jeszcze przypomnieć to co było dla nas ważne oraz jakie hasło miała przysięga bursztynowiec');
    expect(pack.recordIds, contains('old-canon'),
        reason: 'Wstęp pytania nie może usunąć jedynego istotnego terminu.');
    expect(pack.text, contains('LATARNIA'));
    expect(pack.text, isNot(contains('WYCOFANY_FAKT')));
  });

  test(
      'Długi kandydat nie blokuje pobrania późniejszego krótkiego trafnego faktu',
      () async {
    final longBody = 'dalekopis ${List.filled(700, 'własny').join(' ')}';
    // Więcej niż strona 40: krótki fakt wymaga następnego odczytu SQL.
    for (var i = 0; i < 42; i++) {
      await put(fact('a-long-${i.toString().padLeft(2, '0')}', longBody));
    }
    await put(fact('z-short', 'dalekopis utrwalone hasło powrotu: KOMPAS.'));
    await restart();
    final pack = await store.contextPack(access(),
        query: 'dalekopis', maxRecords: 2, maxCharacters: 1600);
    expect(pack.recordIds, contains('active-session'));
    expect(pack.recordIds, contains('z-short'),
        reason:
            'SQL ma stronicować kandydatów po pominięciu zbyt dużych wpisów.');
    expect(pack.text, contains('KOMPAS'));
    expect(pack.text.length, lessThanOrEqualTo(1600));
    expect(pack.limited, isTrue);
  });

  test(
      'Jawnie wybrany wpis przekraczający budżet nie może zostać cicho zastąpiony innym',
      () async {
    await put(fact('manual-large', List.filled(900, 'lore').join(' ')));
    await expectLater(
        store.contextPack(access(),
            selectedRecordIds: ['manual-large'], maxCharacters: 1600),
        throwsStateError);
    await expectLater(
        store.contextPack(access(),
            selectedRecordIds: ['manual-large'],
            maxCharacters: 1600,
            includeCheckpoint: false),
        throwsStateError);
    expect((await store.readCampaign(campaign.id, access())).revision, head);
  });

  test(
      'Limit liczby rekordów nie może pominąć jawnego wyboru za obowiązkowym checkpointem',
      () async {
    await expectLater(
        store.contextPack(access(),
            selectedRecordIds: ['old-canon'], maxRecords: 1),
        throwsStateError);
    expect((await store.readCheckpoint(access()))!.goal, 'Własny cel sesji 24');
    final without = await store.contextPack(access(),
        selectedRecordIds: ['old-canon'],
        maxRecords: 1,
        includeCheckpoint: false);
    expect(without.recordIds, ['old-canon']);
  });

  test(
      'Cofnięta zgoda i pending nie wracają przez ręczny wybór lub po restarcie',
      () async {
    for (final id in ['withdrawn-canon', 'pending-canon']) {
      await expectLater(store.contextPack(access(), selectedRecordIds: [id]),
          throwsStateError);
      await expectLater(
          store.contextPack(access(role: AccessRole.rpgPlayer),
              selectedRecordIds: [id]),
          throwsStateError);
    }
    final history = await store.recordHistory('withdrawn-canon', access());
    expect(history.first.record.approved, isFalse);
    expect(history.last.record.approved, isTrue,
        reason:
            'Archiwum zachowuje audyt zgody, ale nie nadaje jej bieżącemu wpisowi.');
    final player = await store.contextPack(access(role: AccessRole.rpgPlayer),
        query: 'bursztynowiec');
    expect(player.recordIds, ['old-canon']);
    expect(player.text, isNot(contains('Własny cel sesji 24')));
  });

  test(
      'GMsecret wymaga ręcznego wyboru i nigdy nie trafia do gracza, indeksu lub recenzji',
      () async {
    final gm = access();
    expect((await store.contextPack(gm, query: 'gmsekretnik')).text,
        isNot(contains('TAJEMNICA_MG')));
    expect((await store.contextPack(gm, selectedRecordIds: ['gm-secret'])).text,
        contains('TAJEMNICA_MG'));
    for (final caller in [
      access(role: AccessRole.rpgPlayer),
      access(allowSecret: false)
    ]) {
      await expectLater(
          store.contextPack(caller, selectedRecordIds: ['gm-secret']),
          throwsStateError);
    }
    for (final purpose in [
      MemoryPurpose.export,
      MemoryPurpose.reviewerContext,
      MemoryPurpose.retrievalIndex
    ]) {
      final pack =
          await store.contextPack(gm, purpose: purpose, query: 'gmsekretnik');
      expect(pack.text, isNot(contains('TAJEMNICA_MG')));
      expect(pack.text, isNot(contains('Własny cel sesji 24')));
      await expectLater(
          store.contextPack(gm,
              purpose: purpose, selectedRecordIds: ['gm-secret']),
          throwsStateError);
    }
    expect(
        await database.db.query('rpg_terms',
            where: 'campaign_id=? AND record_id IN (?,?)',
            whereArgs: [campaign.id, 'gm-secret', 'active-session']),
        isEmpty);
  });

  test(
      'Właściwa hierarchia źródeł i izolacja edycji nie zależą od liczby sesji',
      () async {
    await put(fact('z-own', 'chronologia własny zatwierdzony kanon.'));
    await put(fact('a-official', 'chronologia testowa reguła właściwej edycji.',
        authority: LoreAuthority.officialEdition));
    await put(fact('b-extra', 'chronologia materiał pomocniczy.',
        authority: LoreAuthority.supplementary));
    final before = head;
    await expectLater(
        put(fact('wrong-edition', 'chronologia inna edycja.',
            authority: LoreAuthority.officialEdition,
            edition: 'Inna testowa edycja')),
        throwsStateError);
    expect(head, before);
    final pack = await store.contextPack(access(), query: 'chronologia');
    expect(
        pack.recordIds, ['z-own', 'a-official', 'b-extra', 'active-session']);
    final other = await store.create(
        name: 'Drugi własny świat',
        edition: 'Inna testowa edycja',
        ownerId: 'local-owner');
    expect(
        (await store.contextPack(access(campaignId: other.id),
                query: 'chronologia'))
            .recordIds,
        isEmpty);
    await expectLater(
        store.contextPack(access(owner: 'other-owner'), query: 'chronologia'),
        throwsStateError);
    await expectLater(
        store.contextPack(access(projectId: 'other-project'),
            query: 'chronologia'),
        throwsStateError);
  });

  test(
      'Za duży pełny checkpoint daje błąd zamiast ukrytego obcięcia stanu sesji',
      () async {
    head = await store.saveCheckpoint(
        CampaignCheckpoint(
            goal: List.filled(700, 'własny cel').join(' '),
            scene: 'Scena',
            openThreads: 'Wątki',
            party: 'Drużyna',
            worldClock: 'Zegar'),
        access(),
        expectedRevision: head);
    await restart();
    await expectLater(
        store.contextPack(access(),
            query: 'bursztynowiec', maxCharacters: 1200),
        throwsStateError);
    final explicit = await store.contextPack(access(),
        query: 'bursztynowiec', maxCharacters: 1200, includeCheckpoint: false);
    expect(explicit.recordIds, ['old-canon']);
    expect(explicit.text, contains('LATARNIA'));
    expect(explicit.text.length, lessThanOrEqualTo(1200));
    expect(explicit.text, isNot(contains('Własny cel')));
    expect(
        (await store.readCheckpoint(access()))!.goal.length, greaterThan(1200));
  });

  test(
      'Ręcznie wybrany materiał pomocniczy nie wyprzedza kanonu i właściwej edycji',
      () async {
    await put(fact('z-own', 'chronologia własny zatwierdzony kanon.'));
    await put(fact('a-official', 'chronologia testowa reguła właściwej edycji.',
        authority: LoreAuthority.officialEdition));
    await put(fact('b-extra', 'chronologia materiał pomocniczy.',
        authority: LoreAuthority.supplementary));
    final before = head;
    final pack = await store.contextPack(access(),
        query: 'chronologia', selectedRecordIds: ['b-extra']);
    expect(
        pack.recordIds, ['z-own', 'a-official', 'b-extra', 'active-session']);
    expect(pack.recordIds.toSet(), hasLength(4));
    expect((await store.readCampaign(campaign.id, access())).revision, before);
  });

  test(
      'Jawne pominięcie checkpointu nie zmienia roli ani zasad ochrony sekretów',
      () async {
    final full = await store.contextPack(access(),
        query: 'bursztynowiec', includeCheckpoint: true);
    expect(full.recordIds.last, 'active-session');
    expect(full.text, contains('Własny cel sesji 24'));
    final selected = await store.contextPack(access(),
        query: 'bursztynowiec', includeCheckpoint: false);
    expect(selected.recordIds, ['old-canon']);
    expect(selected.text, isNot(contains('Własny cel sesji 24')));
    expect(selected.context.role, AccessRole.gameMaster);
    expect(selected.campaignId, campaign.id);
    expect(selected.revision, head);
    expect(selected.fingerprint, isNot(full.fingerprint));
    expect((await store.readCheckpoint(access()))!.goal, 'Własny cel sesji 24');
    final explicitSecret = await store.contextPack(access(),
        query: 'gmsekretnik',
        selectedRecordIds: ['gm-secret'],
        includeCheckpoint: false);
    expect(explicitSecret.recordIds, ['gm-secret']);
    for (final include in [true, false]) {
      final player = await store.contextPack(access(role: AccessRole.rpgPlayer),
          query: 'bursztynowiec', includeCheckpoint: include);
      expect(player.recordIds, ['old-canon']);
      expect(player.text, isNot(contains('TAJEMNICA_MG')));
      expect(player.text, isNot(contains('Własny cel sesji 24')));
      await expectLater(
          store.contextPack(access(role: AccessRole.rpgPlayer),
              selectedRecordIds: ['gm-secret'], includeCheckpoint: include),
          throwsStateError);
      await expectLater(
          store.contextPack(access(allowSecret: false),
              selectedRecordIds: ['gm-secret'], includeCheckpoint: include),
          throwsStateError);
    }
  });
}
