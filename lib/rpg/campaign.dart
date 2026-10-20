import '../security/memory_access.dart';

enum LoreAuthority { approvedCampaignCanon, officialEdition, supplementary }

enum LoreVerification { unverified, verified }

class LoreCitation {
  const LoreCitation({
    required this.sourceId,
    required this.title,
    required this.authority,
    required this.edition,
    this.page,
    this.userVerified = false,
  });
  final String sourceId;
  final String title;
  final LoreAuthority authority;
  final String edition;
  final String? page;
  final bool userVerified;

  LoreVerification get verification => userVerified &&
          sourceId.trim().isNotEmpty &&
          title.trim().isNotEmpty &&
          page != null &&
          page!.trim().isNotEmpty
      ? LoreVerification.verified
      : LoreVerification.unverified;
}

class LorePolicy {
  const LorePolicy();
  List<LoreCitation> prioritize(
    Iterable<LoreCitation> citations, {
    required String edition,
  }) {
    final eligible = citations
        .where(
          (citation) =>
              citation.verification == LoreVerification.verified &&
              (citation.authority != LoreAuthority.officialEdition ||
                  citation.edition == edition),
        )
        .toList()
      ..sort((a, b) => a.authority.index.compareTo(b.authority.index));
    return List.unmodifiable(eligible);
  }
}

const rpgRoles = <String>[
  'Główny MG',
  'Koordynator czasu i świata',
  'Sędzia mechaniki',
  'Agent drużyny',
  'Agent ważnych NPC',
  'Agent frakcji',
  'Agent wątków',
  'Agent ekwipunku',
  'Agent walki',
  'Agent lokacji',
  'Agent ciągłości',
  'Agent ilustracji (asynchroniczny)',
];

const loreControlRoles = <String>[
  'Koordynator lore',
  'Weryfikator oficjalnego kanonu i podręczników',
  'Weryfikator chronologii i geografii',
  'Weryfikator frakcji i kultur',
  'Weryfikator bestiariusza i magii',
  'Weryfikator lokalnego kanonu kampanii',
  'Niezależny kontroler źródeł i stron',
];

class CampaignManifest {
  CampaignManifest({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.edition,
    required this.createdAt,
    this.schemaVersion = 1,
    this.requiresVerifiedImport = false,
    List<String> verifiedCanonSourceIds = const [],
  }) : verifiedCanonSourceIds = List.unmodifiable(verifiedCanonSourceIds) {
    if (id.isEmpty ||
        ownerId.isEmpty ||
        name.isEmpty ||
        edition.isEmpty ||
        schemaVersion != 1 ||
        (requiresVerifiedImport && verifiedCanonSourceIds.isEmpty)) {
      throw ArgumentError(
        'Kampania wymaga własnego manifestu i zweryfikowanego kanonu importu.',
      );
    }
  }
  final String id;
  final String ownerId;
  final String name;
  final String edition;
  final DateTime createdAt;
  final int schemaVersion;
  final bool requiresVerifiedImport;
  final List<String> verifiedCanonSourceIds;

  Map<String, Object> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'ownerId': ownerId,
        'name': name,
        'edition': edition,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'verifiedCanonSourceIds': verifiedCanonSourceIds,
      };
}

class CampaignRevision {
  const CampaignRevision(this.number, this.at, this.kind);
  final int number;
  final DateTime at;
  final String kind;
}

/// Isolated, auditable in-memory aggregate. Storage persistence is separate.
/// No narration or decision for a player's character is performed here.
class CampaignJournal {
  CampaignJournal(this.manifest, {DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final CampaignManifest manifest;
  final DateTime Function() _now;
  final _policy = const MemoryAccessPolicy();
  final List<CampaignRevision> _revisions = [];
  final List<Map<String, MemoryRecord>> _snapshots = [{}];
  int get revision => _revisions.length;

  void _authorize(AccessContext context) {
    if (context.principalId != manifest.ownerId ||
        context.role != AccessRole.gameMaster ||
        context.campaignId != manifest.id) {
      throw StateError('Zmiana świata wymaga uprawnień MG właściwej kampanii.');
    }
  }

  void _checkRevision(int expectedRevision) {
    if (expectedRevision != revision) {
      throw StateError('Konflikt rewizji; odczytaj aktualny stan kampanii.');
    }
  }

  void put(
    MemoryRecord record,
    AccessContext context, {
    required int expectedRevision,
  }) {
    _authorize(context);
    _checkRevision(expectedRevision);
    if (record.ownerId != manifest.ownerId ||
        record.campaignId != manifest.id ||
        record.projectId != context.projectId) {
      throw StateError(
        'Nie można mieszać właścicieli, projektów ani kampanii.',
      );
    }
    final prior = _snapshots.last[record.id];
    if (record.version != (prior?.version ?? 0) + 1) {
      throw StateError('Nieciągła wersja rekordu kampanii.');
    }
    final next = Map<String, MemoryRecord>.from(_snapshots.last)
      ..[record.id] = record;
    _snapshots.add(Map.unmodifiable(next));
    _revisions.add(
      CampaignRevision(revision + 1, _now().toUtc(), 'recordUpdated'),
    );
  }

  void rollback(
    int targetRevision,
    AccessContext context, {
    required int expectedRevision,
  }) {
    _authorize(context);
    _checkRevision(expectedRevision);
    if (targetRevision < 0 || targetRevision > revision) {
      throw RangeError('Nieprawidłowa rewizja docelowa.');
    }
    _snapshots.add(Map.unmodifiable(_snapshots[targetRevision]));
    _revisions.add(CampaignRevision(revision + 1, _now().toUtc(), 'rollback'));
  }

  List<CampaignRevision> audit(AccessContext context) {
    _authorize(context);
    return List.unmodifiable(_revisions);
  }

  List<MemoryRecord> read(AccessContext context, MemoryPurpose purpose) {
    if (context.campaignId != manifest.id) return const [];
    return _policy.select(_snapshots.last.values, context, purpose);
  }
}

/// The actual k100/PS mechanics need user-provided official rules; no invented
/// talents or hidden campaign facts are bundled in this profile.
const wfrp4eProfile = <String, Object>{
  'id': 'wfrp4e',
  'edition': 'WFRP 4e',
  'dice': 'k100',
  'successMetric': 'PS',
  'rulesStatus': 'wymaga zweryfikowanych materiałów',
  'autoStartCampaign': false,
  'playerDecisionsBelongToPlayer': true,
};
