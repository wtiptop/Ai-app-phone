import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/encrypted_backup.dart';

class BackupCancelled extends BackupException {
  const BackupCancelled() : super('Operację kopii anulowano.');
}

class ArchiveManifest {
  ArchiveManifest({required Map<String, int> counts, required this.createdAt})
      : counts = Map.unmodifiable(counts);
  final Map<String, int> counts;
  final String createdAt;
  int get records => counts.values.fold(0, (a, b) => a + b);
  Map<String, Object> toJson() => {
        'format': 'scalajaca.data.archive',
        'version': 2,
        'schema': 3,
        'owner': 'local-owner',
        'createdAt': createdAt,
        'counts': counts,
      };
  static ArchiveManifest parse(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw.length != 6 ||
        raw['format'] != 'scalajaca.data.archive' ||
        raw['version'] != 2 ||
        raw['schema'] != 3 ||
        raw['owner'] != 'local-owner' ||
        raw['createdAt'] is! String ||
        (raw['createdAt'] as String).length > 64 ||
        DateTime.tryParse(raw['createdAt'] as String) == null ||
        raw['counts'] is! Map<String, dynamic>) {
      throw const BackupException('Nieprawidłowy manifest kopii.');
    }
    final counts = <String, int>{};
    for (final e in (raw['counts'] as Map<String, dynamic>).entries) {
      if (e.key.length > 64 ||
          e.value is! int ||
          e.value < 0 ||
          e.value > EncryptedArchive.maxRecords) {
        throw const BackupException('Nieprawidłowe liczniki kopii.');
      }
      counts[e.key] = e.value as int;
    }
    final manifest =
        ArchiveManifest(counts: counts, createdAt: raw['createdAt'] as String);
    if (counts.isEmpty ||
        counts.length > 32 ||
        manifest.records > EncryptedArchive.maxRecords) {
      throw const BackupException('Kopia przekracza limit rekordów.');
    }
    return manifest;
  }
}

/// Strumieniowy format v2. Każdy blok jest uwierzytelniony i łączy się z poprzednim
/// tagiem. Dopiero stopka oraz EOF kończą poprawny strumień danych.
class EncryptedArchive {
  static const blockBytes = 256 * 1024;
  static const maxArchiveBytes = 2 * 1024 * 1024 * 1024;
  static const maxRecordBytes = 32 * 1024 * 1024;
  static const maxRecords = 2000000;
  static const iterations = 600000;
  static final magic = Uint8List.fromList(ascii.encode('SCALABK2\n'));

  static void validatePassphrase(String value) {
    if (value.runes.length < 12 || utf8.encode(value).length > 4096) {
      throw const BackupException(
          'Hasło kopii musi mieć co najmniej 12 znaków i nie więcej niż 4096 bajtów.');
    }
  }

  static void checkCancelled(bool Function()? cancelled) {
    if (cancelled?.call() ?? false) throw const BackupCancelled();
  }

  static Future<SecretKey> _derive(String value, List<int> salt) async {
    // Kosztowny KDF nie blokuje interfejsu. Hasło i klucz nie są zapisywane.
    final bytes = await Isolate.run(() async {
      final key = await Pbkdf2(
              macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
          .deriveKey(secretKey: SecretKey(utf8.encode(value)), nonce: salt);
      return key.extractBytes();
    });
    return SecretKey(bytes);
  }

  Future<ArchiveManifest> write(
      Stream<Map<String, Object?>> rows,
      Map<String, int> counts,
      String passphrase,
      Future<void> Function(Uint8List bytes) output,
      {bool Function()? isCancelled,
      void Function(int records, int total)? onProgress}) async {
    validatePassphrase(passphrase);
    final manifest = ArchiveManifest.parse(ArchiveManifest(
            counts: counts, createdAt: DateTime.now().toUtc().toIso8601String())
        .toJson());
    checkCancelled(isCancelled);
    final random = Random.secure();
    final salt =
        Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
    final prefix =
        Uint8List.fromList(List.generate(8, (_) => random.nextInt(256)));
    final header = Uint8List.fromList(utf8.encode(jsonEncode({
      'format': 'scalajaca.encrypted-stream',
      'version': 2,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': iterations,
      'cipher': 'AES-256-GCM',
      'salt': base64Encode(salt),
      'noncePrefix': base64Encode(prefix),
      'blockBytes': blockBytes,
    })));
    final key = await _derive(passphrase, salt);
    checkCancelled(isCancelled);
    var written = 0;
    Future<void> send(Uint8List bytes) async {
      checkCancelled(isCancelled);
      if (written + bytes.length > maxArchiveBytes) {
        throw const BackupException(
            'Kopia przekracza limit 2 GiB. Niczego nie pominięto; zapisu nie ukończono.');
      }
      await output(bytes);
      written += bytes.length;
    }

    await send(
        Uint8List.fromList([...magic, ..._u32(header.length), ...header]));
    final frames = _FrameWriter(header, prefix, key, send, isCancelled);
    await frames.add(1, utf8.encode(jsonEncode(manifest.toJson())));
    final pending = BytesBuilder(copy: false);
    var records = 0, dataBytes = 0, dataFrames = 0;
    final seen = {for (final name in counts.keys) name: 0};
    Future<void> flush() async {
      if (pending.isEmpty) return;
      await frames.add(2, pending.takeBytes());
      dataFrames++;
    }

    await for (final row in rows) {
      checkCancelled(isCancelled);
      final name = row['table'];
      if (row.length != 2 ||
          name is! String ||
          !seen.containsKey(name) ||
          row['row'] is! Map) {
        throw const BackupException('Nieprawidłowy rekord danych kopii.');
      }
      seen[name] = seen[name]! + 1;
      if (seen[name]! > counts[name]! || ++records > maxRecords) {
        throw const BackupException(
            'Dane zmieniły się podczas tworzenia kopii.');
      }
      final encoded = utf8.encode('${jsonEncode(row)}\n');
      if (encoded.length > maxRecordBytes) {
        throw const BackupException(
            'Pojedynczy rekord kopii przekracza 32 MiB. Kopii nie ukończono.');
      }
      dataBytes += encoded.length;
      var offset = 0;
      while (offset < encoded.length) {
        final n = min(blockBytes - pending.length, encoded.length - offset);
        pending.add(Uint8List.sublistView(encoded, offset, offset + n));
        offset += n;
        if (pending.length == blockBytes) await flush();
      }
      if (records == 1 || records % 50 == 0) {
        onProgress?.call(records, manifest.records);
      }
    }
    await flush();
    if (!_sameCounts(seen, counts)) {
      throw const BackupException('Niepełny snapshot danych kopii.');
    }
    await frames.add(
        3,
        utf8.encode(jsonEncode({
          'format': 'scalajaca.archive-end',
          'records': records,
          'dataFrames': dataFrames,
          'dataBytes': dataBytes,
          'counts': seen,
        })));
    onProgress?.call(records, manifest.records);
    return manifest;
  }

  Future<ArchiveReader> open(Stream<Uint8List> input, String passphrase,
      {bool Function()? isCancelled,
      void Function(int records, int total)? onProgress}) async {
    validatePassphrase(passphrase);
    final source = _ByteReader(input, isCancelled);
    try {
      final start = await source.exact(magic.length);
      if (!_sameBytes(start, magic)) {
        throw const BackupException(
            'Nieobsługiwany format pełnej kopii. Starsze kopie JSON przywróć z menu starszych kopii.');
      }
      final length = _get32(await source.exact(4));
      if (length < 2 || length > 4096) {
        throw const BackupException('Nieprawidłowy nagłówek kopii.');
      }
      final header = await source.exact(length);
      final raw = jsonDecode(utf8.decode(header));
      if (raw is! Map<String, dynamic> ||
          raw.length != 8 ||
          raw['format'] != 'scalajaca.encrypted-stream' ||
          raw['version'] != 2 ||
          raw['kdf'] != 'PBKDF2-HMAC-SHA256' ||
          raw['iterations'] != iterations ||
          raw['cipher'] != 'AES-256-GCM' ||
          raw['blockBytes'] != blockBytes ||
          raw['salt'] is! String ||
          (raw['salt'] as String).length > 32 ||
          raw['noncePrefix'] is! String ||
          (raw['noncePrefix'] as String).length > 24) {
        throw const BackupException(
            'Nieobsługiwane parametry szyfrowanej kopii.');
      }
      final salt = base64Decode(raw['salt'] as String);
      final prefix = base64Decode(raw['noncePrefix'] as String);
      if (salt.length != 16 || prefix.length != 8) {
        throw const BackupException('Nieprawidłowy nagłówek kopii.');
      }
      checkCancelled(isCancelled);
      final key = await _derive(passphrase, salt);
      checkCancelled(isCancelled);
      final frames = _FrameReader(source, header, prefix, key, isCancelled);
      final first = await frames.next();
      if (first.type != 1) throw const BackupException('Brak manifestu kopii.');
      final manifest =
          ArchiveManifest.parse(jsonDecode(utf8.decode(first.plaintext)));
      return ArchiveReader._(frames, manifest, isCancelled, onProgress);
    } catch (e) {
      await source.close();
      if (e is BackupException) rethrow;
      throw const BackupException(
          'Nie można odczytać kopii: złe hasło lub uszkodzone dane.');
    }
  }
}

class ArchiveReader {
  ArchiveReader._(this._frames, this.manifest, this._cancelled, this._progress);
  final _FrameReader _frames;
  final ArchiveManifest manifest;
  final bool Function()? _cancelled;
  final void Function(int, int)? _progress;
  bool _started = false;

  Stream<Map<String, Object?>> records() async* {
    if (_started) throw StateError('Kopia może być odczytana tylko raz.');
    _started = true;
    final rowBytes = BytesBuilder(copy: false);
    final seen = {for (final name in manifest.counts.keys) name: 0};
    var rows = 0, dataFrames = 0, dataBytes = 0;
    try {
      while (true) {
        EncryptedArchive.checkCancelled(_cancelled);
        final frame = await _frames.next();
        if (frame.type == 3) {
          final footer = jsonDecode(utf8.decode(frame.plaintext));
          if (rowBytes.isNotEmpty ||
              footer is! Map<String, dynamic> ||
              footer.length != 5 ||
              footer['format'] != 'scalajaca.archive-end' ||
              footer['records'] != rows ||
              footer['dataFrames'] != dataFrames ||
              footer['dataBytes'] != dataBytes ||
              !_sameCounts(seen, manifest.counts) ||
              footer['counts'] is! Map ||
              !_sameCounts(seen, footer['counts'] as Map) ||
              !await _frames.source.atEnd()) {
            throw const BackupException(
                'Kopia jest niepełna albo zawiera dane po zakończeniu.');
          }
          _progress?.call(rows, manifest.records);
          return;
        }
        if (frame.type != 2 || frame.plaintext.isEmpty) {
          throw const BackupException('Nieprawidłowa kolejność bloków kopii.');
        }
        dataFrames++;
        dataBytes += frame.plaintext.length;
        var start = 0;
        for (var i = 0; i < frame.plaintext.length; i++) {
          if (frame.plaintext[i] != 10) continue;
          if (rowBytes.length + i - start > EncryptedArchive.maxRecordBytes) {
            throw const BackupException(
                'Pojedynczy rekord kopii przekracza 32 MiB.');
          }
          rowBytes.add(Uint8List.sublistView(frame.plaintext, start, i));
          final raw = jsonDecode(utf8.decode(rowBytes.takeBytes()));
          if (raw is! Map<String, dynamic> ||
              raw.length != 2 ||
              raw['table'] is! String ||
              raw['row'] is! Map<String, dynamic> ||
              !seen.containsKey(raw['table'])) {
            throw const BackupException('Nieprawidłowy rekord danych kopii.');
          }
          final table = raw['table'] as String;
          seen[table] = seen[table]! + 1;
          if (seen[table]! > manifest.counts[table]! ||
              ++rows > EncryptedArchive.maxRecords) {
            throw const BackupException('Nieprawidłowa liczba rekordów kopii.');
          }
          EncryptedArchive.checkCancelled(_cancelled);
          yield {'table': table, 'row': raw['row']};
          if (rows == 1 || rows % 50 == 0) {
            _progress?.call(rows, manifest.records);
          }
          start = i + 1;
        }
        if (rowBytes.length + frame.plaintext.length - start >
            EncryptedArchive.maxRecordBytes) {
          throw const BackupException(
              'Pojedynczy rekord kopii przekracza 32 MiB.');
        }
        rowBytes.add(Uint8List.sublistView(frame.plaintext, start));
      }
    } catch (e) {
      if (e is BackupException) rethrow;
      throw const BackupException(
          'Nie można odczytać kopii: złe hasło lub uszkodzone dane.');
    } finally {
      await close();
    }
  }

  Future<void> close() => _frames.source.close();
}

Uint8List _u32(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.big)).buffer.asUint8List();
int _get32(Uint8List value) =>
    ByteData.sublistView(value).getUint32(0, Endian.big);
bool _sameBytes(List<int> a, List<int> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);
bool _sameCounts(Map a, Map b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
Uint8List _nonce(List<int> prefix, int seq) =>
    Uint8List.fromList([...prefix, ..._u32(seq)]);
Uint8List _frameHeader(int type, int seq, int length) =>
    Uint8List.fromList([type, ..._u32(seq), ..._u32(length)]);
Uint8List _aad(List<int> header, List<int> frame, List<int> tag) =>
    Uint8List.fromList([
      ...EncryptedArchive.magic,
      ..._u32(header.length),
      ...header,
      ...frame,
      ...tag
    ]);

class _FrameWriter {
  _FrameWriter(this.header, this.prefix, this.key, this.output, this.cancelled);
  final Uint8List header, prefix;
  final SecretKey key;
  final Future<void> Function(Uint8List) output;
  final bool Function()? cancelled;
  final cipher = AesGcm.with256bits();
  var seq = 0;
  List<int> tag = List.filled(16, 0);
  Future<void> add(int type, List<int> plaintext) async {
    EncryptedArchive.checkCancelled(cancelled);
    if (seq > 0xffffffff || plaintext.length > EncryptedArchive.blockBytes) {
      throw const BackupException('Przekroczono limit bloków kopii.');
    }
    final metadata = _frameHeader(type, seq, plaintext.length);
    final box = await cipher.encrypt(plaintext,
        secretKey: key,
        nonce: _nonce(prefix, seq),
        aad: _aad(header, metadata, tag));
    // Native bridge accepts a maximum of one 256 KiB part per write.
    await output(metadata);
    await output(Uint8List.fromList(box.cipherText));
    await output(Uint8List.fromList(box.mac.bytes));
    tag = box.mac.bytes;
    seq++;
  }
}

class _PlainFrame {
  const _PlainFrame(this.type, this.plaintext);
  final int type;
  final Uint8List plaintext;
}

class _FrameReader {
  _FrameReader(this.source, this.header, this.prefix, this.key, this.cancelled);
  final _ByteReader source;
  final Uint8List header;
  final List<int> prefix;
  final SecretKey key;
  final bool Function()? cancelled;
  final cipher = AesGcm.with256bits();
  var seq = 0;
  List<int> tag = List.filled(16, 0);
  Future<_PlainFrame> next() async {
    EncryptedArchive.checkCancelled(cancelled);
    final metadata = await source.exact(9);
    final type = metadata[0],
        number = _get32(Uint8List.sublistView(metadata, 1, 5));
    final size = _get32(Uint8List.sublistView(metadata, 5, 9));
    if (number != seq ||
        type < 1 ||
        type > 3 ||
        size > EncryptedArchive.blockBytes) {
      throw const BackupException(
          'Nieprawidłowy numer lub rozmiar bloku kopii.');
    }
    final ciphertext = await source.exact(size), mac = await source.exact(16);
    final plaintext = await cipher.decrypt(
        SecretBox(ciphertext, nonce: _nonce(prefix, seq), mac: Mac(mac)),
        secretKey: key,
        aad: _aad(header, metadata, tag));
    tag = mac;
    seq++;
    return _PlainFrame(type, Uint8List.fromList(plaintext));
  }
}

class _ByteReader {
  _ByteReader(Stream<Uint8List> stream, this.cancelled)
      : iterator = StreamIterator(stream);
  final StreamIterator<Uint8List> iterator;
  final bool Function()? cancelled;
  Uint8List chunk = Uint8List(0);
  int offset = 0, bytes = 0;
  bool _closed = false, _ended = false;
  Future<bool> _advance() async {
    if (_ended) return false;
    var empty = 0;
    do {
      EncryptedArchive.checkCancelled(cancelled);
      if (!await iterator.moveNext()) {
        _ended = true;
        return false;
      }
      chunk = iterator.current;
      offset = 0;
      bytes += chunk.length;
      if (bytes > EncryptedArchive.maxArchiveBytes ||
          chunk.length > EncryptedArchive.blockBytes ||
          ++empty > 1024) {
        throw const BackupException(
            'Strumień kopii przekracza dozwolone limity.');
      }
    } while (chunk.isEmpty);
    return true;
  }

  Future<Uint8List> exact(int length) async {
    final result = BytesBuilder(copy: false);
    while (result.length < length) {
      EncryptedArchive.checkCancelled(cancelled);
      if (offset == chunk.length && !await _advance()) {
        throw const BackupException(
            'Kopia jest urwana. Nie przywrócono danych.');
      }
      final n = min(length - result.length, chunk.length - offset);
      result.add(Uint8List.sublistView(chunk, offset, offset + n));
      offset += n;
    }
    return result.takeBytes();
  }

  Future<bool> atEnd() async => offset == chunk.length && !await _advance();
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await iterator.cancel();
  }
}
