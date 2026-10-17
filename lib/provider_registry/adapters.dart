import 'dart:async';
import 'dart:convert';

import 'http_provider_adapter.dart';
import 'provider_adapter.dart';
import 'sse.dart';

Map<String, dynamic> _json(SseEvent event) =>
    jsonDecode(event.data) as Map<String, dynamic>;
TokenUsage? _usage(
  dynamic value, {
  String input = 'input_tokens',
  String output = 'output_tokens',
}) {
  if (value is! Map) {
    return null;
  }
  return TokenUsage(
    inputTokens: (value[input] as num?)?.toInt(),
    outputTokens: (value[output] as num?)?.toInt(),
  );
}

class OpenAiAdapter extends HttpProviderAdapter {
  OpenAiAdapter({super.clientFactory, super.config});
  @override
  String get id => 'openai';
  @override
  String get label => 'OpenAI';
  @override
  Uri generationUri(ProviderRequest request) =>
      Uri.https('api.openai.com', '/v1/responses');
  @override
  Uri get modelsUri => Uri.https('api.openai.com', '/v1/models');
  @override
  Map<String, String> headers(String apiKey) => {
        'Authorization': 'Bearer $apiKey',
      };
  @override
  Map<String, Object?> body(ProviderRequest request) => {
        'model': request.model,
        'stream': true,
        'store': false,
        'max_output_tokens': request.maxOutputTokens,
        'input': [
          for (final turn in request.turns)
            {'role': turn.role.name, 'content': turn.text},
        ],
      };
  @override
  Stream<ProviderEvent> parseEvents(Stream<SseEvent> events) async* {
    await for (final event in events) {
      final data = _json(event);
      switch (data['type']) {
        case 'response.output_text.delta':
          yield ProviderEvent(delta: data['delta'] as String? ?? '');
        case 'response.completed':
          yield ProviderEvent(
            done: true,
            usage: _usage((data['response'] as Map?)?['usage']),
          );
        case 'response.incomplete':
          final usage = _usage((data['response'] as Map?)?['usage']);
          if (usage != null) {
            yield ProviderEvent(usage: usage);
          }
          throw const ProviderException(
            'incomplete',
            'Dostawca zakończył odpowiedź przed jej ukończeniem (np. limit tokenów).',
          );
        case 'response.refusal.delta':
          throw const ProviderException(
            'blocked',
            'Dostawca odmówił realizacji żądania.',
          );
        case 'response.failed':
        case 'error':
          throw const ProviderException(
            'provider_error',
            'Dostawca zgłosił błąd podczas generowania.',
          );
      }
    }
  }

  @override
  List<ProviderModel> parseModels(Map<String, dynamic> json) => [
        for (final item in json['data'] as List<dynamic>? ?? [])
          ProviderModel(id: item['id'] as String, label: item['id'] as String),
      ];
}

class AnthropicAdapter extends HttpProviderAdapter {
  /// W MVP użyj klucza ograniczonego do konkretnego workspace w Console.
  AnthropicAdapter({super.clientFactory, super.config});
  @override
  String get id => 'anthropic';
  @override
  String get label => 'Claude / Anthropic';
  @override
  Uri generationUri(ProviderRequest request) =>
      Uri.https('api.anthropic.com', '/v1/messages');
  @override
  Uri get modelsUri =>
      Uri.https('api.anthropic.com', '/v1/models', {'limit': '1000'});
  @override
  Map<String, String> headers(String apiKey) => {
        'Authorization': 'Bearer $apiKey',
        'anthropic-version': '2023-06-01',
      };
  @override
  Map<String, Object?> body(ProviderRequest request) => {
        'model': request.model,
        'stream': true,
        'max_tokens': request.maxOutputTokens,
        if (request.turns.any((turn) => turn.role == ChatRole.system))
          'system': request.turns
              .where((turn) => turn.role == ChatRole.system)
              .map((turn) => turn.text)
              .join('\n\n'),
        'messages': [
          for (final turn in request.turns.where(
            (turn) => turn.role != ChatRole.system,
          ))
            {'role': turn.role.name, 'content': turn.text},
        ],
      };
  @override
  Stream<ProviderEvent> parseEvents(Stream<SseEvent> events) async* {
    var usage = const TokenUsage();
    String? stopReason;
    await for (final event in events) {
      final data = _json(event);
      switch (data['type']) {
        case 'message_start':
          final update = _usage((data['message'] as Map?)?['usage']);
          if (update != null) {
            usage = usage.merge(update);
          }
        case 'content_block_delta':
          final delta = data['delta'] as Map?;
          if (delta?['type'] == 'text_delta') {
            yield ProviderEvent(delta: delta?['text'] as String? ?? '');
          }
        case 'message_delta':
          final update = _usage(data['usage']);
          if (update != null) {
            usage = usage.merge(update);
          }
          stopReason = (data['delta'] as Map?)?['stop_reason'] as String?;
        case 'message_stop':
          if (stopReason == 'max_tokens' ||
              stopReason == 'pause_turn' ||
              stopReason == 'tool_use') {
            yield ProviderEvent(usage: usage);
            throw const ProviderException(
              'incomplete',
              'Odpowiedź wymaga kontynuacji lub funkcji niedostępnej w tekstowym MVP.',
            );
          }
          yield ProviderEvent(done: true, usage: usage);
        case 'error':
          throw const ProviderException(
            'provider_error',
            'Claude zgłosił błąd podczas generowania.',
          );
      }
    }
  }

  @override
  List<ProviderModel> parseModels(Map<String, dynamic> json) => [
        for (final item in json['data'] as List<dynamic>? ?? [])
          ProviderModel(
            id: item['id'] as String,
            label: item['display_name'] as String? ?? item['id'] as String,
          ),
      ];
  @override
  Uri? nextModelsPage(Map<String, dynamic> json) => json['has_more'] == true
      ? Uri.https('api.anthropic.com', '/v1/models', {
          'limit': '1000',
          'after_id': json['last_id'] as String,
        })
      : null;
}

class GeminiAdapter extends HttpProviderAdapter {
  GeminiAdapter({super.clientFactory, super.config});
  @override
  String get id => 'gemini';
  @override
  String get label => 'Google Gemini';
  @override
  Uri generationUri(ProviderRequest request) {
    final model = request.model.startsWith('models/')
        ? request.model.substring(7)
        : request.model;
    return Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:streamGenerateContent',
      {'alt': 'sse'},
    );
  }

  @override
  Uri get modelsUri => Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/models',
        {'pageSize': '1000'},
      );
  @override
  Map<String, String> headers(String apiKey) => {'x-goog-api-key': apiKey};
  @override
  Map<String, Object?> body(ProviderRequest request) => {
        'generationConfig': {'maxOutputTokens': request.maxOutputTokens},
        if (request.turns.any((turn) => turn.role == ChatRole.system))
          'systemInstruction': {
            'parts': [
              for (final turn in request.turns.where(
                (turn) => turn.role == ChatRole.system,
              ))
                {'text': turn.text},
            ],
          },
        'contents': [
          for (final turn in request.turns.where(
            (turn) => turn.role != ChatRole.system,
          ))
            {
              'role': turn.role == ChatRole.assistant ? 'model' : 'user',
              'parts': [
                {'text': turn.text},
              ],
            },
        ],
      };
  @override
  Stream<ProviderEvent> parseEvents(Stream<SseEvent> events) async* {
    await for (final event in events) {
      final data = _json(event);
      if (data['error'] != null) {
        throw const ProviderException(
          'provider_error',
          'Gemini zgłosiło błąd podczas generowania.',
        );
      }
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) {
        if ((data['promptFeedback'] as Map?)?['blockReason'] != null) {
          throw const ProviderException(
            'blocked',
            'Dostawca zablokował żądanie zgodnie ze swoją polityką.',
          );
        }
        continue;
      }
      final candidate = candidates.first as Map;
      final parts =
          (candidate['content'] as Map?)?['parts'] as List<dynamic>? ?? [];
      final delta = parts
          .where((part) => part['thought'] != true)
          .map((part) => part['text'] as String? ?? '')
          .join();
      final reason = candidate['finishReason'] as String?;
      final usage = _usage(
        data['usageMetadata'],
        input: 'promptTokenCount',
        output: 'candidatesTokenCount',
      );
      yield ProviderEvent(delta: delta, usage: usage, done: reason == 'STOP');
      if (reason != null && reason != 'STOP') {
        throw const ProviderException(
          'incomplete',
          'Gemini zakończyło niepełną odpowiedź (limit lub zasady bezpieczeństwa).',
        );
      }
    }
  }

  @override
  List<ProviderModel> parseModels(Map<String, dynamic> json) => [
        for (final item in json['models'] as List<dynamic>? ?? [])
          if ((item['supportedGenerationMethods'] as List<dynamic>? ?? [])
              .contains(
            'generateContent',
          ))
            ProviderModel(
              id: item['name'] as String,
              label: item['displayName'] as String? ?? item['name'] as String,
            ),
      ];
  @override
  Uri? nextModelsPage(Map<String, dynamic> json) =>
      json['nextPageToken'] != null
          ? Uri.https('generativelanguage.googleapis.com', '/v1beta/models', {
              'pageSize': '1000',
              'pageToken': json['nextPageToken'] as String,
            })
          : null;
}

class XaiAdapter extends HttpProviderAdapter {
  XaiAdapter({super.clientFactory, super.config});
  @override
  String get id => 'xai';
  @override
  String get label => 'Grok / xAI';
  @override
  Uri generationUri(ProviderRequest request) =>
      Uri.https('api.x.ai', '/v1/chat/completions');
  @override
  Uri get modelsUri => Uri.https('api.x.ai', '/v1/models');
  @override
  Map<String, String> headers(String apiKey) => {
        'Authorization': 'Bearer $apiKey',
      };
  @override
  Map<String, Object?> body(ProviderRequest request) => {
        'model': request.model,
        'stream': true,
        'max_tokens': request.maxOutputTokens,
        'messages': [
          for (final turn in request.turns)
            {'role': turn.role.name, 'content': turn.text},
        ],
      };
  @override
  Stream<ProviderEvent> parseEvents(Stream<SseEvent> events) async* {
    TokenUsage? usage;
    var incomplete = false;
    await for (final event in events) {
      if (event.data == '[DONE]') {
        if (incomplete) {
          throw const ProviderException(
            'incomplete',
            'Grok zakończył niepełną odpowiedź.',
          );
        }
        yield ProviderEvent(done: true, usage: usage);
        continue;
      }
      final data = _json(event);
      if (data['error'] != null) {
        throw const ProviderException(
          'provider_error',
          'Grok zgłosił błąd podczas generowania.',
        );
      }
      final update = _usage(
        data['usage'],
        input: 'prompt_tokens',
        output: 'completion_tokens',
      );
      if (update != null) {
        usage = (usage ?? const TokenUsage()).merge(update);
      }
      final choices = data['choices'] as List<dynamic>? ?? [];
      if (choices.isNotEmpty) {
        final choice = choices.first as Map;
        final reason = choice['finish_reason'];
        if (reason != null && reason != 'stop') {
          incomplete = true;
        }
        final delta = (choice['delta'] as Map?)?['content'] as String? ?? '';
        if (delta.isNotEmpty) {
          yield ProviderEvent(delta: delta, usage: update);
        }
      }
    }
  }

  @override
  List<ProviderModel> parseModels(Map<String, dynamic> json) => [
        for (final item in json['data'] as List<dynamic>? ?? [])
          ProviderModel(id: item['id'] as String, label: item['id'] as String),
      ];
}

class DemoAdapter implements ProviderAdapter {
  DemoAdapter({this.chunkDelay = const Duration(milliseconds: 40)});
  final Duration chunkDelay;
  Completer<void>? _cancelled;
  @override
  String get id => 'demo';
  @override
  String get label => 'Demo lokalne — bez AI';
  @override
  void cancel() {
    if (_cancelled != null && !_cancelled!.isCompleted) {
      _cancelled!.complete();
    }
  }

  @override
  Future<List<ProviderModel>> discoverModels(String apiKey) async => const [
        ProviderModel(
          id: 'demo-local',
          label: 'Atrapa lokalna (bez sieci i opłat)',
        ),
      ];
  @override
  Stream<ProviderEvent> stream(ProviderRequest request) async* {
    if (_cancelled != null) {
      throw const ProviderException('busy', 'Demo realizuje już żądanie.');
    }
    final cancellation = _cancelled = Completer<void>();
    try {
      const reply =
          'To lokalne demo Scalającej, bez połączenia z modelem AI. Historia jest zapisywana na telefonie. Aby uzyskać prawdziwą odpowiedź AI, skonfiguruj dostawcę i świadomie włącz zapytania API. Treść tego komunikatu jest stałą atrapą.';
      for (final word in reply.split(' ')) {
        await Future.any([
          Future<void>.delayed(chunkDelay),
          cancellation.future,
        ]);
        if (cancellation.isCompleted) {
          throw const ProviderException(
            'cancelled',
            'Zatrzymano lokalne demo.',
          );
        }
        yield ProviderEvent(delta: '$word ');
      }
      yield const ProviderEvent(done: true);
    } finally {
      if (identical(_cancelled, cancellation)) {
        _cancelled = null;
      }
    }
  }
}
