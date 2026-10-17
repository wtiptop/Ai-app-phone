enum AgentRunState {
  draft,
  awaitingApproval,
  approved,
  running,
  awaitingReview,
  correctionRequired,
  completed,
  cancelled,
  failed,
}

enum AgentPermission {
  selectedMemoryRead,
  modelQuery,
  fileModification,
  sendMessage,
  shareData,
  purchase,
  repositoryModification,
}

class AgentPlan {
  AgentPlan({
    required this.id,
    required this.ownerId,
    required this.goal,
    required List<String> steps,
    Set<AgentPermission> permissions = const {},
    this.maxCorrections = 2,
    this.executorId = 'executor',
    this.controllerId = 'controller',
  })  : steps = List.unmodifiable(steps),
        permissions = Set.unmodifiable(permissions) {
    if (id.isEmpty ||
        ownerId.isEmpty ||
        goal.isEmpty ||
        steps.isEmpty ||
        maxCorrections < 0 ||
        maxCorrections > 2 ||
        executorId.isEmpty ||
        controllerId.isEmpty ||
        executorId == controllerId ||
        ownerId == controllerId) {
      throw ArgumentError(
        'Plan wymaga właściciela, celu, kroków i najwyżej 2 korekt.',
      );
    }
  }
  final String id;
  final String ownerId;
  final String goal;
  final List<String> steps;
  final Set<AgentPermission> permissions;
  final int maxCorrections;
  final String executorId;
  final String controllerId;
}

class AgentEvent {
  const AgentEvent(this.state, this.at, this.reason);
  final AgentRunState state;
  final DateTime at;
  final String reason;
}

/// A plan/consent state machine, NOT an autonomous tool executor. Approval is
/// capability-scoped. Actual external actions need a separate execution gateway.
class AgentRun {
  AgentRun(this.plan, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final AgentPlan plan;
  final DateTime Function() _now;
  AgentRunState _state = AgentRunState.draft;
  int _corrections = 0;
  Set<AgentPermission> _approvedPermissions = const {};
  final List<AgentEvent> _events = [];
  AgentRunState get state => _state;
  int get corrections => _corrections;
  List<AgentEvent> get events => List.unmodifiable(_events);

  void _require(Set<AgentRunState> allowed) {
    if (!allowed.contains(_state)) {
      throw StateError('Niedozwolony stan zadania: ${_state.name}.');
    }
  }

  void _move(AgentRunState next, String reason) {
    _state = next;
    _events.add(AgentEvent(next, _now().toUtc(), reason));
  }

  void requestApproval() {
    _require({AgentRunState.draft});
    _move(AgentRunState.awaitingApproval, 'Plan oczekuje zgody właściciela.');
  }

  void approve({
    required String principalId,
    required Set<AgentPermission> permissions,
  }) {
    _require({AgentRunState.awaitingApproval});
    if (principalId != plan.ownerId ||
        !permissions.containsAll(plan.permissions) ||
        !plan.permissions.containsAll(permissions)) {
      throw StateError(
        'Zgoda musi pochodzić od właściciela i obejmować dokładny zakres planu.',
      );
    }
    _approvedPermissions = Set.unmodifiable(permissions);
    _move(AgentRunState.approved, 'Właściciel zatwierdził plan i zakres.');
  }

  bool permits(AgentPermission permission) =>
      _state == AgentRunState.running &&
      _approvedPermissions.contains(permission);

  void start() {
    _require({AgentRunState.approved, AgentRunState.correctionRequired});
    _move(AgentRunState.running, 'Rozpoczęto zatwierdzony plan.');
  }

  void submitForReview() {
    _require({AgentRunState.running});
    _move(AgentRunState.awaitingReview, 'Wynik oczekuje niezależnej kontroli.');
  }

  void review({
    required String reviewerId,
    required bool accepted,
    required String reason,
  }) {
    _require({AgentRunState.awaitingReview});
    if (reviewerId != plan.controllerId || reason.trim().isEmpty) {
      throw StateError('Wymagany niezależny kontroler i uzasadnienie.');
    }
    if (accepted) {
      _move(
        AgentRunState.completed,
        'Niezależny kontroler zaakceptował wynik.',
      );
    } else if (_corrections < plan.maxCorrections) {
      _corrections++;
      _move(
        AgentRunState.correctionRequired,
        'Niezależny kontroler wymaga korekty.',
      );
    } else {
      _move(AgentRunState.failed, 'Wyczerpano limit korekt.');
    }
  }

  void cancel() {
    _require({
      AgentRunState.draft,
      AgentRunState.awaitingApproval,
      AgentRunState.approved,
      AgentRunState.running,
      AgentRunState.awaitingReview,
      AgentRunState.correctionRequired,
    });
    _move(AgentRunState.cancelled, 'Właściciel zatrzymał zadanie.');
  }

  void fail(String reason) {
    _require({AgentRunState.running, AgentRunState.awaitingReview});
    if (reason.trim().isEmpty) throw ArgumentError('Wymagany powód błędu.');
    // Audit events intentionally exclude arbitrary model/source/error text.
    _move(AgentRunState.failed, 'Zadanie zakończono błędem.');
  }

  /// Resume requires a new visible approval; permissions are revoked on failure.
  void requestResume() {
    _require({AgentRunState.failed});
    if (_corrections >= plan.maxCorrections) {
      throw StateError('Brak pozostałych iteracji korekty.');
    }
    _approvedPermissions = const {};
    _move(
      AgentRunState.awaitingApproval,
      'Wznowienie wymaga ponownego zatwierdzenia.',
    );
  }
}
