import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'provider_adapter.dart';
import 'sse.dart';

typedef HttpClientFactory = http.Client Function();

class ProviderHttpConfig {
  const ProviderHttpConfig({
    this.connectTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 45),
    this.totalTimeout = const Duration(minutes: 5),
  });
  final Duration connectTimeout;
  final Duration idleTimeout;
  final Duration totalTimeout;
}

class _Operation {
  _Operation(this.client);
  final http.Client client;
  final cancelled = Completer<void>();
  ProviderException? reason;
  void stop(ProviderException error) {
    if (cancelled.isCompleted) {
      return;
    }
    reason = error;
    cancelled.complete();
    client.close();
  }
}

abstract class HttpProviderAdapter implements ProviderAdapter {
  HttpProviderAdapter({
    HttpClientFactory? clientFactory,
    this.config = const ProviderHttpConfig(),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final HttpClientFactory _clientFactory;
  final ProviderHttpConfig config;
  _Operation? _active;
  Uri generationUri(ProviderRequest request);
  Map<String, String> headers(String apiKey);
  Map<String, Object?> body(ProviderRequest request);
  Stream<ProviderEvent> parseEvents(Stream<SseEvent> events);
  Uri get modelsUri;
  List<ProviderModel> parseModels(Map<String, dynamic> json);
  Uri? nextModelsPage(Map<String, dynamic> json) => null;

  void _validateKey(String key) {
    if (key.trim().isEmpty) {
      throw const ProviderException(
        'missing_key',
        'Dodaj własny klucz API w ustawieniach dostawcy.',
      );
    }
    if (key.contains('\r') || key.contains('\n')) {
      throw const ProviderException(
        'invalid_key',
        'Klucz ma nieprawidłowy format.',
      );
    }
  }

  _Operation _begin() {
    if (_active != null) {
      throw const ProviderException('busy', 'Dostawca realizuje już żądanie.');
    }
    return _active = _Operation(_clientFactory());
  }

  @override
  void cancel() => _active?.stop(
        const ProviderException(
          'cancelled',
          'Zatrzymano odpowiedź. Dostawca mógł naliczyć zużycie.',
        ),
      );

  Future<T> _wait<T>(Future<T> future, _Operation operation) => Future.any([
        future,
        operation.cancelled.future.then<T>((_) => throw operation.reason!),
      ]);

  /// Domyka także źródło, które po Client.close nie emituje końca (np. atrapa
  /// albo wadliwy transport). Dzięki temu cleanup async* nie czeka na idle timeout.
  Stream<List<int>> _interruptibleBytes(
    Stream<List<int>> source,
    _Operation operation,
  ) {
    late StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;
    var finished = false;
    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        subscription = source.listen(
          (chunk) {
            if (!finished) controller.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            if (!finished) controller.addError(error, stack);
          },
          onDone: () {
            if (!finished) {
              finished = true;
              unawaited(controller.close());
            }
          },
        );
        operation.cancelled.future.then((_) {
          if (!finished) {
            finished = true;
            controller.addError(operation.reason!);
            unawaited(controller.close());
            unawaited(subscription?.cancel());
          }
        });
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        finished = true;
        return subscription?.cancel();
      },
    );
    return controller.stream;
  }

  void _checkStatus(int status) {
    if (status >= 200 && status < 300) {
      return;
    }
    final (code, message) = switch (status) {
      401 || 403 => (
          'authentication',
          'Odmowa dostępu. Sprawdź klucz i uprawnienia.'
        ),
      402 => (
          'billing',
          'Dostawca wymaga aktywnych środków lub rozliczeń API.',
        ),
      404 => (
          'model_not_found',
          'Model lub zasób jest niedostępny dla tego konta.',
        ),
      429 => (
          'rate_limit',
          'Osiągnięto limit dostawcy. Ponów ręcznie później.',
        ),
      >= 500 => ('server', 'Błąd serwera dostawcy. Ponów ręcznie później.'),
      _ => (
          'request',
          'Dostawca odrzucił żądanie. Sprawdź konfigurację modelu.',
        ),
    };
    // Nie czytamy/nie wyświetlamy body błędu: może zawierać prompt lub sekret.
    throw ProviderException(code, message, httpStatus: status);
  }

  ProviderException _safeError(Object error, _Operation operation) {
    if (operation.reason != null) {
      return operation.reason!;
    }
    if (error is ProviderException) {
      return error;
    }
    if (error is TimeoutException) {
      return const ProviderException(
        'timeout',
        'Przekroczono czas oczekiwania. Ponów ręcznie.',
      );
    }
    if (error is FormatException || error is TypeError) {
      return const ProviderException(
        'protocol',
        'Nieprawidłowy format odpowiedzi dostawcy.',
      );
    }
    return const ProviderException(
      'network',
      'Połączenie przerwane. Sprawdź dostęp do internetu.',
    );
  }

  Future<Uint8List> _catalogBytes(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > 8 * 1024 * 1024) {
        throw const FormatException('Zbyt duży katalog modeli.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  @override
  Stream<ProviderEvent> stream(ProviderRequest request) async* {
    _validateKey(request.apiKey);
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$')
            .hasMatch(request.model) ||
        request.turns.isEmpty ||
        request.maxOutputTokens < 1) {
      throw const ProviderException(
        'invalid_request',
        'Podaj model, wiadomość i dodatni limit tokenów.',
      );
    }
    final operation = _begin();
    final timer = Timer(
      config.totalTimeout,
      () => operation.stop(
        const ProviderException(
          'timeout',
          'Przekroczono łączny czas odpowiedzi.',
        ),
      ),
    );
    StreamIterator<ProviderEvent>? iterator;
    try {
      final req = http.Request('POST', generationUri(request))
        ..followRedirects = false
        ..headers.addAll({
          ...headers(request.apiKey),
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode(body(request));
      final response = await _wait(
        operation.client.send(req).timeout(config.connectTimeout),
        operation,
      );
      _checkStatus(response.statusCode);
      final contentType = response.headers['content-type'];
      if (contentType == null ||
          !contentType.toLowerCase().startsWith('text/event-stream')) {
        throw const ProviderException(
          'protocol',
          'Dostawca nie zwrócił strumienia SSE.',
        );
      }
      iterator = StreamIterator(
        parseEvents(decodeSse(_interruptibleBytes(
          response.stream.timeout(config.idleTimeout),
          operation,
        ))),
      );
      var completed = false;
      while (await _wait(iterator.moveNext(), operation)) {
        final event = iterator.current;
        yield event;
        if (event.done) {
          completed = true;
          break;
        }
      }
      if (!completed) {
        throw const ProviderException(
          'interrupted',
          'Odpowiedź jest niepełna: strumień zakończył się przed potwierdzeniem.',
        );
      }
    } catch (error) {
      throw _safeError(error, operation);
    } finally {
      timer.cancel();
      operation.client.close();
      await iterator?.cancel();
      if (identical(_active, operation)) {
        _active = null;
      }
    }
  }

  @override
  Future<List<ProviderModel>> discoverModels(String apiKey) async {
    _validateKey(apiKey);
    final operation = _begin();
    final timer = Timer(
      config.totalTimeout,
      () => operation.stop(
        const ProviderException(
          'timeout',
          'Przekroczono czas pobierania katalogu.',
        ),
      ),
    );
    try {
      final result = <ProviderModel>[];
      Uri? page = modelsUri;
      final visited = <String>{};
      while (page != null) {
        if (page.scheme != 'https' ||
            page.host != modelsUri.host ||
            !visited.add(page.toString()) ||
            visited.length > 100) {
          throw const ProviderException(
            'protocol',
            'Nieprawidłowa paginacja katalogu.',
          );
        }
        final req = http.Request('GET', page)
          ..followRedirects = false
          ..headers.addAll(headers(apiKey));
        final response = await _wait(
          operation.client.send(req).timeout(config.connectTimeout),
          operation,
        );
        _checkStatus(response.statusCode);
        final raw = await _wait(
          _catalogBytes(_interruptibleBytes(
            response.stream.timeout(config.idleTimeout),
            operation,
          )),
          operation,
        );
        final decoded = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
        result.addAll(parseModels(decoded));
        page = nextModelsPage(decoded);
      }
      return List.unmodifiable(
        {for (final model in result) model.id: model}.values,
      );
    } catch (error) {
      throw _safeError(error, operation);
    } finally {
      timer.cancel();
      operation.client.close();
      if (identical(_active, operation)) {
        _active = null;
      }
    }
  }
}
