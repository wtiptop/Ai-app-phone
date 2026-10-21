import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../provider_registry/provider_registry.dart';
import '../storage/app_database.dart';
import '../storage/models.dart';
import '../costs/local_cost_gate.dart';
import '../memory/context_packet.dart';
import 'prepared_chat.dart';
import '../local_inference/source_guidance.dart';

class ChatSession extends ChangeNotifier {
  ChatSession(this.store, this.registry);
  final AppDatabase store;
  final ProviderRegistry registry;
  Conversation? conversation;
  List<Message> messages = [];
  bool busy = false;
  bool private = false;
  bool _cancelled = false;
  String? error;
  ProviderAdapter? _active;
  int _version = 0, totalMessages = 0;
  int _loadSerial = 0;
  String? scopeKey;
  bool confidential = false;

  Future<void> bindScope(ContextAttachment attachment) async {
    if (busy || conversation == null || messages.isNotEmpty) {
      throw StateError('Nowy zakres pamięci wymaga nowej rozmowy.');
    }
    scopeKey = attachment.scopeKey;
    confidential = attachment.confidential;
    _version++;
    if (!private) {
      await store.db.insert('chat_scopes', {
        'conversation_id': conversation!.id,
        'scope_key': scopeKey,
        'confidential': confidential ? 1 : 0
      });
    }
    notifyListeners();
  }

  Future<PreparedChat> prepare(String text, String provider, String model,
      {bool repeat = false, ContextAttachment? attachment}) async {
    if (busy || text.trim().isEmpty) {
      throw StateError('Poczekaj na zakończenie odpowiedzi.');
    }
    if (scopeKey != attachment?.scopeKey &&
        (scopeKey != null || attachment != null)) {
      throw StateError(
          'Otwórz nową rozmowę z właściwym zakresem pamięci lub kampanii.');
    }
    if (private && messages.length >= 128) {
      throw StateError(
          'Prywatna sesja osiągnęła limit pamięci RAM. Rozpocznij nową rozmowę.');
    }
    final version = _version;
    final history = List<Message>.of(messages);
    if (repeat) {
      final i = history.lastIndexWhere((m) => m.role == 'user');
      if (i >= 0) history.removeRange(i, history.length);
    }
    final output = isLocalProvider(provider) ? 512 : 1024;
    final context = isLocalProvider(provider)
        ? (provider == 'colibri_local'
            ? 4096
            : await store.setting('local_context', 4096))
        : 0;
    final budget = isLocalProvider(provider) ? context - output - 256 : 24000;
    final localSources = isLocalProvider(provider) && attachment != null;
    final prefix = <ChatTurn>[
      if (localSources)
        const ChatTurn(role: ChatRole.system, text: sourceGuidance),
      if (attachment != null && !localSources)
        ChatTurn(role: ChatRole.user, text: attachment.text),
    ];
    // MiniCPM otrzymuje źródła i pytanie w jednej turze użytkownika.
    // Dwie sąsiednie tury user pogarszały odpowiedzi w polskiej kampanii.
    final latest = ChatTurn(
        role: ChatRole.user,
        text: localSources
            ? 'Sources:\n${attachment.text}\nQuestion:\n${text.trim()}'
            : text.trim());
    int size(List<ChatTurn> turns) => utf8
        .encode(jsonEncode([
          for (final t in turns) {'role': t.role.name, 'content': t.text}
        ]))
        .length;
    if (size([...prefix, latest]) > budget) {
      throw StateError(
          'Wiadomość i wybrane źródła przekraczają budżet kontekstu. Wybierz mniej fragmentów lub zwiększ kontekst MiniCPM do 4096.');
    }
    final selected = <ChatTurn>[];
    final eligible = history
        .where((m) =>
            m.role == 'user' ||
            (m.role == 'assistant' && m.status == 'complete'))
        .toList();
    for (final m in eligible.reversed) {
      final turn = ChatTurn(
          role: m.role == 'user' ? ChatRole.user : ChatRole.assistant,
          text: m.text);
      if (size([...prefix, turn, ...selected, latest]) > budget) break;
      selected.insert(0, turn);
    }
    // Historia zaczyna się od pytania, nie wyrwanej odpowiedzi modelu.
    while (selected.isNotEmpty && selected.first.role == ChatRole.assistant) {
      selected.removeAt(0);
    }
    final turns = [...prefix, ...selected, latest];
    final omitted =
        (totalMessages - history.length) + (eligible.length - selected.length);
    final digest = await contentDigest(jsonEncode({
      'provider': provider,
      'model': model,
      'scope': scopeKey,
      'output': output,
      'sourceGrounded': isLocalProvider(provider) && attachment != null,
      'turns': [
        for (final t in turns) {'role': t.role.name, 'text': t.text}
      ]
    }));
    if (version != _version) {
      throw StateError('Rozmowa zmieniła się. Otwórz podgląd ponownie.');
    }
    return PreparedChat(
        provider: provider,
        model: model,
        userText: text.trim(),
        turns: turns,
        digest: digest,
        sessionVersion: version,
        omitted: omitted < 0 ? 0 : omitted,
        maxOutputTokens: output,
        attachment: attachment);
  }

  Future<void> create({bool privateMode = false}) async {
    if (busy) return;
    final ticket = ++_loadSerial;
    _version++;
    final next = privateMode
        ? Conversation(
            id: newId(),
            title: 'Prywatna rozmowa',
            updated: DateTime.now(),
          )
        : await store.createConversation();
    if (ticket != _loadSerial) return;
    private = privateMode;
    conversation = next;
    messages = [];
    totalMessages = 0;
    scopeKey = null;
    confidential = false;
    _version++;
    error = null;
    notifyListeners();
  }

  Future<void> load(Conversation c) async {
    if (busy) return;
    final ticket = ++_loadSerial;
    _version++;
    final nextMessages = await store.messages(c.id, limit: 80, latest: true);
    final count = await store.messageCount(c.id);
    final scopes = await store.db.query('chat_scopes',
        where: 'conversation_id=?', whereArgs: [c.id], limit: 1);
    if (ticket != _loadSerial) return;
    private = false;
    conversation = c;
    messages = nextMessages;
    totalMessages = count;
    scopeKey = scopes.isEmpty ? null : scopes.single['scope_key'] as String;
    confidential = scopes.isNotEmpty && scopes.single['confidential'] == 1;
    _version++;
    error = null;
    notifyListeners();
  }

  Future<void> saveDraft(String value) async {
    if (!private && conversation != null) {
      await store.draft(conversation!.id, value);
    }
  }

  Future<void> send(
    String text,
    String provider,
    String model,
    String key, {
    bool repeat = false,
    RequestPermit? permit,
    String? expectedEndpoint,
    PreparedChat? prepared,
  }) async {
    if (busy || text.trim().isEmpty) return;
    if (prepared != null &&
        (prepared.provider != provider ||
            prepared.model != model ||
            prepared.userText != text.trim() ||
            prepared.sessionVersion != _version ||
            prepared.attachment?.scopeKey != scopeKey)) {
      throw StateError('Podgląd kontekstu jest nieaktualny.');
    }
    if (scopeKey != null && prepared == null) {
      throw StateError(
          'Wymagany zatwierdzony pakiet właściwego projektu lub kampanii.');
    }
    if (provider != 'demo') {
      if (permit == null) {
        error = 'Wymagana zgoda na koszt i odbiorcę.';
        notifyListeners();
        return;
      }
      permit.consume(provider, model, contextDigest: prepared?.digest);
    }
    busy = true;
    _cancelled = false;
    error = null;
    _version++;
    notifyListeners();
    try {
      if (prepared != null &&
          await prepared.calculateDigest(scopeKey) != prepared.digest) {
        throw StateError(
            'Pakiet kontekstu różni się od zatwierdzonego podglądu.');
      }
      if (prepared?.attachment != null) await prepared!.attachment!.validate();
      conversation ??= private
          ? Conversation(
              id: newId(),
              title: 'Prywatna rozmowa',
              updated: DateTime.now(),
            )
          : await store.createConversation();
      if (!repeat) {
        final user = Message(
          id: newId(),
          conversationId: conversation!.id,
          role: 'user',
          text: text.trim(),
          provider: provider,
          model: model,
        );
        messages.add(user);
        totalMessages++;
        if (!private) {
          await store.saveMessage(user);
          await store.draft(conversation!.id, '');
          if (messages.length == 1) {
            final title = text.trim().split('\n').first;
            await store.db.update(
              'conversations',
              {
                'title': await store.cipher.seal(
                  title.length > 60 ? '${title.substring(0, 60)}…' : title,
                ),
              },
              where: 'id=?',
              whereArgs: [conversation!.id],
            );
          }
        }
      }
      final lastUser = messages.lastIndexWhere((m) => m.role == 'user');
      final history =
          repeat && lastUser >= 0 ? messages.take(lastUser + 1) : messages;
      final turns = prepared?.turns ??
          [
            for (final m in history)
              if (m.role == 'user' ||
                  (m.role == 'assistant' && m.status == 'complete'))
                ChatTurn(
                  role: m.role == 'user' ? ChatRole.user : ChatRole.assistant,
                  text: m.text,
                ),
          ];
      var response = Message(
        id: newId(),
        conversationId: conversation!.id,
        role: 'assistant',
        text: '',
        provider: provider,
        model: model,
        status: 'streaming',
      );
      messages.add(response);
      totalMessages++;
      if (!private) await store.saveMessage(response);
      if (!private &&
          prepared != null &&
          (prepared.attachment != null || prepared.omitted > 0)) {
        await store.db.insert('chat_context_receipts', {
          'message_id': response.id,
          'digest': prepared.digest,
          'evidence': await store.cipher.seal(prepared.receipt),
          'omitted': prepared.omitted,
          'created': DateTime.now().millisecondsSinceEpoch
        });
      }
      var lastSave = DateTime.now();
      try {
        if (_cancelled) {
          throw const ProviderException(
            'cancelled',
            'Anulowano przed wysłaniem.',
          );
        }
        _active = registry.adapter(provider);
        await for (final event in _active!.stream(
          ProviderRequest(
            model: model,
            turns: turns,
            apiKey: key,
            expectedEndpoint: expectedEndpoint,
            maxOutputTokens: prepared?.maxOutputTokens ?? 1024,
            sourceGrounded: prepared?.sourceGrounded ?? false,
          ),
        )) {
          if (_cancelled) break;
          response = response.copyWith(
            text: response.text + event.delta,
            status: event.done ? 'complete' : 'streaming',
            inputTokens: event.usage?.inputTokens,
            outputTokens: event.usage?.outputTokens,
          );
          messages[messages.length - 1] = response;
          if (!private &&
              (event.done ||
                  DateTime.now().difference(lastSave).inSeconds >= 1)) {
            await store.saveMessage(response);
            lastSave = DateTime.now();
          }
          notifyListeners();
        }
        if (_cancelled) {
          response = response.copyWith(status: 'cancelled');
        } else if (response.status != 'complete') {
          response = response.copyWith(status: 'interrupted');
        }
      } on ProviderException catch (e) {
        response = response.copyWith(
          status: _cancelled || e.code == 'cancelled' ? 'cancelled' : 'error',
        );
        if (!_cancelled) error = e.message;
      } catch (_) {
        response = response.copyWith(status: 'error');
        error =
            'Nie udało się uzyskać odpowiedzi. Sprawdź połączenie i konfigurację.';
      }
      messages[messages.length - 1] = response;
      if (!private) await store.saveMessage(response);
    } on StateError catch (e) {
      error = e.message.toString();
    } catch (_) {
      error =
          'Nie udało się zapisać rozmowy. Sprawdź wolne miejsce i spróbuj ponownie.';
    } finally {
      busy = false;
      if (!private && messages.length > 80) {
        messages = messages.sublist(messages.length - 80);
      }
      _active = null;
      notifyListeners();
    }
  }

  void cancel() {
    _cancelled = true;
    _active?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _active?.cancel();
    super.dispose();
  }
}
