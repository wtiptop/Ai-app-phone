import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/provider_registry/provider_registry.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:scalajaca/ui/provider_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase store;
  late MemorySecrets secrets;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    secrets = MemorySecrets();
    store = await AppDatabase.open(ContentCipher(secrets),
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });
  tearDown(() async => store.close());

  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: ProviderCard(
        provider: MiniCpmAdapter(
            readEndpoint: () => store.setting('endpoint_minicpm', '')),
        store: store,
        secrets: secrets,
      ),
    ))));
    await flush(tester);
    await tester.tap(find.text('MiniCPM • własny serwer'));
    await tester.pumpAndSettle();
  }

  testWidgets('UI jawnie odróżnia serwer od silnika offline', (tester) async {
    await boot(tester);
    expect(
        find.textContaining('Model offline jest osobną opcją'), findsOneWidget);
    expect(field('Adres HTTPS serwera MiniCPM'), findsOneWidget);
    expect(field('Klucz własnego serwera (opcjonalny)'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'Zmiana odbiorcy usuwa poprzedni sekret i wymaga nowej deklaracji',
      (tester) async {
    await tester.runAsync(() async {
      await store.setSetting('endpoint_minicpm', 'https://old.example.org/v1');
      await store.setSetting('model_minicpm', 'owner-model');
      await store.setSetting('input_rate_minicpm', 0.0);
      await store.setSetting('output_rate_minicpm', 0.0);
      await store.setSetting('minicpm_self_hosted_free', true);
      await secrets.write('api_minicpm', 'old-server-secret-placeholder');
    });
    await boot(tester);
    await tester.ensureVisible(field('Adres HTTPS serwera MiniCPM'));
    await tester.enterText(
        field('Adres HTTPS serwera MiniCPM'), 'https://new.example.org/v1');
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.text('Zapisz'));
    await tester.tap(find.text('Zapisz'));
    await flush(tester);
    expect(await tester.runAsync(() => store.setting('endpoint_minicpm', '')),
        'https://new.example.org/v1');
    expect(await secrets.read('api_minicpm'), isNull);
    expect(await tester.runAsync(() => store.setting('paid_enabled', false)),
        isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
