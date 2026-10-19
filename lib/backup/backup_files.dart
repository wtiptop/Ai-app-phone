import 'package:flutter/services.dart';

class BackupFilesException implements Exception {
  const BackupFilesException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Każdy zapis/odczyt musi być awaitowany. Identyfikatory są nieprzezroczyste.
/// Most przenosi wyłącznie szyfrotekst; hasła i klucze pozostają w warstwie Dart.
abstract interface class BackupFilesGateway {
  Future<String> create();
  Future<void> write(String id, Uint8List bytes);
  Future<bool> save(String id, String filename);
  Future<String?> open();
  Future<Uint8List> read(String id, {int maxBytes = 65536});
  Future<void> close(String id);
}

class BackupFilesBridge implements BackupFilesGateway {
  BackupFilesBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('pl.scalajaca/backup_files');
  final MethodChannel _channel;
  static const maxWriteBytes = 262144;
  static const maxReadBytes = 65536;
  static const maxArchiveBytes = 2147483648;

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const BackupFilesException('unsupported',
          'Strumieniowa kopia plikowa jest dostępna w aplikacji na Androida.');
    } on PlatformException catch (error) {
      throw BackupFilesException(
          error.code,
          switch (error.code) {
            'busy' => 'Poczekaj na zakończenie operacji na kopii zapasowej.',
            'limit' => 'Przekroczono rozmiar bloku lub limit kopii 2 GiB.',
            'cancelled' => 'Operację na kopii zapasowej anulowano.',
            _ => 'Nie można odczytać lub zapisać pliku kopii zapasowej.',
          });
    }
  }

  @override
  Future<String> create() async {
    final id = await _call<String>('create');
    if (id == null || id.isEmpty) {
      throw const BackupFilesException(
          'file_error', 'Nie można przygotować szyfrowanej kopii zapasowej.');
    }
    return id;
  }

  @override
  Future<void> write(String id, Uint8List bytes) async {
    if (bytes.length > maxWriteBytes) {
      throw const BackupFilesException(
          'limit', 'Blok szyfrowanej kopii przekracza 256 KiB.');
    }
    await _call<void>('write', {'id': id, 'bytes': bytes});
  }

  @override
  Future<bool> save(String id, String filename) async =>
      await _call<bool>('save', {'id': id, 'filename': filename}) ?? false;

  @override
  Future<String?> open() => _call<String>('open');

  @override
  Future<Uint8List> read(String id, {int maxBytes = maxReadBytes}) async {
    if (maxBytes < 1 || maxBytes > maxReadBytes) {
      throw const BackupFilesException(
          'limit', 'Blok odczytu kopii musi mieć od 1 do 65536 bajtów.');
    }
    final bytes =
        await _call<Uint8List>('read', {'id': id, 'maxBytes': maxBytes});
    if (bytes == null || bytes.length > maxBytes) {
      throw const BackupFilesException(
          'file_error', 'Nieprawidłowa odpowiedź odczytu kopii zapasowej.');
    }
    return bytes;
  }

  @override
  Future<void> close(String id) => _call<void>('close', {'id': id});
}
