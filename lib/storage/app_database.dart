import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../auth/secret_store.dart';
import 'models.dart';

class AppDatabase {
  AppDatabase(this.db, this.cipher);
  final Database db;
  final ContentCipher cipher;
  static Future<AppDatabase> open(
    ContentCipher cipher, {
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final location = path ?? p.join(await f.getDatabasesPath(), 'scalajaca.db');
    await cipher.initialize(requireExisting: await f.databaseExists(location));
    final database = await f.openDatabase(
      location,
      options: OpenDatabaseOptions(
        singleInstance: location != inMemoryDatabasePath,
        version: 2,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.rawQuery('PRAGMA journal_mode = WAL');
        },
        onCreate: (db, version) async {
          await createV1(db);
          await migrateV2(db);
        },
        onUpgrade: (db, old, version) async {
          if (old < 2) await migrateV2(db);
        },
      ),
    );
    // Zasada: nigdy automatycznie nie ponawiamy żądania po restarcie.
    await database.update(
      'messages',
      {'status': 'interrupted'},
      where: 'status = ?',
      whereArgs: ['streaming'],
    );
    await database.update(
      'operations',
      {'status': 'interrupted'},
      where: 'status = ?',
      whereArgs: ['running'],
    );
    return AppDatabase(database, cipher);
  }

  static Future<void> createV1(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE conversations(id TEXT PRIMARY KEY, title TEXT NOT NULL, draft TEXT NOT NULL, updated INTEGER NOT NULL, pinned INTEGER NOT NULL DEFAULT 0)',
    );
    await db.execute(
      'CREATE TABLE messages(id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE, role TEXT NOT NULL, content TEXT NOT NULL, provider TEXT NOT NULL, model TEXT NOT NULL, status TEXT NOT NULL, created INTEGER NOT NULL, input_tokens INTEGER, output_tokens INTEGER)',
    );
    await db.execute(
      'CREATE INDEX messages_conversation ON messages(conversation_id, created)',
    );
    await db.execute(
      'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE notes(id TEXT PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL, folder TEXT NOT NULL, updated INTEGER NOT NULL)',
    );
  }

  static Future<void> migrateV2(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE operations(id TEXT PRIMARY KEY, conversation_id TEXT, status TEXT NOT NULL, type TEXT NOT NULL, created INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, dedup_key TEXT NOT NULL UNIQUE)',
    );
    await db.execute(
      'CREATE TABLE tasks(id TEXT PRIMARY KEY, title TEXT NOT NULL, done INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE cost_reservations(id TEXT PRIMARY KEY, amount REAL NOT NULL, created INTEGER NOT NULL, provider TEXT NOT NULL)',
    );
  }

  Future<Conversation> createConversation([
    String title = 'Nowa rozmowa',
  ]) async {
    final id = newId(), now = DateTime.now();
    await db.insert('conversations', {
      'id': id,
      'title': await cipher.seal(title),
      'draft': await cipher.seal(''),
      'updated': now.millisecondsSinceEpoch,
    });
    return Conversation(id: id, title: title, updated: now);
  }

  Future<List<Conversation>> conversations([String query = '']) async {
    final rows = await db.query(
      'conversations',
      orderBy: 'pinned DESC, updated DESC',
    );
    final values = <Conversation>[];
    for (final r in rows) {
      final item = Conversation(
        id: r['id'] as String,
        title: await cipher.open(r['title'] as String),
        draft: await cipher.open(r['draft'] as String),
        updated: DateTime.fromMillisecondsSinceEpoch(r['updated'] as int),
        pinned: r['pinned'] == 1,
      );
      if (query.isEmpty ||
          item.title.toLowerCase().contains(query.toLowerCase()) ||
          (await messages(item.id))
              .any((m) => m.text.toLowerCase().contains(query.toLowerCase()))) {
        values.add(item);
      }
    }
    return values;
  }

  Future<List<Message>> messages(String conversationId) async {
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created, rowid',
    );
    return Future.wait(
      rows.map(
        (r) async => Message(
          id: r['id'] as String,
          conversationId: conversationId,
          role: r['role'] as String,
          text: await cipher.open(r['content'] as String),
          provider: r['provider'] as String,
          model: r['model'] as String,
          status: r['status'] as String,
          inputTokens: r['input_tokens'] as int?,
          outputTokens: r['output_tokens'] as int?,
        ),
      ),
    );
  }

  Future<void> saveMessage(Message m) async {
    final content = await cipher.seal(m.text);
    await db.transaction((tx) async {
      final old = await tx.query(
        'messages',
        columns: ['created'],
        where: 'id=?',
        whereArgs: [m.id],
      );
      await tx.insert(
          'messages',
          {
            'id': m.id,
            'conversation_id': m.conversationId,
            'role': m.role,
            'content': content,
            'provider': m.provider,
            'model': m.model,
            'status': m.status,
            'created': old.isEmpty
                ? DateTime.now().millisecondsSinceEpoch
                : old.first['created'],
            'input_tokens': m.inputTokens,
            'output_tokens': m.outputTokens,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.update(
        'conversations',
        {'updated': DateTime.now().millisecondsSinceEpoch},
        where: 'id=?',
        whereArgs: [m.conversationId],
      );
    });
  }

  Future<void> draft(String id, String value) async => db.update(
        'conversations',
        {'draft': await cipher.seal(value)},
        where: 'id=?',
        whereArgs: [id],
      );
  Future<void> pin(String id, bool value) async => db.update(
        'conversations',
        {'pinned': value ? 1 : 0},
        where: 'id=?',
        whereArgs: [id],
      );
  Future<void> deleteConversation(String id) => db.transaction((tx) async {
        await tx
            .delete('operations', where: 'conversation_id=?', whereArgs: [id]);
        await tx.delete('conversations', where: 'id=?', whereArgs: [id]);
      });
  Future<T> setting<T>(String key, T fallback) async {
    final rows = await db.query('settings', where: 'key=?', whereArgs: [key]);
    return rows.isEmpty
        ? fallback
        : jsonDecode(rows.first['value'] as String) as T;
  }

  Future<void> setSetting(String key, Object value) async => db.insert(
        'settings',
        {'key': key, 'value': jsonEncode(value)},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
  Future<void> saveNote(
    String title,
    String text,
    String folder, {
    String? id,
  }) async {
    if (!memoryFolders.contains(folder)) {
      throw ArgumentError('Nieznany katalog');
    }
    await db.insert(
        'notes',
        {
          'id': id ?? newId(),
          'title': await cipher.seal(title),
          'content': await cipher.seal(text),
          'folder': folder,
          'updated': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<LocalNote>> notes([String query = '']) async {
    final result = <LocalNote>[];
    for (final r in await db.query('notes', orderBy: 'updated DESC')) {
      final n = LocalNote(
        id: r['id'] as String,
        title: await cipher.open(r['title'] as String),
        text: await cipher.open(r['content'] as String),
        folder: r['folder'] as String,
        updated: DateTime.fromMillisecondsSinceEpoch(r['updated'] as int),
      );
      if (query.isEmpty ||
          '${n.title} ${n.text}'.toLowerCase().contains(query.toLowerCase())) {
        result.add(n);
      }
    }
    return result;
  }

  Future<void> deleteNote(String id) async =>
      db.delete('notes', where: 'id=?', whereArgs: [id]);
  Future<String> queue(String conversationId, {String type = 'draft'}) async {
    if (type != 'draft') {
      throw ArgumentError('Nieobsługiwany typ operacji.');
    }
    final id = newId();
    return db.transaction((tx) async {
      final conversation = await tx.query('conversations',
          columns: ['id'], where: 'id=?', whereArgs: [conversationId]);
      if (conversation.isEmpty) {
        throw StateError('Brak rozmowy dla szkicu.');
      }
      await tx.insert(
          'operations',
          {
            'id': id,
            'conversation_id': conversationId,
            'status': 'pending',
            'type': type,
            'created': DateTime.now().millisecondsSinceEpoch,
            'dedup_key': '$conversationId:$type',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      final rows = await tx.query('operations',
          columns: ['id'],
          where: 'dedup_key=?',
          whereArgs: ['$conversationId:$type']);
      return rows.single['id'] as String;
    });
  }

  Future<void> close() => db.close();
}
