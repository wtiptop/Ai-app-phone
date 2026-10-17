import 'adapters.dart';
import 'provider_adapter.dart';

export 'adapters.dart';
export 'http_provider_adapter.dart' show HttpClientFactory, ProviderHttpConfig;
export 'provider_adapter.dart';
export 'provider_descriptor.dart';

class ProviderRegistry {
  ProviderRegistry(Iterable<ProviderAdapter> adapters)
      : _adapters = {for (final adapter in adapters) adapter.id: adapter};
  factory ProviderRegistry.standard() => ProviderRegistry([
        DemoAdapter(),
        OpenAiAdapter(),
        AnthropicAdapter(),
        GeminiAdapter(),
        XaiAdapter(),
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
