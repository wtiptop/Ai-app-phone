import 'package:flutter/material.dart';

import '../auth/secret_store.dart';
import '../provider_registry/provider_registry.dart';
import '../storage/app_database.dart';

Future<bool> confirm(
  BuildContext context,
  String title,
  String content, {
  String action = 'Potwierdzam',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

void notice(BuildContext context, String text) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class ProviderSettings extends StatelessWidget {
  const ProviderSettings({
    super.key,
    required this.store,
    required this.secrets,
    required this.registry,
  });
  final AppDatabase store;
  final SecretStore secrets;
  final ProviderRegistry registry;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Dostawcy AI')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Twoje dane • Twój wybór',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'API i abonament aplikacji konsumenckiej to odrębne sposoby dostępu. Zapis klucza nie uruchamia zapytań. Klucz BYOK w telefonie może zostać przejęty na zrootowanym urządzeniu. Ustaw limity także u dostawcy.',
            ),
            for (final p in registry.adapters.where((p) => p.id != 'demo'))
              ProviderCard(provider: p, store: store, secrets: secrets),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Logowanie / plan ChatGPT: rozszerzenie zaplanowane. Oficjalna ścieżka OSS wymaga osobnej autoryzacji użycia planu; tożsamość nie wystarcza. Claude, Google i xAI: patrz macierz integracji. Żadne prywatne konto nie jest podłączone.',
                ),
              ),
            ),
          ],
        ),
      );
}

class ProviderCard extends StatefulWidget {
  const ProviderCard({
    super.key,
    required this.provider,
    required this.store,
    required this.secrets,
  });
  final ProviderAdapter provider;
  final AppDatabase store;
  final SecretStore secrets;
  @override
  State<ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<ProviderCard> {
  final keyInput = TextEditingController(), model = TextEditingController();
  final inputRate = TextEditingController(),
      outputRate = TextEditingController();
  bool configured = false, working = false;
  String status = 'Wymaga konfiguracji';
  List<ProviderModel> models = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.provider.id;
    model.text = await widget.store.setting('model_$id', '');
    final i = await widget.store.setting<double>('input_rate_$id', -1);
    final o = await widget.store.setting<double>('output_rate_$id', -1);
    inputRate.text = i < 0 ? '' : i.toString();
    outputRate.text = o < 0 ? '' : o.toString();
    configured = (await widget.secrets.read('api_$id'))?.isNotEmpty ?? false;
    if (mounted) {
      setState(
        () => status = configured
            ? 'Klucz zapisany • połączenie niesprawdzone'
            : 'Wymaga konfiguracji',
      );
    }
  }

  @override
  void dispose() {
    keyInput.dispose();
    model.dispose();
    inputRate.dispose();
    outputRate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final i = double.tryParse(inputRate.text.replaceAll(',', '.'));
    final o = double.tryParse(outputRate.text.replaceAll(',', '.'));
    if (model.text.trim().isEmpty ||
        i == null ||
        o == null ||
        !i.isFinite ||
        !o.isFinite ||
        i < 0 ||
        o < 0) {
      notice(
        context,
        'Podaj ID modelu oraz nieujemne stawki USD / 1 mln tokenów.',
      );
      return;
    }
    setState(() => working = true);
    try {
      final id = widget.provider.id;
      if (keyInput.text.trim().isNotEmpty) {
        await widget.secrets.write('api_$id', keyInput.text.trim());
      }
      await widget.store.setSetting('model_$id', model.text.trim());
      await widget.store.setSetting('input_rate_$id', i);
      await widget.store.setSetting('output_rate_$id', o);
      await widget.store.setSetting(
        'rates_date_$id',
        DateTime.now().toIso8601String(),
      );
      keyInput.clear();
      await _load();
      if (mounted) {
        notice(
          context,
          'Konfiguracja zapisana lokalnie. Nie wykonano zapytania AI.',
        );
      }
    } catch (_) {
      if (mounted) {
        notice(context, 'Nie udało się zapisać bezpiecznej konfiguracji.');
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _test() async {
    if (!await confirm(
      context,
      'Test połączenia',
      'Pobierz katalog z oficjalnego API ${widget.provider.label}. Zostanie wysłany zapisany klucz; bez promptu i bez generowania odpowiedzi. Katalog potwierdza uwierzytelnienie, nie uprawnienia wybranego modelu.',
      action: 'Pobierz katalog',
    )) {
      return;
    }
    setState(() => working = true);
    try {
      final key = await widget.secrets.read('api_${widget.provider.id}') ?? '';
      final found = await widget.provider.discoverModels(key);
      if (mounted) {
        setState(() {
          models = found;
          status =
              'Katalog pobrany: ${found.length} modeli • tekst/streaming do sprawdzenia';
        });
      }
    } on ProviderException catch (e) {
      if (mounted) setState(() => status = e.message);
    } catch (_) {
      if (mounted) setState(() => status = 'Nie udało się pobrać katalogu.');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 12),
        child: ExpansionTile(
          title: Text(widget.provider.label),
          subtitle: Text(status),
          leading: const Icon(Icons.hub_outlined),
          childrenPadding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.provider.id == 'gemini'
                  ? 'Google API • przetwarzanie w chmurze. Ograniczenia wieku/przeznaczenia i Paid Services w EOG: sprawdź aktualne warunki Gemini API przed użyciem.'
                  : 'Oficjalne API • BYOK • przetwarzanie w chmurze dostawcy. Brak gwarancji regionu danych.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyInput,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Klucz API',
                hintText: configured
                    ? 'Pozostaw puste, aby zachować'
                    : 'Wprowadź swój klucz',
              ),
            ),
            TextField(
              controller: model,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'ID modelu (konfigurowalne)',
              ),
            ),
            if (models.isNotEmpty)
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Wybierz z katalogu'),
                items: models
                    .map(
                      (m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(m.label, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      model.text = v;
                      inputRate.clear();
                      outputRate.clear();
                    });
                  }
                },
              ),
            TextField(
              controller: inputRate,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Wejście: USD / 1 mln tokenów',
              ),
            ),
            TextField(
              controller: outputRate,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Wyjście: USD / 1 mln tokenów',
              ),
            ),
            const Text(
              'Cennik sprawdza właściciel. Zmiana modelu wymaga aktualizacji stawek. Szacunek nie jest rachunkiem dostawcy.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: working ? null : _save,
                  child: const Text('Zapisz'),
                ),
                OutlinedButton(
                  onPressed: working ? null : _test,
                  child: const Text('Test / katalog'),
                ),
                TextButton(
                  onPressed: working
                      ? null
                      : () async {
                          await widget.secrets
                              .delete('api_${widget.provider.id}');
                          await _load();
                        },
                  child: const Text('Usuń klucz'),
                ),
              ],
            ),
            if (working) const LinearProgressIndicator(),
          ],
        ),
      );
}
