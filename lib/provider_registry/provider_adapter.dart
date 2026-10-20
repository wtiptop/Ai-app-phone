/// Typy transportu. Nie przechowują sekretów ani nie zapisują diagnostyki.
enum ChatRole { system, user, assistant }

class ChatTurn {
  const ChatTurn({required this.role, required this.text});
  final ChatRole role;
  final String text;
}

class ProviderRequest {
  ProviderRequest({
    required this.model,
    required List<ChatTurn> turns,
    this.apiKey = '',
    this.maxOutputTokens = 1024,
    this.expectedEndpoint,
    this.sourceGrounded = false,
  }) : turns = List.unmodifiable(turns);

  final String model;
  final List<ChatTurn> turns;
  final String apiKey;
  final int maxOutputTokens;

  /// Jawny pakiet źródeł: lokalny model używa zachowawczego dekodowania.
  final bool sourceGrounded;

  /// Adres własnego serwera pokazany w zgodzie; chroni przed zmianą konfiguracji.
  final String? expectedEndpoint;

  // Celowo bez toString(): klucz i treść nie należą do logów.
}

class TokenUsage {
  const TokenUsage({this.inputTokens, this.outputTokens});
  final int? inputTokens;
  final int? outputTokens;

  TokenUsage merge(TokenUsage other) => TokenUsage(
        inputTokens: other.inputTokens ?? inputTokens,
        outputTokens: other.outputTokens ?? outputTokens,
      );
}

class ProviderEvent {
  const ProviderEvent({this.delta = '', this.usage, this.done = false});
  final String delta;
  final TokenUsage? usage;
  final bool done;
}

class ProviderModel {
  const ProviderModel({required this.id, required this.label});
  final String id;
  final String label;
  // API katalogu nie gwarantuje wspólnego formatu cen ani kontekstu.
  double? get inputPricePerMillion => null;
  double? get outputPricePerMillion => null;
  int? get contextTokens => null;
}

class ProviderException implements Exception {
  const ProviderException(this.code, this.message, {this.httpStatus});
  final String code;
  final String message;
  final int? httpStatus;

  @override
  String toString() => message;
}

abstract class ProviderAdapter {
  String get id;
  String get label;
  Stream<ProviderEvent> stream(ProviderRequest request);

  /// Wyłącznie na jawną akcję użytkownika; to wywołanie sieciowe.
  Future<List<ProviderModel>> discoverModels(String apiKey);

  /// Zamyka aktywnego klienta HTTP. Bez ponawiania płatnego POST.
  void cancel();
}

/// Punkt rozszerzeń dla oficjalnego delegowanego dostępu; brak implementacji SSO.
abstract class DelegatedAccountConnector {
  String get providerId;
  Future<void> signIn();
  Future<void> revoke();
  bool get grantsInference;
}
