import 'package:flutter_test/flutter_test.dart';
import 'package:scalajaca/agents/agent_run.dart';
import 'package:scalajaca/costs/budget_guard.dart';
import 'package:scalajaca/optional_jarvis_bridge/jarvis_bridge.dart';

BudgetGuard guard({
  DateTime Function()? now,
  int calls = 4,
  int steps = 3,
  int daily = 100,
  int monthly = 200,
  int perRun = 100,
  Iterable<CostEntry> entries = const [],
}) =>
    BudgetGuard(
      limits: BudgetLimits(
        maxCalls: calls,
        maxSteps: steps,
        maxDuration: const Duration(minutes: 1),
        maxRunMicros: perRun,
        dailyMicros: daily,
        monthlyMicros: monthly,
      ),
      now: now,
      priorEntries: entries,
    );

AgentRun agent() => AgentRun(
      AgentPlan(
        id: 'job',
        ownerId: 'owner',
        goal: 'Opracuj plan',
        steps: ['Analiza', 'Recenzja'],
        permissions: {AgentPermission.selectedMemoryRead},
      ),
    );

void approveAndStart(AgentRun run) {
  run.requestApproval();
  run.approve(
    principalId: 'owner',
    permissions: {AgentPermission.selectedMemoryRead},
  );
  run.start();
}

void main() {
  test('Płatne wywołanie wymaga uprzedniej zgody i górnej rezerwy', () {
    final g = guard()..begin('job');
    expect(
      () => g.reserveCall('job', paid: true, maximumChargeMicros: 10),
      throwsA(isA<BudgetExceeded>()),
    );
    g.begin('approved', paidApproved: true);
    expect(
      () => g.reserveCall('approved', paid: true),
      throwsA(isA<BudgetExceeded>()),
    );
    expect(
      () => g.reserveCall('approved', paid: true, maximumChargeMicros: 0),
      throwsA(isA<BudgetExceeded>()),
    );
    expect(
      () => g.reserveCall('approved', paid: false, maximumChargeMicros: 1),
      throwsA(isA<BudgetExceeded>()),
    );
    expect(g.pending, isEmpty);
  });

  test(
    'Równoległe rezerwy nie przekraczają dnia; brak usage zużywa całą rezerwę',
    () {
      final g = guard()
        ..begin('a', paidApproved: true)
        ..begin('b', paidApproved: true);
      final a = g.reserveCall('a', paid: true, maximumChargeMicros: 60);
      expect(
        () => g.reserveCall('b', paid: true, maximumChargeMicros: 41),
        throwsA(isA<BudgetExceeded>()),
      );
      final b = g.reserveCall('b', paid: true, maximumChargeMicros: 40);
      g.commit(a);
      g.commit(b, actualChargeMicros: 30);
      expect(g.entries.fold<int>(0, (sum, e) => sum + e.amountMicros), 90);
      expect(() => g.commit(a), throwsA(isA<BudgetExceeded>()));
    },
  );

  test('Budżet miesiąca obejmuje historię z innych dni', () {
    final now = DateTime.utc(2026, 10, 17);
    final g = guard(
      now: () => now,
      daily: 100,
      monthly: 100,
      entries: [
        CostEntry(
          runId: 'prior',
          amountMicros: 90,
          reservedAt: DateTime.utc(2026, 10, 1),
          committedAt: DateTime.utc(2026, 10, 1),
        ),
      ],
    )..begin('job', paidApproved: true);
    expect(
      () => g.reserveCall('job', paid: true, maximumChargeMicros: 11),
      throwsA(isA<BudgetExceeded>()),
    );
    expect(
      g.reserveCall('job', paid: true, maximumChargeMicros: 10).maximumMicros,
      10,
    );
  });

  test('Twarde limity kroków, wywołań, czasu i cofnięcie zegara', () {
    var now = DateTime.utc(2026, 10, 17);
    final g = guard(now: () => now, calls: 1, steps: 1)..begin('job');
    g.step('job');
    expect(() => g.step('job'), throwsA(isA<BudgetExceeded>()));
    g.commit(g.reserveCall('job', paid: false));
    expect(
      () => g.reserveCall('job', paid: false),
      throwsA(isA<BudgetExceeded>()),
    );
    g.begin('clock');
    now = now.add(const Duration(minutes: 1));
    expect(() => g.step('clock'), throwsA(isA<BudgetExceeded>()));
    g.begin('backward');
    now = now.subtract(const Duration(seconds: 1));
    expect(() => g.step('backward'), throwsA(isA<BudgetExceeded>()));
  });

  test(
    'Zatrzymanie zachowuje rezerwę; nadmiarowy rachunek blokuje zadanie',
    () {
      final g = guard()..begin('job', paidApproved: true);
      final reservation = g.reserveCall(
        'job',
        paid: true,
        maximumChargeMicros: 30,
      );
      g.stop('job');
      expect(g.reservedMicros, 30);
      expect(
        () => g.reserveCall('job', paid: true, maximumChargeMicros: 1),
        throwsA(isA<BudgetExceeded>()),
      );
      g.commit(reservation);
      g.begin('over', paidApproved: true);
      final over = g.reserveCall('over', paid: true, maximumChargeMicros: 10);
      expect(
        () => g.commit(over, actualChargeMicros: 11),
        throwsA(isA<BudgetExceeded>()),
      );
      expect(g.entries.last.amountMicros, 11);
      expect(() => g.step('over'), throwsA(isA<BudgetExceeded>()));
    },
  );

  test(
    'Potwierdzony brak wysłania zwalnia rezerwę, nie przywraca liczby wywołań',
    () {
      final g = guard(calls: 1)..begin('job', paidApproved: true);
      final reservation = g.reserveCall(
        'job',
        paid: true,
        maximumChargeMicros: 30,
      );
      g.releaseUnsent(reservation);
      expect(g.reservedMicros, 0);
      expect(
        () => g.reserveCall('job', paid: true, maximumChargeMicros: 30),
        throwsA(isA<BudgetExceeded>()),
      );
    },
  );

  test(
    'Nie można pominąć planu, podszyć się pod właściciela ani rozszerzyć zgody',
    () {
      final run = agent();
      expect(run.start, throwsStateError);
      run.requestApproval();
      expect(
        () => run.approve(
          principalId: 'intruder',
          permissions: {AgentPermission.selectedMemoryRead},
        ),
        throwsStateError,
      );
      expect(
        () => run.approve(
          principalId: 'owner',
          permissions: {
            AgentPermission.selectedMemoryRead,
            AgentPermission.sendMessage,
          },
        ),
        throwsStateError,
      );
      run.approve(
        principalId: 'owner',
        permissions: {AgentPermission.selectedMemoryRead},
      );
      run.start();
      expect(run.permits(AgentPermission.selectedMemoryRead), isTrue);
      expect(run.permits(AgentPermission.sendMessage), isFalse);
      run.cancel();
      expect(run.permits(AgentPermission.selectedMemoryRead), isFalse);
      expect(run.start, throwsStateError);
    },
  );

  test('Niezależny kontroler i najwyżej dwie korekty', () {
    final run = agent();
    approveAndStart(run);
    for (var i = 0; i < 3; i++) {
      run.submitForReview();
      expect(
        () => run.review(
          reviewerId: 'executor',
          accepted: true,
          reason: 'Samokontrola',
        ),
        throwsStateError,
      );
      run.review(
        reviewerId: 'controller',
        accepted: false,
        reason: 'Popraw wymaganie.',
      );
      if (i < 2) run.start();
    }
    expect(run.corrections, 2);
    expect(run.state, AgentRunState.failed);
    expect(run.requestResume, throwsStateError);
  });

  test(
    'Dziennik stanów agentów nie utrwala surowego sekretu z uzasadnienia',
    () {
      final run = agent();
      approveAndStart(run);
      run.submitForReview();
      run.review(
        reviewerId: 'controller',
        accepted: false,
        reason: 'GM_SECRET: SPOILER',
      );
      expect(
        run.events.any((event) => event.reason.contains('SPOILER')),
        isFalse,
      );
      run.start();
      run.fail('sk-sekret-klucza');
      expect(
        run.events.any((event) => event.reason.contains('sk-sekret')),
        isFalse,
      );
    },
  );

  test('Wznowienie po błędzie wymaga ponownego zatwierdzenia', () {
    final run = agent();
    approveAndStart(run);
    run.fail('Brak połączenia.');
    run.requestResume();
    expect(run.state, AgentRunState.awaitingApproval);
    expect(run.start, throwsStateError);
    run.approve(
      principalId: 'owner',
      permissions: {AgentPermission.selectedMemoryRead},
    );
    run.start();
    run.submitForReview();
    run.review(
      reviewerId: 'controller',
      accepted: true,
      reason: 'Wynik zweryfikowano.',
    );
    expect(run.state, AgentRunState.completed);
  });

  test('Opcjonalny most JARVIS jest domyślnie wyłączony i odwołalny', () async {
    const bridge = DisabledJarvisBridge();
    expect(bridge.status, JarvisBridgeStatus.disabled);
    expect(bridge.grantedPermissions, isEmpty);
    await expectLater(
      bridge.delegateApprovedTask('job'),
      throwsA(isA<JarvisBridgeUnavailable>()),
    );
    await expectLater(
      bridge.synchronizeSelectedNotes(['note']),
      throwsA(isA<JarvisBridgeUnavailable>()),
    );
    await bridge.disconnectAndRevoke();
    expect(bridge.status, JarvisBridgeStatus.disabled);
  });
}
