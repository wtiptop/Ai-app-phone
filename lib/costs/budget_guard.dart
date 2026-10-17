/// Amounts are integer micro-units of one currency (default: USD). Never mix
/// currencies. The caller must set provider token/output limits consistent with
/// maximumChargeMicros; an estimate alone is not a maximum reservation.
class BudgetLimits {
  const BudgetLimits({
    this.maxSteps = 8,
    this.maxCalls = 4,
    this.maxDuration = const Duration(minutes: 2),
    this.maxRunMicros = 0,
    this.dailyMicros = 0,
    this.monthlyMicros = 0,
    this.currency = 'USD',
  });
  final int maxSteps;
  final int maxCalls;
  final Duration maxDuration;
  final int maxRunMicros;
  final int dailyMicros;
  final int monthlyMicros;
  final String currency;
}

class BudgetExceeded implements Exception {
  const BudgetExceeded(this.message);
  final String message;
  @override
  String toString() => 'BudgetExceeded: $message';
}

class CostReservation {
  CostReservation._(this.id, this.runId, this.maximumMicros, this.createdAt);
  final int id;
  final String runId;
  final int maximumMicros;
  final DateTime createdAt;
}

class CostEntry {
  const CostEntry({
    required this.runId,
    required this.amountMicros,
    required this.reservedAt,
    required this.committedAt,
  });
  final String runId;
  final int amountMicros;
  final DateTime reservedAt;
  final DateTime committedAt;
}

class _Run {
  _Run(this.startedAt, this.paidApproved) : watch = Stopwatch()..start();
  final DateTime startedAt;
  final bool paidApproved;
  final Stopwatch watch;
  int steps = 0;
  int calls = 0;
  int committedMicros = 0;
  bool stopped = false;
}

/// Fail-closed, synchronous reservation prevents concurrent overbooking inside
/// one isolate. Persist the ledger and unresolved reservations atomically BEFORE
/// sending a paid request. This domain object alone is not durable storage.
class BudgetGuard {
  BudgetGuard({
    required this.limits,
    DateTime Function()? now,
    Iterable<CostEntry> priorEntries = const [],
  })  : _now = now ?? DateTime.now,
        _entries = List.of(priorEntries) {
    if (limits.maxSteps < 1 ||
        limits.maxCalls < 1 ||
        limits.maxDuration <= Duration.zero ||
        limits.maxRunMicros < 0 ||
        limits.dailyMicros < 0 ||
        limits.monthlyMicros < 0 ||
        limits.currency.isEmpty ||
        _entries.any((e) => e.amountMicros < 0)) {
      throw ArgumentError('Nieprawidłowe limity budżetu.');
    }
  }

  final BudgetLimits limits;
  final DateTime Function() _now;
  final List<CostEntry> _entries;
  final Map<String, _Run> _runs = {};
  final Map<int, CostReservation> _reservations = {};
  int _sequence = 0;
  List<CostEntry> get entries => List.unmodifiable(_entries);
  List<CostReservation> get pending => List.unmodifiable(_reservations.values);

  void begin(String runId, {bool paidApproved = false}) {
    if (runId.isEmpty || _runs.containsKey(runId)) {
      throw const BudgetExceeded(
        'Identyfikator zadania jest pusty lub już istnieje.',
      );
    }
    _runs[runId] = _Run(_now().toUtc(), paidApproved);
  }

  _Run _active(String runId) {
    final run = _runs[runId];
    if (run == null || run.stopped) {
      throw const BudgetExceeded('Zadanie nie jest aktywne.');
    }
    final elapsed = _now().toUtc().difference(run.startedAt);
    if (elapsed.isNegative ||
        elapsed >= limits.maxDuration ||
        run.watch.elapsed >= limits.maxDuration) {
      run.stopped = true;
      throw const BudgetExceeded(
        'Przekroczono czas zadania lub zmieniono zegar.',
      );
    }
    return run;
  }

  void step(String runId) {
    final run = _active(runId);
    if (run.steps >= limits.maxSteps) {
      throw const BudgetExceeded('Przekroczono limit kroków.');
    }
    run.steps++;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  int _spent(DateTime now, bool monthly) => _entries.where((entry) {
        final same = monthly ? _sameMonth : _sameDay;
        // Requests spanning a boundary count in both periods, conservatively.
        return same(entry.reservedAt, now) || same(entry.committedAt, now);
      }).fold(0, (sum, entry) => sum + entry.amountMicros);

  int get reservedMicros => _reservations.values.fold(
        0,
        (sum, reservation) => sum + reservation.maximumMicros,
      );

  CostReservation reserveCall(
    String runId, {
    required bool paid,
    int? maximumChargeMicros,
  }) {
    final run = _active(runId);
    if (run.calls >= limits.maxCalls) {
      throw const BudgetExceeded('Przekroczono limit wywołań.');
    }
    if (paid &&
        (!run.paidApproved ||
            maximumChargeMicros == null ||
            maximumChargeMicros <= 0)) {
      throw const BudgetExceeded(
        'Płatne wywołanie wymaga zgody i jawnej górnej rezerwy kosztu.',
      );
    }
    if (!paid && maximumChargeMicros != null && maximumChargeMicros != 0) {
      throw const BudgetExceeded(
        'Bezpłatne wywołanie nie może rezerwować opłaty.',
      );
    }
    final amount = maximumChargeMicros ?? 0;
    final now = _now().toUtc();
    final runReserved = _reservations.values
        .where((r) => r.runId == runId)
        .fold(0, (sum, r) => sum + r.maximumMicros);
    if (run.committedMicros + runReserved + amount > limits.maxRunMicros ||
        _spent(now, false) + reservedMicros + amount > limits.dailyMicros ||
        _spent(now, true) + reservedMicros + amount > limits.monthlyMicros) {
      throw const BudgetExceeded(
        'Przekroczono budżet zadania, dnia lub miesiąca.',
      );
    }
    final reservation = CostReservation._(++_sequence, runId, amount, now);
    _reservations[reservation.id] = reservation;
    run.calls++;
    return reservation;
  }

  /// Missing provider usage: charge the FULL reserve; never silently refund it.
  void commit(CostReservation reservation, {int? actualChargeMicros}) {
    final current = _reservations[reservation.id];
    if (!identical(current, reservation)) {
      throw const BudgetExceeded('Nieprawidłowa lub już rozliczona rezerwa.');
    }
    final actual = actualChargeMicros ?? reservation.maximumMicros;
    if (actual < 0) {
      throw const BudgetExceeded('Ujemny koszt jest niedozwolony.');
    }
    final run = _runs[reservation.runId]!;
    _entries.add(
      CostEntry(
        runId: reservation.runId,
        amountMicros: actual,
        reservedAt: reservation.createdAt,
        committedAt: _now().toUtc(),
      ),
    );
    run.committedMicros += actual;
    _reservations.remove(reservation.id);
    if (actual > reservation.maximumMicros) {
      run.stopped = true;
      throw const BudgetExceeded(
        'Dostawca przekroczył rezerwę; zablokowano dalsze wywołania.',
      );
    }
  }

  /// Allowed only when transport proves the request was never sent. Network
  /// timeouts/cancellation after dispatch must commit the full reserve instead.
  void releaseUnsent(CostReservation reservation) {
    if (!identical(_reservations[reservation.id], reservation)) {
      throw const BudgetExceeded('Nieprawidłowa rezerwa.');
    }
    _reservations.remove(reservation.id);
  }

  /// Stop never refunds in-flight reservations: providers may still charge.
  void stop(String runId) {
    final run = _runs[runId];
    if (run != null) run.stopped = true;
  }
}
