import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scalajaca/provider_registry/provider_registry.dart';

String frame(Map<String, Object?> value) => 'data: ${jsonEncode(value)}\n\n';
String completion({String reason = 'stop'}) => [
      frame({
        'choices': [
          {
            'delta': {'content': 'Cześć 🌍'},
            'finish_reason': null,
          },
        ],
      }),
      frame({
        'choices': [
          {'delta': {}, 'finish_reason': reason},
        ],
      }),
      frame({
        'choices': [],
        'usage': {'prompt_tokens': 12, 'completion_tokens': 3},
      }),
      'data: [DONE]\n\n',
    ].join();
ProviderRequest request({String key = ''}) => ProviderRequest(
      model: 'MiniCPM5-1B',
      expectedEndpoint: 'https://ai.example.org:8443/v1',
      apiKey: key,
      turns: const [ChatTurn(role: ChatRole.user, text: 'Cześć')],
    );

class TrackingClient extends http.BaseClient {
  TrackingClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  int calls = 0;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls++;
    return handler(request);
  }

  @override
  void close() => closed = true;
}

TrackingClient response(String body, {int status = 200}) => TrackingClient(
      (_) async => http.StreamedResponse(
        Stream.fromIterable(utf8.encode(body).map((b) => [b])),
        status,
        headers: {'content-type': 'text/event-stream; charset=utf-8'},
      ),
    );

MiniCpmAdapter adapter(http.Client client) => MiniCpmAdapter(
      readEndpoint: () async => 'https://ai.example.org:8443/v1',
      clientFactory: () => client,
    );

void main() {
  for (final invalid in [
    '',
    'http://ai.example.org/v1',
    'file:///v1',
    'https:///v1',
    'https://user:secret@ai.example.org/v1',
    'https://ai.example.org/v1?api_key=secret',
    'https://ai.example.org/v1#secret',
    'https://ai.example.org/v1/chat/completions',
    'https://ai.example.org:0/v1',
    'https://ai.example.org:65536/v1',
    'https://ai.example.org/vi l',
    'https://ai.example.org/../v1',
    'https://ai.example.org\\evil/v1',
  ]) {
    test('Adres MiniCPM odrzuca: $invalid', () {
      expect(
        () => MiniCpmEndpoint.parse(invalid),
        throwsA(isA<ProviderException>()),
      );
    });
  }
  test('Normalizuje bazę HTTPS i zachowuje jawny port', () {
    final endpoint = MiniCpmEndpoint.parse(' https://ai.example.org:8443/ ');
    expect(endpoint.recipient, 'https://ai.example.org:8443/v1');
    expect(endpoint.resource('models').path, '/v1/models');
  });
  test('Zmiana zatwierdzonego odbiorcy nie wysyła klucza ani promptu',
      () async {
    final client = response(completion());
    final provider = adapter(client);
    await expectLater(
        provider
            .stream(ProviderRequest(
              model: 'MiniCPM5-1B',
              apiKey: 'server-secret-placeholder',
              expectedEndpoint: 'https://old.example.org/v1',
              turns: const [ChatTurn(role: ChatRole.user, text: 'sekret')],
            ))
            .toList(),
        throwsA(isA<ProviderException>()
            .having((e) => e.code, 'kod', 'recipient_changed')));
    expect(client.calls, 0);
    await expectLater(
        provider.discoverModels('server-secret-placeholder',
            expectedEndpoint: 'https://old.example.org/v1'),
        throwsA(isA<ProviderException>()
            .having((e) => e.code, 'kod', 'recipient_changed')));
    expect(client.calls, 0);
  });
  test(
    'Rejestr standardowy dodaje opcjonalny adapter bez połączenia',
    () async {
      final registry = ProviderRegistry.standard();
      expect(registry.adapter('minicpm'), isA<MiniCpmAdapter>());
      await expectLater(
        registry.adapter('minicpm').stream(request()).toList(),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.code,
            'kod',
            'invalid_endpoint',
          ),
        ),
      );
    },
  );
  test(
    'Mapuje tekst, limit, profil i Bearer tylko do własnego serwera',
    () async {
      final client = MockClient((req) async {
        expect(
          req.url.toString(),
          'https://ai.example.org:8443/v1/chat/completions',
        );
        expect(req.followRedirects, isFalse);
        expect(
          req.headers['Authorization'],
          'Bearer server-secret-placeholder',
        );
        final body = jsonDecode(req.body) as Map;
        expect(body['model'], 'MiniCPM5-1B');
        expect(body['messages'], [
          {'role': 'user', 'content': 'Cześć'},
        ]);
        expect(body['max_tokens'], 1024);
        expect(body['stream_options'], {'include_usage': true});
        expect(body['min_p'], 0.0);
        expect(body['chat_template_kwargs'], {'enable_thinking': false});
        expect(body.containsKey('tools'), isFalse);
        return http.Response(
          completion(),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });
      final events = await adapter(client)
          .stream(request(key: 'server-secret-placeholder'))
          .toList();
      expect(events.map((e) => e.delta).join(), 'Cześć 🌍');
      expect(events.last.done, isTrue);
      expect(events.last.usage?.inputTokens, 12);
      expect(events.last.usage?.outputTokens, 3);
    },
  );
  test('Nie wymaga klucza i dekoduje UTF-8 rozcięte co bajt', () async {
    final client = response(completion());
    final events = await adapter(client).stream(request()).toList();
    expect(events.first.delta, 'Cześć 🌍');
    expect(client.closed, isTrue);
    expect(client.calls, 1);
  });
  test(
      'Katalog pochodzi ze wskazanego HTTPS; bez Authorization dla pustego klucza',
      () async {
    final client = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.toString(), 'https://ai.example.org:8443/v1/models');
      expect(req.headers.containsKey('Authorization'), isFalse);
      expect(req.followRedirects, isFalse);
      return http.Response('{"data":[{"id":"owner-model-alias"}]}', 200);
    });
    expect(
      (await adapter(client).discoverModels('')).single.id,
      'owner-model-alias',
    );
  });
  test('Klucz z CR/LF nie wychodzi do sieci', () async {
    final client = response(completion());
    await expectLater(
      adapter(client).stream(request(key: 'secret\r\nx: y')).toList(),
      throwsA(
        isA<ProviderException>().having((e) => e.code, 'kod', 'invalid_key'),
      ),
    );
    expect(client.calls, 0);
  });
  for (final status in [302, 401, 429, 503]) {
    test('HTTP $status: brak ponowienia i brak sekretu z body błędu', () async {
      final client = response(
        'PROMPT i server-secret-placeholder',
        status: status,
      );
      await expectLater(
        adapter(client).stream(request()).toList(),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.message,
            'wiadomość',
            isNot(contains('server-secret-placeholder')),
          ),
        ),
      );
      expect(client.calls, 1);
      expect(client.closed, isTrue);
    });
  }
  test('Odrzuca uciętą odpowiedź i sam znacznik DONE', () async {
    for (final body in [completion(reason: 'length'), 'data: [DONE]\n\n']) {
      await expectLater(
        adapter(response(body)).stream(request()).toList(),
        throwsA(
          isA<ProviderException>().having((e) => e.code, 'kod', 'incomplete'),
        ),
      );
    }
  });
  test('Brak DONE oznacza przerwany strumień', () async {
    await expectLater(
      adapter(
        response(
          frame({
            'choices': [
              {
                'delta': {'content': 'część'},
              },
            ],
          }),
        ),
      ).stream(request()).toList(),
      throwsA(
        isA<ProviderException>().having((e) => e.code, 'kod', 'interrupted'),
      ),
    );
  });
  test('Wywołania narzędzi są odrzucone, nie wykonywane', () async {
    await expectLater(
      adapter(
        response(
          frame({
            'choices': [
              {
                'delta': {'tool_calls': []},
              },
            ],
          }),
        ),
      ).stream(request()).toList(),
      throwsA(
        isA<ProviderException>().having(
          (e) => e.code,
          'kod',
          'unsupported_tools',
        ),
      ),
    );
  });
  test('Anulowanie przed odczytem konfiguracji nie uruchamia HTTP', () async {
    final endpoint = Completer<String>();
    final client = response(completion());
    final provider = MiniCpmAdapter(
      readEndpoint: () => endpoint.future,
      clientFactory: () => client,
    );
    final pending = provider.stream(request()).toList();
    final check = expectLater(
      pending,
      throwsA(
        isA<ProviderException>().having((e) => e.code, 'kod', 'cancelled'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    provider.cancel();
    endpoint.complete('https://ai.example.org/v1');
    await check;
    expect(client.calls, 0);
  });
  test(
    'Anulowanie podczas oczekiwania na nagłówki zwalnia transport',
    () async {
      final started = Completer<void>();
      final client = TrackingClient((_) {
        started.complete();
        return Completer<http.StreamedResponse>().future;
      });
      final provider = adapter(client);
      final check = expectLater(
        provider.stream(request()).toList(),
        throwsA(
          isA<ProviderException>().having((e) => e.code, 'kod', 'cancelled'),
        ),
      );
      await started.future;
      await expectLater(
        provider.discoverModels(''),
        throwsA(isA<ProviderException>().having((e) => e.code, 'kod', 'busy')),
      );
      provider.cancel();
      await check.timeout(const Duration(seconds: 2));
      expect(client.closed, isTrue);
    },
  );
}
