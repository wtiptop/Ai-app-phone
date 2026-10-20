import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/chat/chat_session.dart';
import 'package:scalajaca/chat/prepared_chat.dart';
import 'package:scalajaca/costs/local_cost_gate.dart';
import 'package:scalajaca/memory/context_packet.dart';
import 'package:scalajaca/provider_registry/provider_registry.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:scalajaca/storage/models.dart';
import 'package:scalajaca/storage/transfers.dart';
import 'package:scalajaca/local_inference/source_guidance.dart';

class _Recorder extends ProviderAdapter {
  @override
  String get id => 'minicpm_local';
  @override
  String get label => 'Test bez sieci';
  final requests = <ProviderRequest>[];
  @override
  void cancel() {}
  @override
  Future<List<ProviderModel>> discoverModels(String key) async => [];
  @override
  Stream<ProviderEvent> stream(ProviderRequest request) async* {
    requests.add(request);
    yield const ProviderEvent(delta: 'wynik', done: true);
  }
}

void main() {
  late AppDatabase db;
  late ChatSession session;
  late _Recorder recorder;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await AppDatabase.open(ContentCipher(MemorySecrets()),
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    await db.setSetting('model_minicpm_local', 'fixture');
    recorder = _Recorder();
    session = ChatSession(db, ProviderRegistry([recorder]));
    await session.create();
  });
  tearDown(() async {
    session.dispose();
    await db.close();
  });
  ContextAttachment attachment(
          {String scope = 'rpg:one:gameMaster', bool invalid = false}) =>
      ContextAttachment(
          label: 'Dane testowe',
          text: 'GM_FIXTURE_ONLY',
          scopeKey: scope,
          confidential: true,
          receipt: {'revision': 1},
          validate: () async {
            if (invalid) throw StateError('Źródło cofnięte');
          });
  Future<void> send(PreparedChat prepared, {String? digest}) async {
    final permit = await LocalCostGate(db).authorize(
        'minicpm_local', 'fixture', 0,
        contextDigest: digest ?? prepared.digest);
    await session.send(prepared.userText, 'minicpm_local', 'fixture', '',
        prepared: prepared, permit: permit);
  }

  test('Zatwierdzony snapshot dociera dokładnie do adaptera i zachowuje źródło',
      () async {
    final a = attachment();
    await session.bindScope(a);
    final p = await session.prepare('Pytanie', 'minicpm_local', 'fixture',
        attachment: a);
    await send(p);
    expect(recorder.requests.single.turns.map((t) => t.text),
        p.turns.map((t) => t.text));
    expect(recorder.requests.single.sourceGrounded, isTrue);
    expect(p.turns.first.role, ChatRole.system);
    expect(p.turns.first.text, sourceGuidance);
    expect(p.turns.map((t) => t.role), [ChatRole.system, ChatRole.user]);
    expect(p.turns.last.text, 'Sources:\nGM_FIXTURE_ONLY\nQuestion:\nPytanie');
    final evidence = await db.db.query('chat_context_receipts');
    expect(evidence, hasLength(1));
    expect(await db.cipher.open(evidence.single['evidence'] as String),
        contains('GM_FIXTURE_ONLY'));
  });
  test('Zwykły czat nie dostaje instrukcji źródeł ani trybu zachowawczego',
      () async {
    final p = await session.prepare('Cześć', 'minicpm_local', 'fixture');
    await send(p);
    expect(p.sourceGrounded, isFalse);
    expect(recorder.requests.single.sourceGrounded, isFalse);
    expect(p.turns, hasLength(1));
  });
  test('Usunięcie załącznika zmienia digest nawet przy identycznych rolach',
      () async {
    final a = attachment();
    await session.bindScope(a);
    final p = await session.prepare('Pytanie', 'minicpm_local', 'fixture',
        attachment: a);
    final changed = PreparedChat(
        provider: p.provider,
        model: p.model,
        userText: p.userText,
        turns: p.turns,
        digest: p.digest,
        sessionVersion: p.sessionVersion,
        omitted: p.omitted,
        maxOutputTokens: p.maxOutputTokens);
    expect(await changed.calculateDigest(session.scopeKey), isNot(p.digest));
  });
  test('Cofnięcie źródła po podglądzie blokuje dispatch', () async {
    final a = attachment(invalid: true);
    await session.bindScope(a);
    await send(await session.prepare('Pytanie', 'minicpm_local', 'fixture',
        attachment: a));
    expect(recorder.requests, isEmpty);
    expect(session.error, contains('cofnięte'));
    expect(await db.messageCount(session.conversation!.id), 0);
  });
  test('Zmienione role lub tekst nie mogą użyć zatwierdzonego digestu',
      () async {
    final p = await session.prepare('Pytanie', 'minicpm_local', 'fixture');
    final forged = PreparedChat(
        provider: p.provider,
        model: p.model,
        userText: p.userText,
        turns: [const ChatTurn(role: ChatRole.system, text: 'PODMIENIONO')],
        digest: p.digest,
        sessionVersion: p.sessionVersion,
        omitted: p.omitted,
        maxOutputTokens: p.maxOutputTokens);
    await send(forged);
    expect(recorder.requests, isEmpty);
    expect(session.error, contains('różni'));
  });
  test('Zgoda na inny pakiet nie uprawnia do wysyłki', () async {
    final p = await session.prepare('Pytanie', 'minicpm_local', 'fixture');
    await expectLater(send(p, digest: 'inny'), throwsStateError);
    expect(recorder.requests, isEmpty);
  });
  test('Historia MG nie przechodzi do roli gracza ani ogólnej rozmowy',
      () async {
    final a = attachment();
    await session.bindScope(a);
    await send(await session.prepare('Pytanie', 'minicpm_local', 'fixture',
        attachment: a));
    final c = session.conversation!;
    await session.load(c);
    expect(session.confidential, isTrue);
    await expectLater(
        session.prepare('Dalej', 'minicpm_local', 'fixture'), throwsStateError);
    await expectLater(
        session.prepare('Dalej', 'minicpm_local', 'fixture',
            attachment: attachment(scope: 'rpg:one:rpgPlayer')),
        throwsStateError);
    await session.create();
    final p =
        await session.prepare('Jawne pytanie', 'minicpm_local', 'fixture');
    expect(p.preview, isNot(contains('GM_FIXTURE_ONLY')));
    expect(session.confidential, isFalse);
  });
  test('Klasyczna kopia wyklucza czaty zakresowe, eksport MG jest blokowany',
      () async {
    final a = attachment();
    await session.bindScope(a);
    await send(await session.prepare('Sekret MG', 'minicpm_local', 'fixture',
        attachment: a));
    await expectLater(
        Transfers(db).markdown(session.conversation!), throwsStateError);
    expect(await Transfers(db).snapshot(), isNot(contains('Sekret MG')));
  });
  test('Długa historia ma ograniczony kontekst i stronicowany odczyt',
      () async {
    final c = session.conversation!;
    for (var i = 0; i < 120; i++) {
      await db.saveMessage(Message(
          id: 'm$i',
          conversationId: c.id,
          role: i.isEven ? 'user' : 'assistant',
          text: 'Wpis $i ${'długi tekst ' * 25}'));
    }
    await session.load(c);
    expect(session.messages, hasLength(80));
    expect(session.totalMessages, 120);
    final p = await session.prepare('Co dalej?', 'minicpm_local', 'fixture');
    expect(p.omitted, greaterThan(40));
    expect(p.preview, isNot(contains('Wpis 0 ')));
    expect(
        (await db.messages(c.id, limit: 40)).first.text, startsWith('Wpis 0 '));
    expect(await db.messageCount(c.id), 120);
  });
}
