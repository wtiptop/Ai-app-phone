import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:scalajaca/provider_registry/provider_registry.dart';
import 'package:scalajaca/provider_registry/http_provider_adapter.dart';
import 'package:scalajaca/provider_registry/sse.dart';

ProviderRequest request({
  String apiKey = 'test-only-placeholder',
  String model = 'configured-model',
}) =>
    ProviderRequest(
      model: model,
      apiKey: apiKey,
      turns: const [
        ChatTurn(role: ChatRole.system, text: 'Zasady'),
        ChatTurn(role: ChatRole.user, text: 'Cześć'),
      ],
    );

String frame(Map<String, Object?> data) => 'data: ${jsonEncode(data)}\n\n';

class TrackingClient extends http.BaseClient {
  TrackingClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  int sends = 0;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) {
    sends++;
    return handler(req);
  }

  @override
  void close() {
    closed = true;
  }
}

TrackingClient streamed(
  String body, {
  void Function(http.BaseRequest)? inspect,
  int status = 200,
}) =>
    TrackingClient((req) async {
      inspect?.call(req);
      final bytes = utf8.encode(body);
      // Każdy bajt osobno: granice SSE/JSON/UTF-8 rozcięte przez transport.
      return http.StreamedResponse(
        Stream.fromIterable(bytes.map((byte) => [byte])),
        status,
        headers: {'content-type': 'text/event-stream; charset=utf-8'},
      );
    });

List<HttpProviderAdapter> allAdapters(
  HttpClientFactory factory, {
  ProviderHttpConfig config = const ProviderHttpConfig(),
}) =>
    [
      OpenAiAdapter(clientFactory: factory, config: config),
      AnthropicAdapter(clientFactory: factory, config: config),
      GeminiAdapter(clientFactory: factory, config: config),
      XaiAdapter(clientFactory: factory, config: config),
    ];

void main() {
  group('SSE', () {
    test(
      'wielowierszowe data, komentarze, BOM, CRLF i rozcięte UTF-8',
      () async {
        final bytes = utf8.encode(
          '\uFEFF: komentarz\r\nevent: wynik\r\ndata: zażółć\r\ndata: gęślą\r\nid: 1\r\n\r\n',
        );
        final events = await decodeSse(
          Stream.fromIterable(bytes.map((byte) => [byte])),
        ).toList();
        expect(events, hasLength(1));
        expect(events.single.data, 'zażółć\ngęślą');
        expect(events.single.event, 'wynik');
      },
    );
    test('ignoruje niedomknięte zdarzenie na końcu', () async {
      expect(
        await decodeSse(Stream.value(utf8.encode('data: niepełne'))).toList(),
        isEmpty,
      );
    });
    test('ogranicza rozmiar pojedynczego zdarzenia', () async {
      final raw = 'data: ${'x' * (2 * 1024 * 1024 + 1)}\n\n';
      await expectLater(
        decodeSse(Stream.value(utf8.encode(raw))),
        emitsError(isA<FormatException>()),
      );
    });
  });

  test('OpenAI Responses mapuje żądanie, delta, usage i completed', () async {
    final client = streamed(
      frame({'type': 'response.output_text.delta', 'delta': 'Cześć 🌍'}) +
          frame({
            'type': 'response.completed',
            'response': {
              'usage': {'input_tokens': 7, 'output_tokens': 3},
            },
          }),
      inspect: (req) {
        expect(req.url.toString(), 'https://api.openai.com/v1/responses');
        expect(req.followRedirects, isFalse);
        expect(req.headers['Authorization'], 'Bearer test-only-placeholder');
        final body = jsonDecode((req as http.Request).body) as Map;
        expect(body['store'], isFalse);
        expect(body['stream'], isTrue);
        expect(body['max_output_tokens'], 1024);
        expect(body['input'][0]['role'], 'system');
      },
    );
    final events = await OpenAiAdapter(clientFactory: () => client)
        .stream(request())
        .toList();
    expect(events.map((event) => event.delta).join(), 'Cześć 🌍');
    expect(events.last.done, isTrue);
    expect(events.last.usage?.inputTokens, 7);
    expect(client.closed, isTrue);
  });

  test(
    'Claude oddziela system, łączy skumulowane użycie, kończy message_stop',
    () async {
      final client = streamed(
        [
          frame({
            'type': 'message_start',
            'message': {
              'usage': {'input_tokens': 10, 'output_tokens': 1},
            },
          }),
          frame({'type': 'ping'}),
          frame({
            'type': 'content_block_delta',
            'delta': {'type': 'thinking_delta', 'thinking': 'Ukryte'},
          }),
          frame({
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': 'Witaj'},
          }),
          frame({
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 5},
          }),
          frame({'type': 'message_stop'})
        ].join(),
        inspect: (req) {
          expect(req.url.host, 'api.anthropic.com');
          expect(req.headers['anthropic-version'], '2023-06-01');
          final body = jsonDecode((req as http.Request).body) as Map;
          expect(body['system'], 'Zasady');
          expect(body['messages'], hasLength(1));
        },
      );
      final events = await AnthropicAdapter(clientFactory: () => client)
          .stream(request())
          .toList();
      expect(events.map((event) => event.delta).join(), 'Witaj');
      expect(events.last.usage?.inputTokens, 10);
      expect(events.last.usage?.outputTokens, 5);
      expect(events.last.done, isTrue);
    },
  );

  test(
    'Gemini używa nagłówka klucza, systemInstruction, pomija thought',
    () async {
      final client = streamed(
        frame({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'thought': true, 'text': 'Ukryte'},
                  {'text': 'Dzień dobry'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
          'usageMetadata': {'promptTokenCount': 8, 'candidatesTokenCount': 4},
        }),
        inspect: (req) {
          expect(
            req.url.toString(),
            'https://generativelanguage.googleapis.com/v1beta/models/custom-model:streamGenerateContent?alt=sse',
          );
          expect(req.url.query.contains('key='), isFalse);
          expect(req.headers['x-goog-api-key'], 'test-only-placeholder');
          final body = jsonDecode((req as http.Request).body) as Map;
          expect(body['systemInstruction']['parts'][0]['text'], 'Zasady');
          expect(body['contents'][0]['role'], 'user');
        },
      );
      final events = await GeminiAdapter(clientFactory: () => client)
          .stream(request(model: 'models/custom-model'))
          .toList();
      expect(events.single.delta, 'Dzień dobry');
      expect(events.single.usage?.outputTokens, 4);
      expect(events.single.done, isTrue);
    },
  );

  test(
    'xAI czeka na DONE i przyjmuje końcowe użycie po finish_reason',
    () async {
      final client = streamed(
        [
          frame({
            'choices': [
              {
                'delta': {'content': 'Hej'},
                'finish_reason': null,
              },
            ],
          }),
          frame({
            'choices': [
              {'delta': {}, 'finish_reason': 'stop'},
            ],
          }),
          frame({
            'choices': [],
            'usage': {'prompt_tokens': 11, 'completion_tokens': 6},
          }),
          'data: [DONE]\n\n'
        ].join(),
        inspect: (req) {
          expect(req.url.toString(), 'https://api.x.ai/v1/chat/completions');
          final body = jsonDecode((req as http.Request).body) as Map;
          expect(body['stream'], isTrue);
        },
      );
      final events = await XaiAdapter(clientFactory: () => client)
          .stream(request())
          .toList();
      expect(events.first.delta, 'Hej');
      expect(events.last.usage?.inputTokens, 11);
      expect(events.last.usage?.outputTokens, 6);
      expect(events.last.done, isTrue);
    },
  );

  group('wspólne zabezpieczenia transportu', () {
    for (final index in [0, 1, 2, 3]) {
      test('dostawca $index: brak klucza nie wykonuje sieci', () async {
        final client = streamed('');
        final adapter = allAdapters(() => client)[index];
        await expectLater(
          adapter.stream(request(apiKey: '')),
          emitsError(
            isA<ProviderException>().having(
              (e) => e.code,
              'code',
              'missing_key',
            ),
          ),
        );
        expect(client.sends, 0);
      });
      test('dostawca $index: 429 bez retry i bez ujawniania body', () async {
        final client = streamed('tajny prompt i klucz', status: 429);
        final adapter = allAdapters(() => client)[index];
        await expectLater(
          adapter.stream(request()),
          emitsError(
            isA<ProviderException>()
                .having((e) => e.code, 'code', 'rate_limit')
                .having(
                  (e) => e.toString().contains('tajny'),
                  'sanityzacja',
                  false,
                ),
          ),
        );
        expect(client.sends, 1);
        expect(client.closed, isTrue);
      });
      test('dostawca $index: urwany stream nie udaje sukcesu', () async {
        final client = streamed(': keep-alive\n\n');
        final adapter = allAdapters(() => client)[index];
        await expectLater(
          adapter.stream(request()),
          emitsError(
            isA<ProviderException>().having(
              (e) => e.code,
              'code',
              'interrupted',
            ),
          ),
        );
      });
      test(
        'dostawca $index: błąd wewnątrz SSE jest jawny i zredagowany',
        () async {
          final client = streamed(
            frame({
              'type': 'error',
              'error': {'message': 'tajny-prompt-klucz'},
            }),
          );
          final adapter = allAdapters(() => client)[index];
          await expectLater(
            adapter.stream(request()),
            emitsError(
              isA<ProviderException>()
                  .having((e) => e.code, 'code', 'provider_error')
                  .having(
                    (e) => e.toString().contains('tajny'),
                    'redakcja SSE',
                    false,
                  ),
            ),
          );
        },
      );
    }

    test(
      'anulowanie przed nagłówkami zamyka klienta i kończy oczekiwanie',
      () async {
        final started = Completer<void>();
        final client = TrackingClient((req) {
          started.complete();
          return Completer<http.StreamedResponse>().future;
        });
        final adapter = OpenAiAdapter(clientFactory: () => client);
        final result = expectLater(
          adapter.stream(request()),
          emitsError(
            isA<ProviderException>().having((e) => e.code, 'code', 'cancelled'),
          ),
        );
        await started.future;
        adapter.cancel();
        await result;
        expect(client.closed, isTrue);
      },
    );
    test('anulowanie podczas oczekiwania na chunk', () async {
      final bytes = StreamController<List<int>>();
      final started = Completer<void>();
      final client = TrackingClient((req) async {
        started.complete();
        return http.StreamedResponse(
          bytes.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final adapter = OpenAiAdapter(clientFactory: () => client);
      final result = expectLater(
        adapter.stream(request()),
        emitsError(
          isA<ProviderException>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      await started.future;
      await Future<void>.delayed(Duration.zero);
      adapter.cancel();
      await result;
      await bytes.close();
      expect(client.closed, isTrue);
    });
    test('timeout nagłówków i brak retry', () async {
      final client = TrackingClient(
        (req) => Completer<http.StreamedResponse>().future,
      );
      final adapter = OpenAiAdapter(
        clientFactory: () => client,
        config: const ProviderHttpConfig(
          connectTimeout: Duration(milliseconds: 5),
        ),
      );
      await expectLater(
        adapter.stream(request()),
        emitsError(
          isA<ProviderException>().having((e) => e.code, 'code', 'timeout'),
        ),
      );
      expect(client.sends, 1);
      expect(client.closed, isTrue);
    });
    test('timeout bezczynności strumienia zamyka klienta', () async {
      final bytes = StreamController<List<int>>();
      final client = TrackingClient(
        (req) async => http.StreamedResponse(
          bytes.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      final adapter = OpenAiAdapter(
        clientFactory: () => client,
        config: const ProviderHttpConfig(
          idleTimeout: Duration(milliseconds: 5),
        ),
      );
      await expectLater(
        adapter.stream(request()),
        emitsError(
          isA<ProviderException>().having((e) => e.code, 'code', 'timeout'),
        ),
      );
      expect(client.closed, isTrue);
      await bytes.close();
    });
    test('odrzuca JSON lub HTML zamiast SSE', () async {
      final client = TrackingClient(
        (req) async => http.StreamedResponse(
          Stream.value(utf8.encode('{}')),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectLater(
        OpenAiAdapter(clientFactory: () => client).stream(request()),
        emitsError(
          isA<ProviderException>().having((e) => e.code, 'code', 'protocol'),
        ),
      );
    });
    test('błędny JSON nie ujawnia odpowiedzi dostawcy', () async {
      final client = streamed('data: tajny-nieprawidłowy-json\n\n');
      await expectLater(
        OpenAiAdapter(clientFactory: () => client).stream(request()),
        emitsError(
          isA<ProviderException>()
              .having((e) => e.code, 'code', 'protocol')
              .having((e) => e.toString().contains('tajny'), 'redakcja', false),
        ),
      );
    });
    test(
      'odrzuca przekierowanie zamiast wysyłać klucz do obcej domeny',
      () async {
        final client = streamed(
          '',
          status: 307,
          inspect: (req) => expect(req.followRedirects, isFalse),
        );
        await expectLater(
          OpenAiAdapter(clientFactory: () => client).stream(request()),
          emitsError(isA<ProviderException>()),
        );
        expect(client.sends, 1);
      },
    );
    test('nieprawidłowy model nie wykonuje sieci', () async {
      final client = streamed('');
      await expectLater(
        GeminiAdapter(clientFactory: () => client)
            .stream(request(model: 'https://evil.invalid/?key=leak')),
        emitsError(isA<ProviderException>()),
      );
      expect(client.sends, 0);
    });
    test('401 mapuje błąd autoryzacji', () async {
      final client = streamed('', status: 401);
      await expectLater(
        OpenAiAdapter(clientFactory: () => client).stream(request()),
        emitsError(
          isA<ProviderException>().having(
            (e) => e.code,
            'code',
            'authentication',
          ),
        ),
      );
    });
    test('OpenAI incomplete zachowuje sygnał niepełności', () async {
      final client = streamed(frame({'type': 'response.incomplete'}));
      await expectLater(
        OpenAiAdapter(clientFactory: () => client).stream(request()),
        emitsError(
          isA<ProviderException>().having((e) => e.code, 'code', 'incomplete'),
        ),
      );
    });
  });

  group('katalog modeli tylko na żądanie', () {
    test('OpenAI i xAI mapują katalog bez sugerowania cen', () async {
      for (final factory in [OpenAiAdapter.new, XaiAdapter.new]) {
        var calls = 0;
        final client = MockClient((req) async {
          calls++;
          expect(req.method, 'GET');
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'konto-model'},
              ],
            }),
            200,
          );
        });
        final adapter = factory(clientFactory: () => client);
        expect(calls, 0);
        final models = await adapter.discoverModels('test-placeholder');
        expect(models.single.id, 'konto-model');
        expect(models.single.inputPricePerMillion, isNull);
        expect(calls, 1);
      }
    });
    test('Claude obsługuje paginację i nazwę wyświetlaną', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'a', 'display_name': 'Model A'},
              ],
              'has_more': true,
              'last_id': 'a',
            }),
            200,
          );
        }
        expect(req.url.queryParameters['after_id'], 'a');
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'b'},
            ],
            'has_more': false,
          }),
          200,
        );
      });
      final result = await AnthropicAdapter(clientFactory: () => client)
          .discoverModels('test-placeholder');
      expect(result.map((model) => model.id), ['a', 'b']);
      expect(result.first.label, 'Model A');
    });
    test('Gemini filtruje embeddingi i obsługuje pageToken', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode({
              'models': [
                {
                  'name': 'models/text',
                  'displayName': 'Tekst',
                  'supportedGenerationMethods': ['generateContent'],
                },
                {
                  'name': 'models/embed',
                  'supportedGenerationMethods': ['embedContent'],
                },
              ],
              'nextPageToken': 'second',
            }),
            200,
          );
        }
        expect(req.url.queryParameters['pageToken'], 'second');
        return http.Response(jsonEncode({'models': []}), 200);
      });
      final result = await GeminiAdapter(clientFactory: () => client)
          .discoverModels('test-placeholder');
      expect(result.single.id, 'models/text');
      expect(calls, 2);
    });
  });

  test('lokalne Demo nie nazywa atrapy prawdziwym AI', () async {
    final demo = DemoAdapter(chunkDelay: Duration.zero);
    final events = await demo.stream(request(apiKey: '')).toList();
    expect(events.last.done, isTrue);
    expect(
      events.map((event) => event.delta).join(),
      contains('bez połączenia z modelem AI'),
    );
    expect(events.last.usage, isNull);
    expect((await demo.discoverModels('')).single.id, 'demo-local');
  });
}
