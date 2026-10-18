import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scalajaca/auth/secret_store.dart';
import 'package:scalajaca/storage/app_database.dart';
import 'package:scalajaca/storage/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory scratch;
  late String databasePath;
  late MemorySecrets secrets;
  final opened = <AppDatabase>[];

  Future<AppDatabase> open() async {
    final result = await AppDatabase.open(
      ContentCipher(secrets),
      factory: databaseFactoryFfi,
      path: databasePath,
    );
    opened.add(result);
    return result;
  }

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    secrets = MemorySecrets();
    final parent = await Directory(
      p.join(Directory.current.path, 'work', 'storage-tests'),
    ).create(recursive: true);
    scratch = await parent.createTemp('run-');
    databasePath = p.join(scratch.path, 'scalajaca.db');
    opened.clear();
  });
  tearDown(() async {
    for (final store in opened) {
      if (store.db.isOpen) await store.close();
    }
    final parent = p.normalize(
      p.absolute(p.join(Directory.current.path, 'work', 'storage-tests')),
    );
    final target = p.normalize(p.absolute(scratch.path));
    if (!p.isWithin(parent, target)) {
      throw StateError('Odmowa sprzątania poza katalogiem testów.');
    }
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  test('Migracja v1→v3 zachowuje dane i dodaje nowe tabele', () async {
    final cipher = ContentCipher(secrets);
    await cipher.initialize();
    final legacy = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => AppDatabase.createV1(db),
      ),
    );
    try {
      await legacy.insert('conversations', {
        'id': 'legacy-conversation',
        'title': await cipher.seal('Rozmowa v1'),
        'draft': await cipher.seal('Niewysłany szkic'),
        'updated': 1,
        'pinned': 1,
      });
      await legacy.insert('messages', {
        'id': 'legacy-message',
        'conversation_id': 'legacy-conversation',
        'role': 'user',
        'content': await cipher.seal('Treść sprzed migracji 😀'),
        'provider': 'demo',
        'model': 'demo-local',
        'status': 'complete',
        'created': 1,
      });
      await legacy.insert('settings', {'key': 'theme', 'value': '"dark"'});
      await legacy.insert('notes', {
        'id': 'legacy-note',
        'title': await cipher.seal('Notatka v1'),
        'content': await cipher.seal('Dane nie mogą zniknąć.'),
        'folder': 'INBOX',
        'updated': 1,
      });
    } finally {
      await legacy.close();
    }
    final store = await open();
    expect(await store.db.getVersion(), 3);
    final conversation = (await store.conversations()).single;
    expect(conversation.title, 'Rozmowa v1');
    expect(conversation.draft, 'Niewysłany szkic');
    expect(conversation.pinned, isTrue);
    expect(
      (await store.messages(conversation.id)).single.text,
      'Treść sprzed migracji 😀',
    );
    expect((await store.notes()).single.text, 'Dane nie mogą zniknąć.');
    expect(await store.setting('theme', 'system'), 'dark');
    for (final table in [
      'operations',
      'tasks',
      'cost_reservations',
      'memory_collections',
      'memory_versions',
      'analysis_checkpoints',
      'chat_context_receipts',
      'chat_scopes',
      'rpg_campaigns'
    ]) {
      expect(await store.db.query(table), isEmpty);
    }
  });

  test('Migracja v2→v3 zachowuje istniejący czat i rezerwy', () async {
    final cipher = ContentCipher(secrets);
    await cipher.initialize();
    final legacy = await databaseFactoryFfi.openDatabase(databasePath,
        options: OpenDatabaseOptions(
            version: 2,
            onCreate: (db, _) async {
              await AppDatabase.createV1(db);
              await AppDatabase.migrateV2(db);
            }));
    await legacy.insert('conversations', {
      'id': 'v2',
      'title': await cipher.seal('Zachowane'),
      'draft': await cipher.seal('Szkic'),
      'updated': 1
    });
    await legacy.insert('cost_reservations',
        {'id': 'reserve', 'amount': 0.1, 'created': 1, 'provider': 'fixture'});
    await legacy.close();
    final store = await open();
    expect(await store.db.getVersion(), 3);
    expect((await store.conversations()).single.draft, 'Szkic');
    expect((await store.db.query('cost_reservations')).single['amount'], 0.1);
    expect(await store.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
    'Zamknięcie i ponowne otwarcie zachowuje rozmowę, szkic i notatkę',
    () async {
      var store = await open();
      final conversation = await store.createConversation('Zażółć gęślą jaźń');
      await store.draft(conversation.id, 'Szkic po restarcie 😀');
      await store.pin(conversation.id, true);
      await store.saveMessage(
        Message(
          id: 'persisted-message',
          conversationId: conversation.id,
          role: 'user',
          text: 'Szukana fraza — Berlin/Hamburg',
        ),
      );
      await store.saveNote(
        'Dokument PL/DE',
        'Własna pamięć bez Obsidiana.',
        'PERSONAL',
      );
      await store.close();

      store = await open();
      final restored = (await store.conversations()).single;
      expect(restored.id, conversation.id);
      expect(restored.draft, 'Szkic po restarcie 😀');
      expect(restored.pinned, isTrue);
      expect(
        (await store.messages(restored.id)).single.text,
        'Szukana fraza — Berlin/Hamburg',
      );
      expect(await store.conversations('berlin/hamburg'), hasLength(1));
      expect(await store.conversations('nieistniejąca fraza'), isEmpty);
      expect((await store.notes('obsidiana')).single.folder, 'PERSONAL');
    },
  );

  test('Restart oznacza przerwane streamy i operacje bez ponawiania', () async {
    var store = await open();
    final conversation = await store.createConversation();
    for (final status in ['streaming', 'complete', 'cancelled']) {
      await store.saveMessage(
        Message(
          id: status,
          conversationId: conversation.id,
          role: 'assistant',
          text: 'Częściowa treść $status',
          status: status,
        ),
      );
    }
    for (final status in ['running', 'pending', 'cancelled']) {
      await store.db.insert('operations', {
        'id': status,
        'conversation_id': conversation.id,
        'status': status,
        'type': 'draft',
        'created': 1,
        'attempts': 2,
        'dedup_key': status,
      });
    }
    await store.close();
    store = await open();
    final messages = {
      for (final m in await store.messages(conversation.id)) m.id: m,
    };
    expect(messages['streaming']!.status, 'interrupted');
    expect(messages['streaming']!.text, 'Częściowa treść streaming');
    expect(messages['complete']!.status, 'complete');
    expect(messages['cancelled']!.status, 'cancelled');
    final operations = {
      for (final op in await store.db.query('operations')) op['id']: op,
    };
    expect(operations, hasLength(3));
    expect(operations['running']!['status'], 'interrupted');
    expect(operations['pending']!['status'], 'pending');
    expect(operations['cancelled']!['status'], 'cancelled');
    expect(operations.values.every((op) => op['attempts'] == 2), isTrue);
  });

  test(
    'Kolejka deduplikuje szkic, a usunięcie rozmowy czyści powiązania',
    () async {
      final store = await open();
      final conversation = await store.createConversation();
      await store.saveMessage(
        Message(
          id: 'message',
          conversationId: conversation.id,
          role: 'user',
          text: 'Treść',
        ),
      );
      final first = await store.queue(conversation.id);
      final second = await store.queue(conversation.id);
      expect(second, first);
      expect(await store.db.query('operations'), hasLength(1));
      await store.deleteConversation(conversation.id);
      expect(await store.conversations(), isEmpty);
      expect(await store.db.query('messages'), isEmpty);
      expect(await store.db.query('operations'), isEmpty);
    },
  );

  test(
    'Nieudany zapis obcego conversationId nie pozostawia wiadomości',
    () async {
      final store = await open();
      final conversation = await store.createConversation('Zachowana rozmowa');
      await expectLater(
        store.saveMessage(
          const Message(
            id: 'orphan',
            conversationId: 'nieistniejący-id',
            role: 'user',
            text: 'Nie może powstać osierocona wiadomość',
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await store.db.query('messages'), isEmpty);
      expect((await store.conversations()).single.id, conversation.id);
    },
  );

  test('Utrata klucza istniejącej bazy nie nadpisuje go nowym', () async {
    final store = await open();
    await store.createConversation('Dane do odzyskania z kopii');
    await store.close();
    await secrets.delete('local_content_key_v1');
    await expectLater(open(), throwsStateError);
    expect(await secrets.read('local_content_key_v1'), isNull);
    expect(await File(databasePath).exists(), isTrue);
  });
}
