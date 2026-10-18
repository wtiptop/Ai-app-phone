import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/memory/memory_store.dart';
import 'package:scalajaca/memory/vault_bridge.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:scalajaca/ui/vault_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Gateway implements VaultGateway {
  int reads = 0, exports = 0;
  final picks = <bool>[];
  @override
  Future<List<VaultHandle>> status() async =>
      [const VaultHandle(id: 'local-test', writable: false)];
  @override
  Future<VaultHandle?> pick({bool writable = false}) async {
    picks.add(writable);
    return VaultHandle(id: 'local-test', writable: writable);
  }

  @override
  Future<VaultListing> list(String handleId,
          {String? cursor, int limit = 100}) async =>
      const VaultListing(items: [
        VaultFile(
            id: 'signed-test', path: 'Lore/Król.md', bytes: 49, modified: 1)
      ]);
  @override
  Future<String> read(String handleId, String documentId) async {
    reads++;
    return '# Król\nKról Arven strzeże północnej bramy.';
  }

  @override
  Future<String> export(
      String handleId, String filename, String content) async {
    exports++;
    return 'Scalajaca-Exports/test.md';
  }

  @override
  Future<void> cancel(String handleId) async {}
  @override
  Future<void> disconnect(String handleId) async {}
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 18; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 300,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('vault-scroll')),
                matching: find.byType(Scrollable))
            .first);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late MemoryStore memory;
  late _Gateway gateway;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    database = await AppDatabase.open(ContentCipher(MemorySecrets()),
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    memory = MemoryStore(database);
    gateway = _Gateway();
  });
  tearDown(() async => database.close());
  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(
        MaterialApp(home: VaultPage(store: memory, gateway: gateway)));
    await _flush(tester);
  }

  testWidgets('połączenie samo nie czyta vaultu i nie prosi o zapis',
      (tester) async {
    await boot(tester);
    await tester.tap(find.text('Połącz lokalny vault — tylko odczyt'));
    await _flush(tester);
    expect(gateway.picks, [false]);
    expect(gateway.reads, 0);
    expect(gateway.exports, 0);
    expect((await tester.runAsync(() => memory.collections()))!.single.name,
        'Moja pamięć');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('import wymaga podglądu i zatwierdzenia przed doborem źródeł',
      (tester) async {
    final collection = (await tester.runAsync(() =>
        memory.createCollection(name: 'Archiwum', vaultId: 'local-test')))!;
    await boot(tester);
    await _reveal(tester, find.text('Importuj / wznów'));
    await tester.tap(find.text('Importuj / wznów'));
    await _flush(tester);
    final docs =
        (await tester.runAsync(() => memory.documents(collection.id)))!;
    expect(docs.single.approval, 'pending');
    expect(gateway.reads, 1);
    expect(
        (await tester.runAsync(() => memory.retrieve(collection.id, 'Arven')))!
            .excerpts,
        isEmpty);
    await _flush(tester);
    final docTile = find.text('Lore/Król.md', skipOffstage: false);
    await _reveal(tester, docTile);
    await tester.tap(docTile);
    await _flush(tester);
    expect(find.textContaining('Król Arven strzeże'), findsOneWidget);
    await tester.tap(find.text('Zatwierdź tę wersję'));
    await _flush(tester);
    final search = find.widgetWithText(
        TextField, 'Szukaj po słowach w zatwierdzonych źródłach');
    await _reveal(tester, search);
    await tester.enterText(search, 'Arven');
    await _reveal(tester, find.text('Szukaj w pamięci'));
    await tester.tap(find.text('Szukaj w pamięci'));
    await _flush(tester);
    expect(find.text('Użyj w czacie'), findsNothing);
    await _reveal(tester, find.text('Podgląd wybranych źródeł'));
    await tester.tap(find.text('Podgląd wybranych źródeł'));
    await _flush(tester);
    expect(find.text('Kontekst do następnej wiadomości'), findsOneWidget);
    expect(find.text('Użyj w czacie'), findsOneWidget);
    expect(gateway.exports, 0);
    expect(gateway.picks, isEmpty);
    await tester.tap(find.text('Wróć'));
    await _flush(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('sekret MG nie ma przycisku zatwierdzenia do ogólnej pamięci',
      (tester) async {
    final collection = (await tester.runAsync(() =>
        memory.createCollection(name: 'Zastrzeżone', vaultId: 'local-test')))!;
    await tester.runAsync(() => memory.ingest(
        collection.id, 'GM_SECRET/Sekret.md', 'Ukryta tożsamość antagonisty.'));
    await boot(tester);
    await _reveal(tester, find.text('GM_SECRET/Sekret.md'));
    await tester.tap(find.text('GM_SECRET/Sekret.md'));
    await _flush(tester);
    expect(find.textContaining('wyłączona z ogólnej pamięci'), findsOneWidget);
    expect(find.text('Zatwierdź tę wersję'), findsNothing);
    await tester.tap(find.text('Zamknij'));
    await _flush(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('wcześniejszy punkt analizy jest odczytywany z bazy',
      (tester) async {
    final collection = (await tester.runAsync(
        () => memory.createCollection(name: 'Wieloetapowe badanie')))!;
    await tester.runAsync(() => memory.saveCheckpoint(collection.id,
        goal: 'Zbadać północną bramę',
        findings: 'Brama zamknięta.',
        nextStep: 'Porównać kroniki.',
        sources: 'Kronika.md w1'));
    await boot(tester);
    await _reveal(tester, find.text('Zbadać północną bramę'));
    await tester.tap(find.text('Zbadać północną bramę'));
    await _flush(tester);
    expect(find.textContaining('Porównać kroniki.'), findsOneWidget);
    expect(gateway.reads, 0);
    expect(gateway.exports, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
