import 'dart:convert';
import 'dart:math';

import '../provider_registry/provider_adapter.dart';
import 'local_engine.dart';

/// Ten adapter nie importuje transportu HTTP i nie ma fallbacku do sieci.
class LocalModelAdapter implements ProviderAdapter {
  LocalModelAdapter({required this.engine, Future<int> Function()? readContext})
      : readContext = readContext ?? (() async => 2048);
  final LocalInferenceEngine engine;
  final Future<int> Function() readContext;
  bool _busy = false, _cancelled = false;
  @override
  String get id => 'minicpm_local';
  @override
  String get label => 'MiniCPM • offline w telefonie';
  @override
  Future<List<ProviderModel>> discoverModels(String apiKey) async => [
        for (final model in (await engine.status()).models)
          ProviderModel(
              id: model.id,
              label: '${model.name} • ${(model.bytes / 1048576).round()} MiB'),
      ];
  @override
  void cancel() {
    _cancelled = true;
    engine.cancel();
  }

  @override
  Stream<ProviderEvent> stream(ProviderRequest request) async* {
    if (_busy) throw localError('busy');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(request.model) ||
        request.apiKey.isNotEmpty ||
        request.turns.isEmpty ||
        request.turns.length > 128 ||
        request.maxOutputTokens < 1 ||
        utf8
                .encode(jsonEncode([
                  for (final t in request.turns)
                    {'role': t.role.name, 'content': t.text}
                ]))
                .length >
            65536) {
      throw localError('invalid_request');
    }
    _busy = true;
    _cancelled = false;
    try {
      final context = await readContext();
      if (_cancelled) throw localError('cancelled');
      if (![1024, 2048, 4096].contains(context)) {
        throw localError('invalid_request');
      }
      var done = false;
      await for (final event in engine.generate(
          model: request.model,
          turns: request.turns,
          context: context,
          maxTokens: min(512, request.maxOutputTokens))) {
        if (_cancelled) throw localError('cancelled');
        yield event;
        if (event.done) {
          done = true;
          break;
        }
      }
      if (!done) throw localError('interrupted');
    } finally {
      _busy = false;
    }
  }
}
