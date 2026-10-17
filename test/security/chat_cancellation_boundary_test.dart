import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/chat/chat_session.dart';
import 'package:scalajaca/costs/local_cost_gate.dart';
import 'package:scalajaca/provider_registry/provider_registry.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:scalajaca/storage/models.dart';

class _CountingAdapter extends ProviderAdapter {
  _CountingAdapter([this.provider = 'demo']);
  final String provider;
  int dispatched = 0;
  @override
  String get id => provider;
  @override
  String get label => 'Lokalna atrapa testowa';
  @override
  void cancel() {}
  @override
  Future<List<ProviderModel>> discoverModels(String apiKey) async => [];
  @override
  Stream<ProviderEvent> stream(ProviderRequest request) async* {
    dispatched++;
    yield const ProviderEvent(delta: 'Lokalny wynik', done: true);
  }
}

class _PausedSave extends AppDatabase {
  _PausedSave(super.db, super.cipher);
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> saveMessage(Message message) async {
    if (message.role == 'user') {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    await super.saveMessage(message);
  }
}

class _PausedCreate extends AppDatabase {
  _PausedCreate(super.db, super.cipher);
  final entered = Completer<void>();
  final release = Completer<void>();
  int createCalls = 0;
  @override
  Future<Conversation> createConversation([
    String title = 'Nowa rozmowa',
  ]) async {
    createCalls++;
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return super.createConversation(title);
  }
}

void main() {
  late AppDatabase original;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    original = await AppDatabase.open(
      ContentCipher(MemorySecrets()),
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(() async => original.close());

  test('Anulowanie przed dispatch nie wywołuje nawet adaptera', () async {
    final store = _PausedSave(original.db, original.cipher);
    final adapter = _CountingAdapter();
    final session = ChatSession(store, ProviderRegistry([adapter]));
    await session.create();
    final pending = session.send(
      'Anuluj przed siecią',
      'demo',
      'demo-local',
      '',
    );
    await store.entered.future;
    session.cancel();
    store.release.complete();
    await pending;
    expect(adapter.dispatched, 0);
    expect(session.busy, isFalse);
    session.dispose();
  });

  test('Podwójna pierwsza wysyłka nie tworzy dwóch żądań ani rozmów', () async {
    final store = _PausedCreate(original.db, original.cipher);
    final adapter = _CountingAdapter();
    final session = ChatSession(store, ProviderRegistry([adapter]));
    final first = session.send('Pierwsza wiadomość', 'demo', 'demo-local', '');
    await store.entered.future;
    final second = session.send('Drugie kliknięcie', 'demo', 'demo-local', '');
    store.release.complete();
    await Future.wait([first, second]);
    expect(store.createCalls, 1);
    expect(adapter.dispatched, 1);
    expect((await store.conversations()).length, 1);
    session.dispose();
  });

  test('Tryb prywatny nie zapisuje rozmowy, szkicu ani wiadomości', () async {
    final adapter = _CountingAdapter();
    final session = ChatSession(original, ProviderRegistry([adapter]));
    await session.create(privateMode: true);
    await session.saveDraft('Nie zapisuj szkicu');
    await session.send('Nie zapisuj wiadomości', 'demo', 'demo-local', '');
    expect(session.messages.length, 2);
    expect(await original.conversations(), isEmpty);
    expect(await original.db.query('messages'), isEmpty);
    session.dispose();
  });

  test(
    'Brak permit blokuje płatny dispatch, a zatwierdzenie jest jednorazowe',
    () async {
      final adapter = _CountingAdapter('openai');
      final session = ChatSession(original, ProviderRegistry([adapter]));
      await session.send('Bez zgody', 'openai', 'test-model', 'test-key');
      expect(adapter.dispatched, 0);
      expect(session.error, contains('zgoda'));
      expect(await original.conversations(), isEmpty);
      await original.setSetting('paid_enabled', true);
      final permit =
          await LocalCostGate(original).authorize('openai', 'test-model', 0.01);
      await session.send(
        'Zatwierdzone',
        'openai',
        'test-model',
        'test-key',
        permit: permit,
      );
      expect(adapter.dispatched, 1);
      await expectLater(
        session.send(
          'Ponownie',
          'openai',
          'test-model',
          'test-key',
          permit: permit,
        ),
        throwsStateError,
      );
      expect(adapter.dispatched, 1);
      session.dispose();
    },
  );
}
