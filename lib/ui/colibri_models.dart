import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../local_inference/colibri_engine.dart';
import '../local_inference/local_engine.dart';
import '../provider_registry/provider_adapter.dart';
import '../storage/app_database.dart';
import 'provider_settings.dart';

class ColibriModelsPage extends StatefulWidget {
  const ColibriModelsPage(
      {super.key, required this.engine, required this.store});
  final LocalInferenceEngine engine;
  final AppDatabase store;
  @override
  State<ColibriModelsPage> createState() => _ColibriModelsPageState();
}

class _ColibriModelsPageState extends State<ColibriModelsPage> {
  final hash = TextEditingController();
  LocalEngineStatus? status;
  String selected = '', error = '';
  bool working = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    hash.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final value = await widget.engine.status();
      final choice = await widget.store.setting('model_colibri_local', '');
      if (mounted) {
        setState(() {
          status = value;
          selected = choice;
          error = '';
        });
      }
    } on ProviderException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Nie można odczytać magazynu Colibri.');
      }
    }
  }

  Future<void> _import() async {
    final expected = hash.text.trim().toLowerCase();
    if (expected.isNotEmpty && !RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
      notice(context, colibriError('invalid_hash').message);
      return;
    }
    setState(() => working = true);
    try {
      final model = await widget.engine.importModel(expectedSha256: expected);
      if (model != null) {
        await widget.store.setSetting('model_colibri_local', model.id);
        await _load();
        if (mounted) {
          notice(context,
              'Paczka Colibri zainstalowana. Wybierz Colibri offline w czacie.');
        }
      }
    } on ProviderException catch (e) {
      if (mounted) notice(context, e.message);
    } catch (_) {
      if (mounted) {
        notice(context, 'Nie udało się zainstalować paczki Colibri.');
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Colibri offline — port Androida')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Eksperymentalny silnik lokalny',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
            'Colibri jest silnikiem, a nie modelem. Ten port uruchamia OLMoE Instruct bezpośrednio w telefonie przez CPU, bez serwera i klucza API. Wagi nie są częścią APK. Nie przełącza zapytań do internetu.'),
        const SizedBox(height: 8),
        const Text(
            'Obsługiwany profil: allenai/OLMoE-1B-7B-0125-Instruct po konwersji do scalonego int8 Colibri. To około 7–8 GB plików; ich przygotowanie wymaga pobrania około 14 GB źródeł. ZIP oraz prywatna kopia wag zajmują miejsce równocześnie. Pozostaw dodatkowo 512 MiB rezerwy.'),
        const SizedBox(height: 8),
        const Text(
            'Pixel 9: zgodny ARM64. Uruchomienie wymaga co najmniej 4 GiB wolnego RAM; dostępna pamięć zależy od Androida i innych aplikacji. Próg nie gwarantuje wydajności. Pełne wagi i jakość polskiej narracji tego portu nie zostały jeszcze zweryfikowane na fizycznym Pixelu 9.'),
        const SizedBox(height: 8),
        const Text(
            'Instalacja: przygotuj ZIP narzędziem tools/colibri/package_model.py z repozytorium Scalającej, skopiuj go na telefon, następnie wybierz poniżej. Instalator sprawdzi manifest, kompletność i SHA-256 każdego pliku. Korzystaj z zaufanych wag. Sumy potwierdzają integralność, nie tożsamość wydawcy.'),
        if (error.isNotEmpty)
          Text(error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
        TextField(
            controller: hash,
            enabled: !working,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
                labelText: 'SHA-256 manifestu (zalecane)',
                helperText:
                    'Suma podana przez narzędzie pakujące; opcjonalna')),
        FilledButton.icon(
            onPressed: working ? null : _import,
            icon: const Icon(Icons.install_mobile_outlined),
            label: const Text('Zainstaluj paczkę Colibri ZIP')),
        if (working) ...[
          const LinearProgressIndicator(),
          const Text(
              'Trwa wybór lub sprawdzanie paczki. Duże pliki wymagają czasu. Pozostań na ekranie.'),
          TextButton(
              onPressed: widget.engine.cancelImport,
              child: const Text('Anuluj instalację')),
        ],
        const SizedBox(height: 12),
        const Text(
            'Kontekst: 4096 tokenów, maks. 512 nowych tokenów, 3 minuty obliczeń. Stop, przejście w tło lub przegrzanie kończy proces i zwalnia jego pamięć. Starsze dane pozostają w lokalnej bazie; do modelu trafiają wybrane, uprawnione fragmenty.'),
        for (final model in status?.models ?? <LocalModel>[])
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(model.name,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                            '${(model.bytes / 1073741824).toStringAsFixed(2)} GiB • ${model.profile}'),
                        SelectableText('Manifest SHA-256: ${model.id}'),
                        Wrap(spacing: 8, children: [
                          FilledButton(
                              onPressed: working
                                  ? null
                                  : () async {
                                      await widget.store.setSetting(
                                          'model_colibri_local', model.id);
                                      await _load();
                                    },
                              child: Text(selected == model.id
                                  ? 'Wybrany do czatu'
                                  : 'Wybierz model')),
                          TextButton(
                              onPressed: () => Clipboard.setData(
                                  ClipboardData(text: model.id)),
                              child: const Text('Kopiuj sumę')),
                          TextButton(
                              onPressed: working
                                  ? null
                                  : () async {
                                      if (!await confirm(
                                          context,
                                          'Usuń wagi Colibri?',
                                          'Usunie prywatną kopię ${model.name}. Historia pozostanie.',
                                          action: 'Usuń wagi')) {
                                        return;
                                      }
                                      if (!mounted) return;
                                      setState(() => working = true);
                                      try {
                                        await widget.engine
                                            .removeModel(model.id);
                                        if (selected == model.id) {
                                          await widget.store.setSetting(
                                              'model_colibri_local', '');
                                        }
                                        await _load();
                                      } on ProviderException catch (e) {
                                        if (context.mounted) {
                                          notice(context, e.message);
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => working = false);
                                        }
                                      }
                                    },
                              child: const Text('Usuń')),
                        ]),
                      ]))),
      ]));
}
