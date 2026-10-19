import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/backup/backup_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/backup-files');
  final bridge = BackupFilesBridge(channel: channel);
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'create' || 'open' => 'opaque-handle',
        'read' => Uint8List.fromList([1, 2, 3]),
        'save' => true,
        _ => null,
      };
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('Most przekazuje tylko handle i szyfrotekst w ograniczonych blokach',
      () async {
    final id = await bridge.create();
    await bridge.write(id, Uint8List(262144));
    expect(await bridge.save(id, 'test.scalabackup'), isTrue);
    expect(await bridge.open(), id);
    expect(await bridge.read(id), [1, 2, 3]);
    await bridge.close(id);
    expect(calls.map((c) => c.method),
        ['create', 'write', 'save', 'open', 'read', 'close']);
    expect(calls[1].arguments.keys, unorderedEquals(['id', 'bytes']));
  });
  test('Przekroczony blok zapisu nie trafia do kanału natywnego', () async {
    await expectLater(bridge.write('id', Uint8List(262145)),
        throwsA(isA<BackupFilesException>()));
    expect(calls, isEmpty);
  });
  test('Nieprawidłowe rozmiary odczytu nie trafiają do kanału', () async {
    for (final size in [0, -1, 65537]) {
      await expectLater(bridge.read('id', maxBytes: size),
          throwsA(isA<BackupFilesException>()));
    }
    expect(calls, isEmpty);
  });
  test('Błąd platformy nie ujawnia ścieżki ani komunikatu providera', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(
                code: 'io', message: 'PRIVATE_PATH_AND_CONTENT'));
    try {
      await bridge.open();
      fail('Oczekiwano błędu');
    } on BackupFilesException catch (e) {
      expect(e.message, isNot(contains('PRIVATE_PATH')));
    }
  });
  test('Zbyt duża odpowiedź natywnego odczytu jest odrzucana', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => Uint8List(65537));
    await expectLater(bridge.read('id'), throwsA(isA<BackupFilesException>()));
  });
}
