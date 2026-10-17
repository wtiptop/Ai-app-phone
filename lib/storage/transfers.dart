import 'dart:convert';

import 'package:flutter/services.dart';

import 'app_database.dart';
import 'models.dart';

class AndroidFiles {
  static const _channel = MethodChannel('pl.scalajaca/files');
  static Future<void> save(String name, String content) =>
      _channel.invokeMethod('save', {'name': name, 'content': content});
  static Future<String?> importText() =>
      _channel.invokeMethod<String>('import');
  static Future<void> share(String content) =>
      _channel.invokeMethod('share', {'content': content});
}

class Transfers {
  Transfers(this.store);
  final AppDatabase store;
  Future<String> markdown(Conversation c) async {
    final messages = await store.messages(c.id);
    final buffer = StringBuffer(
      '# ${c.title}\n\nEksport Scalająca • ${DateTime.now().toIso8601String()}\n\n',
    );
    for (final m in messages) {
      buffer.writeln(
        '## ${m.role == 'user' ? 'Ty' : m.provider} · ${m.model} · ${m.status}\n\n${m.text}\n',
      );
    }
    return buffer.toString();
  }

  /// Portable backup contains plaintext inside encryption envelope, NEVER keys.
  Future<String> snapshot() async => jsonEncode({
        'format': 'scalajaca.data',
        'v': 1,
        'conversations': [
          for (final c in await store.conversations())
            {
              'title': c.title,
              'draft': c.draft,
              'pinned': c.pinned,
              'messages': [
                for (final m in await store.messages(c.id))
                  {
                    'role': m.role,
                    'text': m.text,
                    'provider': m.provider,
                    'model': m.model,
                    'status': m.status,
                    'input': m.inputTokens,
                    'output': m.outputTokens,
                  },
              ],
            },
        ],
        'notes': [
          for (final n in await store.notes())
            {'title': n.title, 'text': n.text, 'folder': n.folder},
        ],
        'tasks': [
          for (final t in await store.db.query('tasks'))
            {
              'title': await store.cipher.open(t['title'] as String),
              'done': t['done'],
            },
        ],
      });

  Future<void> restore(String json) async {
    if (utf8.encode(json).length > 16 * 1024 * 1024) {
      throw const FormatException('Za duża kopia.');
    }
    final data = jsonDecode(json) as Map<String, dynamic>;
    if (data['format'] != 'scalajaca.data' || data['v'] != 1) {
      throw const FormatException('Nieobsługiwany format kopii.');
    }
    final conversations = data['conversations'] as List;
    final notes = data['notes'] as List;
    final tasks = data['tasks'] as List;
    // Append-only restore; malformed input rolls back the entire transaction.
    await store.db.transaction((tx) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final raw in conversations) {
        final c = raw as Map<String, dynamic>;
        final id = newId();
        await tx.insert('conversations', {
          'id': id,
          'title': await store.cipher.seal(c['title'] as String),
          'draft': await store.cipher.seal(c['draft'] as String),
          'pinned': c['pinned'] == true ? 1 : 0,
          'updated': now,
        });
        for (final raw in c['messages'] as List) {
          final m = raw as Map<String, dynamic>;
          if (!['user', 'assistant'].contains(m['role'])) {
            throw const FormatException('Niedozwolona rola w kopii.');
          }
          await tx.insert('messages', {
            'id': newId(),
            'conversation_id': id,
            'role': m['role'],
            'content': await store.cipher.seal(m['text'] as String),
            'provider': m['provider'] as String,
            'model': m['model'] as String,
            'status': m['status'] as String,
            'created': now,
            'input_tokens': m['input'],
            'output_tokens': m['output'],
          });
        }
      }
      for (final raw in notes) {
        final n = raw as Map<String, dynamic>;
        if (!memoryFolders.contains(n['folder'])) {
          throw const FormatException('Nieznany katalog.');
        }
        await tx.insert('notes', {
          'id': newId(),
          'title': await store.cipher.seal(n['title'] as String),
          'content': await store.cipher.seal(n['text'] as String),
          'folder': n['folder'],
          'updated': now,
        });
      }
      for (final raw in tasks) {
        final t = raw as Map<String, dynamic>;
        // Snapshot tasks use the same local cipher; export decoded by caller below.
        await tx.insert('tasks', {
          'id': newId(),
          'title': await store.cipher.seal(t['title'] as String),
          'done': t['done'] == 1 ? 1 : 0,
          'created': now,
        });
      }
    });
  }
}
