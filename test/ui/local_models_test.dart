import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/local_inference/local_engine.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:scalajaca/ui/local_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local/local_adapter_test.dart' show FakeLocalEngine, modelId;

class Engine extends FakeLocalEngine {
  String? importedHash;
  int imports = 0;
  final models = <LocalModel>[
    const LocalModel(
        id: modelId,
        name: 'MiniCPM5 1B',
        profile: 'minicpm5_1b',
        bytes: 688065920)
  ];
  @override
  Future<LocalEngineStatus> status() async => LocalEngineStatus(
      commit: '5aeac37a35b44fde4bdffaec9159f2fcb253b622',
      models: List.of(models));
  @override
  Future<LocalModel?> importModel({String expectedSha256 = ''}) async {
    importedHash = expectedSha256;
    imports++;
    final model = LocalModel(
        id: 'b' * 64, name: 'MiniCPM5 2B', profile: 'minicpm5_2b', bytes: 1000);
    models.add(model);
    return model;
  }

  @override
  Future<void> removeModel(String id) async =>
      models.removeWhere((m) => m.id == id);
}

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
  late Engine engine;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    store = await AppDatabase.open(ContentCipher(MemorySecrets()),
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    engine = Engine();
  });
  tearDown(() async => store.close());
  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(
        MaterialApp(home: LocalModelsPage(engine: engine, store: store)));
    await flush(tester);
  }

  testWidgets('Wybór lokalnego modelu nie włącza API ani inferencji',
      (tester) async {
    await boot(tester);
    expect(find.textContaining('Silnik llama.cpp jest częścią APK'),
        findsOneWidget);
    await tester.scrollUntilVisible(find.text('Wybierz model'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Wybierz model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wybierz model'));
    await flush(tester);
    expect(
        await tester.runAsync(() => store.setting('model_minicpm_local', '')),
        modelId);
    expect(await tester.runAsync(() => store.setting('paid_enabled', false)),
        isFalse);
    expect(engine.calls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Import i potwierdzone usunięcie aktualizują wybór',
      (tester) async {
    await boot(tester);
    await tester.ensureVisible(find.text('Importuj plik GGUF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importuj plik GGUF'));
    await flush(tester);
    expect(
        await tester.runAsync(() => store.setting('model_minicpm_local', '')),
        'b' * 64);
    // Komunikat importu chwilowo zasłania dolny przycisk na małym ekranie.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('MiniCPM5 2B'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Usuń').last);
    await tester.tap(find.text('Usuń').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń wagi'));
    await flush(tester);
    expect(
        await tester.runAsync(() => store.setting('model_minicpm_local', '')),
        '');
    expect(engine.models, hasLength(1));
    expect(engine.calls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Wpisanie hash 2B nie pobiera ani nie wybiera modelu; import przekazuje hash',
      (tester) async {
    await boot(tester);
    await tester.ensureVisible(find.text('Wpisz hash 2B'));
    await tester.tap(find.text('Wpisz hash 2B'));
    await flush(tester);
    expect(engine.imports, 0);
    expect(engine.calls, 0);
    expect(
        await tester.runAsync(() => store.setting('model_minicpm_local', '')),
        '');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'ec2d5801640099e97d8d7e8003ad4d81f336e757811f03a26173dddf386602fd');
    await tester.ensureVisible(find.text('Importuj plik GGUF'));
    await tester.tap(find.text('Importuj plik GGUF'));
    await flush(tester);
    expect(engine.importedHash,
        'ec2d5801640099e97d8d7e8003ad4d81f336e757811f03a26173dddf386602fd');
    expect(engine.imports, 1);
    expect(engine.calls, 0);
    expect(await tester.runAsync(() => store.setting('paid_enabled', false)),
        isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
