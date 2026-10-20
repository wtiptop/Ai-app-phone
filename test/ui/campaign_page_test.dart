import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/rpg/campaign.dart';
import 'package:scalajaca/rpg/campaign_store.dart';
import 'package:scalajaca/security/memory_access.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:scalajaca/ui/campaign_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final dialogs = find.byType(AlertDialog);
    final scrollable = dialogs.evaluate().isEmpty
        ? find.byType(Scrollable).first
        : find
            .descendant(of: dialogs.last, matching: find.byType(Scrollable))
            .last;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 180, scrollable: scrollable);
    }
  }
  await tester.ensureVisible(finder);
  await flush(tester);
}

void main() {
  setUpAll(sqfliteFfiInit);
  testWidgets(
      'Mały ekran pozwala zatwierdzić sekret MG bez przepełnienia formularza',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = (await tester.runAsync(() => AppDatabase.open(
        ContentCipher(MemorySecrets()),
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath)))!;
    final store = CampaignStore(db);
    final campaign = (await tester.runAsync(() => store.create(
        ownerId: 'local-owner',
        name: 'Test małego ekranu',
        edition: 'Własny świat')))!;
    await tester.pumpWidget(
        MaterialApp(home: CampaignPage(store: store, ownerId: 'local-owner')));
    await flush(tester);
    await tester.tap(find.text(campaign.name));
    await flush(tester);
    await reveal(tester, find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await flush(tester);
    await reveal(tester, find.text('Zatwierdź własny wpis'));
    await tester.tap(find.text('Zatwierdź własny wpis'));
    await flush(tester);
    expect(find.text('Wpis zatwierdzany przez MG'), findsOneWidget);
    Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label);
    await reveal(tester, field('Tytuł wpisu'));
    await tester.enterText(field('Tytuł wpisu'), 'Testowy sekret');
    await reveal(tester, field('Treść lub fragment Markdown'));
    await tester.enterText(field('Treść lub fragment Markdown'),
        'Fikcyjny szczegół tylko dla MG.');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final approval =
        find.text('Zatwierdzam wpis do pamięci MG wybranej kampanii');
    await reveal(tester, approval);
    await tester.tap(approval);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zapisz zatwierdzony wpis'));
    await flush(tester);
    expect(tester.takeException(), isNull);
    final rows = (await tester.runAsync(() => store.listRecords(AccessContext(
        principalId: 'local-owner',
        role: AccessRole.gameMaster,
        campaignId: campaign.id,
        allowGmSecretContext: true))))!;
    expect(rows.single.title, 'Testowy sekret');
    expect(rows.single.visibility, MemoryVisibility.gmSecret);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(db.close);
  });

  testWidgets(
      'Historia sesji wymaga widoku MG i jawnego wznowienia, zachowując bieżący kanon',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = (await tester.runAsync(() => AppDatabase.open(
        ContentCipher(MemorySecrets()),
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath)))!;
    final store = CampaignStore(db);
    final campaign = (await tester.runAsync(() => store.create(
        ownerId: 'local-owner',
        name: 'Historia na małym ekranie',
        edition: 'Własna edycja')))!;
    final access = AccessContext(
        principalId: 'local-owner',
        role: AccessRole.gameMaster,
        campaignId: campaign.id,
        allowGmSecretContext: true);
    await tester.runAsync(() async {
      await store.saveCheckpoint(
          const CampaignCheckpoint(
              goal: 'Dawny cel testowy',
              scene: 'Dawna scena',
              openThreads: 'Dawny wątek',
              party: 'Drużyna',
              worldClock: 'Dzień 1'),
          access,
          expectedRevision: 0);
      await store.putRecord(
          CampaignRecord(
              id: 'gate',
              campaignId: campaign.id,
              title: 'Aktualny kanon',
              content: 'Brama zamknięta po obecnych wydarzeniach.',
              kind: CampaignRecordKind.canon,
              citation: const LoreCitation(
                  sourceId: 'own',
                  title: 'Własny kanon',
                  page: '1',
                  authority: LoreAuthority.approvedCampaignCanon,
                  edition: 'Własna edycja',
                  userVerified: true)),
          access,
          expectedRevision: 1,
          userApproved: true);
      await store.saveCheckpoint(
          const CampaignCheckpoint(
              goal: 'Aktualny cel testowy',
              scene: 'Nowa scena',
              openThreads: 'Nowy wątek',
              party: 'Drużyna',
              worldClock: 'Dzień 2'),
          access,
          expectedRevision: 2);
    });
    await tester.pumpWidget(
        MaterialApp(home: CampaignPage(store: store, ownerId: 'local-owner')));
    await flush(tester);
    await tester.tap(find.text(campaign.name));
    await flush(tester);
    expect(find.text('Historia sesji MG'), findsNothing);
    await reveal(tester, find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await flush(tester);
    await reveal(tester, find.text('Historia sesji MG'));
    await tester.tap(find.text('Historia sesji MG'));
    await flush(tester);
    await reveal(tester, find.text('Rewizja 1'));
    await tester.tap(find.text('Rewizja 1'));
    await flush(tester);
    expect(find.textContaining('Archiwalna notatka nie jest aktualnym kanonem'),
        findsOneWidget);
    expect(find.textContaining('Cel: Dawny cel testowy'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog).last,
            matching: find.byType(SelectableText)),
        findsNothing);
    await reveal(tester, find.text('Wybierz punkt do wznowienia'));
    await tester.tap(find.text('Wybierz punkt do wznowienia'));
    await flush(tester);
    expect(find.text('Wznowić punkt sesji z r1?'), findsOneWidget);
    expect((await tester.runAsync(() => store.readCheckpoint(access)))!.goal,
        'Aktualny cel testowy');
    await tester.tap(find.text('Wznów jako nową rewizję'));
    await flush(tester);
    expect((await tester.runAsync(() => store.readCheckpoint(access)))!.goal,
        'Dawny cel testowy');
    final records = (await tester.runAsync(() => store.listRecords(access)))!;
    expect(records.firstWhere((r) => r.id == 'gate').content,
        'Brama zamknięta po obecnych wydarzeniach.');
    expect(
        (await tester.runAsync(() => store.readCampaign(campaign.id, access)))!
            .revision,
        4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(db.close);
  });

  testWidgets(
      'MG widzi różnice historycznego sekretu, gracz nie otrzymuje przycisku archiwum',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = (await tester.runAsync(() => AppDatabase.open(
        ContentCipher(MemorySecrets()),
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath)))!;
    final store = CampaignStore(db);
    final campaign = (await tester.runAsync(() => store.create(
        ownerId: 'local-owner',
        name: 'Historia zmiany lore',
        edition: 'Własna edycja')))!;
    final access = AccessContext(
        principalId: 'local-owner',
        role: AccessRole.gameMaster,
        campaignId: campaign.id,
        allowGmSecretContext: true);
    CampaignRecord fact(
            String text, MemoryVisibility visibility) =>
        CampaignRecord(
            id: 'npc',
            campaignId: campaign.id,
            title: 'Własny NPC',
            content: text,
            kind: CampaignRecordKind.canon,
            visibility: visibility,
            citation: const LoreCitation(
                sourceId: 'own',
                title: 'Źródło',
                page: '1',
                authority: LoreAuthority.approvedCampaignCanon,
                edition: 'Własna edycja',
                userVerified: true));
    await tester.runAsync(() async {
      await store.putRecord(
          fact('DAWNY_SEKRET_MG', MemoryVisibility.gmSecret), access,
          expectedRevision: 0, userApproved: true);
      await store.putRecord(
          fact('Jawna obecna wiedza.', MemoryVisibility.campaign), access,
          expectedRevision: 1, userApproved: true);
    });
    await tester.pumpWidget(
        MaterialApp(home: CampaignPage(store: store, ownerId: 'local-owner')));
    await flush(tester);
    await tester.tap(find.text(campaign.name));
    await flush(tester);
    expect(find.text('Historia wersji tego wpisu'), findsNothing);
    await reveal(tester, find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await flush(tester);
    await reveal(tester, find.text('Historia wersji tego wpisu'));
    await tester.tap(find.text('Historia wersji tego wpisu'));
    await flush(tester);
    await reveal(tester, find.text('Rewizja 1'));
    await tester.tap(find.text('Rewizja 1'));
    await flush(tester);
    expect(find.text('DAWNY_SEKRET_MG'), findsOneWidget);
    expect(
        find.textContaining(
            'Różnice względem bieżącego wpisu: Treść, Widoczność'),
        findsOneWidget);
    expect(find.text('Wybierz punkt do wznowienia'), findsNothing);
    expect(
        find.descendant(
            of: find.byType(AlertDialog).last,
            matching: find.byType(SelectableText)),
        findsNothing);
    await tester.tap(find.text('Zamknij podgląd'));
    await flush(tester);
    await tester.tap(find.text('Zamknij historię'));
    await flush(tester);
    await reveal(tester, find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await flush(tester);
    expect(find.text('DAWNY_SEKRET_MG'), findsNothing);
    expect(find.text('Historia wersji tego wpisu'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(db.close);
  });
}
