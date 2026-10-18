import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/local_inference/android_local_engine.dart';
import 'package:scalajaca/provider_registry/provider_adapter.dart';

class Channel extends MethodChannel {
  Channel() : super('test-local');
  Future<dynamic> Function(MethodCall)? handler;
  final calls = <String>[];
  Future<dynamic> Function(String, dynamic)? invoke;
  @override
  Future<void> setMethodCallHandler(
      Future<dynamic> Function(MethodCall)? handler) async {
    this.handler = handler;
  }

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    calls.add(method);
    return await invoke?.call(method, arguments) as T?;
  }

  Future<void> event(Map<String, Object?> data) async {
    await handler?.call(MethodCall('event', data));
  }
}

Stream<ProviderEvent> run(AndroidLocalEngine engine) => engine.generate(
    model: 'a' * 64,
    turns: const [ChatTurn(role: ChatRole.user, text: 'Cześć')],
    context: 2048,
    maxTokens: 32);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Kanał składa UTF-8 rozcięte między tokenami i kończy usage', () async {
    final channel = Channel();
    final engine = AndroidLocalEngine(channel: channel);
    channel.invoke = (method, args) async {
      if (method == 'generate') {
        scheduleMicrotask(() async {
          for (final byte in utf8.encode('Zażółć 🌍')) {
            await channel.event({
              'requestId': args['requestId'],
              'type': 'bytes',
              'bytes': Uint8List.fromList([byte])
            });
          }
          await channel.event({
            'requestId': args['requestId'],
            'type': 'done',
            'reason': 'stop',
            'inputTokens': 9,
            'outputTokens': 3
          });
        });
      }
      return null;
    };
    final events = await run(engine).toList();
    expect(events.map((e) => e.delta).join(), 'Zażółć 🌍');
    expect(events.last.usage?.inputTokens, 9);
    expect(events.last.done, isTrue);
    engine.dispose();
  });
  test('Błąd platformy nie ujawnia wiadomości lub sekretu wyjątku', () async {
    final channel = Channel()
      ..invoke = (m, a) async {
        if (m == 'generate') {
          throw PlatformException(
              code: 'memory', message: 'secret-prompt-placeholder');
        }
        return null;
      };
    final engine = AndroidLocalEngine(channel: channel);
    await expectLater(
        run(engine).toList(),
        throwsA(isA<ProviderException>().having((e) => e.message, 'komunikat',
            isNot(contains('secret-prompt-placeholder')))));
    engine.dispose();
  });
  test('Limit tokenów jest zgłaszany jako częściowa odpowiedź', () async {
    final channel = Channel();
    final engine = AndroidLocalEngine(channel: channel);
    channel.invoke = (m, a) async {
      if (m == 'generate') {
        scheduleMicrotask(() => channel.event({
              'requestId': a['requestId'],
              'type': 'done',
              'reason': 'length',
              'inputTokens': 1,
              'outputTokens': 32
            }));
      }
      return null;
    };
    await expectLater(
        run(engine).toList(),
        throwsA(isA<ProviderException>()
            .having((e) => e.code, 'kod', 'output_limit')));
    engine.dispose();
  });
  test('Stop trafia do natywnego żądania, obce zdarzenia są ignorowane',
      () async {
    final channel = Channel();
    final engine = AndroidLocalEngine(channel: channel);
    final started = Completer<void>();
    String id = '';
    channel.invoke = (m, a) async {
      if (m == 'generate') {
        id = a['requestId'];
        started.complete();
      }
      if (m == 'stop' && id.isNotEmpty) {
        await channel
            .event({'requestId': id, 'type': 'done', 'reason': 'cancelled'});
      }
      return null;
    };
    final check = expectLater(
        run(engine).toList(),
        throwsA(isA<ProviderException>()
            .having((e) => e.code, 'kod', 'cancelled')));
    await started.future;
    await channel
        .event({'requestId': 'other', 'type': 'done', 'reason': 'stop'});
    engine.cancel();
    await check;
    expect(channel.calls, contains('stop'));
    engine.dispose();
  });
}
