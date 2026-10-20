import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import '../provider_registry/provider_adapter.dart';
import 'local_engine.dart';

class _Terminal {
  const _Terminal({this.error, this.input, this.output});
  final ProviderException? error;
  final int? input, output;
}

class _Run {
  _Run(this.id);
  final String id;
  final bytes = StreamController<List<int>>();
  final terminal = Completer<_Terminal>();
  void finish(_Terminal result) {
    if (terminal.isCompleted) return;
    terminal.complete(result);
    unawaited(bytes.close());
  }
}

class AndroidLocalEngine implements LocalInferenceEngine {
  AndroidLocalEngine({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('pl.scalajaca/local_inference') {
    _channel.setMethodCallHandler(_event);
  }
  final MethodChannel _channel;
  _Run? _active;
  int _serial = 0;
  bool _disposed = false;
  LocalModel _model(Map<dynamic, dynamic> json) => LocalModel(
      id: json['id'] as String,
      name: json['name'] as String,
      profile: json['profile'] as String,
      bytes: json['bytes'] as int);
  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw localError(e.code);
    } on MissingPluginException {
      throw localError('unsupported_abi');
    }
  }

  @override
  Future<LocalEngineStatus> status() async {
    final data = await _call<Map<dynamic, dynamic>>('status');
    if (data == null) throw localError('native_error');
    return LocalEngineStatus(commit: data['engineCommit'] as String, models: [
      for (final model in data['models'] as List) _model(model as Map)
    ]);
  }

  @override
  Future<LocalModel?> importModel({String expectedSha256 = ''}) async {
    final data = await _call<Map<dynamic, dynamic>>(
        'import', {'expectedSha256': expectedSha256});
    return data == null ? null : _model(data);
  }

  @override
  Future<void> removeModel(String id) async =>
      _call<void>('delete', {'model': id});
  @override
  Future<void> cancelImport() async => _call<void>('cancelImport');

  Future<void> _event(MethodCall call) async {
    if (call.method != 'event') return;
    final data = call.arguments as Map;
    final run = _active;
    if (run == null ||
        run.id != data['requestId'] ||
        run.terminal.isCompleted) {
      return;
    }
    switch (data['type']) {
      case 'bytes':
        run.bytes.add(data['bytes'] as Uint8List);
      case 'error':
        run.finish(_Terminal(error: localError(data['code'] as String)));
      case 'done':
        final reason = data['reason'];
        final error = switch (reason) {
          'stop' => null,
          'length' => localError('output_limit'),
          'cancelled' => localError('cancelled'),
          'timeout' => localError('timeout'),
          _ => localError('native_error'),
        };
        run.finish(_Terminal(
            error: error,
            input: data['inputTokens'] as int?,
            output: data['outputTokens'] as int?));
    }
  }

  @override
  Stream<ProviderEvent> generate(
      {required String model,
      required List<ChatTurn> turns,
      required int context,
      required int maxTokens,
      bool sourceGrounded = false}) async* {
    if (_disposed) throw localError('native_error');
    if (_active != null) throw localError('busy');
    final run = _active =
        _Run('local_${DateTime.now().microsecondsSinceEpoch}_${_serial++}');
    final timeout = Timer(const Duration(minutes: 4), () {
      cancel();
      run.finish(_Terminal(error: localError('timeout')));
    });
    try {
      try {
        await _call<void>('generate', {
          'requestId': run.id,
          'model': model,
          'turns': [
            for (final t in turns) {'role': t.role.name, 'text': t.text}
          ],
          'context': context,
          'maxTokens': maxTokens,
          'sourceGrounded': sourceGrounded
        });
      } on ProviderException catch (e) {
        run.finish(_Terminal(error: e));
      }
      await for (final text
          in const Utf8Decoder(allowMalformed: true).bind(run.bytes.stream)) {
        yield ProviderEvent(delta: text);
      }
      final result = await run.terminal.future;
      if (result.error != null) throw result.error!;
      yield ProviderEvent(
          done: true,
          usage: TokenUsage(
              inputTokens: result.input, outputTokens: result.output));
    } finally {
      timeout.cancel();
      if (identical(_active, run)) {
        // Obejmuje też anulowanie subskrypcji bez przycisku Stop.
        unawaited(_call<void>('stop', {'requestId': run.id})
            .catchError((Object _) {}));
        _active = null;
      }
      if (!run.bytes.isClosed) unawaited(run.bytes.close());
    }
  }

  @override
  void cancel() {
    final run = _active;
    if (run != null) {
      unawaited(
          _call<void>('stop', {'requestId': run.id}).catchError((Object _) {}));
    }
  }

  void dispose() {
    cancel();
    _disposed = true;
    _active?.finish(_Terminal(error: localError('cancelled')));
    _channel.setMethodCallHandler(null);
  }
}
