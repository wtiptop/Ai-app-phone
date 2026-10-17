// Fallback runtime checks for environments blocking the Flutter test runner's
// local WebSocket. Run directly with Dart; no network or Flutter engine needed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scalajaca/agents/agent_run.dart';
import 'package:scalajaca/costs/budget_guard.dart';
import 'package:scalajaca/optional_jarvis_bridge/jarvis_bridge.dart';
import 'package:scalajaca/rpg/campaign.dart';
import 'package:scalajaca/security/encrypted_backup.dart';
import 'package:scalajaca/security/memory_access.dart';

int _passed = 0;
void check(bool condition, String label) {
  if (!condition) throw StateError('FAIL: $label');
  _passed++;
}

Future<void> rejects<T>(FutureOr<void> Function() action, String label) async {
  try {
    await action();
  } catch (error) {
    if (error is T) {
      _passed++;
      return;
    }
    rethrow;
  }
  throw StateError('FAIL: $label nie zostało odrzucone.');
}

Future<void> main() async {
  const policy = MemoryAccessPolicy();
  const gm = AccessContext(
      principalId: 'owner',
      role: AccessRole.gameMaster,
      campaignId: 'a',
      allowGmSecretContext: true);
  const player = AccessContext(
      principalId: 'player',
      role: AccessRole.rpgPlayer,
      campaignId: 'a',
      allowGmSecretContext: true);
  final secret = MemoryRecord(
      id: 'secret',
      ownerId: 'owner',
      authorId: 'owner',
      createdAt: DateTime.utc(2026),
      source: 'local',
      content: 'SPOILER',
      visibility: MemoryVisibility.gmSecret,
      approval: MemoryApproval.approved,
      campaignId: 'a',
      sharedWith: {'player'});
  for (final purpose in MemoryPurpose.values) {
    check(policy.select([secret], player, purpose).isEmpty,
        'sekret gracza/${purpose.name}');
  }
  for (final purpose in [
    MemoryPurpose.reviewerContext,
    MemoryPurpose.retrievalIndex,
    MemoryPurpose.export
  ]) {
    check(policy.select([secret], gm, purpose).isEmpty,
        'sekret MG/${purpose.name}');
  }
  check(policy.select([secret], gm, MemoryPurpose.modelContext).length == 1,
      'jawny kontekst MG');
  const otherCampaign = AccessContext(
      principalId: 'owner',
      role: AccessRole.gameMaster,
      campaignId: 'b',
      allowGmSecretContext: true);
  check(
      policy
          .select([secret], otherCampaign, MemoryPurpose.modelContext).isEmpty,
      'izolacja kampanii');
  final directory = ChannelIdentityDirectory({
    ChannelIdentityDirectory.mappingKey('telegram', 'verified-subject'):
        'owner',
  });
  check(
      directory.resolve(
              channel: 'discord', authenticatedSubject: 'verified-subject') ==
          null,
      'izolacja identyfikatorów transportu');
  check(
      directory.resolve(channel: 'telegram', authenticatedSubject: 'owner') ==
          null,
      'podszycie nazwą');

  var now = DateTime.utc(2026, 10, 17);
  final budget = BudgetGuard(
      limits: const BudgetLimits(
          maxSteps: 1,
          maxCalls: 2,
          maxRunMicros: 100,
          dailyMicros: 100,
          monthlyMicros: 100),
      now: () => now);
  budget.begin('a', paidApproved: true);
  budget.begin('b', paidApproved: true);
  await rejects<BudgetExceeded>(() {
    budget.reserveCall('a', paid: true);
  }, 'nieznana cena bez rezerwy');
  final reservation =
      budget.reserveCall('a', paid: true, maximumChargeMicros: 70);
  await rejects<BudgetExceeded>(() {
    budget.reserveCall('b', paid: true, maximumChargeMicros: 31);
  }, 'równoległe przekroczenie budżetu');
  budget.stop('a');
  check(budget.reservedMicros == 70, 'stop zachowuje rezerwę');
  budget.commit(reservation);
  check(budget.entries.single.amountMicros == 70,
      'brak usage kosztuje całą rezerwę');
  await rejects<BudgetExceeded>(() {
    budget.commit(reservation);
  }, 'powtórne rozliczenie');
  budget.step('b');
  await rejects<BudgetExceeded>(() {
    budget.step('b');
  }, 'limit kroków');
  now = now.add(const Duration(minutes: 2));
  await rejects<BudgetExceeded>(() {
    budget.reserveCall('b', paid: false);
  }, 'limit czasu');

  final run = AgentRun(AgentPlan(
      id: 'run',
      ownerId: 'owner',
      goal: 'Plan',
      steps: ['Wykonaj', 'Skontroluj'],
      permissions: {AgentPermission.modelQuery}));
  await rejects<StateError>(run.start, 'start bez zatwierdzenia');
  run.requestApproval();
  await rejects<StateError>(
      () => run.approve(
          principalId: 'intruder', permissions: {AgentPermission.modelQuery}),
      'podszycie właściciela');
  run.approve(principalId: 'owner', permissions: {AgentPermission.modelQuery});
  run.start();
  for (var i = 0; i < 3; i++) {
    run.submitForReview();
    await rejects<StateError>(
        () => run.review(
            reviewerId: 'executor', accepted: true, reason: 'Samokontrola'),
        'brak niezależnego kontrolera');
    run.review(reviewerId: 'controller', accepted: false, reason: 'SPOILER');
    if (i < 2) run.start();
  }
  check(run.state == AgentRunState.failed && run.corrections == 2,
      'najwyżej dwie korekty');
  check(!run.events.any((event) => event.reason.contains('SPOILER')),
      'brak sekretów w audit logu');

  final campaign = CampaignJournal(CampaignManifest(
      id: 'a',
      ownerId: 'owner',
      name: 'Test',
      edition: 'WFRP 4e',
      createdAt: now));
  campaign.put(secret, gm, expectedRevision: 0);
  check(campaign.read(player, MemoryPurpose.export).isEmpty,
      'eksport kampanii bez spoilerów');
  campaign.rollback(0, gm, expectedRevision: 1);
  check(
      campaign.revision == 2 &&
          campaign.read(gm, MemoryPurpose.modelContext).isEmpty,
      'audytowalny rollback');
  const bridge = DisabledJarvisBridge();
  await rejects<JarvisBridgeUnavailable>(
      () => bridge.delegateApprovedTask('run'), 'wyłączony most');

  final backup = EncryptedBackup();
  const passphrase = 'Unikalna testowa fraza backupu!';
  const plaintext = 'Zażółć gęślą jaźń: prywatne dane.';
  final envelope = await backup.encrypt(utf8.encode(plaintext), passphrase);
  check(!envelope.contains(plaintext), 'szyfrogram bez jawnej treści');
  check(utf8.decode(await backup.decrypt(envelope, passphrase)) == plaintext,
      'AES-GCM PBKDF2 roundtrip');
  final decoded = jsonDecode(envelope) as Map<String, dynamic>;
  final second =
      jsonDecode(await backup.encrypt(utf8.encode(plaintext), passphrase))
          as Map<String, dynamic>;
  check(
      second['nonce'] != decoded['nonce'] && second['salt'] != decoded['salt'],
      'losowy nonce i sól');
  final ciphertext = base64Decode(decoded['ciphertext'] as String);
  ciphertext[0] ^= 1;
  decoded['ciphertext'] = base64Encode(ciphertext);
  await rejects<BackupException>(() async {
    await backup.decrypt(jsonEncode(decoded), passphrase);
  }, 'zmodyfikowany szyfrogram');
  await rejects<BackupException>(() async {
    await backup.decrypt(envelope, 'Inne długie hasło testowe');
  }, 'nieprawidłowe hasło');
  await rejects<BackupException>(() async {
    await backup.decrypt('{"version":99}', passphrase);
  }, 'nieznana wersja');
  stdout.writeln(
      'PASS: $_passed niezależnych kontroli domeny/kryptografii. Bez sieci i Flutter engine.');
}
