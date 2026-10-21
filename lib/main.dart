import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'auth/secret_store.dart';
import 'provider_registry/provider_registry.dart';
import 'storage/app_database.dart';
import 'ui/home.dart';
import 'local_inference/android_local_engine.dart';
import 'local_inference/colibri_engine.dart';
import 'local_inference/native_licenses.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerNativeLicenses();
  try {
    final secrets = KeystoreSecrets();
    final store = await AppDatabase.open(ContentCipher(secrets));
    runApp(ScalajacaApp(store: store, secrets: secrets));
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 48),
                    const Text(
                      'Nie można otworzyć bezpiecznej pamięci. Dane nie zostały usunięte. Uruchom ponownie aplikację lub przywróć kopię na sprawnym urządzeniu.',
                    ),
                    TextButton(
                      onPressed: main,
                      child: const Text('Spróbuj ponownie'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScalajacaApp extends StatefulWidget {
  const ScalajacaApp({super.key, required this.store, required this.secrets});
  final AppDatabase store;
  final SecretStore secrets;
  @override
  State<ScalajacaApp> createState() => _ScalajacaAppState();
}

class _ScalajacaAppState extends State<ScalajacaApp> {
  late final localEngine = AndroidLocalEngine();
  late final colibriEngine = AndroidColibriEngine();
  late final registry = ProviderRegistry.standard(
    colibriAdapter: ColibriAdapter(engine: colibriEngine),
    miniCpmEndpoint: () => widget.store.setting('endpoint_minicpm', ''),
    localAdapter: LocalModelAdapter(
        engine: localEngine,
        readContext: () => widget.store.setting('local_context', 4096)),
  );
  @override
  void dispose() {
    registry.cancelAll();
    localEngine.dispose();
    colibriEngine.dispose();
    super.dispose();
  }

  ThemeMode mode = ThemeMode.system;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final setting = await widget.store.setting('theme', 'system');
    if (mounted) {
      setState(
        () => mode = ThemeMode.values.firstWhere(
          (m) => m.name == setting,
          orElse: () => ThemeMode.system,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Scalająca',
        debugShowCheckedModeBanner: false,
        locale: const Locale('pl'),
        supportedLocales: const [Locale('pl')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        themeMode: mode,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xff526b57),
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xfff8f9f5),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xff9bd4a7),
          brightness: Brightness.dark,
        ),
        home: Home(
          store: widget.store,
          secrets: widget.secrets,
          registry: registry,
          themeMode: mode,
          onTheme: (value) async {
            await widget.store.setSetting('theme', value.name);
            setState(() => mode = value);
          },
        ),
      );
}
