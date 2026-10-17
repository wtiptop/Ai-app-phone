import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/secret_store.dart';
import '../costs/local_cost_gate.dart';
import '../provider_registry/provider_registry.dart';
import '../storage/app_database.dart';
import 'provider_settings.dart';

class Comparison extends StatefulWidget {
  const Comparison({
    super.key,
    required this.store,
    required this.secrets,
    required this.registry,
  });
  final AppDatabase store;
  final SecretStore secrets;
  final ProviderRegistry registry;
  @override
  State<Comparison> createState() => _ComparisonState();
}

class _ComparisonState extends State<Comparison> {
  final prompt = TextEditingController();
  final selected = <String>{'demo', 'openai'};
  final results = <String, String>{}, statuses = <String, String>{};
  final estimates = <String, double>{};
  final modelNames = <String, String>{};
  bool busy = false, cancelled = false, disposed = false;
  @override
  void dispose() {
    disposed = true;
    for (final id in selected) {
      widget.registry.adapter(id).cancel();
    }
    prompt.dispose();
    super.dispose();
  }

  void update(VoidCallback callback) {
    if (mounted && !disposed) setState(callback);
  }

  Future<void> _start() async {
    if (busy ||
        prompt.text.trim().isEmpty ||
        selected.length < 2 ||
        selected.length > 4) {
      return;
    }
    update(() {
      busy = true;
      cancelled = false;
      results.clear();
      statuses.clear();
      estimates.clear();
    });
    try {
      final keys = <String, String>{};
      final permits = <String, RequestPermit>{};
      final gate = LocalCostGate(widget.store);
      for (final id in selected) {
        keys[id] =
            id == 'demo' ? '' : await widget.secrets.read('api_$id') ?? '';
        modelNames[id] = id == 'demo'
            ? 'demo-local'
            : await widget.store.setting('model_$id', '');
        if (id != 'demo' && (keys[id]!.isEmpty || modelNames[id]!.isEmpty)) {
          throw StateError(
            'Skonfiguruj ${widget.registry.adapter(id).label} w Dostawcach.',
          );
        }
        estimates[id] = await gate.estimate(id, modelNames[id]!, prompt.text);
      }
      if (!mounted || cancelled) return;
      if (!await confirm(
        context,
        'Zatwierdź porównanie',
        'Ta sama wiadomość trafi wyłącznie do:\n${selected.map((id) => '${widget.registry.adapter(id).label} / ${modelNames[id]} · rezerwa ${estimates[id]!.toStringAsFixed(6)} USD').join('\n')}\n\nHistoria i notatki nie są dołączane. Odpowiedzi nie są przesyłane między modelami. Cennik pochodzi z Twojej konfiguracji; rezerwa nie gwarantuje kwoty rachunku.\n\nWiadomość:\n${prompt.text}',
        action: 'Wyślij do wskazanych odbiorców',
      )) {
        return;
      }
      permits.addAll(await gate.authorizeMany({
        for (final id in selected)
          id: (model: modelNames[id]!, amount: estimates[id]!)
      }));
      if (cancelled) return;
      await Future.wait(
        selected.map((id) async {
          try {
            if (cancelled) return;
            permits[id]?.consume(id, modelNames[id]!);
            update(() {
              results[id] = '';
              statuses[id] = 'Generowanie';
            });
            await for (final e in widget.registry.adapter(id).stream(
                  ProviderRequest(
                    model: modelNames[id]!,
                    apiKey: keys[id]!,
                    turns: [
                      ChatTurn(role: ChatRole.user, text: prompt.text),
                    ],
                  ),
                )) {
              if (cancelled) break;
              update(() {
                results[id] = (results[id] ?? '') + e.delta;
                if (e.done) {
                  statuses[id] =
                      'Ukończono${e.usage?.outputTokens == null ? '' : ' · ${e.usage!.outputTokens} tokenów wyjścia'}';
                }
              });
            }
            if (cancelled) update(() => statuses[id] = 'Anulowano');
          } on ProviderException catch (e) {
            update(() => statuses[id] = e.message);
          } catch (_) {
            update(() => statuses[id] = 'Nie udało się uzyskać odpowiedzi.');
          }
        }),
      );
    } on StateError catch (e) {
      if (mounted) notice(context, e.message.toString());
    } catch (_) {
      if (mounted) notice(context, 'Nie udało się uruchomić porównania.');
    } finally {
      update(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('Porównanie modeli')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '2–4 niezależne odpowiedzi',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Jawni odbiorcy i osobne wyniki. Wersja eksperymentalna: wyniki w RAM, skopiuj je przed wyjściem. Demo jest atrapą, a zgodność modeli nie stanowi dowodu prawdziwości.',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in widget.registry.adapters)
                      FilterChip(
                        label: Text(p.label),
                        selected: selected.contains(p.id),
                        onSelected: busy
                            ? null
                            : (value) => update(() {
                                  if (value && selected.length < 4) {
                                    selected.add(p.id);
                                  } else if (!value) {
                                    selected.remove(p.id);
                                  }
                                }),
                      ),
                  ],
                ),
                TextField(
                  controller: prompt,
                  minLines: 2,
                  maxLines: 8,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Wiadomość do wszystkich wybranych modeli',
                  ),
                ),
                const SizedBox(height: 12),
                if (busy)
                  FilledButton.icon(
                    onPressed: () {
                      cancelled = true;
                      for (final id in selected) {
                        widget.registry.adapter(id).cancel();
                      }
                    },
                    icon: const Icon(Icons.stop),
                    label: const Text('Zatrzymaj'),
                  )
                else
                  FilledButton(
                    onPressed: _start,
                    child: const Text('Sprawdź koszt i odbiorców'),
                  ),
                for (final id in selected)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.registry.adapter(id).label,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '${modelNames[id] ?? 'Model z konfiguracji'} • ${statuses[id] ?? 'Oczekuje'}',
                          ),
                          Text(
                            estimates.containsKey(id)
                                ? 'Rezerwa: ${estimates[id]!.toStringAsFixed(6)} USD'
                                : 'Koszt: wymaga cennika / demo 0 USD',
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            results[id] ?? 'Odpowiedź pojawi się tutaj.',
                          ),
                          if (results[id]?.isNotEmpty ?? false)
                            TextButton.icon(
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: results[id]!),
                              ),
                              icon: const Icon(Icons.copy),
                              label: const Text('Kopiuj'),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}
