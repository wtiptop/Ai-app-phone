import 'package:flutter/services.dart';

class VaultHandle {
  const VaultHandle(
      {required this.id, required this.writable, this.available = true});
  final String id;
  final bool writable;
  final bool available;
  factory VaultHandle.fromMap(Map<dynamic, dynamic> value) => VaultHandle(
        id: value['id'] as String,
        writable: value['writable'] as bool,
        available: value['available'] as bool? ?? true,
      );
}

class VaultFile {
  const VaultFile(
      {required this.id,
      required this.path,
      required this.bytes,
      required this.modified});

  /// Podpisany token natywny; nie jest dowolnym URI ani ścieżką.
  final String id;
  final String path;
  final int bytes;

  /// Znacznik modyfikacji dostawcy, milisekundy od epoki; 0 oznacza brak danych.
  final int modified;
  factory VaultFile.fromMap(Map<dynamic, dynamic> value) => VaultFile(
        id: value['id'] as String,
        path: value['path'] as String,
        bytes: value['bytes'] as int,
        modified: value['modified'] as int,
      );
}

class VaultListing {
  const VaultListing({required this.items, this.nextCursor});
  final List<VaultFile> items;
  final String? nextCursor;
}

class VaultException implements Exception {
  const VaultException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

abstract interface class VaultGateway {
  Future<VaultHandle?> pick({bool writable = false});
  Future<List<VaultHandle>> status();
  Future<VaultListing> list(String handleId, {String? cursor, int limit = 100});
  Future<String> read(String handleId, String documentId);
  Future<String> export(String handleId, String filename, String content);
  Future<void> disconnect(String handleId);
  Future<void> cancel(String handleId);
}

/// Dostęp do lokalnego vaultu wyłącznie po systemowym wyborze użytkownika.
/// Wybór writable musi być poprzedzony jawną zgodą na eksport w UI.
class VaultBridge implements VaultGateway {
  VaultBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('pl.scalajaca/vault');
  final MethodChannel _channel;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      throw const VaultException('unsupported',
          'Lokalny vault jest dostępny w aplikacji na Androida.');
    } on PlatformException catch (error) {
      // Nie przepuszczamy tekstu wyjątku systemu ani ścieżek plików do UI/logów.
      final message = switch (error.code) {
        'busy' => 'Poczekaj na zakończenie operacji na pamięci.',
        'vault_limit' =>
          'Osiągnięto limit 8 połączeń. Wybierz ponownie połączony vault tylko do odczytu albo odłącz nieużywane źródło, zachowując jego dane.',
        'cancelled' =>
          'Operację anulowano lub przekroczono czas. Możesz wznowić skanowanie.',
        'invalid_cursor' =>
          'Wznów skanowanie od początku. Poprzedni kursor jest niedostępny.',
        'revoked' ||
        'permission' =>
          'Uprawnienie do katalogu jest niedostępne. Połącz lokalny vault ponownie.',
        _ =>
          'Operacja niedostępna. Sprawdź uprawnienie do lokalnego katalogu, format UTF-8 i limit 1 MiB.',
      };
      throw VaultException(error.code, message);
    }
  }

  @override
  Future<VaultHandle?> pick({bool writable = false}) async {
    final value =
        await _call<Map<dynamic, dynamic>>('pick', {'writable': writable});
    return value == null ? null : VaultHandle.fromMap(value);
  }

  @override
  Future<List<VaultHandle>> status() async {
    final values = await _call<List<dynamic>>('status') ?? const [];
    return values
        .map((value) => VaultHandle.fromMap(value as Map))
        .toList(growable: false);
  }

  @override
  Future<VaultListing> list(String handleId,
      {String? cursor, int limit = 100}) async {
    if (limit < 1 || limit > 200) {
      throw const VaultException(
          'limit', 'Rozmiar strony musi mieścić się w zakresie 1–200.');
    }
    final value = await _call<Map<dynamic, dynamic>>(
        'list', {'handleId': handleId, 'cursor': cursor, 'limit': limit});
    if (value == null) {
      throw const VaultException('vault_error', 'Nie można odczytać katalogu.');
    }
    return VaultListing(
      items: (value['items'] as List)
          .map((item) => VaultFile.fromMap(item as Map))
          .toList(growable: false),
      nextCursor: value['nextCursor'] as String?,
    );
  }

  @override
  Future<String> read(String handleId, String documentId) async =>
      await _call<String>(
          'read', {'handleId': handleId, 'documentId': documentId}) ??
      '';

  @override
  Future<String> export(
          String handleId, String filename, String content) async =>
      await _call<String>('export',
          {'handleId': handleId, 'filename': filename, 'content': content}) ??
      '';

  @override
  Future<void> disconnect(String handleId) =>
      _call<void>('disconnect', {'handleId': handleId});

  @override
  Future<void> cancel(String handleId) =>
      _call<void>('cancel', {'handleId': handleId});
}
