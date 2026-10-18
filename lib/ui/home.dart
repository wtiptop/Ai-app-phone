import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../auth/secret_store.dart';
import '../chat/chat_session.dart';
import '../costs/local_cost_gate.dart';
import '../provider_registry/provider_registry.dart';
import '../security/encrypted_backup.dart';
import '../storage/app_database.dart';
import '../storage/models.dart';
import '../storage/transfers.dart';
import 'comparison.dart';
import 'provider_settings.dart';

class Home extends StatefulWidget {
  const Home({
    super.key,
    required this.store,
    required this.secrets,
    required this.registry,
    required this.onTheme,
    this.themeMode = ThemeMode.system,
  });
  final AppDatabase store;
  final SecretStore secrets;
  final ProviderRegistry registry;
  final ValueChanged<ThemeMode> onTheme;
  final ThemeMode themeMode;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late final ChatSession session;
  late final LocalCostGate costs;
  final composer = TextEditingController(), search = TextEditingController();
  final scroll = ScrollController();
  int tab = 0;
  String provider = 'demo', model = 'demo-local', memoryQuery = '';
  bool privateMode = false, loading = true, paid = false, _sending = false;
  bool noPersonalReviewers = true, _onboarding = false;
  List<Conversation> history = [];
  List<LocalNote> notes = [];
  List<Map<String, Object?>> tasks = [], operations = [];
  Future<void> _draftWrites = Future.value();
  String? _loadError;

  @override
  void initState() {
    super.initState();
    session = ChatSession(widget.store, widget.registry);
    costs = LocalCostGate(widget.store);
    session.addListener(_changed);
    _load();
  }

  Future<void> _load() async {
    try {
      paid = await widget.store.setting('paid_enabled', false);
      privateMode = await widget.store.setting('private', false);
      noPersonalReviewers = await widget.store.setting(
        'no_personal_reviewers',
        true,
      );
      history = await widget.store.conversations(search.text);
      notes = await widget.store.notes(memoryQuery);
      tasks = await widget.store.db.query('tasks', orderBy: 'created DESC');
      tasks = [
        for (final t in tasks)
          {...t, 'title': await widget.store.cipher.open(t['title'] as String)},
      ];
      operations = await widget.store.db.query(
        'operations',
        orderBy: 'created DESC',
      );
      if (mounted) {
        setState(() {
          loading = false;
          _loadError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          _loadError =
              'Nie można odczytać lokalnych danych. Niczego nie usunięto. Sprawdź pamięć urządzenia i kopię zapasową.';
        });
      }
    }
  }

  void _changed() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    session.removeListener(_changed);
    session.dispose();
    composer.dispose();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _onboard() async {
    if (_onboarding) return;
    _onboarding = true;
    if (await widget.store.setting('onboarded', false) || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Witaj w Scalającej'),
        content: const SingleChildScrollView(
          child: Text(
            'Twoja samodzielna aplikacja Android.\n\nBez konta działa demo, szyfrowana lokalna historia, notatki, szkice i zadania. Demo nie jest modelem AI.\n\nAPI wymaga własnego klucza, cennika i zgody na wysłanie danych. Abonament aplikacji dostawcy nie jest automatycznym uprawnieniem API.\n\nOPPO i Obsidian są opcjonalne. Import, eksport oraz konfigurację znajdziesz w Ustawieniach. Nie ma telemetrii ani mikrofonu w tle.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zacznij bez konta'),
          ),
        ],
      ),
    );
    await widget.store.setSetting('onboarded', true);
  }

  Future<void> _new() async {
    await _draftWrites;
    await session.create(privateMode: privateMode);
    composer.clear();
    await _load();
  }

  Future<void> _chooseProvider() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Dokąd wysłać wiadomość?'),
              subtitle: Text(
                'Zmiana zachowuje lokalną historię. Przed wysłaniem zobaczysz jej zakres.',
              ),
            ),
            for (final p in widget.registry.adapters)
              ListTile(
                title: Text(p.label),
                subtitle: Text(
                  p.id == 'demo'
                      ? 'Działa offline • jawna atrapa • 0 USD'
                      : p.id == 'minicpm_local'
                          ? 'Bez sieci • wbudowany llama.cpp • import GGUF'
                          : p.id == 'minicpm'
                              ? 'Eksperymentalna • opcjonalny własny serwer HTTPS'
                              : 'Wymaga klucza i modelu • API',
                ),
                trailing: provider == p.id ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, p.id),
              ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Konfiguruj dostawców'),
              onTap: () => Navigator.pop(context, 'settings'),
            ),
            const ListTile(
              title: Text('Auto / konsensus'),
              subtitle: Text(
                'Zaplanowane • bez automatycznego przekazywania historii',
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || chosen == null) return;
    if (chosen == 'settings') {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ProviderSettings(
            store: widget.store,
            secrets: widget.secrets,
            registry: widget.registry,
          ),
        ),
      );
      return;
    }
    final selectedModel = chosen == 'demo'
        ? 'demo-local'
        : await widget.store.setting('model_$chosen', '');
    if (mounted) {
      setState(() {
        provider = chosen;
        model = selectedModel;
      });
    }
  }

  Future<void> _send({bool retry = false}) async {
    if (_sending || session.busy) return;
    final text = retry
        ? session.messages.where((m) => m.role == 'user').lastOrNull?.text ?? ''
        : composer.text;
    if (text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await _draftWrites;
      RequestPermit? permit;
      String key = '';
      String? expectedEndpoint;
      if (provider != 'demo') {
        key = provider == 'minicpm_local'
            ? ''
            : await widget.secrets.read('api_$provider') ?? '';
        model = await widget.store.setting('model_$provider', '');
        if ((provider != 'minicpm' &&
                provider != 'minicpm_local' &&
                key.isEmpty) ||
            model.isEmpty) {
          throw StateError(provider == 'minicpm_local'
              ? 'Zaimportuj i wybierz GGUF w Ustawienia → Dostawcy → MiniCPM offline.'
              : 'Wprowadź klucz i model w Ustawienia → Dostawcy.');
        }
        final contextText = [
          for (final m in session.messages)
            if (m.role == 'user' || m.status == 'complete') m.text,
          if (!retry) text,
        ].join('\n');
        final estimate = await costs.estimate(provider, model, contextText);
        final target = widget.registry.adapter(provider);
        final recipient = target is MiniCpmAdapter
            ? (await target.endpoint()).recipient
            : provider == 'minicpm_local'
                ? 'Wyłącznie ten telefon • bez sieci'
                : target.label;
        if (target is MiniCpmAdapter) expectedEndpoint = recipient;
        final costInfo = provider == 'minicpm_local'
            ? '0 USD za API. Obliczenia korzystają z CPU, RAM i baterii telefonu. Limit wyjścia: 512 tokenów.'
            : provider == 'minicpm' && estimate == 0
                ? 'Własny serwer bez opłat za API według Twojej deklaracji. '
                    'Aplikacja nie weryfikuje jego rozliczeń. Limit wyjścia: 1024 tokeny.'
                : 'Lokalna rezerwa: ${estimate.toStringAsFixed(6)} USD. '
                    'To konserwatywny szacunek według Twoich stawek, nie gwarancja rachunku. '
                    'Limit wyjścia: 1024 tokeny. Anulowanie może pozostawić opłatę u dostawcy.';
        if (!mounted) return;
        if (!await confirm(
          context,
          provider == 'minicpm_local'
              ? 'Uruchom model offline?'
              : 'Wyślij do ${widget.registry.adapter(provider).label}?',
          'Odbiorca: $recipient\nModel: $model\n\n${provider == 'minicpm_local' ? 'Lokalny model przetworzy' : 'Zostanie wysłana'} treść tej rozmowy: wiadomości użytkownika i ukończone odpowiedzi modeli. Pamięć, inne czaty i pliki nie są dołączane.\n\n$costInfo\n\nNowa wiadomość:\n$text',
          action: provider == 'minicpm_local'
              ? 'Uruchom offline'
              : 'Zatwierdź wysłanie i koszt',
        )) {
          return;
        }
        permit = await costs.authorize(provider, model, estimate);
      }
      if (session.conversation == null) {
        await session.create(privateMode: privateMode);
      }
      if (!retry) composer.clear();
      await session.send(
        text,
        provider,
        model,
        key,
        repeat: retry,
        permit: permit,
        expectedEndpoint: expectedEndpoint,
      );
      await _load();
    } on StateError catch (e) {
      if (mounted) notice(context, e.message.toString());
    } catch (_) {
      if (mounted) {
        notice(
          context,
          'Operacja nie powiodła się. Dane nie zostały usunięte.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _history() async {
    await _draftWrites;
    await _load();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: search,
                    decoration: const InputDecoration(
                      labelText: 'Szukaj w lokalnej historii',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (q) async {
                      final list = await widget.store.conversations(q);
                      if (context.mounted) update(() => history = list);
                    },
                  ),
                ),
                Expanded(
                  child: history.isEmpty
                      ? const Center(child: Text('Brak zapisanych rozmów'))
                      : ListView(
                          children: [
                            for (final c in history)
                              ListTile(
                                leading: Icon(
                                  c.pinned
                                      ? Icons.push_pin
                                      : Icons.chat_bubble_outline,
                                ),
                                title: Text(c.title),
                                subtitle: Text(
                                  c.updated.toLocal().toString().substring(
                                        0,
                                        16,
                                      ),
                                ),
                                onTap: () async {
                                  await session.load(c);
                                  composer.text = c.draft;
                                  if (context.mounted) Navigator.pop(context);
                                },
                                trailing: PopupMenuButton<String>(
                                  onSelected: (action) async {
                                    if (action == 'pin') {
                                      await widget.store.pin(c.id, !c.pinned);
                                    }
                                    if (!context.mounted) return;
                                    if (action == 'delete') {
                                      if (!await confirm(
                                        context,
                                        'Usunąć rozmowę?',
                                        'Usuniesz lokalną historię „${c.title}”.',
                                        action: 'Usuń',
                                      )) {
                                        return;
                                      }
                                      await widget.store.deleteConversation(
                                        c.id,
                                      );
                                      if (session.conversation?.id == c.id) {
                                        await session.create(
                                          privateMode: privateMode,
                                        );
                                        composer.clear();
                                      }
                                    }
                                    if (action == 'export') {
                                      try {
                                        await AndroidFiles.save(
                                          'rozmowa.md',
                                          await Transfers(widget.store)
                                              .markdown(c),
                                        );
                                      } catch (_) {
                                        if (context.mounted) {
                                          notice(
                                            context,
                                            'Nie zapisano eksportu.',
                                          );
                                        }
                                      }
                                    }
                                    await _load();
                                    if (context.mounted) update(() {});
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'pin',
                                      child: Text('Przypnij / odepnij'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'export',
                                      child: Text('Eksport Markdown'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Usuń'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!),
                  TextButton(
                    onPressed: _load,
                    child: const Text('Spróbuj ponownie'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _onboard());
    final busy = session.busy || _sending;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          [
            'Scalająca',
            'Agenci',
            'Projekty i pamięć',
            'Zadania',
            'Ustawienia',
          ][tab],
        ),
        actions: tab == 0
            ? [
                IconButton(
                  tooltip: 'Historia i wyszukiwanie',
                  onPressed: busy ? null : _history,
                  icon: const Icon(Icons.history),
                ),
                IconButton(
                  tooltip: 'Nowa rozmowa',
                  onPressed: busy ? null : _new,
                  icon: const Icon(Icons.add_comment_outlined),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: switch (tab) {
          0 => _chat(),
          1 => _agents(),
          2 => _memory(),
          3 => _tasks(),
          _ => _settings(),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Czat',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            label: 'Agenci',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            label: 'Pamięć',
          ),
          NavigationDestination(icon: Icon(Icons.task_alt), label: 'Zadania'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Ustawienia'),
        ],
      ),
    );
  }

  Widget _chat() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        session.busy || _sending ? null : _chooseProvider,
                    icon: const Icon(Icons.hub_outlined),
                    label: Text(
                      '${widget.registry.adapter(provider).label} · ${model.isEmpty ? 'wybierz model' : model}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Porównaj modele',
                  icon: const Icon(Icons.view_week_outlined),
                  onPressed: session.busy || _sending
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => Comparison(
                                store: widget.store,
                                secrets: widget.secrets,
                                registry: widget.registry,
                              ),
                            ),
                          ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                session.private
                    ? 'Tryb prywatny • rozmowa tylko w RAM'
                    : provider == 'demo'
                        ? 'DEMO OFFLINE • atrapa odpowiedzi • bez opłat'
                        : provider == 'minicpm_local'
                            ? 'MiniCPM OFFLINE • obliczenia w tym telefonie • bez API'
                            : provider == 'minicpm'
                                ? 'MiniCPM • dane trafią na Twój serwer HTTPS'
                                : 'API • dane opuszczą telefon po potwierdzeniu',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
          Expanded(
            child: session.messages.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.all_inclusive, size: 72),
                            const SizedBox(height: 20),
                            Text(
                              'Jedno miejsce na Twoje myśli.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Rozmowy, pamięć i zadania na Twoim telefonie.\nZacznij lokalnie, bez konta.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                ActionChip(
                                  label: const Text('Wypróbuj demo'),
                                  onPressed: () => setState(
                                    () => composer.text =
                                        'Pokaż, jak działa Scalająca.',
                                  ),
                                ),
                                ActionChip(
                                  label: const Text('Dodaj notatkę'),
                                  onPressed: () => _noteEditor(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: session.messages.length,
                    itemBuilder: (context, index) {
                      final m = session.messages[index];
                      return Align(
                        alignment: m.role == 'user'
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 720),
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: m.role == 'user'
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLow,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.role == 'user'
                                    ? 'Ty'
                                    : '${m.provider} · ${m.model}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              if (m.text.isNotEmpty)
                                MarkdownBody(
                                  data: m.text,
                                  selectable: true,
                                  imageBuilder: (uri, title, alt) => Text(
                                    '[Obraz: ${alt ?? 'bez opisu'} • pobieranie wyłączone]',
                                  ),
                                ),
                              if (m.status == 'streaming')
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: LinearProgressIndicator(),
                                ),
                              if (m.role != 'user')
                                Text(
                                  '${_statusLabel(m.status)} • ${m.provider == 'demo' || m.provider == 'minicpm_local' ? '0 USD za API' : m.provider == 'minicpm' ? 'koszt wg konfiguracji własnego serwera' : 'koszt wg API / lokalnej rezerwy'}${m.inputTokens == null ? '' : ' • wejście ${m.inputTokens}, wyjście ${m.outputTokens ?? '?'} tokenów'}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              Wrap(
                                children: [
                                  IconButton(
                                    tooltip: 'Kopiuj tekst',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.copy, size: 18),
                                    onPressed: () => Clipboard.setData(
                                      ClipboardData(text: m.text),
                                    ),
                                  ),
                                  if (m.role == 'user')
                                    IconButton(
                                      tooltip: 'Edytuj jako nową wiadomość',
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                      onPressed: session.busy
                                          ? null
                                          : () => setState(
                                                () => composer.text = m.text,
                                              ),
                                    ),
                                  IconButton(
                                    tooltip: 'Udostępnij wybrany tekst',
                                    icon: const Icon(
                                      Icons.share_outlined,
                                      size: 18,
                                    ),
                                    onPressed: () async {
                                      if (await confirm(
                                        context,
                                        'Udostępnić tekst?',
                                        'Wybrana aplikacja otrzyma tę wiadomość:\n\n${m.text}',
                                        action: 'Otwórz Sharesheet',
                                      )) {
                                        try {
                                          await AndroidFiles.share(m.text);
                                        } catch (_) {
                                          if (context.mounted) {
                                            notice(
                                              context,
                                              'Udostępnianie wymaga Androida.',
                                            );
                                          }
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (session.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                session.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (session.messages.isNotEmpty && !session.busy)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _sending ? null : () => _send(retry: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Ponów ostatnią odpowiedź'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: composer,
                    minLines: 1,
                    maxLines: 5,
                    enabled: !session.busy,
                    decoration: InputDecoration(
                      hintText: 'Napisz wiadomość…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onChanged: (value) {
                      _draftWrites = _draftWrites.then((_) async {
                        if (session.conversation == null) {
                          await session.create(privateMode: privateMode);
                        }
                        await session.saveDraft(value);
                      }).catchError((Object _) {
                        if (mounted) {
                          notice(context, 'Nie udało się zapisać szkicu.');
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                if (session.busy)
                  Semantics(
                    label: 'Anuluj generowanie',
                    button: true,
                    onTap: session.cancel,
                    child: ExcludeSemantics(
                      child: IconButton.filled(
                        tooltip: 'Anuluj generowanie',
                        onPressed: session.cancel,
                        icon: const Icon(Icons.stop),
                      ),
                    ),
                  )
                else
                  Semantics(
                    label: 'Wyślij wiadomość',
                    button: true,
                    enabled: !_sending,
                    onTap: _sending ? null : _send,
                    child: ExcludeSemantics(
                      child: IconButton.filled(
                        tooltip: 'Wyślij wiadomość',
                        onPressed: _sending ? null : _send,
                        icon: const Icon(Icons.arrow_upward),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );

  String _statusLabel(String s) => switch (s) {
        'complete' => 'Ukończono',
        'cancelled' => 'Anulowano',
        'interrupted' => 'Przerwano',
        'error' => 'Błąd',
        'pending' => 'Oczekuje',
        'running' => 'W trakcie',
        _ => 'Generowanie',
      };

  Widget _memory() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Twoja pamięć. Na urządzeniu.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Ręczne notatki i wyszukiwanie lokalne. Notatki nie są automatycznie wysyłane do modeli. RPG i sekrety MG mają odrębny moduł domenowy; nie importuj ich tutaj.',
          ),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Szukaj w notatkach',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) async {
              memoryQuery = value;
              await _load();
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _noteEditor(),
                icon: const Icon(Icons.add),
                label: const Text('Notatka'),
              ),
              OutlinedButton.icon(
                onPressed: _importNote,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Import Markdown'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (notes.isEmpty)
            const Text(
                'Brak notatek. Dodaj pierwszą — zadziała bez internetu.'),
          for (final n in notes)
            Card(
              child: ListTile(
                title: Text(n.title),
                subtitle: Text(
                  '${n.folder}\n${n.text}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _noteEditor(note: n),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'export') {
                      try {
                        await AndroidFiles.save(
                          '${n.folder.toLowerCase()}-notatka.md',
                          '# ${n.title}\n\n${n.text}',
                        );
                      } catch (_) {
                        if (mounted) notice(context, 'Nie zapisano notatki.');
                      }
                    }
                    if (v == 'delete' &&
                        mounted &&
                        await confirm(
                          context,
                          'Usunąć notatkę?',
                          n.title,
                          action: 'Usuń',
                        )) {
                      await widget.store.deleteNote(n.id);
                      await _load();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'export',
                      child: Text('Eksport Markdown'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Usuń')),
                  ],
                ),
              ),
            ),
        ],
      );
  Future<void> _noteEditor({LocalNote? note, String? imported}) async {
    final title = TextEditingController(
      text: note?.title ?? (imported == null ? '' : 'Zaimportowana notatka'),
    );
    final content = TextEditingController(text: note?.text ?? imported ?? '');
    var folder = note?.folder ?? 'INBOX';
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(note == null ? 'Nowa notatka' : 'Edytuj notatkę'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Tytuł'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: folder,
                    items: memoryFolders
                        .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                        .toList(),
                    onChanged: (v) => update(() => folder = v ?? folder),
                  ),
                  TextField(
                    controller: content,
                    minLines: 5,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: 'Treść • Markdown',
                    ),
                  ),
                  const Text(
                    'Import jest danymi, nie instrukcjami systemowymi. Zapis zatwierdzasz ręcznie.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Zapisz lokalnie'),
            ),
          ],
        ),
      ),
    );
    if (save == true && title.text.trim().isNotEmpty) {
      await widget.store.saveNote(
        title.text.trim(),
        content.text,
        folder,
        id: note?.id,
      );
      await _load();
    }
    // Controllers may still be used by the closing route's animation until next frame.
    Future.delayed(const Duration(milliseconds: 300), () {
      title.dispose();
      content.dispose();
    });
  }

  Future<void> _importNote() async {
    try {
      final text = await AndroidFiles.importText();
      if (text != null && mounted) await _noteEditor(imported: text);
    } catch (_) {
      if (mounted) {
        notice(
          context,
          'Nie zaimportowano pliku. Obsługiwany jest tekst do 16 MB.',
        );
      }
    }
  }

  Widget _tasks() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Sprawy do zrobienia',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text(
            'Lista działa lokalnie. Przypomnienia i harmonogram powiadomień są zaplanowane; zadania nie uruchamiają się w tle.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _addTask,
            icon: const Icon(Icons.add),
            label: const Text('Dodaj zadanie'),
          ),
          for (final t in tasks)
            CheckboxListTile(
              value: t['done'] == 1,
              title: Text(t['title'] as String),
              onChanged: (v) async {
                await widget.store.db.update(
                  'tasks',
                  {'done': v == true ? 1 : 0},
                  where: 'id=?',
                  whereArgs: [t['id']],
                );
                await _load();
              },
            ),
          const Divider(),
          const Text(
            'Kolejka niewysłanych operacji',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Zapisuje odnośnik do szkicu. Wysyłka wyłącznie ręczna z czatu po sprawdzeniu odbiorcy.',
          ),
          for (final op in operations)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text('Szkic • ${_statusLabel(op['status'] as String)}'),
              subtitle: const Text('Nie wykonano automatycznej wysyłki'),
              trailing: IconButton(
                tooltip: 'Usuń z kolejki',
                icon: const Icon(Icons.close),
                onPressed: () async {
                  await widget.store.db.delete(
                    'operations',
                    where: 'id=?',
                    whereArgs: [op['id']],
                  );
                  await _load();
                },
              ),
            ),
          if (session.conversation != null && !session.private)
            OutlinedButton(
              onPressed: () async {
                await session.saveDraft(composer.text);
                await widget.store.queue(session.conversation!.id);
                await _load();
              },
              child: const Text('Zapisz bieżący szkic w kolejce'),
            ),
        ],
      );
  Future<void> _addTask() async {
    final input = TextEditingController();
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nowe zadanie'),
        content: TextField(
          controller: input,
          decoration: const InputDecoration(labelText: 'Co chcesz zrobić?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dodaj'),
          ),
        ],
      ),
    );
    if (yes == true && input.text.trim().isNotEmpty) {
      await widget.store.db.insert('tasks', {
        'id': newId(),
        'title': await widget.store.cipher.seal(input.text.trim()),
        'created': DateTime.now().millisecondsSinceEpoch,
      });
      await _load();
    }
    Future.delayed(const Duration(milliseconds: 300), input.dispose);
  }

  Widget _agents() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Plan pod Twoją kontrolą',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text(
            'Eksperymentalne: zaimplementowano silnik stanów, role, reguły dostępu i limity. Wykonywanie agentów przez modele oraz narzędzia nie jest jeszcze podłączone do interfejsu.',
          ),
          const SizedBox(height: 16),
          for (final name in [
            'Asystent osobisty i PL–DE',
            'Programowanie i IT',
            'Badania i źródła',
            'Gospodarka / GPW',
            'Technologie / AI',
            'Gry i RPG',
            'Komunikacja',
          ])
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(name),
                subtitle: const Text(
                  'Kierownik → wykonawca → niezależny kontroler • zaplanowane połączenie z modelami',
                ),
              ),
            ),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Plan → uprawnienia i budżet → wykonanie → weryfikacja → raport. Domyślnie maks. 2 korekty. Brak automatycznych działań zewnętrznych. Zgodność modeli nie dowodzi prawdziwości.',
              ),
            ),
          ),
        ],
      );
  Widget _settings() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: const Text('Dostawcy AI'),
              subtitle:
                  const Text('Klucze • modele • cenniki • test połączenia'),
              onTap: session.busy
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ProviderSettings(
                            store: widget.store,
                            secrets: widget.secrets,
                            registry: widget.registry,
                          ),
                        ),
                      );
                      await _load();
                    },
            ),
          ),
          SwitchListTile(
            title: const Text('Zezwalaj na płatne API'),
            subtitle: const Text(
              'Domyślnie wyłączone. Każda wysyłka wymaga także potwierdzenia.',
            ),
            value: paid,
            onChanged: (v) async {
              if (v &&
                  !await confirm(
                    context,
                    'Zezwolić na API?',
                    'API może być płatne niezależnie od abonamentu. Limity lokalne nie blokują użycia w innych aplikacjach. Włącz dopiero po sprawdzeniu cennika i zasad dostawcy.',
                  )) {
                return;
              }
              await widget.store.setSetting('paid_enabled', v);
              await _load();
            },
          ),
          ListTile(
            title: const Text('Budżety i lokalne rezerwy'),
            subtitle: const Text(
              'USD • dzień / miesiąc (UTC) • bez fikcyjnych cen',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _budgets,
          ),
          SwitchListTile(
            title: const Text('Tryb prywatny / bez zapisu'),
            subtitle: const Text(
              'Dotyczy nowych rozmów. Historia w RAM; po zamknięciu zostanie utracona.',
            ),
            value: privateMode,
            onChanged: (v) async {
              await widget.store.setSetting('private', v);
              await _load();
            },
          ),
          SwitchListTile(
            title: const Text('Nie wysyłaj danych osobistych do recenzentów'),
            subtitle: const Text(
              'Polityka zapisana; recenzenci jeszcze niepodłączeni.',
            ),
            value: noPersonalReviewers,
            onChanged: (v) async {
              await widget.store.setSetting('no_personal_reviewers', v);
              await _load();
            },
          ),
          const SwitchListTile(
            title: Text('Potwierdzenie wielu dostawców'),
            subtitle: Text('W tej wersji zawsze wymagane.'),
            value: true,
            onChanged: null,
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Motyw'),
            trailing: DropdownButton<ThemeMode>(
              value: widget.themeMode,
              items: const [
                DropdownMenuItem(
                    value: ThemeMode.system, child: Text('Systemowy')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Jasny')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Ciemny')),
              ],
              onChanged: (v) {
                if (v != null) widget.onTheme(v);
              },
            ),
          ),
          const ListTile(
            leading: Icon(Icons.language),
            title: Text('Język: polski'),
            subtitle: Text(
              'Interfejs polski; wydzielenie tekstów i kolejne tłumaczenia zaplanowane.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.enhanced_encryption_outlined),
            title: const Text('Zaszyfrowana kopia danych'),
            subtitle:
                const Text('AES-GCM • hasło właściciela • bez kluczy API'),
            onTap: () => _backup(false),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Przywróć zaszyfrowaną kopię'),
            subtitle: const Text('Dopisuje dane bez usuwania istniejących'),
            onTap: () => _backup(true),
          ),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: const Text('Import Markdown'),
            subtitle:
                const Text('Ręczny podgląd przed zapisem • bez Obsidiana'),
            onTap: _importNote,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.balance_outlined),
            title: const Text('Licencje zależności'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Scalająca',
              applicationVersion: '0.1.0',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.link_off),
            title: Text('JARVIS / OPPO: wyłączony'),
            subtitle: Text(
              'Zaplanowane opcjonalne parowanie. Brak połączeń i zależności.',
            ),
          ),
          const ListTile(
            title: Text('Kalendarz, poczta, komunikatory i głos'),
            subtitle: Text(
              'Zaplanowane. Brak przyznanych uprawnień, tokenów i mikrofonu w tle.',
            ),
          ),
          const ListTile(
            title: Text('Diagnostyka lokalna'),
            subtitle: Text(
              'Wersja 0.1.0 • baza v2 • brak telemetrii i logowania treści. Stan transportu widoczny w czacie.',
            ),
          ),
        ],
      );
  Future<void> _budgets() async {
    final d = TextEditingController(
      text: '${await widget.store.setting<double>('daily_budget', 1)}',
    );
    final m = TextEditingController(
      text: '${await widget.store.setting<double>('monthly_budget', 5)}',
    );
    final rows = await widget.store.db.query('cost_reservations');
    final sum = rows.fold<double>(
      0,
      (value, r) => value + (r['amount'] as num).toDouble(),
    );
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Budżety lokalne'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rezerwy wszystkich wywołań: ${sum.toStringAsFixed(6)} USD. Zachowujemy pełną rezerwę po błędzie/anulowaniu. Rzeczywisty rachunek sprawdzaj u dostawcy.',
              ),
              TextField(
                controller: d,
                decoration: const InputDecoration(
                  labelText: 'Limit dnia (USD)',
                ),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: m,
                decoration: const InputDecoration(
                  labelText: 'Limit miesiąca (USD)',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );
    if (yes == true) {
      final daily = double.tryParse(d.text.replaceAll(',', '.')),
          monthly = double.tryParse(m.text.replaceAll(',', '.'));
      if (daily != null &&
          monthly != null &&
          daily.isFinite &&
          monthly.isFinite &&
          daily > 0 &&
          monthly > 0) {
        await widget.store.setSetting('daily_budget', daily);
        await widget.store.setSetting('monthly_budget', monthly);
      } else if (mounted) {
        notice(context, 'Podaj dodatnie, skończone limity.');
      }
    }
    Future.delayed(const Duration(milliseconds: 300), () {
      d.dispose();
      m.dispose();
    });
  }

  Future<void> _backup(bool restore) async {
    final pass = TextEditingController();
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(restore ? 'Przywróć kopię' : 'Utwórz kopię'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Hasło minimum 12 znaków. Nie zapisujemy go i nie możemy go odzyskać. Kopia zawiera rozmowy, notatki i zadania; nie zawiera sekretów, ustawień ani rezerw kosztowych.',
            ),
            TextField(
              controller: pass,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Hasło kopii'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dalej'),
          ),
        ],
      ),
    );
    if (yes == true) {
      try {
        final backups = EncryptedBackup(), transfers = Transfers(widget.store);
        if (restore) {
          final file = await AndroidFiles.importText();
          if (file == null) return;
          final raw = await backups.decrypt(file, pass.text);
          await transfers.restore(utf8.decode(raw));
          await _load();
          if (mounted) notice(context, 'Dane przywrócone jako nowe rekordy.');
        } else {
          final encrypted = await backups.encrypt(
            utf8.encode(await transfers.snapshot()),
            pass.text,
          );
          await AndroidFiles.save('scalajaca-kopia.json', encrypted);
        }
      } on BackupException catch (e) {
        if (mounted) notice(context, e.message);
      } catch (_) {
        if (mounted) {
          notice(
            context,
            'Nie udało się wykonać operacji na kopii. Istniejące dane zachowano.',
          );
        }
      }
    }
    Future.delayed(const Duration(milliseconds: 300), pass.dispose);
  }
}
