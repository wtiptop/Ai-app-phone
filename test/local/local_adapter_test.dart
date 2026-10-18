import 'dart:async';
import 'package:test/test.dart';
import 'package:scalajaca/local_inference/local_adapter.dart';
import 'package:scalajaca/local_inference/local_engine.dart';
import 'package:scalajaca/provider_registry/provider_adapter.dart';

const modelId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class FakeLocalEngine implements LocalInferenceEngine {
  int calls = 0, stops = 0;
  int? context, limit;
  String? selected;
  Stream<ProviderEvent> response = Stream.fromIterable(const [
    ProviderEvent(delta: 'Odpowiedź'),
    ProviderEvent(
        done: true, usage: TokenUsage(inputTokens: 8, outputTokens: 2))
  ]);
  @override
  Stream<ProviderEvent> generate(
      {required String model,
      required List<ChatTurn> turns,
      required int context,
      required int maxTokens}) {
    calls++;
    selected = model;
    this.context = context;
    limit = maxTokens;
    return response;
  }

  @override
  void cancel() {
    stops++;
  }

  @override
  Future<LocalEngineStatus> status() async =>
      const LocalEngineStatus(commit: 'test', models: [
        LocalModel(
            id: modelId,
            name: 'MiniCPM5 1B',
            profile: 'minicpm5_1b',
            bytes: 1000)
      ]);
  @override
  Future<LocalModel?> importModel({String expectedSha256 = ''}) async => null;
  @override
  Future<void> removeModel(String id) async {}
  @override
  Future<void> cancelImport() async {}
}

ProviderRequest input(
        {String id = modelId,
        String key = '',
        String text = 'Witaj',
        int maxTokens = 1024}) =>
    ProviderRequest(
        model: id,
        apiKey: key,
        turns: [ChatTurn(role: ChatRole.user, text: text)],
        maxOutputTokens: maxTokens);
void main() {
  test('Lokalny adapter przekazuje tekst i usage, ogranicza wyjście do 512',
      () async {
    final engine = FakeLocalEngine();
    final adapter =
        LocalModelAdapter(engine: engine, readContext: () async => 4096);
    final events = await adapter.stream(input()).toList();
    expect(events.first.delta, 'Odpowiedź');
    expect(events.last.done, isTrue);
    expect(events.last.usage?.inputTokens, 8);
    expect(engine.context, 4096);
    expect(engine.limit, 512);
    expect(engine.selected, modelId);
  });
  test('Mniejszy limit żądania pozostaje zachowany', () async {
    final engine = FakeLocalEngine();
    await LocalModelAdapter(engine: engine)
        .stream(input(maxTokens: 16))
        .toList();
    expect(engine.limit, 16);
  });
  for (final id in [
    '',
    '../model.gguf',
    '/sdcard/model.gguf',
    'g' * 64,
    'a' * 63
  ]) {
    test('Nie przekazuje ścieżki lub złego ID: $id', () async {
      final engine = FakeLocalEngine();
      await expectLater(
          LocalModelAdapter(engine: engine).stream(input(id: id)).toList(),
          throwsA(isA<ProviderException>()));
      expect(engine.calls, 0);
    });
  }
  test('Sekret API nigdy nie trafia do silnika offline', () async {
    final engine = FakeLocalEngine();
    await expectLater(
        LocalModelAdapter(engine: engine)
            .stream(input(key: 'cloud-secret-placeholder'))
            .toList(),
        throwsA(isA<ProviderException>()));
    expect(engine.calls, 0);
  });
  test('Limit bajtów, liczby wiadomości i kontekstu działa przed silnikiem',
      () async {
    final engine = FakeLocalEngine();
    final adapter =
        LocalModelAdapter(engine: engine, readContext: () async => 2049);
    await expectLater(
        adapter.stream(input()).toList(), throwsA(isA<ProviderException>()));
    await expectLater(adapter.stream(input(text: 'ą' * 40000)).toList(),
        throwsA(isA<ProviderException>()));
    await expectLater(
        adapter
            .stream(ProviderRequest(model: modelId, turns: [
              for (var i = 0; i < 129; i++)
                const ChatTurn(role: ChatRole.user, text: 'x')
            ]))
            .toList(),
        throwsA(isA<ProviderException>()));
    expect(engine.calls, 0);
  });
  test('Stop przed zakończeniem konfiguracji nie uruchamia modelu', () async {
    final ready = Completer<int>();
    final engine = FakeLocalEngine();
    final adapter =
        LocalModelAdapter(engine: engine, readContext: () => ready.future);
    final check = expectLater(
        adapter.stream(input()).toList(),
        throwsA(isA<ProviderException>()
            .having((e) => e.code, 'kod', 'cancelled')));
    await Future<void>.delayed(Duration.zero);
    adapter.cancel();
    ready.complete(2048);
    await check;
    expect(engine.calls, 0);
  });
  test('Przerwany strumień i brak modelu są błędem bez fallbacku', () async {
    final engine = FakeLocalEngine()
      ..response = Stream.value(const ProviderEvent(delta: 'część'));
    final adapter = LocalModelAdapter(engine: engine);
    await expectLater(
        adapter.stream(input()).toList(), throwsA(isA<ProviderException>()));
    engine.response = Stream.error(localError('missing_model'));
    await expectLater(
        adapter.stream(input()).toList(),
        throwsA(isA<ProviderException>()
            .having((e) => e.code, 'kod', 'missing_model')));
    expect(engine.calls, 2);
  });
  test('Katalog obejmuje tylko lokalnie zaimportowane modele', () async {
    final engine = FakeLocalEngine();
    final models = await LocalModelAdapter(engine: engine).discoverModels('');
    expect(models.single.id, modelId);
    expect(engine.calls, 0);
  });
}
