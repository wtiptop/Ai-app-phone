import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/auth/secret_store.dart';
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
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
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
}
