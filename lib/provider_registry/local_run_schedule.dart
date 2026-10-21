import 'provider_adapter.dart';

/// Dostawcy zdalni mogą pracować równolegle. Lokalne silniki współdzielą RAM
/// telefonu, więc drugi zaczyna dopiero po zakończeniu i zwolnieniu pierwszego.
Future<void> runProviderRequests(
    Iterable<String> providers, Future<void> Function(String) run) async {
  final ids = List<String>.of(providers);
  await Future.wait([
    for (final id in ids.where((id) => !isLocalProvider(id))) run(id),
    () async {
      for (final id in ids.where(isLocalProvider)) {
        await run(id);
      }
    }(),
  ]);
}
