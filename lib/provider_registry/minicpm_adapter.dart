import 'dart:async';
import 'dart:convert';

import 'http_provider_adapter.dart';
import 'provider_adapter.dart';
import 'sse.dart';

/// Opcjonalny serwer właściciela. Nie oznacza wbudowanej inferencji w APK.
class MiniCpmEndpoint {
  MiniCpmEndpoint._(this.baseUri);
  final Uri baseUri;

  factory MiniCpmEndpoint.parse(String value) {
    final raw = value.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        raw.contains(RegExp(r'[\s\x00-\x1f\x7f\\]')) ||
        raw.contains('/../') ||
        raw.contains('/./') ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535 ||
        !['', '/', '/v1', '/v1/'].contains(uri.path)) {
      throw const ProviderException(
        'invalid_endpoint',
        'Podaj adres HTTPS serwera MiniCPM, np. https://ai.example.org/v1. '
            'Bez hasła, parametrów i fragmentu w adresie. HTTP nie jest obsługiwane.',
      );
    }
    return MiniCpmEndpoint._(uri.replace(path: '/v1'));
  }

  Uri resource(String name) => baseUri.replace(path: '/v1/$name');
  String get recipient => baseUri.toString();
}

typedef MiniCpmEndpointReader = Future<String> Function();

class MiniCpmAdapter implements ProviderAdapter {
  MiniCpmAdapter({
    required this.readEndpoint,
    this.clientFactory,
    this.config = const ProviderHttpConfig(),
  });
  final MiniCpmEndpointReader readEndpoint;
  final HttpClientFactory? clientFactory;
  final ProviderHttpConfig config;
  _MiniCpmHttp? _active;
  bool _busy = false, _cancelled = false;

  @override
  String get id => 'minicpm';
  @override
  String get label => 'MiniCPM • własny serwer';

  Future<MiniCpmEndpoint> endpoint() async =>
      MiniCpmEndpoint.parse(await readEndpoint());

  Future<_MiniCpmHttp> _begin() async {
    if (_busy) {
      throw const ProviderException('busy', 'MiniCPM realizuje już żądanie.');
    }
    _busy = true;
    _cancelled = false;
    try {
      final target = await endpoint();
      if (_cancelled) {
        throw const ProviderException('cancelled', 'Zatrzymano MiniCPM.');
      }
      return _active = _MiniCpmHttp(
        target,
        clientFactory: clientFactory,
        config: config,
      );
    } catch (_) {
      _busy = false;
      rethrow;
    }
  }

  void _finish() {
    _active = null;
    _busy = false;
  }

  @override
  void cancel() {
    _cancelled = true;
    _active?.cancel();
  }

  @override
  Stream<ProviderEvent> stream(ProviderRequest request) async* {
    final transport = await _begin();
    try {
      if (request.expectedEndpoint != transport.endpoint.recipient) {
        throw const ProviderException(
          'recipient_changed',
          'Adres MiniCPM zmienił się lub nie został zatwierdzony. Potwierdź odbiorcę ponownie.',
        );
      }
      yield* transport.stream(request);
    } finally {
      _finish();
    }
  }

  @override
  Future<List<ProviderModel>> discoverModels(String apiKey,
      {String? expectedEndpoint}) async {
    final transport = await _begin();
    try {
      if (expectedEndpoint != null &&
          expectedEndpoint != transport.endpoint.recipient) {
        throw const ProviderException('recipient_changed',
            'Adres MiniCPM zmienił się. Potwierdź odbiorcę ponownie.');
      }
      return await transport.discoverModels(apiKey);
    } finally {
      _finish();
    }
  }
}

class _MiniCpmHttp extends HttpProviderAdapter {
  _MiniCpmHttp(this.endpoint, {super.clientFactory, super.config});
  final MiniCpmEndpoint endpoint;
  bool _stopped = false;
  @override
  void cancel() {
    _stopped = true;
    super.cancel();
  }

  @override
  String get id => 'minicpm';
  @override
  String get label => 'MiniCPM • własny serwer';
  @override
  Uri generationUri(ProviderRequest request) =>
      endpoint.resource('chat/completions');
  @override
  Uri get modelsUri => endpoint.resource('models');

  @override
  void validateKey(String key) {
    if (_stopped) {
      throw const ProviderException('cancelled', 'Zatrzymano MiniCPM.');
    }
    // llama-server może nie wymagać klucza. Sekret, jeśli podany, pozostaje BYOK.
    if (key.isNotEmpty) super.validateKey(key);
  }

  @override
  Map<String, String> headers(String apiKey) => {
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      };

  @override
  Map<String, Object?> body(ProviderRequest request) => {
        'model': request.model,
        'messages': [
          for (final turn in request.turns)
            {'role': turn.role.name, 'content': turn.text},
        ],
        'stream': true,
        'stream_options': {'include_usage': true},
        'max_tokens': request.maxOutputTokens,
        'temperature': 0.7,
        'top_p': 0.95,
        'min_p': 0.0,
        'chat_template_kwargs': {'enable_thinking': false},
      };

  @override
  List<ProviderModel> parseModels(Map<String, dynamic> json) => [
        for (final item in json['data'] as List<dynamic>)
          ProviderModel(id: item['id'] as String, label: item['id'] as String),
      ];

  int? _count(Object? value) {
    if (value == null) return null;
    if (value is! int || value < 0) throw const FormatException();
    return value;
  }

  @override
  Stream<ProviderEvent> parseEvents(Stream<SseEvent> events) async* {
    TokenUsage? usage;
    var stopped = false;
    await for (final event in events) {
      if (event.data == '[DONE]') {
        if (!stopped) {
          throw const ProviderException(
            'incomplete',
            'MiniCPM nie potwierdził kompletnej odpowiedzi.',
          );
        }
        yield ProviderEvent(done: true, usage: usage);
        return;
      }
      final data = jsonDecode(event.data) as Map<String, dynamic>;
      if (data['error'] != null) {
        throw const ProviderException(
          'provider_error',
          'Serwer MiniCPM zgłosił błąd podczas generowania.',
        );
      }
      final rawUsage = data['usage'] as Map?;
      if (rawUsage != null) {
        usage = (usage ?? const TokenUsage()).merge(
          TokenUsage(
            inputTokens: _count(rawUsage['prompt_tokens']),
            outputTokens: _count(rawUsage['completion_tokens']),
          ),
        );
      }
      final choices = data['choices'] as List<dynamic>;
      if (choices.isEmpty) continue;
      final choice = choices.first as Map;
      final delta = choice['delta'] as Map?;
      if (delta?['tool_calls'] != null || delta?['function_call'] != null) {
        throw const ProviderException(
          'unsupported_tools',
          'MiniCPM zwrócił wywołanie narzędzia. Ten adapter obsługuje tekst.',
        );
      }
      final reason = choice['finish_reason'];
      if (reason != null) {
        if (reason != 'stop') {
          throw const ProviderException(
            'incomplete',
            'MiniCPM przerwał odpowiedź, np. przez limit tokenów.',
          );
        }
        stopped = true;
      }
      final text = delta?['content'] as String? ?? '';
      if (text.isNotEmpty) yield ProviderEvent(delta: text, usage: usage);
    }
  }
}
