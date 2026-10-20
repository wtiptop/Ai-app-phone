import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/chat/chat_session.dart';
import 'package:scalajaca/provider_registry/provider_registry.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:scalajaca/storage/models.dart';
import 'package:scalajaca/ui/home.dart';
import 'package:scalajaca/rpg/campaign_store.dart';
import 'package:scalajaca/ui/campaign_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local/local_adapter_test.dart' show FakeLocalEngine, modelId;

/// Rejestruje próbę wejścia do adaptera, bez wykonywania sieci i opłat.
class _CountingApi implements ProviderAdapter {
  int calls = 0;
  @override
  String get id => 'openai';
  @override
  String get label => 'OpenAI test';
  @override
  void cancel() {}
  @override
  Future<List<ProviderModel>> discoverModels(String apiKey) async => const [];
  @override
  Stream<ProviderEvent> stream(ProviderRequest request) async* {
    calls++;
    yield const ProviderEvent(delta: 'Nie powinno być wywołane', done: true);
  }
}

Finder _field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

/// SQLite FFI wykonuje pracę poza fake clockiem widget testu. Dajemy jej realny
/// czas, a animacjom czas testowy, bez sieci i bez oczekiwania na urządzenie.
Future<void> _flush(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _boot(
  WidgetTester tester,
  AppDatabase store,
  SecretStore secrets, {
  ProviderRegistry? registry,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Home(
        store: store,
        secrets: secrets,
        registry: registry ??
            ProviderRegistry([
              DemoAdapter(chunkDelay: Duration.zero),
              _CountingApi(),
            ]),
        onTheme: (_) {},
      ),
    ),
  );
  await _flush(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase store;
  late MemorySecrets secrets;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    secrets = MemorySecrets();
    store = await AppDatabase.open(
      ContentCipher(secrets),
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await store.setSetting('onboarded', true);
  });
  tearDown(() async => store.close());

  for (final contextSize in [1024, 2048]) {
    testWidgets(
        'Mały kontekst $contextSize pozwala czytać kampanię, ale wymaga 4096 dla modelu',
        (tester) async {
      final engine = FakeLocalEngine();
      await tester.runAsync(() async {
        await store.setSetting('local_context', contextSize);
        await store.setSetting('model_minicpm_local', modelId);
        await CampaignStore(store).create(
            name: 'Własna kampania testowa',
            edition: 'Testowa',
            ownerId: 'local-owner');
      });
      await _boot(tester, store, secrets,
          registry: ProviderRegistry([
            DemoAdapter(chunkDelay: Duration.zero),
            LocalModelAdapter(engine: engine)
          ]));
      await tester.tap(find.textContaining('Demo lokalne').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('MiniCPM • offline w telefonie').last);
      await tester.pumpAndSettle();
      await _flush(tester);
      await tester.tap(find.text('Pamięć'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kampanie RPG i lore'));
      await _flush(tester);
      expect(find.byType(CampaignPage), findsOneWidget);
      await tester.tap(find.text('Własna kampania testowa'));
      await _flush(tester);
      await tester.scrollUntilVisible(
          find.text('Podgląd pakietu dla czatu'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(
                  FilledButton, 'Podgląd pakietu dla czatu'))
              .onPressed,
          isNull);
      await tester.scrollUntilVisible(
          find.textContaining(
              'Dla pakietów kampanii MiniCPM ustaw kontekst 4096'),
          150,
          scrollable: find.byType(Scrollable).first);
      expect(
          find.textContaining('Przeglądanie i zapis kampanii nadal działają.'),
          findsOneWidget);
      expect(engine.calls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Start bez konta pokazuje demo i pięć miejsc nawigacji', (
    tester,
  ) async {
    await _boot(tester, store, secrets);
    expect(find.text('Witaj w Scalającej'), findsNothing);
    expect(find.textContaining('DEMO OFFLINE'), findsOneWidget);
    for (final label in ['Czat', 'Agenci', 'Pamięć', 'Zadania', 'Ustawienia']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      await tester.runAsync(() => store.setting('paid_enabled', false)),
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Czat demo zapisuje treść lokalnie i jasno oznacza atrapę', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _boot(tester, store, secrets);
      await tester.enterText(find.byType(TextField), 'Zażółć gęślą jaźń 😀');
      await _flush(tester);
      await tester.tap(find.byTooltip('Wyślij wiadomość'));
      await _flush(tester, rounds: 30);
      final conversations = await tester.runAsync(() => store.conversations());
      expect(conversations, hasLength(1));
      final messages = await tester.runAsync(
        () => store.messages(conversations!.single.id),
      );
      expect(messages, hasLength(2));
      expect(messages!.first.text, 'Zażółć gęślą jaźń 😀');
      expect(messages.last.status, 'complete');
      expect(messages.last.provider, 'demo');
      expect(messages.last.text, contains('demo'));
      expect(find.textContaining('Ukończono'), findsOneWidget);
      final status = tester.getSemantics(find.textContaining('Ukończono'));
      expect(status.label, contains('Ukończono • 0 USD za API'));
      expect(status.flagsCollection.isLiveRegion, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'Czat uruchamia model lokalny po zgodzie, bez klucza i płatnego API',
      (tester) async {
    final engine = FakeLocalEngine();
    final cloud = _CountingApi();
    await tester
        .runAsync(() => store.setSetting('model_minicpm_local', modelId));
    await _boot(tester, store, secrets,
        registry: ProviderRegistry([
          DemoAdapter(chunkDelay: Duration.zero),
          cloud,
          LocalModelAdapter(engine: engine)
        ]));
    await tester.tap(find.textContaining('Demo lokalne').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MiniCPM • offline w telefonie').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Wiadomość offline');
    await _flush(tester);
    await tester.tap(find.byTooltip('Wyślij wiadomość'));
    await _flush(tester);
    expect(find.text('Uruchom model offline?'), findsOneWidget);
    await tester.tap(find.text('Uruchom offline'));
    await _flush(tester, rounds: 20);
    expect(engine.calls, 1);
    expect(cloud.calls, 0);
    expect(await tester.runAsync(() => store.setting('paid_enabled', false)),
        isFalse);
    final chats = await tester.runAsync(() => store.conversations());
    final messages =
        await tester.runAsync(() => store.messages(chats!.single.id));
    expect(messages!.last.provider, 'minicpm_local');
    expect(messages.last.text, 'Odpowiedź');
    expect(messages.last.status, 'complete');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Pamięć i zadania pozwalają dodać własne lokalne dane', (
    tester,
  ) async {
    await _boot(tester, store, secrets);
    await tester.tap(find.text('Pamięć'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notatka'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Tytuł'), 'Moja lokalna notatka');
    await tester.enterText(
      _field('Treść • Markdown'),
      'Treść bez konta i sieci.',
    );
    await tester.tap(find.text('Zapisz lokalnie'));
    await _flush(tester);
    final notes = await tester.runAsync(() => store.notes());
    expect(notes, hasLength(1));
    expect(notes!.single.folder, 'INBOX');
    expect(find.text('Moja lokalna notatka'), findsOneWidget);

    await tester.tap(find.text('Zadania'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dodaj zadanie'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _field('Co chcesz zrobić?'),
      'Sprawdź prywatną kopię',
    );
    await tester.tap(find.text('Dodaj'));
    await _flush(tester);
    expect(find.text('Sprawdź prywatną kopię'), findsOneWidget);
    final tasks = await tester.runAsync(() => store.db.query('tasks'));
    expect(tasks, hasLength(1));
    final title = await tester.runAsync(
      () => store.cipher.open(tasks!.single['title'] as String),
    );
    expect(title, 'Sprawdź prywatną kopię');
    expect(find.textContaining('nie uruchamiają się w tle'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Mały ekran i tekst 200% zachowują akcje i semantykę', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
      await _boot(tester, store, secrets, textScale: 2);
      final send = tester.getSemantics(find.byTooltip('Wyślij wiadomość'));
      expect(send.label, contains('Wyślij wiadomość'));
      expect(send.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Pamięć'));
      await _flush(tester);
      expect(find.text('Projekty i pamięć'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'Markdown nie wczytuje obrazów sieciowych ani plików z odpowiedzi',
    (tester) async {
      await tester.runAsync(() async {
        final conversation = await store.createConversation('Historia obrazów');
        await store.saveMessage(
          Message(
            id: 'external-images',
            conversationId: conversation.id,
            role: 'assistant',
            text: '![tracker](https://tracker.invalid/pixel)\n\n'
                '![sekret](/data/data/pl.scalajaca/app/secret.png)',
          ),
        );
      });
      await _boot(tester, store, secrets);
      await tester.tap(find.byTooltip('Historia i wyszukiwanie'));
      await _flush(tester);
      await tester.tap(find.text('Historia obrazów'));
      await _flush(tester);
      expect(
        find.byType(Image),
        findsNothing,
        reason: 'Treść modeli nie może sama uruchamiać odczytu URL ani pliku.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'Bez permitu płatne API nie tworzy rozmowy ani nie wchodzi w adapter',
    () async {
      final api = _CountingApi();
      final session = ChatSession(store, ProviderRegistry([api]));
      await session.send(
        'Nie wysyłaj bez zgody',
        api.id,
        'test-model',
        'test-key',
      );
      expect(api.calls, 0);
      expect(session.error, contains('zgoda'));
      expect(session.messages, isEmpty);
      expect(await store.conversations(), isEmpty);
      session.dispose();
    },
  );

  test(
    'Tryb prywatny pozostawia wiadomości wyłącznie w pamięci sesji',
    () async {
      final session = ChatSession(
        store,
        ProviderRegistry([DemoAdapter(chunkDelay: Duration.zero)]),
      );
      await session.create(privateMode: true);
      await session.saveDraft('Prywatny niewysłany szkic');
      await session.send('Prywatna treść', 'demo', 'demo-local', '');
      expect(session.messages, hasLength(2));
      expect(session.messages.first.text, 'Prywatna treść');
      expect(await store.conversations(), isEmpty);
      expect(await store.db.query('messages'), isEmpty);
      session.dispose();
    },
  );
}
