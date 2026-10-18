import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../local_inference/local_engine.dart';
import '../storage/app_database.dart';
import '../provider_registry/provider_adapter.dart';
import 'provider_settings.dart';

class LocalModelsPage extends StatefulWidget {
  const LocalModelsPage({super.key, required this.engine, required this.store});
  final LocalInferenceEngine engine;
  final AppDatabase store;
  @override
  State<LocalModelsPage> createState() => _LocalModelsPageState();
}

class _LocalModelsPageState extends State<LocalModelsPage> {
  final hash = TextEditingController();
  LocalEngineStatus? status;
  String selected = '', error = '';
  int contextTokens = 2048;
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
      final current = await widget.engine.status();
      final chosen = await widget.store.setting('model_minicpm_local', '');
      final context = await widget.store.setting('local_context', 2048);
      if (mounted) {
        setState(() {
          status = current;
          selected = chosen;
          contextTokens = context;
          error = '';
        });
      }
    } on ProviderException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Nie można odczytać magazynu modeli.');
      }
    }
  }

  Future<void> _import() async {
    final expected = hash.text.trim();
    if (expected.isNotEmpty &&
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expected)) {
      notice(context, localError('invalid_hash').message);
      return;
    }
    setState(() => working = true);
    try {
      final model = await widget.engine.importModel(expectedSha256: expected);
      if (model != null) {
        await widget.store.setSetting('model_minicpm_local', model.id);
        await _load();
        if (mounted) {
          notice(context,
              'Model zapisany w telefonie. Możesz wybrać MiniCPM offline w czacie.');
        }
      }
    } on ProviderException catch (e) {
      if (mounted) notice(context, e.message);
    } catch (_) {
      if (mounted) notice(context, 'Import nie został ukończony.');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('MiniCPM offline — modele GGUF')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Model pracuje bezpośrednio w telefonie',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Silnik llama.cpp jest częścią APK. Nie wymaga serwera ani klucza API i nie przełącza się do chmury. Wagi importujesz dobrowolnie jako plik GGUF; nie są dołączone do APK. Obsługiwane: tekstowe MiniCPM5-1B / 2B, zwłaszcza Q4_K_M. Status: eksperymentalna.'),
          const SizedBox(height: 8),
          const Text(
              'MiniCPM5-1B Q4_K_M zajmuje około 657 MiB. Potrzebny jest dodatkowy RAM i 256 MiB wolnego miejsca po imporcie. Import kopiuje plik do prywatnej pamięci aplikacji. Używaj zaufanego źródła i sprawdź SHA-256. Silnik odrzuca uszkodzoną strukturę GGUF i nie wykonuje szablonu z pliku.'),
          if (error.isNotEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (status != null)
            Text(
                'Wbudowany silnik: ${status!.commit.substring(0, status!.commit.length < 12 ? status!.commit.length : 12)}'),
          const SizedBox(height: 12),
          TextField(
              controller: hash,
              enabled: !working,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                  labelText: 'Oczekiwane SHA-256 (zalecane)',
                  hintText: '64 znaki ze strony wydawcy; opcjonalne')),
          const SizedBox(height: 8),
          FilledButton.icon(
              onPressed: working ? null : _import,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Importuj plik GGUF')),
          if (working) ...[
            const LinearProgressIndicator(),
            const Text(
                'Trwa wybór lub import. Kopiowanie i sprawdzanie dużego pliku może potrwać. Pozostań na tym ekranie.'),
            TextButton(
                onPressed: () async {
                  await widget.engine.cancelImport();
                },
                child: const Text('Anuluj import')),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
              initialValue: [1024, 2048, 4096].contains(contextTokens)
                  ? contextTokens
                  : 2048,
              decoration:
                  const InputDecoration(labelText: 'Kontekst lokalny (tokeny)'),
              items: [
                for (final value in [1024, 2048, 4096])
                  DropdownMenuItem(value: value, child: Text('$value'))
              ],
              onChanged: working
                  ? null
                  : (value) async {
                      if (value == null) return;
                      await widget.store.setSetting('local_context', value);
                      if (mounted) setState(() => contextTokens = value);
                    }),
          const Text(
              'Domyślnie 2048 tokenów kontekstu, maks. 512 nowych tokenów, do 4 wątków CPU i 3 min pracy. Dłuższa historia jest odrzucana, bez cichego usuwania wiadomości. Przejście aplikacji w tło lub przegrzanie zatrzymuje obliczenia.'),
          const SizedBox(height: 16),
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
                              '${(model.bytes / 1048576).toStringAsFixed(1)} MiB • ${model.profile}'),
                          SelectableText('SHA-256: ${model.id}'),
                          Wrap(spacing: 8, children: [
                            FilledButton(
                                onPressed: working
                                    ? null
                                    : () async {
                                        await widget.store.setSetting(
                                            'model_minicpm_local', model.id);
                                        await _load();
                                      },
                                child: Text(selected == model.id
                                    ? 'Wybrany do czatu'
                                    : 'Wybierz model')),
                            TextButton(
                                onPressed: () => Clipboard.setData(
                                    ClipboardData(text: model.id)),
                                child: const Text('Kopiuj SHA-256')),
                            TextButton(
                                onPressed: working
                                    ? null
                                    : () async {
                                        if (!await confirm(
                                            context,
                                            'Usuń model z telefonu?',
                                            'Zostaną usunięte wagi ${model.name}. Historia czatów pozostanie. Oryginalny plik wybrany przy imporcie pozostanie w swoim katalogu.',
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
                                                'model_minicpm_local', '');
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
          if (status?.models.isEmpty ?? true)
            const Text(
                'Brak zaimportowanego modelu. Pozostałe funkcje Scalającej są dostępne.'),
        ]),
      );
}
