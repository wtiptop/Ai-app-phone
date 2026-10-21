import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/memory/vault_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/scalajaca/vault');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late VaultBridge bridge;

  setUp(() {
    calls.clear();
    bridge = VaultBridge(channel: channel);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'pick' => {
            'id': 'opaque-handle',
            'writable': call.arguments['writable'],
            'available': true
          },
        'status' => [
            {'id': 'opaque-handle', 'writable': false, 'available': false}
          ],
        'list' => {
            'items': [
              {
                'id': 'signed-token',
                'path': 'Lore/Król.md',
                'bytes': 80,
                'modified': 123
              }
            ],
            'nextCursor': 'signed-cursor'
          },
        'read' => '# Król\nWierny zapis lore.',
        'export' => 'Scalajaca-Exports/result-uuid.md',
        _ => null,
      };
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('domyślny wybór jest tylko do odczytu', () async {
    final handle = await bridge.pick();
    expect(handle!.writable, isFalse);
    expect(calls.single.arguments, {'writable': false});
  });

  test('zapis wymaga osobnego jawnego wywołania pick writable', () async {
    final handle = await bridge.pick(writable: true);
    expect(handle!.writable, isTrue);
    expect(calls.single.arguments, {'writable': true});
  });

  test('strona przekazuje kursor i nie interpretuje dokumentu jako URI',
      () async {
    final page =
        await bridge.list('opaque-handle', cursor: 'previous', limit: 25);
    expect(page.items.single.path, 'Lore/Król.md');
    expect(page.items.single.id, 'signed-token');
    expect(page.nextCursor, 'signed-cursor');
    expect(calls.single.arguments,
        {'handleId': 'opaque-handle', 'cursor': 'previous', 'limit': 25});
    expect(await bridge.read('opaque-handle', page.items.single.id),
        contains('Wierny zapis lore'));
  });

  test('odrzuca nieograniczony rozmiar strony przed kanałem', () async {
    await expectLater(bridge.list('opaque-handle', limit: 201),
        throwsA(isA<VaultException>()));
    await expectLater(
        bridge.list('opaque-handle', limit: 0), throwsA(isA<VaultException>()));
    expect(calls, isEmpty);
  });

  test('status zachowuje cofnięte uprawnienie', () async {
    expect((await bridge.status()).single.available, isFalse);
  });

  test('błędy systemu nie ujawniają ścieżek i treści', () async {
    for (final code in ['vault_error', 'vault_limit']) {
      messenger.setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(
              code: code, message: 'private/vault/secret.md: PRIVATE CONTENT'));
      try {
        await bridge.read('opaque-handle', 'token');
        fail('Oczekiwano błędu');
      } on VaultException catch (error) {
        expect(error.code, code);
        expect(error.message, isNot(contains('private')));
        expect(error.message, isNot(contains('PRIVATE CONTENT')));
        if (code == 'vault_limit') expect(error.message, contains('limit 8'));
      }
    }
  });

  test('kursor unieważniony wymaga skanu od początku', () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'invalid_cursor'));
    await expectLater(
        bridge.list('opaque-handle', cursor: 'old'),
        throwsA(isA<VaultException>()
            .having((e) => e.code, 'code', 'invalid_cursor')));
  });
}
