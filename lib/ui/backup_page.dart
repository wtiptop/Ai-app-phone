import 'package:flutter/material.dart';

import '../backup/backup_coordinator.dart';
import '../backup/backup_files.dart';
import '../backup/encrypted_archive.dart';
import '../security/encrypted_backup.dart';
import '../storage/app_database.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.store});
  final AppDatabase store;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final password = TextEditingController(), repeated = TextEditingController();
  late final BackupCoordinator coordinator = BackupCoordinator(widget.store);
  bool busy = false, changed = false;
  String status = '';
  @override
  void dispose() {
    coordinator.cancel();
    password.dispose();
    repeated.dispose();
    super.dispose();
  }

  Future<bool> _confirm(ArchiveManifest manifest) async {
    if (!mounted) return false;
    return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
                  title: const Text('Przywrócić pełną kopię?'),
                  content: SingleChildScrollView(
                      child: Text(
                          'Odczytano zaszyfrowany manifest z ${manifest.createdAt}.\n'
                          'Projekty: ${manifest.counts['memory_collections'] ?? 0}\n'
                          'Wersje źródeł: ${manifest.counts['memory_versions'] ?? 0}\n'
                          'Checkpointy analiz: ${manifest.counts['analysis_checkpoints'] ?? 0}\n'
                          'Kampanie RPG: ${manifest.counts['rpg_campaigns'] ?? 0}\n'
                          'Wersje lore i checkpointów RPG: ${manifest.counts['rpg_versions'] ?? 0}\n'
                          'Razem rekordów: ${manifest.records}\n\n'
                          'Kopia obejmuje też sekrety MG i poufne rozmowy. Przywracanie zachowuje '
                          'identyfikatory. Jeśli choć jeden rekord już istnieje, cała operacja '
                          'zostanie wycofana. Końcowa kontrola integralności poprzedza zapis.')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Anuluj')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Przywróć')),
                  ],
                )) ??
        false;
  }

  Future<void> _run(bool restore) async {
    if (busy) return;
    try {
      EncryptedArchive.validatePassphrase(password.text);
      if (!restore && password.text != repeated.text) {
        throw const BackupException('Powtórzone hasło jest inne.');
      }
    } on BackupException catch (e) {
      setState(() => status = e.message);
      return;
    }
    setState(() {
      busy = true;
      status = 'Przygotowanie szyfrowanej kopii…';
    });
    final passphrase = password.text;
    password.clear();
    repeated.clear();
    try {
      void progress(int records, int total) {
        if (mounted) {
          setState(() => status =
              '${restore ? 'Przywracanie' : 'Szyfrowanie'}: $records / $total rekordów');
        }
      }

      final completed = restore
          ? await coordinator.restore(passphrase,
              confirm: _confirm, onProgress: progress)
          : await coordinator.create(passphrase, onProgress: progress);
      if (mounted) {
        setState(() {
          changed |= restore && completed;
          status = completed
              ? (restore
                  ? 'Pełna kopia została przywrócona.'
                  : 'Pełna kopia została zapisana.')
              : 'Operację kopii anulowano.';
        });
      }
    } on BackupException catch (e) {
      if (mounted) setState(() => status = e.message);
    } on BackupFilesException catch (e) {
      if (mounted) setState(() => status = e.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            status = 'Operacja nie powiodła się. Dane w aplikacji zachowano. '
                'Możliwa kolizja istniejących identyfikatorów lub nieprawidłowa kopia. '
                'Przywróć kopię do bazy bez tych rekordów.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && busy) coordinator.cancel();
      },
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Pełna szyfrowana kopia'),
            leading: BackButton(
                onPressed:
                    busy ? null : () => Navigator.pop(context, changed))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
              'Projekty, zaimportowane źródła i wszystkie ich wersje, checkpointy, '
              'kampanie RPG, historia lore, sekrety MG, rozmowy z dowodami kontekstu, notatki i zadania. '
              'Kopia jest przeznaczona dla właściciela urządzenia; zawiera także sekrety MG.'),
          const SizedBox(height: 12),
          const Text(
              'Hasło minimum 12 znaków. Zachowaj je poza telefonem — nie można go odzyskać. '
              'AES-256-GCM, PBKDF2-SHA256 (600 000 iteracji). Limit pliku: 2 GiB. '
              'Duże kopie wymagają wolnego miejsca na zaszyfrowany plik roboczy. Pozostaw aplikację otwartą.'),
          const SizedBox(height: 12),
          const Text(
              'Poza kopią: klucze API i urządzenia, zgody na płatności, konfiguracja dostawców, '
              'modele GGUF oraz uprawnienia do folderów. Oryginalne pliki vaultu, których nie zaimportowano, '
              'obrazy i wtyczki Obsidiana wymagają osobnej kopii. Przywracanie nie łączy kont ani folderów.'),
          const SizedBox(height: 16),
          TextField(
              controller: password,
              enabled: !busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                  labelText: 'Hasło kopii', hintText: 'Hasło kopii')),
          TextField(
              controller: repeated,
              enabled: !busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                  labelText: 'Powtórz hasło', hintText: 'Powtórz hasło')),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: busy ? null : () => _run(false),
              child: const Text('Utwórz pełną kopię')),
          OutlinedButton(
              onPressed: busy ? null : () => _run(true),
              child: const Text('Przywróć pełną kopię')),
          if (busy) ...[
            const LinearProgressIndicator(),
            TextButton(
                onPressed: () {
                  coordinator.cancel();
                  setState(() => status = 'Anulowanie po bieżącym bloku…');
                },
                child: const Text('Anuluj operację')),
          ],
          if (status.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 12), child: Text(status)),
        ]),
      ));
}
