import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/backup/encrypted_archive.dart';
import 'package:scalajaca/security/encrypted_backup.dart';

const _passphrase = 'Wyłącznie testowa fraza archiwum 2026!';

void main() {
  late Uint8List archive;
  late _Layout layout;
  late SecretKey fixtureKey;
  late List<Map<String, Object?>> rows;
  final counts = <String, int>{'notes': 1, 'rpg_versions': 1};
  final writes = <int>[];
  final writeProgress = <(int, int)>[];

  setUpAll(() async {
    rows = [
      {
        'table': 'notes',
        'row': {'id': 'note-fixture', 'content': 'żółć 😀 ' * 22000},
      },
      {
        'table': 'rpg_versions',
        'row': {
          'campaign_id': 'fictional-campaign',
          'record_id': 'fictional-secret',
          'revision': 1,
          'payload': 'GM_ONLY_ARCHIVE_FIXTURE',
        },
      },
    ];
    final output = BytesBuilder(copy: false);
    await EncryptedArchive().write(
      Stream.fromIterable(rows),
      counts,
      _passphrase,
      (part) async {
        writes.add(part.length);
        output.add(part);
      },
      onProgress: (done, total) => writeProgress.add((done, total)),
    );
    archive = output.takeBytes();
    layout = _Layout.parse(archive);
    // Rzeczywisty koszt KDF również w testowym konstruktorze błędnych archiwów.
    // Klucz służy wyłącznie fikcyjnym danym, a każdy nowy kontener ma nowy prefiks.
    final salt = base64Decode(layout.parameters['salt'] as String);
    final keyBytes = await Isolate.run(() async {
      final key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 600000,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(_passphrase)),
        nonce: salt,
      );
      return key.extractBytes();
    });
    fixtureKey = SecretKey(keyBytes);
  });

  Future<List<Map<String, Object?>>> decode(Uint8List bytes,
      {String passphrase = _passphrase}) async {
    final reader = await EncryptedArchive().open(_fragments(bytes), passphrase);
    return reader.records().toList();
  }

  test('Roundtrip przekracza 256 KiB i zachowuje Unicode przy stronach 64 KiB',
      () async {
    expect(EncryptedArchive.iterations, 600000);
    expect(EncryptedArchive.maxArchiveBytes, 2 * 1024 * 1024 * 1024);
    expect(archive.length, greaterThan(EncryptedArchive.blockBytes));
    expect(
        writes, everyElement(lessThanOrEqualTo(EncryptedArchive.blockBytes)));
    expect(layout.frames.where((f) => f[0] == 2).length, greaterThan(1));
    expect(writeProgress.first, (1, 2));
    expect(writeProgress.last, (2, 2));
    final progress = <(int, int)>[];
    final reader = await EncryptedArchive().open(
        _fragments(archive), _passphrase,
        onProgress: (done, total) => progress.add((done, total)));
    expect(reader.manifest.counts, counts);
    expect(reader.manifest.records, 2);
    expect(DateTime.tryParse(reader.manifest.createdAt), isNotNull);
    expect(() => reader.manifest.counts.clear(), throwsUnsupportedError);
    expect(await reader.records().toList(), rows);
    expect(progress.first, (1, 2));
    expect(progress.last, (2, 2));
    await expectLater(reader.records().toList(), throwsStateError);
    expect(utf8.decode(archive, allowMalformed: true),
        isNot(contains('GM_ONLY_ARCHIVE_FIXTURE')));
  });

  test('Złe hasło nie odszyfrowuje nawet manifestu', () async {
    await expectLater(decode(archive, passphrase: 'Inna długa fraza testowa'),
        throwsA(isA<BackupException>()));
  });

  test('Nagłówek jest uwierzytelniony także po semantycznie neutralnej zmianie',
      () async {
    final changedHeader =
        Uint8List.fromList(utf8.encode(' ${utf8.decode(layout.header)}'));
    await expectLater(decode(layout.join(header: changedHeader)),
        throwsA(isA<BackupException>()));
  });

  test('Zmiana ciphertextu lub tagu danych jest wykrywana przed yield danych',
      () async {
    final index = layout.frames.indexWhere((f) => f[0] == 2);
    for (final field in ['ciphertext', 'tag']) {
      final frames = layout.copyFrames();
      final part = frames[index];
      part[field == 'ciphertext' ? 9 : part.length - 1] ^= 1;
      var emitted = 0;
      final reader = await EncryptedArchive()
          .open(_fragments(layout.join(frames: frames)), _passphrase);
      await expectLater(reader.records().forEach((_) => emitted++),
          throwsA(isA<BackupException>()));
      expect(emitted, 0, reason: field);
    }
  });

  test('Metadane ramki i końcowy tag nie mogą zostać zmienione', () async {
    final dataIndex = layout.frames.indexWhere((f) => f[0] == 2);
    final changedType = layout.copyFrames();
    changedType[dataIndex][0] = 1;
    await expectLater(decode(layout.join(frames: changedType)),
        throwsA(isA<BackupException>()));
    final changedFooter = layout.copyFrames();
    changedFooter.last[changedFooter.last.length - 1] ^= 1;
    await expectLater(decode(layout.join(frames: changedFooter)),
        throwsA(isA<BackupException>()));
  });

  test('Zmiana kolejności, duplikacja i usunięcie ramki są odrzucane',
      () async {
    final dataIndices = [
      for (var i = 0; i < layout.frames.length; i++)
        if (layout.frames[i][0] == 2) i,
    ];
    final first = dataIndices.first, second = dataIndices[1];
    final reordered = layout.copyFrames();
    final swap = reordered[first];
    reordered[first] = reordered[second];
    reordered[second] = swap;
    final duplicated = layout.copyFrames()
      ..insert(first + 1, Uint8List.fromList(layout.frames[first]));
    final dropped = layout.copyFrames()..removeAt(first);
    for (final invalid in [reordered, duplicated, dropped]) {
      await expectLater(decode(layout.join(frames: invalid)),
          throwsA(isA<BackupException>()));
    }
  });

  test('Urwany nagłówek, blok, stopka i brak stopki nie oznaczają sukcesu',
      () async {
    final firstData = layout.frames.indexWhere((f) => f[0] == 2);
    final beforeData =
        layout.join(frames: layout.frames.take(firstData).toList());
    final partialData = Uint8List.fromList([
      ...beforeData,
      ...layout.frames[firstData].take(100),
    ]);
    final variants = <Uint8List>[
      Uint8List.sublistView(archive, 0, EncryptedArchive.magic.length + 2),
      partialData,
      Uint8List.sublistView(archive, 0, archive.length - 1),
      layout.join(
          frames: layout.frames.take(layout.frames.length - 1).toList()),
    ];
    for (final bytes in variants) {
      await expectLater(decode(bytes), throwsA(isA<BackupException>()));
    }
  });

  test('Dane za poprawną stopką są odrzucane', () async {
    await expectLater(decode(Uint8List.fromList([...archive, 0])),
        throwsA(isA<BackupException>()));
  });

  test('Nowy nonce prefix i ramka z innego archiwum nie są wymienne', () async {
    final other =
        await _authenticated(layout.parameters, fixtureKey, rows, counts);
    final otherLayout = _Layout.parse(other);
    expect(otherLayout.parameters['noncePrefix'],
        isNot(layout.parameters['noncePrefix']));
    expect(await decode(other), rows);
    final mixed = layout.copyFrames();
    final index = mixed.indexWhere((f) => f[0] == 2);
    mixed[index] = otherLayout.frames[index];
    await expectLater(
        decode(layout.join(frames: mixed)), throwsA(isA<BackupException>()));
    final sequence = [
      for (final frame in layout.frames) _read32(frame, 1),
    ];
    expect(sequence, List.generate(sequence.length, (i) => i));
  });

  test('Autentyczny manifest z nieprawidłowym licznikiem nie przechodzi',
      () async {
    final invalid = await _authenticated(
        layout.parameters, fixtureKey, rows, {'notes': 2, 'rpg_versions': 1});
    await expectLater(decode(invalid), throwsA(isA<BackupException>()));
  });

  test('Autentyczna, ale błędna stopka jest odrzucana', () async {
    for (final override in <Map<String, Object?>>[
      {'records': 3},
      {'dataFrames': 999},
      {'dataBytes': 1},
      {
        'counts': {'notes': 2, 'rpg_versions': 1}
      },
    ]) {
      final invalid = await _authenticated(
          layout.parameters, fixtureKey, rows, counts,
          footerOverride: override);
      await expectLater(decode(invalid), throwsA(isA<BackupException>()));
    }
  });

  test('Autentyczna pusta ramka danych i nieznana tabela są odrzucane',
      () async {
    final emptyData = await _authenticated(
        layout.parameters, fixtureKey, const [], {'notes': 0},
        explicitData: [Uint8List(0)]);
    await expectLater(decode(emptyData), throwsA(isA<BackupException>()));
    final unknownTable = await _authenticated(layout.parameters, fixtureKey, [
      {
        'table': 'settings',
        'row': {'paid_enabled': true}
      },
    ], {
      'notes': 1
    });
    await expectLater(decode(unknownTable), throwsA(isA<BackupException>()));
  });

  test('Limity nagłówka, ramek i pojedynczego chunku poprzedzają alokację',
      () async {
    final tooLongHeader = Uint8List.fromList([
      ...EncryptedArchive.magic,
      ..._u32(4097),
    ]);
    await expectLater(decode(tooLongHeader), throwsA(isA<BackupException>()));
    final badKdf = Map<String, dynamic>.from(layout.parameters)
      ..['iterations'] = 0x7fffffff;
    await expectLater(
        decode(layout.join(
            header: Uint8List.fromList(utf8.encode(jsonEncode(badKdf))))),
        throwsA(isA<BackupException>()));
    final tooLongFrame = layout.copyFrames();
    tooLongFrame.first.setRange(5, 9, _u32(EncryptedArchive.blockBytes + 1));
    await expectLater(decode(layout.join(frames: tooLongFrame)),
        throwsA(isA<BackupException>()));
    await expectLater(
        EncryptedArchive().open(
            Stream.value(Uint8List(EncryptedArchive.blockBytes + 1)),
            _passphrase),
        throwsA(isA<BackupException>()));
    await expectLater(
        EncryptedArchive().open(
            Stream.fromIterable(List.generate(1025, (_) => Uint8List(0))),
            _passphrase),
        throwsA(isA<BackupException>()));
  });

  test('Manifest ma ścisłe typy, wersję i ograniczone liczniki', () {
    final valid =
        ArchiveManifest(counts: {'notes': 0}, createdAt: '2026-10-19T00:00:00Z')
            .toJson();
    for (final change in <Map<String, Object?>>[
      {'version': 99},
      {'owner': 'remote-owner'},
      {'schema': 999},
      {'createdAt': 'nie-data'},
      {'counts': <String, int>{}},
      {
        'counts': {'notes': -1}
      },
      {
        'counts': {'notes': true}
      },
      {
        'counts': {'notes': EncryptedArchive.maxRecords + 1}
      },
      {
        'counts': {'a': EncryptedArchive.maxRecords, 'b': 1}
      },
      {
        'counts': {for (var i = 0; i < 33; i++) 'table$i': 0}
      },
      {'extra': 'nieznane pole'},
    ]) {
      expect(() => ArchiveManifest.parse({...valid, ...change}),
          throwsA(isA<BackupException>()));
    }
  });

  test('Krótka fraza i ponad 4096 bajtów są odrzucane bez zapisu', () async {
    var outputCalls = 0;
    for (final pass in ['krótka', '😀' * 1025]) {
      await expectLater(
          EncryptedArchive().write(const Stream.empty(), {'notes': 0}, pass,
              (_) async => outputCalls++),
          throwsA(isA<BackupException>()));
    }
    expect(outputCalls, 0);
  });

  test('Writer odrzuca niezgodny snapshot i rekord przekraczający 32 MiB',
      () async {
    for (final fixture in <({List<Map<String, Object?>> rows, int count})>[
      (rows: const [], count: 1),
      (
        rows: [
          {
            'table': 'notes',
            'row': {'id': 'a'}
          }
        ],
        count: 0
      ),
      (
        rows: [
          {
            'table': 'notes',
            'row': {'content': 'x' * EncryptedArchive.maxRecordBytes},
          },
        ],
        count: 1,
      ),
    ]) {
      final output = BytesBuilder(copy: false);
      await expectLater(
          EncryptedArchive().write(
              Stream.fromIterable(fixture.rows),
              {'notes': fixture.count},
              _passphrase,
              (part) async => output.add(part)),
          throwsA(isA<BackupException>()));
      final partial = output.takeBytes();
      expect(_Layout.parse(partial).frames.where((f) => f[0] == 3), isEmpty);
    }
  });

  test('Anulowanie przed rozpoczęciem nie tworzy archiwum', () async {
    var outputCalls = 0;
    await expectLater(
        EncryptedArchive().write(const Stream.empty(), {'notes': 0},
            _passphrase, (_) async => outputCalls++,
            isCancelled: () => true),
        throwsA(isA<BackupCancelled>()));
    expect(outputCalls, 0);
    await expectLater(
        EncryptedArchive()
            .open(_fragments(archive), _passphrase, isCancelled: () => true),
        throwsA(isA<BackupCancelled>()));
  });

  test('Anulowany writer nie dopisuje stopki', () async {
    var cancelled = false;
    final output = BytesBuilder(copy: false);
    await expectLater(
        EncryptedArchive().write(Stream.fromIterable(rows), counts, _passphrase,
            (part) async {
          output.add(part);
          if (part.length == 9 && part[0] == 2) cancelled = true;
        }, isCancelled: () => cancelled),
        throwsA(isA<BackupCancelled>()));
    expect(cancelled, isTrue);
    await expectLater(
        decode(output.takeBytes()), throwsA(isA<BackupException>()));
  });

  test('Anulowanie po pierwszym rekordzie nie emituje następnego', () async {
    var cancelled = false, emitted = 0;
    final reader = await EncryptedArchive()
        .open(_fragments(archive), _passphrase, isCancelled: () => cancelled);
    await expectLater(
        reader.records().forEach((_) {
          emitted++;
          cancelled = true;
        }),
        throwsA(isA<BackupCancelled>()));
    expect(emitted, 1);
  });
}

Stream<Uint8List> _fragments(Uint8List bytes) async* {
  for (var start = 0; start < bytes.length; start += 65536) {
    yield Uint8List.sublistView(bytes, start, min(start + 65536, bytes.length));
  }
}

Uint8List _u32(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.big)).buffer.asUint8List();
int _read32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset, Endian.big);

class _Layout {
  _Layout(this.header, this.frames);
  final Uint8List header;
  final List<Uint8List> frames;
  Map<String, dynamic> get parameters =>
      jsonDecode(utf8.decode(header)) as Map<String, dynamic>;
  factory _Layout.parse(Uint8List bytes) {
    final offset = EncryptedArchive.magic.length;
    final length = _read32(bytes, offset);
    final header =
        Uint8List.sublistView(bytes, offset + 4, offset + 4 + length);
    var start = offset + 4 + length;
    final frames = <Uint8List>[];
    while (start < bytes.length) {
      final size = _read32(bytes, start + 5);
      final end = start + 9 + size + 16;
      if (end > bytes.length) break;
      frames.add(Uint8List.sublistView(bytes, start, end));
      start = end;
    }
    return _Layout(header, frames);
  }
  List<Uint8List> copyFrames() =>
      [for (final frame in frames) Uint8List.fromList(frame)];
  Uint8List join({Uint8List? header, List<Uint8List>? frames}) {
    final actualHeader = header ?? this.header;
    final result = BytesBuilder(copy: false)
      ..add(EncryptedArchive.magic)
      ..add(_u32(actualHeader.length))
      ..add(actualHeader);
    for (final frame in frames ?? this.frames) {
      result.add(frame);
    }
    return result.takeBytes();
  }
}

/// Buduje poprawnie uwierzytelniony kontener z celowo błędną semantyką.
/// Nie używa prywatnych klas produkcji; KDF pozostaje rzeczywisty i niezmieniony.
Future<Uint8List> _authenticated(Map<String, dynamic> base, SecretKey key,
    List<Map<String, Object?>> rows, Map<String, int> counts,
    {Map<String, Object?> footerOverride = const {},
    List<Uint8List>? explicitData}) async {
  final random = Random.secure();
  final prefix = List.generate(8, (_) => random.nextInt(256));
  final header = Uint8List.fromList(utf8.encode(jsonEncode({
    ...base,
    'noncePrefix': base64Encode(prefix),
  })));
  final manifest =
      ArchiveManifest(counts: counts, createdAt: '2026-10-19T00:00:00Z')
          .toJson();
  final data = Uint8List.fromList(
      utf8.encode(rows.map((r) => '${jsonEncode(r)}\n').join()));
  final parts = explicitData ??
      [
        for (var i = 0; i < data.length; i += EncryptedArchive.blockBytes)
          Uint8List.sublistView(
              data, i, min(i + EncryptedArchive.blockBytes, data.length)),
      ];
  final footer = {
    'format': 'scalajaca.archive-end',
    'records': rows.length,
    'dataFrames': parts.length,
    'dataBytes': parts.fold<int>(0, (sum, part) => sum + part.length),
    'counts': {
      for (final table in counts.keys)
        table: rows.where((r) => r['table'] == table).length,
    },
    ...footerOverride,
  };
  final blocks = <(int, List<int>)>[
    (1, utf8.encode(jsonEncode(manifest))),
    for (final part in parts) (2, part),
    (3, utf8.encode(jsonEncode(footer))),
  ];
  final output = BytesBuilder(copy: false)
    ..add(EncryptedArchive.magic)
    ..add(_u32(header.length))
    ..add(header);
  var seq = 0;
  List<int> previousTag = List.filled(16, 0);
  for (final block in blocks) {
    final metadata =
        Uint8List.fromList([block.$1, ..._u32(seq), ..._u32(block.$2.length)]);
    final box =
        await AesGcm.with256bits().encrypt(block.$2, secretKey: key, nonce: [
      ...prefix,
      ..._u32(seq)
    ], aad: [
      ...EncryptedArchive.magic,
      ..._u32(header.length),
      ...header,
      ...metadata,
      ...previousTag,
    ]);
    output
      ..add(metadata)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    previousTag = box.mac.bytes;
    seq++;
  }
  return output.takeBytes();
}
