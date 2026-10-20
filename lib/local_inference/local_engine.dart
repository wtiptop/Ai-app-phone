import '../provider_registry/provider_adapter.dart';

class LocalModel {
  const LocalModel(
      {required this.id,
      required this.name,
      required this.profile,
      required this.bytes});
  final String id, name, profile;
  final int bytes;
}

class LocalEngineStatus {
  const LocalEngineStatus({required this.commit, required this.models});
  final String commit;
  final List<LocalModel> models;
}

abstract class LocalInferenceEngine {
  Future<LocalEngineStatus> status();
  Future<LocalModel?> importModel({String expectedSha256 = ''});
  Future<void> removeModel(String id);
  Future<void> cancelImport();
  Stream<ProviderEvent> generate(
      {required String model,
      required List<ChatTurn> turns,
      required int context,
      required int maxTokens,
      bool sourceGrounded = false});
  void cancel();
}

ProviderException localError(String code) {
  final message = switch (code) {
    'cancelled' => 'Zatrzymano lokalną inferencję lub import.',
    'busy' => 'Silnik lokalny lub import jest zajęty. Poczekaj na zakończenie.',
    'missing_model' =>
      'Brak modelu. Zaimportuj GGUF w ustawieniach modeli lokalnych.',
    'invalid_gguf' => 'Plik jest niepoprawnym, uszkodzonym lub niepełnym GGUF.',
    'unsupported_model' =>
      'Obecnie obsługiwane są tekstowe MiniCPM5-1B i MiniCPM5-2B w GGUF (architektura llama).',
    'unsupported_quantization' =>
      'Obsługiwane są GGUF F32/F16/BF16, Q8_0 i Q4_K_M/Q6_K. Wybierz zgodną wersję.',
    'hash_mismatch' =>
      'SHA-256 pliku nie zgadza się z podaną sumą. Import odrzucono.',
    'invalid_hash' => 'SHA-256 musi mieć dokładnie 64 znaki szesnastkowe.',
    'file_too_large' =>
      'Model przekracza limit importu 3 GiB. Wybierz mniejszy GGUF.',
    'storage_space' =>
      'Brak miejsca. Import pozostawia co najmniej 256 MiB rezerwy.',
    'memory' =>
      'Za mało wolnego RAM dla modelu. Zwolnij pamięć lub wybierz mniejszy GGUF.',
    'thermal' =>
      'Telefon jest zbyt gorący. Inferencję zatrzymano; poczekaj na schłodzenie.',
    'context_limit' =>
      'Rozmowa przekracza lokalny kontekst. Zacznij nowy czat lub zwiększ limit w ustawieniach.',
    'output_limit' =>
      'Osiągnięto limit 512 tokenów lub limit żądania. Odpowiedź jest częściowa.',
    'timeout' =>
      'Przekroczono czas lokalnej inferencji. Odpowiedź może być częściowa.',
    'unsupported_abi' =>
      'Brak zgodnego silnika w APK. Użyj wersji dla architektury swojego urządzenia.',
    'model_load' =>
      'Silnik nie może załadować tego GGUF. Sprawdź zgodność modelu i wolny RAM.',
    'invalid_request' ||
    'invalid_model_id' =>
      'Nieprawidłowy model lub parametry lokalnej inferencji.',
    'storage' => 'Operacja na prywatnym magazynie modeli nie powiodła się.',
    _ => 'Lokalny silnik przerwał pracę. Dane nie zostały wysłane do chmury.',
  };
  return ProviderException(code, message);
}
