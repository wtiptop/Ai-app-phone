import 'dart:async';

import 'package:flutter/foundation.dart';

import '../provider_registry/provider_registry.dart';
import '../storage/app_database.dart';
import '../storage/models.dart';
import '../costs/local_cost_gate.dart';

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

  Future<void> create({bool privateMode = false}) async {
    if (busy) return;
    private = privateMode;
    conversation = privateMode
        ? Conversation(
            id: newId(),
            title: 'Prywatna rozmowa',
            updated: DateTime.now(),
          )
        : await store.createConversation();
    messages = [];
    error = null;
    notifyListeners();
  }

  Future<void> load(Conversation c) async {
    if (busy) return;
    private = false;
    conversation = c;
    messages = await store.messages(c.id);
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
  }) async {
    if (busy || text.trim().isEmpty) return;
    if (provider != 'demo') {
      if (permit == null) {
        error = 'Wymagana zgoda na koszt i odbiorcę.';
        notifyListeners();
        return;
      }
      permit.consume(provider, model);
    }
    busy = true;
    _cancelled = false;
    error = null;
    notifyListeners();
    try {
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
      final turns = [
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
      if (!private) await store.saveMessage(response);
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
    } catch (_) {
      error =
          'Nie udało się zapisać rozmowy. Sprawdź wolne miejsce i spróbuj ponownie.';
    } finally {
      busy = false;
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
