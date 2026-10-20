import 'dart:convert';

import 'package:flutter/material.dart';

import '../rpg/campaign.dart';
import '../rpg/campaign_store.dart';
import '../security/memory_access.dart';
import '../storage/models.dart';
import '../storage/transfers.dart';

class CampaignPage extends StatefulWidget {
  const CampaignPage(
      {super.key,
      required this.store,
      required this.ownerId,
      this.onContextReady,
      this.contextUnavailableReason,
      this.maxContextCharacters = 6000});
  final CampaignStore store;
  final String ownerId;
  final ValueChanged<CampaignContextPack>? onContextReady;
  final String? contextUnavailableReason;
  final int maxContextCharacters;
  @override
  State<CampaignPage> createState() => _CampaignPageState();
}

class _CampaignPageState extends State<CampaignPage> {
  List<StoredCampaign> campaigns = [];
  List<CampaignRecord> records = [];
  StoredCampaign? selected;
  bool gm = false, busy = false, includeCheckpoint = true;
  int campaignOffset = 0, recordOffset = 0;
  int _loadSerial = 0;
  String? error;
  final contextQuery = TextEditingController();
  final selectedRecordIds = <String>{};
  AccessContext get access => AccessContext(
      principalId: widget.ownerId,
      role: gm ? AccessRole.gameMaster : AccessRole.rpgPlayer,
      campaignId: selected!.id,
      allowGmSecretContext: gm);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    contextQuery.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _load() async {
    final ticket = ++_loadSerial;
    final selectedId = selected?.id, requestedGm = gm;
    final requestedAccess = selected == null ? null : access;
    try {
      final list = await widget.store
          .listCampaigns(ownerId: widget.ownerId, offset: campaignOffset);
      final current = selectedId == null
          ? null
          : await widget.store.readCampaign(selectedId, requestedAccess!);
      final entries = current == null
          ? <CampaignRecord>[]
          : await widget.store
              .listRecords(requestedAccess!, offset: recordOffset);
      if (mounted &&
          ticket == _loadSerial &&
          selected?.id == selectedId &&
          gm == requestedGm) {
        setState(() {
          campaigns = list;
          selected = current;
          records = entries;
        });
      }
    } catch (e) {
      if (mounted && ticket == _loadSerial) setState(() => error = '$e');
    }
  }

  Future<void> _create() async {
    final name = TextEditingController(),
        edition = TextEditingController(text: 'Własny świat');
    try {
      final accepted = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Nowa własna kampania'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        'Powstanie pusta kampania. Nie są dodawane podręczniki ani lore.'),
                    TextField(
                        controller: name,
                        decoration:
                            const InputDecoration(labelText: 'Nazwa kampanii')),
                    TextField(
                        controller: edition,
                        decoration:
                            const InputDecoration(labelText: 'System i edycja'))
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Anuluj')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Utwórz pustą'))
                  ]));
      if (accepted != true || !mounted) return;
      await _run(() async {
        final created = await widget.store.create(
            name: name.text, edition: edition.text, ownerId: widget.ownerId);
        if (!mounted) return;
        setState(() {
          selected = created;
          gm = true;
          includeCheckpoint = true;
          recordOffset = 0;
          selectedRecordIds.clear();
          contextQuery.clear();
        });
        await _load();
      });
    } finally {
      name.dispose();
      edition.dispose();
    }
  }

  Future<void> _add({bool importFile = false, CampaignRecord? initial}) async {
    String? imported;
    if (importFile) {
      try {
        imported = await AndroidFiles.importText();
      } catch (e) {
        if (mounted) setState(() => error = '$e');
        return;
      }
      if (imported == null || !mounted) return;
      if (imported.length > 100000) {
        setState(() => error = 'Wybierz fragment do 100 000 znaków.');
        return;
      }
    }
    if (!mounted) return;
    final record = await showDialog<CampaignRecord>(
        context: context,
        builder: (_) => _RecordDialog(
            campaign: selected!, imported: imported, initial: initial));
    if (record == null || !mounted) return;
    await _run(() async {
      await widget.store.putRecord(record, access,
          expectedRevision: selected!.revision, userApproved: true);
      await _load();
    });
  }

  Future<void> _checkpoint() => _run(() async {
        final checkpoint = await widget.store.readCheckpoint(access);
        if (!mounted) return;
        final result = await showDialog<CampaignCheckpoint>(
            context: context,
            builder: (_) => _CheckpointDialog(initial: checkpoint));
        if (result == null || !mounted) return;
        await widget.store.saveCheckpoint(result, access,
            expectedRevision: selected!.revision);
        await _load();
      });

  Future<void> _sessionHistory() => _run(() async {
        final frozenAccess = access, expectedRevision = selected!.revision;
        final revision = await showDialog<int>(
            context: context,
            builder: (_) => _CampaignHistoryDialog(
                store: widget.store,
                access: frozenAccess,
                recordId: 'active-session',
                checkpointOnly: true));
        if (revision == null || !mounted) return;
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: Text('Wznowić punkt sesji z r$revision?'),
                    content: const Text(
                        'Zapiszę tylko notatkę sesji jako nową rewizję. Nie cofnę kanonu ani stanu świata. Sprawdź zgodność dawnego celu i sceny z obecnym światem przed dalszą grą.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Anuluj')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Wznów jako nową rewizję'))
                    ]));
        if (confirmed != true || !mounted) return;
        await widget.store.resumeCheckpoint(revision, frozenAccess,
            expectedRevision: expectedRevision);
        selectedRecordIds.clear();
        await _load();
      });

  Future<void> _recordHistory(CampaignRecord record) => _run(() async {
        await showDialog<void>(
            context: context,
            builder: (_) => _CampaignHistoryDialog(
                store: widget.store,
                access: access,
                recordId: record.id,
                checkpointOnly: false));
      });

  Future<void> _audit() async {
    try {
      final events = await widget.store.audit(access);
      if (!mounted) return;
      final target = await showDialog<int>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Ostatnie 30 rewizji'),
                  content: SizedBox(
                      width: 400,
                      height: 350,
                      child: ListView(children: [
                        const Text(
                            'Powrót dopisuje nową rewizję. Audyt pozostaje zachowany.'),
                        ListTile(
                            title: const Text('Rewizja 0 · pusta kampania'),
                            trailing: const Icon(Icons.restore),
                            onTap: () => Navigator.pop(ctx, 0)),
                        for (final event in events)
                          ListTile(
                              title: Text(
                                  'Rewizja ${event.revision} · ${event.kind}'),
                              subtitle: Text(event.at.toLocal().toString()),
                              trailing: const Icon(Icons.restore),
                              onTap: () => Navigator.pop(ctx, event.revision)),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Zamknij'))
                  ]));
      if (target == null || !mounted) return;
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: Text('Wrócić do rewizji $target?'),
                  content: const Text(
                      'Zmieni to bieżący kanon, stan świata i checkpoint. Historia audytu nie zostanie usunięta.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Anuluj')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Zatwierdź powrót'))
                  ]));
      if (confirmed != true || !mounted) return;
      await _run(() async {
        await widget.store
            .rollback(target, access, expectedRevision: selected!.revision);
        selectedRecordIds.clear();
        await _load();
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _prepareContext() => _run(() async {
        final pack = await widget.store.contextPack(access,
            query: contextQuery.text,
            includeCheckpoint: includeCheckpoint,
            selectedRecordIds: selectedRecordIds.toList(),
            maxCharacters: widget.maxContextCharacters);
        if (!mounted) return;
        final approved = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: Text(
                        'Podgląd danych · ${gm ? 'MG' : 'gracz'} · r${pack.revision}'),
                    content: SizedBox(
                        width: 600,
                        height: 400,
                        child: SingleChildScrollView(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(gm
                                  ? 'Pakiet może zawierać sekrety MG. Przekaż go wyłącznie świadomie.'
                                  : 'Pakiet zawiera tylko jawny kanon i oddzielną wiedzę gracza.'),
                              if (pack.limited)
                                const Text(
                                    'Osiągnięto limit pakietu. To wycinek pamięci, nie cały świat.'),
                              SelectableText(pack.text),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Anuluj')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Przygotuj dla czatu'))
                    ]));
        if (approved != true || !mounted) return;
        if (widget.onContextReady != null) {
          widget.onContextReady!(pack);
        } else {
          Navigator.pop(context, pack);
        }
      });

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Trwałe kampanie RPG')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'Lokalny właściciel wybiera widok MG lub gracza. To filtr na tym telefonie, nie logowanie innej osoby. Narracja modelu nie zatwierdza zmian świata.'),
        if (error != null)
          Text(error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (busy) const LinearProgressIndicator(),
        FilledButton.tonalIcon(
            onPressed: busy ? null : _create,
            icon: const Icon(Icons.add),
            label: const Text('Utwórz własną pustą kampanię')),
        for (final campaign in campaigns)
          ListTile(
              selected: selected?.id == campaign.id,
              title: Text(campaign.name),
              subtitle:
                  Text('${campaign.edition} · rewizja ${campaign.revision}'),
              onTap: busy
                  ? null
                  : () async {
                      setState(() {
                        selected = campaign;
                        gm = false;
                        includeCheckpoint = true;
                        recordOffset = 0;
                        records = [];
                        selectedRecordIds.clear();
                        contextQuery.clear();
                      });
                      await _load();
                    }),
        Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                  onPressed: busy || campaignOffset == 0
                      ? null
                      : () {
                          setState(() => campaignOffset -= 30);
                          _load();
                        },
                  child: const Text('Poprzednie kampanie')),
              TextButton(
                  onPressed: busy || campaigns.length < 30
                      ? null
                      : () {
                          setState(() => campaignOffset += 30);
                          _load();
                        },
                  child: const Text('Następne'))
            ]),
        if (selected != null) ...[
          const Divider(),
          Text(selected!.name, style: Theme.of(context).textTheme.titleLarge),
          Text('${selected!.edition} · rewizja ${selected!.revision}'),
          SwitchListTile(
              title: const Text('Widok MG z sekretami'),
              value: gm,
              subtitle: Text(gm
                  ? 'Sekrety są widoczne na tym ekranie.'
                  : 'Tylko jawny kanon i wiedza gracza.'),
              onChanged: busy
                  ? null
                  : (value) async {
                      setState(() {
                        gm = value;
                        includeCheckpoint = true;
                        records = [];
                        recordOffset = 0;
                        selectedRecordIds.clear();
                      });
                      await _load();
                    }),
          if (gm) ...[
            OutlinedButton(
                onPressed: busy ? null : () => _add(),
                child: const Text('Zatwierdź własny wpis')),
            OutlinedButton(
                onPressed: busy ? null : () => _add(importFile: true),
                child: const Text('Importuj fragment Markdown do kampanii')),
            OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
                        try {
                          await _checkpoint();
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                        }
                      },
                child: const Text('Stan sesji · zapisz lub wróć')),
            OutlinedButton(
                onPressed: busy ? null : _sessionHistory,
                child: const Text('Historia sesji MG')),
            OutlinedButton(
                onPressed: busy ? null : _audit,
                child: const Text('Audyt i powrót do rewizji')),
          ],
          TextField(
              controller: contextQuery,
              enabled: !busy,
              maxLength: 500,
              decoration: const InputDecoration(
                  labelText: 'Pytanie do pamięci kampanii',
                  helperText:
                      'Dokładne słowa, bez embeddingów. Brak dopasowania oznacza brak źródła.')),
          if (gm)
            SwitchListTile(
                value: includeCheckpoint,
                title: const Text('Dołącz stan sesji MG'),
                subtitle: const Text(
                    'Wyłącz przy szukaniu dawnych faktów, jeśli pełna notatka zajmuje budżet. Zapis pozostaje w historii.'),
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                          includeCheckpoint = value;
                          if (!value) {
                            selectedRecordIds.remove('active-session');
                          }
                        })),
          Text(
              'Wybrane ręcznie: ${selectedRecordIds.length}/20. Sekret MG trafia do pakietu tylko po ręcznym wyborze. Dołączony stan sesji MG jest pierwszy; to notatka, nie nowy kanon.'),
          FilledButton(
              onPressed: busy || widget.contextUnavailableReason != null
                  ? null
                  : _prepareContext,
              child: const Text('Podgląd pakietu dla czatu')),
          if (widget.contextUnavailableReason != null)
            Text(widget.contextUnavailableReason!),
          if (records.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Brak wpisów w wybranym widoku.')),
          for (final record in records)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(record.title,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(
                              '${record.kind.name} · r${record.revision}${record.visibility == MemoryVisibility.gmSecret ? ' · SEKRET MG' : ''}'),
                          Text(record.citation.verification ==
                                  LoreVerification.verified
                              ? 'Źródło potwierdzone przez użytkownika'
                              : 'NIEZWERYFIKOWANE'),
                          Text(
                              '${record.citation.title} · ${record.citation.sourceId} · strona/wpis: ${record.citation.page ?? 'BRAK'}'),
                          if (record.visibility == MemoryVisibility.gmSecret)
                            Text(record.content)
                          else
                            SelectableText(record.content),
                          if (record.kind !=
                              CampaignRecordKind.sessionCheckpoint)
                            CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Wybierz jawnie do pakietu'),
                                value: selectedRecordIds.contains(record.id),
                                onChanged: busy
                                    ? null
                                    : (value) => setState(() {
                                          if (value == true) {
                                            if (selectedRecordIds.length < 20) {
                                              selectedRecordIds.add(record.id);
                                            } else {
                                              error =
                                                  'Możesz wskazać maksymalnie 20 wpisów.';
                                            }
                                          } else {
                                            selectedRecordIds.remove(record.id);
                                          }
                                        })),
                          if (gm &&
                              record.kind !=
                                  CampaignRecordKind.sessionCheckpoint)
                            TextButton(
                                onPressed:
                                    busy ? null : () => _recordHistory(record),
                                child:
                                    const Text('Historia wersji tego wpisu')),
                          if (gm &&
                              record.kind !=
                                  CampaignRecordKind.sessionCheckpoint)
                            TextButton(
                                onPressed:
                                    busy ? null : () => _add(initial: record),
                                child: const Text(
                                    'Zatwierdź zmianę · nowa rewizja')),
                        ]))),
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                    onPressed: busy || recordOffset == 0
                        ? null
                        : () {
                            setState(() => recordOffset -= 30);
                            _load();
                          },
                    child: const Text('Poprzednie wpisy')),
                TextButton(
                    onPressed: busy || records.length < 30
                        ? null
                        : () {
                            setState(() => recordOffset += 30);
                            _load();
                          },
                    child: const Text('Następne wpisy'))
              ]),
        ],
      ]));
}

class _CampaignHistoryDialog extends StatefulWidget {
  const _CampaignHistoryDialog(
      {required this.store,
      required this.access,
      required this.recordId,
      required this.checkpointOnly});
  final CampaignStore store;
  final AccessContext access;
  final String recordId;
  final bool checkpointOnly;
  @override
  State<_CampaignHistoryDialog> createState() => _CampaignHistoryDialogState();
}

class _CampaignHistoryDialogState extends State<_CampaignHistoryDialog> {
  final cursors = <int?>[null];
  List<CampaignHistoryEntry> entries = [];
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = widget.checkpointOnly
          ? await widget.store
              .checkpointHistory(widget.access, beforeRevision: cursors.last)
          : await widget.store.recordHistory(widget.recordId, widget.access,
              beforeRevision: cursors.last);
      if (mounted) setState(() => entries = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _showVersion(CampaignHistoryEntry entry) async {
    setState(() => busy = true);
    try {
      final comparison = await widget.store.compareRecordVersion(
          widget.recordId, entry.record.revision, widget.access);
      if (!mounted) return;
      final resume = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: Text('Archiwum · rewizja ${entry.record.revision}'),
                  content: SizedBox(
                      width: 600,
                      height: 420,
                      child: SingleChildScrollView(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const Text(
                                'Archiwalna notatka nie jest aktualnym kanonem. Sam podgląd nie zmienia świata ani kontekstu modelu.'),
                            Text(
                                'Porównano z bieżącym stanem kampanii r${comparison.campaignRevision}.'),
                            Text(comparison.changedFields.isEmpty
                                ? 'Treść i metadane są zgodne z bieżącym wpisem.'
                                : 'Różnice względem bieżącego wpisu: ${comparison.changedFields.join(', ')}.'),
                            const Divider(),
                            const Text('Wybrana wersja historyczna'),
                            _HistoryRecordView(record: comparison.historical),
                            const Divider(),
                            const Text('Bieżący wpis'),
                            if (comparison.current == null)
                              const Text(
                                  'Brak tego wpisu w aktualnym stanie świata.')
                            else
                              _HistoryRecordView(record: comparison.current!),
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Zamknij podgląd')),
                    if (widget.checkpointOnly && !entry.isCurrent)
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Wybierz punkt do wznowienia'))
                  ]));
      if (resume == true && mounted) {
        Navigator.pop(context, entry.record.revision);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.checkpointOnly
              ? 'Historia sesji MG'
              : 'Historia wersji wpisu'),
          content: SizedBox(
              width: 600,
              height: 420,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Prywatne archiwum MG. Wersje mogą zawierać dawne sekrety. Nie są automatycznie dodawane do promptu ani bieżącego lore.'),
                    if (busy) const LinearProgressIndicator(),
                    if (error != null)
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    Expanded(
                        child: ListView(children: [
                      if (!busy && entries.isEmpty)
                        const Text('Brak zapisów na tej stronie.'),
                      for (final entry in entries)
                        ListTile(
                            title: Text(
                                'Rewizja ${entry.record.revision}${entry.isCurrent ? (widget.checkpointOnly ? ' · bieżący punkt' : ' · bieżąca wersja') : ''}'),
                            subtitle: Text(
                                '${entry.savedAt.toLocal()} · ${entry.eventKind}\n${widget.checkpointOnly ? entry.checkpoint.goal : entry.record.title}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis),
                            trailing: const Icon(Icons.history),
                            onTap: busy ? null : () => _showVersion(entry)),
                    ])),
                    Wrap(spacing: 8, children: [
                      TextButton(
                          onPressed: busy || cursors.length == 1
                              ? null
                              : () {
                                  cursors.removeLast();
                                  _load();
                                },
                          child: const Text('Nowsze zapisy')),
                      TextButton(
                          onPressed: busy || entries.length < 20
                              ? null
                              : () {
                                  cursors.add(entries.last.record.revision);
                                  _load();
                                },
                          child: const Text('Starsze zapisy'))
                    ]),
                  ])),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Zamknij historię'))
          ]);
}

class _HistoryRecordView extends StatelessWidget {
  const _HistoryRecordView({required this.record});
  final CampaignRecord record;
  @override
  Widget build(BuildContext context) {
    final checkpoint = record.kind == CampaignRecordKind.sessionCheckpoint
        ? CampaignCheckpoint.fromJson(
            jsonDecode(record.content) as Map<String, dynamic>)
        : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${record.title} · r${record.revision}'),
      Text(
          '${record.visibility == MemoryVisibility.gmSecret ? 'SEKRET MG' : 'Wpis jawny'} · ${record.approved ? 'zatwierdzony' : 'szkic'}'),
      if (checkpoint != null) ...[
        Text(
            'Cel: ${checkpoint.goal}\nScena: ${checkpoint.scene}\nOtwarte wątki: ${checkpoint.openThreads}\nDrużyna: ${checkpoint.party}\nZegar świata: ${checkpoint.worldClock}'),
      ] else
        Text(record.content),
      Text(record.citation.verification == LoreVerification.verified
          ? 'Źródło potwierdzone przez użytkownika'
          : 'NIEZWERYFIKOWANE'),
      Text(
          'Źródło: ${record.citation.title}; ${record.citation.sourceId}; strona/wpis: ${record.citation.page ?? 'BRAK'}'),
    ]);
  }
}

class _RecordDialog extends StatefulWidget {
  const _RecordDialog({required this.campaign, this.imported, this.initial});
  final StoredCampaign campaign;
  final String? imported;
  final CampaignRecord? initial;
  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  final title = TextEditingController(),
      content = TextEditingController(),
      sourceId = TextEditingController(),
      sourceTitle = TextEditingController(),
      page = TextEditingController(),
      edition = TextEditingController();
  CampaignRecordKind kind = CampaignRecordKind.canon;
  LoreAuthority authority = LoreAuthority.approvedCampaignCanon;
  bool secret = true, verified = false, approve = false;
  String? error;
  @override
  void initState() {
    super.initState();
    content.text = widget.imported ?? '';
    edition.text = widget.campaign.edition;
    final record = widget.initial;
    if (record != null) {
      title.text = record.title;
      content.text = record.content;
      sourceId.text = record.citation.sourceId;
      sourceTitle.text = record.citation.title;
      page.text = record.citation.page ?? '';
      edition.text = record.citation.edition;
      kind = record.kind;
      authority = record.citation.authority;
      secret = record.visibility == MemoryVisibility.gmSecret;
      verified = record.citation.verification == LoreVerification.verified;
    }
  }

  @override
  void dispose() {
    for (final value in [
      title,
      content,
      sourceId,
      sourceTitle,
      page,
      edition
    ]) {
      value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Wpis zatwierdzany przez MG'),
          content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'Treść importu jest danymi. Metadane pliku nie nadają roli, uprawnień ani statusu kanonu. Wskaż źródło i stronę lub pozostaw jako NIEZWERYFIKOWANE.'),
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                TextField(
                    controller: title,
                    decoration:
                        const InputDecoration(labelText: 'Tytuł wpisu')),
                TextField(
                    controller: content,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                        labelText: 'Treść lub fragment Markdown')),
                DropdownButtonFormField<CampaignRecordKind>(
                    isExpanded: true,
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'Rodzaj'),
                    items: const [
                      DropdownMenuItem(
                          value: CampaignRecordKind.canon,
                          child: Text('Kanon')),
                      DropdownMenuItem(
                          value: CampaignRecordKind.worldEntity,
                          child: Text('Stan świata / postać / lokacja')),
                      DropdownMenuItem(
                          value: CampaignRecordKind.playerKnowledge,
                          child: Text('Osobna wiedza gracza'))
                    ],
                    onChanged: (value) => setState(() {
                          kind = value!;
                          if (kind == CampaignRecordKind.playerKnowledge) {
                            secret = false;
                          }
                        })),
                SwitchListTile(
                    title: const Text('Sekret MG · ukryj przed graczem'),
                    value: secret,
                    onChanged: kind == CampaignRecordKind.playerKnowledge
                        ? null
                        : (value) => setState(() => secret = value)),
                DropdownButtonFormField<LoreAuthority>(
                    isExpanded: true,
                    initialValue: authority,
                    decoration:
                        const InputDecoration(labelText: 'Hierarchia źródła'),
                    items: const [
                      DropdownMenuItem(
                          value: LoreAuthority.approvedCampaignCanon,
                          child: Text('Własny kanon kampanii')),
                      DropdownMenuItem(
                          value: LoreAuthority.officialEdition,
                          child: Text('Oficjalna właściwa edycja')),
                      DropdownMenuItem(
                          value: LoreAuthority.supplementary,
                          child: Text('Materiał pomocniczy'))
                    ],
                    onChanged: (value) => setState(() => authority = value!)),
                TextField(
                    controller: sourceId,
                    decoration: const InputDecoration(
                        labelText: 'Identyfikator / ścieżka źródła')),
                TextField(
                    controller: sourceTitle,
                    decoration:
                        const InputDecoration(labelText: 'Tytuł źródła')),
                TextField(
                    controller: page,
                    decoration: const InputDecoration(
                        labelText:
                            'Strona / zakres linii / numer własnego wpisu')),
                TextField(
                    controller: edition,
                    decoration:
                        const InputDecoration(labelText: 'Edycja źródła')),
                CheckboxListTile(
                    title: const Text(
                        'Osobiście sprawdziłem źródło i wskazaną stronę / wpis'),
                    value: verified,
                    onChanged: (value) => setState(() => verified = value!)),
                CheckboxListTile(
                    title: Text(!secret &&
                            kind != CampaignRecordKind.worldEntity
                        ? 'Zatwierdzam wpis i jego publikację w widoku gracza'
                        : 'Zatwierdzam wpis do pamięci MG wybranej kampanii'),
                    value: approve,
                    onChanged: (value) => setState(() => approve = value!)),
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Anuluj')),
            FilledButton(
                onPressed: !approve
                    ? null
                    : () {
                        if (title.text.trim().isEmpty ||
                            content.text.trim().isEmpty) {
                          setState(() => error = 'Podaj tytuł i treść.');
                          return;
                        }
                        if (verified &&
                            (sourceId.text.trim().isEmpty ||
                                sourceTitle.text.trim().isEmpty ||
                                page.text.trim().isEmpty)) {
                          setState(() => error =
                              'Potwierdzenie źródła wymaga identyfikatora, tytułu i strony / wpisu.');
                          return;
                        }
                        if (authority == LoreAuthority.officialEdition &&
                            edition.text != widget.campaign.edition) {
                          setState(() => error =
                              'Oficjalne źródło musi dotyczyć edycji wybranej kampanii.');
                          return;
                        }
                        Navigator.pop(
                            context,
                            CampaignRecord(
                                id: widget.initial?.id ?? newId(),
                                campaignId: widget.campaign.id,
                                title: title.text,
                                content: content.text,
                                kind: kind,
                                visibility: secret
                                    ? MemoryVisibility.gmSecret
                                    : MemoryVisibility.campaign,
                                citation: LoreCitation(
                                    sourceId: sourceId.text,
                                    title: sourceTitle.text,
                                    authority: authority,
                                    edition: edition.text,
                                    page: page.text,
                                    userVerified: verified)));
                      },
                child: const Text('Zapisz zatwierdzony wpis'))
          ]);
}

class _CheckpointDialog extends StatefulWidget {
  const _CheckpointDialog({this.initial});
  final CampaignCheckpoint? initial;
  @override
  State<_CheckpointDialog> createState() => _CheckpointDialogState();
}

class _CheckpointDialogState extends State<_CheckpointDialog> {
  final values = List.generate(5, (_) => TextEditingController());
  static const labels = [
    'Cel sesji',
    'Bieżąca scena',
    'Otwarte wątki',
    'Drużyna',
    'Zegar świata'
  ];
  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      final text = [
        initial.goal,
        initial.scene,
        initial.openThreads,
        initial.party,
        initial.worldClock
      ];
      for (var i = 0; i < values.length; i++) {
        values[i].text = text[i];
      }
    }
  }

  @override
  void dispose() {
    for (final value in values) {
      value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Trwały stan sesji · tylko MG'),
          content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'Po restarcie wrócisz do tego stanu. Zapis nie podejmuje decyzji za gracza.'),
                for (var i = 0; i < values.length; i++)
                  TextField(
                      controller: values[i],
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(labelText: labels[i])),
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Zamknij')),
            FilledButton(
                onPressed: () => Navigator.pop(
                    context,
                    CampaignCheckpoint(
                        goal: values[0].text,
                        scene: values[1].text,
                        openThreads: values[2].text,
                        party: values[3].text,
                        worldClock: values[4].text)),
                child: const Text('Zatwierdź zapis sesji'))
          ]);
}
