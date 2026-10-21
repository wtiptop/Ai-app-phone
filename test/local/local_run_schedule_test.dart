import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/provider_registry/local_run_schedule.dart';

void main() {
  test('Silniki lokalne nie rezerwują jednocześnie tego samego wolnego RAM',
      () async {
    final release = Completer<void>();
    final calls = <String>[];
    final run = runProviderRequests(
        ['minicpm_local', 'openai', 'colibri_local'], (id) async {
      calls.add('start:$id');
      if (id == 'minicpm_local') await release.future;
      calls.add('end:$id');
    });
    await Future<void>.delayed(Duration.zero);
    expect(calls, contains('start:openai'));
    expect(calls, contains('start:minicpm_local'));
    expect(calls, isNot(contains('start:colibri_local')));
    release.complete();
    await run;
    expect(calls.indexOf('start:colibri_local'),
        greaterThan(calls.indexOf('end:minicpm_local')));
  });
}
