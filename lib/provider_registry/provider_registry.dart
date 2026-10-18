import 'adapters.dart';
import 'provider_adapter.dart';
import 'minicpm_adapter.dart';

export 'adapters.dart';
export 'http_provider_adapter.dart' show HttpClientFactory, ProviderHttpConfig;
export 'provider_adapter.dart';
export 'provider_descriptor.dart';
export 'minicpm_adapter.dart';
export '../local_inference/local_adapter.dart';

class ProviderRegistry {
  ProviderRegistry(Iterable<ProviderAdapter> adapters)
      : _adapters = {for (final adapter in adapters) adapter.id: adapter};
  factory ProviderRegistry.standard(
          {MiniCpmEndpointReader? miniCpmEndpoint,
          ProviderAdapter? localAdapter}) =>
      ProviderRegistry([
        DemoAdapter(),
        OpenAiAdapter(),
        AnthropicAdapter(),
        GeminiAdapter(),
        XaiAdapter(),
        MiniCpmAdapter(readEndpoint: miniCpmEndpoint ?? () async => ''),
        if (localAdapter != null) localAdapter,
      ]);
  final Map<String, ProviderAdapter> _adapters;
  List<ProviderAdapter> get adapters => List.unmodifiable(_adapters.values);
  ProviderAdapter adapter(String id) =>
      _adapters[id] ??
      (throw const ProviderException('unknown_provider', 'Nieznany dostawca.'));
  void cancelAll() {
    for (final adapter in adapters) {
      adapter.cancel();
    }
  }
}
