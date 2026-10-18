import 'package:test/test.dart';
import 'package:scalajaca/costs/cost_store.dart';
import 'package:scalajaca/costs/local_cost_gate.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _CostStore implements CostStore {
  _CostStore(this.db);
  @override
  final Database db;
  final settings = <String, Object>{};
  @override
  Future<T> setting<T>(String key, T fallback) async =>
      (settings[key] ?? fallback) as T;
  Future<void> setSetting(String key, Object value) async =>
      settings[key] = value;
  Future<void> close() => db.close();
}

void main() {
  late _CostStore store;
  late LocalCostGate gate;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await database.execute(
        'CREATE TABLE cost_reservations (id TEXT PRIMARY KEY, amount REAL NOT NULL, created INTEGER NOT NULL, provider TEXT NOT NULL)');
    store = _CostStore(database);
    gate = LocalCostGate(store);
    await store.setSetting('model_minicpm', 'owner-model');
    await store.setSetting('input_rate_minicpm', 0.0);
    await store.setSetting('output_rate_minicpm', 0.0);
  });
  tearDown(() async => store.close());

  test('Model w telefonie nie wymaga cennika ani włączenia płatnych API',
      () async {
    await store.setSetting('model_minicpm_local', 'a' * 64);
    expect(await gate.estimate('minicpm_local', 'a' * 64, 'tekst'), 0);
    final permit = await gate.authorize('minicpm_local', 'a' * 64, 0);
    permit.consume('minicpm_local', 'a' * 64);
    await expectLater(
        gate.authorize('minicpm_local', 'inny', 0), throwsStateError);
    await expectLater(
        gate.authorize('minicpm_local', 'a' * 64, 0.1), throwsStateError);
    expect(await store.db.query('cost_reservations'), isEmpty);
    expect(await store.setting('paid_enabled', false), isFalse);
  });

  test('Zero bez deklaracji właściciela blokuje estimate i permit', () async {
    await expectLater(
      gate.estimate('minicpm', 'owner-model', 'treść'),
      throwsStateError,
    );
    await expectLater(
      gate.authorize('minicpm', 'owner-model', 0),
      throwsStateError,
    );
  });
  test('Deklaracja bez opłat nie odblokowuje płatnych API', () async {
    await store.setSetting('minicpm_self_hosted_free', true);
    expect(await gate.estimate('minicpm', 'owner-model', 'treść'), 0);
    final permit = await gate.authorize('minicpm', 'owner-model', 0);
    expect(() => permit.consume('openai', 'owner-model'), throwsStateError);
    permit.consume('minicpm', 'owner-model');
    expect(() => permit.consume('minicpm', 'owner-model'), throwsStateError);
    await expectLater(
      gate.authorize('openai', 'paid-model', 0.1),
      throwsStateError,
    );
    expect(await store.db.query('cost_reservations'), isEmpty);
    expect(await store.setting('paid_enabled', false), isFalse);
  });
  test('Zero wymaga zgodnego modelu i obu stawek 0', () async {
    await store.setSetting('minicpm_self_hosted_free', true);
    await expectLater(
      gate.authorize('minicpm', 'wrong-model', 0),
      throwsStateError,
    );
    await store.setSetting('output_rate_minicpm', 1.0);
    await expectLater(
      gate.authorize('minicpm', 'owner-model', 0),
      throwsStateError,
    );
    expect(await gate.estimate('minicpm', 'owner-model', 'x'), greaterThan(0));
    await expectLater(
      gate.authorize('minicpm', 'owner-model', 0.1),
      throwsStateError,
    );
  });
  test('Porównanie demo + darmowy serwer działa bez płatnego API', () async {
    await store.setSetting('minicpm_self_hosted_free', true);
    final permits = await gate.authorizeMany({
      'demo': (model: 'demo-local', amount: 0),
      'minicpm': (model: 'owner-model', amount: 0),
    });
    permits['minicpm']!.consume('minicpm', 'owner-model');
    await expectLater(
      gate.authorizeMany({
        'minicpm': (model: 'owner-model', amount: 0),
        'openai': (model: 'paid-model', amount: 0.1),
      }),
      throwsStateError,
    );
    expect(await store.db.query('cost_reservations'), isEmpty);
  });
  test('Porównanie z płatnym API rezerwuje wyłącznie jego rzeczywisty koszt',
      () async {
    await store.setSetting('minicpm_self_hosted_free', true);
    await store.setSetting('paid_enabled', true);
    final permits = await gate.authorizeMany({
      'minicpm': (model: 'owner-model', amount: 0),
      'openai': (model: 'paid-model', amount: 0.1),
    });
    final rows = await store.db.query('cost_reservations');
    expect(rows, hasLength(1));
    expect(rows.single['provider'], 'openai');
    expect(rows.single['amount'], 0.1);
    permits['minicpm']!.consume('minicpm', 'owner-model');
  });
  test('Zerowe kwoty innych dostawców nie uzyskują permit', () async {
    await store.setSetting('minicpm_self_hosted_free', true);
    await store.setSetting('paid_enabled', true);
    await expectLater(
        gate.authorize('openai', 'paid-model', 0), throwsStateError);
    expect(await store.db.query('cost_reservations'), isEmpty);
  });
  test('Równoległe rezerwy dodatnie nie przekraczają budżetu SQLite', () async {
    await store.setSetting('paid_enabled', true);
    await store.setSetting('daily_budget', 1.0);
    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        gate
            .authorize('minicpm', 'owner-model', 0.7)
            .then((_) => true, onError: (_) => false),
    ]);
    expect(results.where((ok) => ok), hasLength(1));
    expect(await store.db.query('cost_reservations'), hasLength(1));
  });
}
