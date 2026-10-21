import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/local_inference/local_engine.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:scalajaca/ui/colibri_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local/local_adapter_test.dart' show FakeLocalEngine;
import 'local_models_test.dart' show flush;

class ColibriTestEngine extends FakeLocalEngine {
  String? importedHash;
  int imports = 0;
  final installed = <LocalModel>[];
  @override
  Future<LocalEngineStatus> status() async => LocalEngineStatus(
      commit: 'e0db083cdc9e563e0766cc6fc661ef23c32298e0',
      models: List.of(installed));
  @override
  Future<LocalModel?> importModel({String expectedSha256 = ''}) async {
    imports++;
    importedHash = expectedSha256;
    final model = LocalModel(
        id: expectedSha256,
        name: 'OLMoE pełne',
        profile: 'olmoe-instruct',
        bytes: 7416456156);
    installed.add(model);
    return model;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ColibriTestEngine engine;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await AppDatabase.open(ContentCipher(MemorySecrets()),
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    engine = ColibriTestEngine();
  });
  tearDown(() async => db.close());
  testWidgets(
      'Hash paczki nie instaluje ani nie generuje; dopiero osobny import przekazuje manifest',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: ColibriModelsPage(engine: engine, store: db)));
    await flush(tester);
    await tester.scrollUntilVisible(
        find.text('Wpisz hash paczki OLMoE 0.5.5'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Wpisz hash paczki OLMoE 0.5.5'));
    await flush(tester);
    expect(engine.imports, 0);
    expect(engine.calls, 0);
    expect(
        await tester.runAsync(() => db.setting('model_colibri_local', '')), '');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '504f62581e7a16037d4aac6cc831a6de6e7cd93995501970f34a76de5f44210f');
    await tester.ensureVisible(find.text('Zainstaluj paczkę Colibri ZIP'));
    await tester.tap(find.text('Zainstaluj paczkę Colibri ZIP'));
    await flush(tester);
    expect(engine.imports, 1);
    expect(engine.importedHash,
        '504f62581e7a16037d4aac6cc831a6de6e7cd93995501970f34a76de5f44210f');
    expect(await tester.runAsync(() => db.setting('model_colibri_local', '')),
        engine.importedHash);
    expect(await tester.runAsync(() => db.setting('paid_enabled', false)),
        isFalse);
    expect(engine.calls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
