import 'dart:async';

import 'package:flutter/material.dart';

import '../memory/context_packet.dart';
import '../memory/memory_store.dart';
import '../memory/vault_bridge.dart';
import '../memory/vault_import.dart';

/// Pamięć nie trafia do modelu do chwili wybrania źródeł i zatwierdzenia podglądu.
class VaultPage extends StatefulWidget {
  const VaultPage(
      {super.key,
      required this.store,
      this.gateway,
      this.maxPacketBytes = 1600});
  final MemoryStore store;
  final VaultGateway? gateway;
  final int maxPacketBytes;
  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  late final VaultGateway _gateway;
  late final VaultImporter _importer;
  final _name = TextEditingController(text: 'Moja pamięć');
  final _query = TextEditingController();
  final _goal = TextEditingController();
  final _findings = TextEditingController();
  final _next = TextEditingController();
  final _sources = TextEditingController();
  List<MemoryCollection> _collections = [];
  List<VaultHandle> _handles = [];
  List<MemoryDocument> _documents = [];
  List<AnalysisCheckpoint> _checkpoints = [];
  MemoryCollection? _selected;
  ContextPacket? _packet;
  MemorySearchPage? _searchPage;
  AnalysisCheckpoint? _resumedCheckpoint;
  final _chosen = <String>{};
  int _offset = 0,
      _searchOffset = 0,
      _checkpointOffset = 0,
      _collectionOffset = 0;
  bool _busy = false, _importing = false;
  String? _error;
  String _progress = '';

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? VaultBridge();
    _importer = VaultImporter(widget.store, _gateway);
    unawaited(_guard(_reload));
  }

  @override
  void dispose() {
    if (_importing && _selected != null) {
      unawaited(_importer.cancel(_selected!).catchError((Object _) {}));
    }
    for (final controller in [
      _name,
      _query,
      _goal,
      _findings,
      _next,
      _sources
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is VaultException
            ? error.message
            : 'Operacja nie powiodła się. Sprawdź uprawnienie i spróbuj ponownie.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    final collections =
        await widget.store.collections(offset: _collectionOffset);
    List<VaultHandle> handles;
    try {
      handles = await _gateway.status();
    } catch (_) {
      handles = [];
    }
    if (!mounted) return;
    final selectedId = _selected?.id;
    _collections = collections;
    _handles = handles;
    final selected = collections.where((c) => c.id == selectedId).firstOrNull ??
        collections.firstOrNull;
    if (_selected?.id != selected?.id) _clearProjectState();
    _selected = selected;
    await _loadDocuments();
    if (mounted) setState(() {});
  }

  Future<void> _loadDocuments() async {
    final selected = _selected;
    if (selected == null) {
      _documents = [];
      _checkpoints = [];
      return;
    }
    final documents =
        await widget.store.documents(selected.id, offset: _offset);
    final checkpoints =
        await widget.store.checkpoints(selected.id, offset: _checkpointOffset);
    final progress = await _importer.progress(selected);
    if (!mounted) return;
    setState(() {
      _documents = documents;
      _checkpoints = checkpoints;
      if (progress != null) _progress = _progressLabel(progress);
    });
  }

  String _progressLabel(VaultImportProgress progress) {
    final status = switch (progress.status) {
      'running' => 'Importowanie',
      'completed' => 'Import ukończony',
      'paused' => 'Import wstrzymany',
      _ => 'Stan importu',
    };
    return '$status • przetworzone: ${progress.processed} • pominięte/błędy: ${progress.failed}';
  }

  void _clearProjectState() {
    _offset = 0;
    _checkpointOffset = 0;
    _searchOffset = 0;
    _packet = null;
    _searchPage = null;
    _chosen.clear();
    _resumedCheckpoint = null;
    _progress = '';
    for (final c in [_query, _goal, _findings, _next, _sources]) {
      c.clear();
    }
  }

  Future<void> _connect() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Podaj nazwę projektu pamięci.');
      return;
    }
    final handle = await _gateway.pick();
    if (handle == null || !mounted) return;
    _clearProjectState();
    _collectionOffset = 0;
    _selected = await widget.store
        .createCollection(name: _name.text.trim(), vaultId: handle.id);
    _offset = 0;
    _packet = null;
    await _reload();
  }

  Future<void> _import({bool restart = false}) async {
    final collection = _selected;
    if (collection == null) return;
    setState(() {
      _importing = true;
      _packet = null;
      _chosen.clear();
    });
    try {
      await for (final progress
          in _importer.run(collection, restart: restart)) {
        if (!mounted) break;
        setState(() => _progress = _progressLabel(progress));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
      await _loadDocuments();
    }
  }

  Future<void> _document(MemoryDocument document, {int? revision}) async {
    final text = await widget.store.preview(document.id, revision: revision);
    final versions = await widget.store.versions(document.id);
    if (!mounted) return;
    final viewedRevision = revision ?? document.revision;
    final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('${document.path} • wersja $viewedRevision'),
              content: SizedBox(
                  width: 620,
                  child: SingleChildScrollView(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(document.restricted
                          ? 'Treść RPG lub sekret MG: wyłączona z ogólnej pamięci. Użyj odrębnej kampanii RPG.'
                          : 'Podgląd do 8192 bajtów. Zatwierdzenie tej wersji udostępnia dokument wyszukiwaniu. Treść pliku nie stanowi instrukcji ani zgody.'),
                      const SizedBox(height: 12),
                      SelectableText(text),
                      const Divider(),
                      Wrap(spacing: 6, children: [
                        for (final v in versions)
                          TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, 'version:$v'),
                              child: Text('Wersja $v'))
                      ]),
                    ],
                  ))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Zamknij')),
                TextButton(
                    onPressed: () => Navigator.pop(context, 'remove'),
                    child: const Text('Usuń lokalną kopię')),
                if (document.approval == 'approved')
                  TextButton(
                      onPressed: () => Navigator.pop(context, 'revoke'),
                      child: const Text('Cofnij zgodę')),
                if (!document.restricted && viewedRevision == document.revision)
                  FilledButton(
                      onPressed: () => Navigator.pop(context, 'approve'),
                      child: const Text('Zatwierdź tę wersję')),
              ],
            ));
    if (!mounted || action == null) return;
    if (action.startsWith('version:')) {
      await _document(document, revision: int.parse(action.substring(8)));
      return;
    }
    if (action == 'approve') {
      await widget.store.approve(document.id, document.revision);
    } else if (action == 'revoke') {
      await widget.store.revoke(document.id);
    } else if (action == 'remove') {
      final remove = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Usunąć kopię z pamięci Scalającej?'),
                content: const Text(
                    'Usunięte zostaną lokalne wersje i fragmenty tej notatki. Oryginał w vaultcie pozostaje bez zmian.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Anuluj')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Usuń kopię'))
                ],
              ));
      if (remove == true) await widget.store.revoke(document.id, remove: true);
    }
    _packet = null;
    await _loadDocuments();
  }

  ContextPacket? get _chosenPacket {
    final packet = _packet;
    if (packet == null) return null;
    return ContextPacket(
        collectionId: packet.collectionId,
        ownerId: packet.ownerId,
        excerpts: packet.excerpts.where((e) => _chosen.contains(e.chunkId)),
        limited: packet.limited);
  }

  Future<void> _search({int offset = 0}) async {
    final collection = _selected;
    if (collection == null) return;
    final page =
        await widget.store.search(collection.id, _query.text, offset: offset);
    final initial = await widget.store.retrieveSelected(
        collection.id, page.excerpts.take(6).map((e) => e.chunkId).toList(),
        maxBytes: widget.maxPacketBytes);
    final packet = ContextPacket(
        collectionId: collection.id,
        ownerId: collection.ownerId,
        excerpts: page.excerpts);
    if (!mounted) return;
    setState(() {
      _packet = packet;
      _searchPage = page;
      _searchOffset = offset;
      _chosen.clear();
      _chosen.addAll(initial.excerpts.map((e) => e.chunkId));
    });
  }

  Future<ContextPacket?> _boundedSelection() async {
    final collection = _selected;
    if (collection == null || _chosen.isEmpty) return null;
    return widget.store.retrieveSelected(collection.id, _chosen.toList(),
        maxBytes: widget.maxPacketBytes, maxChunks: 20);
  }

  Future<void> _previewContext() async {
    final packet = await _boundedSelection();
    if (packet == null || packet.excerpts.isEmpty) return;
    await widget.store.validate(packet);
    if (!mounted) return;
    final use = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Kontekst do następnej wiadomości'),
              content: SizedBox(
                  width: 620,
                  child: SingleChildScrollView(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${packet.bytes} bajtów • ${packet.excerpts.length} fragmentów. Te źródła zostaną dołączone do następnej wiadomości. Wybór dostawcy i wysłanie następują w czacie.'),
                      if (packet.limited)
                        const Text(
                            'Wybrane fragmenty skrócono do budżetu. Poniżej widać dokładnie dane dla modelu. Zmniejsz wybór, aby zachować więcej tekstu.'),
                      const SizedBox(height: 12),
                      SelectableText(packet.text),
                    ],
                  ))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Wróć')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Użyj w czacie'))
              ],
            ));
    if (use == true && mounted) {
      await widget.store.validate(packet);
      if (!mounted) return;
      Navigator.pop<ContextAttachment>(
          context,
          ContextAttachment(
            label: 'Pamięć: ${packet.excerpts.length} fragmentów',
            text: packet.text,
            validate: () => widget.store.validate(packet),
            receipt: {
              'collectionId': packet.collectionId,
              'sources': [for (final e in packet.excerpts) e.toJson()]
            },
          ));
    }
  }

  Future<void> _saveCheckpoint() async {
    final collection = _selected;
    if (collection == null) return;
    await widget.store.saveCheckpoint(collection.id,
        goal: _goal.text,
        findings: _findings.text,
        nextStep: _next.text,
        sources: _sources.text);
    _checkpointOffset = 0;
    _resumedCheckpoint = null;
    await _loadDocuments();
  }

  Future<void> _resumeAnalysis(AnalysisCheckpoint item) async {
    final collection = _selected;
    if (collection == null) return;
    final fresh = await widget.store.checkpoint(collection.id, item.id);
    if (!mounted) return;
    setState(() {
      _goal.text = fresh.goal;
      _findings.text = fresh.findings;
      _next.text = fresh.nextStep;
      _sources.text = fresh.sources;
      _resumedCheckpoint = fresh;
    });
  }

  Future<void> _export(String content, String filename) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Podgląd nowego eksportu'),
              content: SizedBox(
                  width: 620,
                  child: SingleChildScrollView(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          'Po zatwierdzeniu osobno wybierzesz katalog z prawem zapisu. Powstanie wyłącznie nowy plik w Scalajaca-Exports. Anulowanie zapisu może pozostawić nową niekompletną kopię.'),
                      const SizedBox(height: 12),
                      SelectableText(content),
                    ],
                  ))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Anuluj')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Zezwól na wybór katalogu do eksportu'))
              ],
            ));
    if (confirmed != true) return;
    final handle = await _gateway.pick(writable: true);
    if (handle == null) return;
    try {
      await _gateway.export(handle.id, filename, content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Zapisano nową kopię w Scalajaca-Exports.')));
      }
    } finally {
      // Uprawnienie zapisu dotyczy tylko tej jawnie zatwierdzonej operacji.
      await _gateway.disconnect(handle.id);
    }
  }

  Widget _section(String title, List<Widget> children) => Card(
      semanticContainer: false,
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...children
          ])));

  @override
  Widget build(BuildContext context) {
    final collection = _selected;
    final packet = _chosenPacket;
    final connected = collection != null &&
        _handles.any((h) => h.id == collection.vaultId && h.available);
    return Scaffold(
      appBar: AppBar(title: const Text('Obsidian i duża pamięć')),
      // Każda lista danych jest stronicowana. Stałe drzewo kart zachowuje
      // pozycję czytania, gdy karta wyszukiwania rozrasta się po odpowiedzi.
      body: SingleChildScrollView(
          key: const ValueKey('vault-scroll'),
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
                'Lokalny vault Markdown w pamięci telefonu lub na karcie SD. Scalająca nie uruchamia pluginów Obsidiana ani nie korzysta z Obsidian Sync. Po imporcie treść jest lokalną zaszyfrowaną kopią, a model dostaje wyłącznie wybrane fragmenty po podglądzie.'),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            _section('Projekty pamięci', [
              TextField(
                  controller: _name,
                  maxLength: 160,
                  decoration:
                      const InputDecoration(labelText: 'Nazwa nowego projektu'),
                  enabled: !_busy),
              FilledButton.icon(
                  onPressed: _busy ? null : () => _guard(_connect),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Połącz lokalny vault — tylko odczyt')),
              if (_collections.isNotEmpty)
                DropdownButtonFormField<String>(
                    key: ValueKey(collection?.id),
                    isExpanded: true,
                    initialValue: collection?.id,
                    decoration:
                        const InputDecoration(labelText: 'Projekt pamięci'),
                    items: [
                      for (final item in _collections)
                        DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name,
                                overflow: TextOverflow.ellipsis))
                    ],
                    onChanged: _busy
                        ? null
                        : (id) => _guard(() async {
                              _clearProjectState();
                              _selected =
                                  _collections.firstWhere((c) => c.id == id);
                              await _loadDocuments();
                            })),
              Wrap(spacing: 8, children: [
                TextButton(
                    onPressed: _busy || _collectionOffset == 0
                        ? null
                        : () => _guard(() async {
                              _collectionOffset -= 50;
                              await _reload();
                            }),
                    child: const Text('Poprzednie projekty')),
                TextButton(
                    onPressed: _busy || _collections.length < 50
                        ? null
                        : () => _guard(() async {
                              _collectionOffset += 50;
                              await _reload();
                            }),
                    child: const Text('Następne projekty')),
              ]),
              if (collection != null && !connected)
                OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _guard(() async {
                              final handle = await _gateway.pick();
                              if (handle == null || !mounted) return;
                              await widget.store
                                  .reconnectVault(collection.id, handle.id);
                              await _reload();
                            }),
                    icon: const Icon(Icons.folder_open),
                    label: const Text(
                        'Połącz ponownie folder wybranego projektu')),
              for (final handle in _handles)
                ListTile(
                    dense: true,
                    title: Text(handle.writable
                        ? 'Dostęp do eksportu'
                        : 'Dostęp tylko do odczytu'),
                    subtitle: Text(handle.available
                        ? 'Uprawnienie aktywne'
                        : 'Uprawnienie cofnięte — lokalne kopie pozostają'),
                    trailing: IconButton(
                        tooltip: 'Odłącz uprawnienie',
                        onPressed: _busy
                            ? null
                            : () => _guard(() async {
                                  await _gateway.disconnect(handle.id);
                                  await _reload();
                                }),
                        icon: const Icon(Icons.link_off))),
            ]),
            if (collection != null) ...[
              _section('Import i przegląd źródeł', [
                const Text(
                    'Pliki .md/.markdown do 1 MiB, do 20 poziomów. Ukryte katalogi, .obsidian, .git i własne eksporty są pomijane. Skan jest wznawialny; po zmianie vaultu uruchom ponowny skan. Nie jest to spójny snapshot ani uniwersalny sandbox symlinków.'),
                Wrap(spacing: 8, children: [
                  FilledButton(
                      onPressed: _busy || !connected
                          ? null
                          : () => _guard(() => _import()),
                      child: const Text('Importuj / wznów')),
                  TextButton(
                      onPressed: _busy || !connected
                          ? null
                          : () => _guard(() => _import(restart: true)),
                      child: const Text('Skanuj od początku')),
                  if (_importing)
                    TextButton(
                        onPressed: () async {
                          try {
                            await _importer.cancel(collection);
                          } catch (_) {
                            if (mounted) {
                              setState(() => _error =
                                  'Nie udało się przerwać operacji. Poczekaj na limit czasu.');
                            }
                          }
                        },
                        child: const Text('Anuluj import')),
                ]),
                if (_progress.isNotEmpty) Text(_progress),
                const Text(
                    'Nowe i zmienione notatki oczekują na zatwierdzenie. Sekrety MG i treści kampanii nie trafiają do ogólnego wyszukiwania.'),
                for (final doc in _documents)
                  Semantics(
                      container: true,
                      child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(doc.path),
                          subtitle: Text(
                              'Wersja ${doc.revision} • ${doc.bytes} B • ${doc.restricted ? "wyłączone: RPG / sekret MG" : doc.approval == "approved" ? "zatwierdzony" : "oczekuje"}'),
                          trailing: const Icon(Icons.visibility),
                          onTap: _busy
                              ? null
                              : () => _guard(() => _document(doc)))),
                if (_documents.isEmpty)
                  const Text('Brak zaimportowanych dokumentów na tej stronie.'),
                Wrap(spacing: 8, children: [
                  TextButton(
                      onPressed: _busy || _offset == 0
                          ? null
                          : () => _guard(() async {
                                _offset -= 30;
                                await _loadDocuments();
                              }),
                      child: const Text('Poprzednie źródła')),
                  TextButton(
                      onPressed: _busy || _documents.length < 30
                          ? null
                          : () => _guard(() async {
                                _offset += 30;
                                await _loadDocuments();
                              }),
                      child: const Text('Następne źródła'))
                ]),
              ]),
              _section('Odnajdź wcześniejsze dane', [
                TextField(
                    controller: _query,
                    onChanged: (_) => setState(() {
                          _packet = null;
                          _searchPage = null;
                          _searchOffset = 0;
                          _chosen.clear();
                        }),
                    maxLength: 512,
                    decoration: const InputDecoration(
                        labelText:
                            'Szukaj po słowach w zatwierdzonych źródłach'),
                    enabled: !_busy),
                FilledButton(
                    onPressed: _busy ? null : () => _guard(_search),
                    child: const Text('Szukaj w pamięci')),
                if (_searchPage != null) ...[
                  Text(
                      'Znalezione fragmenty: ${_searchPage!.total}. Strona ${_searchOffset ~/ 10 + 1}. Wybrane: ${_chosen.length}. Wybór dotyczy tej strony.'),
                  const Text(
                      'Dokładne słowa, z pominięciem słów pospolitych. Najpierw różne dokumenty; brak wyszukiwania semantycznego. Do modelu trafi tylko podgląd w ustalonym budżecie.'),
                  if (_searchPage!.queryLimited)
                    const Text(
                        'Do rankingu użyto pierwszych 12 różnych istotnych słów.'),
                ],
                if (_packet != null && _packet!.excerpts.isEmpty)
                  const Text(
                      'Brak zatwierdzonych źródeł pasujących do zapytania.'),
                if (_packet != null) ...[
                  for (final excerpt in _packet!.excerpts)
                    CheckboxListTile(
                        key: ValueKey('recall:${excerpt.chunkId}'),
                        contentPadding: EdgeInsets.zero,
                        value: _chosen.contains(excerpt.chunkId),
                        title: Text(
                            '${excerpt.path} • w${excerpt.revision} • linie ${excerpt.startLine}–${excerpt.endLine}'),
                        subtitle: Text(excerpt.text,
                            maxLines: 4, overflow: TextOverflow.ellipsis),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  if (value == true) {
                                    _chosen.add(excerpt.chunkId);
                                  } else {
                                    _chosen.remove(excerpt.chunkId);
                                  }
                                })),
                  Wrap(spacing: 8, children: [
                    TextButton(
                        onPressed: _busy || _searchOffset == 0
                            ? null
                            : () => _guard(
                                () => _search(offset: _searchOffset - 10)),
                        child: const Text('Poprzednie wyniki')),
                    TextButton(
                        onPressed: _busy || _searchPage?.hasMore != true
                            ? null
                            : () => _guard(
                                () => _search(offset: _searchOffset + 10)),
                        child: const Text('Następne wyniki')),
                  ]),
                  FilledButton(
                      onPressed:
                          _busy || packet == null || packet.excerpts.isEmpty
                              ? null
                              : () => _guard(_previewContext),
                      child: const Text('Podgląd wybranych źródeł')),
                  TextButton(
                      onPressed:
                          _busy || packet == null || packet.excerpts.isEmpty
                              ? null
                              : () => _guard(() async {
                                    final selected = await _boundedSelection();
                                    if (selected == null ||
                                        selected.excerpts.isEmpty) {
                                      return;
                                    }
                                    await widget.store.validate(selected);
                                    await _export(
                                        selected.text, 'Wybrane-zrodla.md');
                                  }),
                      child: const Text('Eksportuj wybrane źródła')),
                ],
              ]),
              _section('Punkt wznowienia długiej analizy', [
                const Text(
                    'Zapisujesz własne ustalenia i następny krok. Każdy zapis z tego formularza tworzy osobny punkt; starsze pozostają. Notatki analizy nie nadają źródłom zatwierdzenia i nie są automatycznie wysyłane do modelu.'),
                if (_resumedCheckpoint != null)
                  Text(
                      'Wczytano: ${_resumedCheckpoint!.goal} (w${_resumedCheckpoint!.revision}). Sprawdź aktualne źródła przed dalszą analizą.'),
                TextField(
                    controller: _goal,
                    maxLength: 1000,
                    decoration: const InputDecoration(labelText: 'Cel analizy'),
                    enabled: !_busy),
                TextField(
                    controller: _findings,
                    maxLength: 6000,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Ustalenia'),
                    enabled: !_busy),
                TextField(
                    controller: _next,
                    maxLength: 3000,
                    minLines: 2,
                    maxLines: 4,
                    decoration:
                        const InputDecoration(labelText: 'Następny krok'),
                    enabled: !_busy),
                TextField(
                    controller: _sources,
                    maxLength: 2000,
                    decoration:
                        const InputDecoration(labelText: 'Źródła i wersje'),
                    enabled: !_busy),
                FilledButton(
                    onPressed: _busy ? null : () => _guard(_saveCheckpoint),
                    child: const Text('Zatwierdź i zapisz punkt wznowienia')),
                for (final item in _checkpoints)
                  ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(item.goal),
                      subtitle: Text('Wersja ${item.revision}'),
                      children: [
                        SelectableText(
                            'Ustalenia:\n${item.findings}\n\nNastępny krok:\n${item.nextStep}\n\nŹródła:\n${item.sources}'),
                        Wrap(spacing: 8, children: [
                          TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _guard(() => _resumeAnalysis(item)),
                              child: const Text('Wróć do tej analizy')),
                          TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _guard(() async {
                                        await _resumeAnalysis(item);
                                        final query = _next.text.trim().isEmpty
                                            ? _goal.text
                                            : _next.text;
                                        _query.text = query.runes
                                            .take(512)
                                            .map(String.fromCharCode)
                                            .join();
                                        await _search();
                                      }),
                              child: const Text(
                                  'Odszukaj źródła do kolejnego kroku')),
                          TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _guard(() => _export(
                                      '# ${item.goal}\n\n## Ustalenia\n${item.findings}\n\n## Następny krok\n${item.nextStep}\n\n## Źródła\n${item.sources}',
                                      'Punkt-analizy.md')),
                              child: const Text('Eksportuj punkt analizy'))
                        ]),
                      ]),
                Wrap(spacing: 8, children: [
                  TextButton(
                      onPressed: _busy || _checkpointOffset == 0
                          ? null
                          : () => _guard(() async {
                                _checkpointOffset -= 30;
                                await _loadDocuments();
                              }),
                      child: const Text('Nowsze punkty analizy')),
                  TextButton(
                      onPressed: _busy || _checkpoints.length < 30
                          ? null
                          : () => _guard(() async {
                                _checkpointOffset += 30;
                                await _loadDocuments();
                              }),
                      child: const Text('Starsze punkty analizy')),
                ]),
              ]),
            ],
          ])),
    );
  }
}
