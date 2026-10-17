/// Domain-only authorization. Contexts must be built by trusted application code,
/// never by parsing instructions, model output, document metadata or chat text.
enum AccessRole { owner, trustedUser, guest, rpgPlayer, gameMaster }

enum MemoryVisibility { private, shared, campaign, gmSecret }

enum MemoryApproval { pending, approved, rejected }

enum MemoryPurpose {
  localView,
  modelContext,
  reviewerContext,
  retrievalIndex,
  export
}

class AccessContext {
  const AccessContext({
    required this.principalId,
    required this.role,
    this.projectId,
    this.campaignId,
    this.allowGmSecretContext = false,
    this.allowPersonalDataToReviewer = false,
  });

  final String principalId;
  final AccessRole role;
  final String? projectId;
  final String? campaignId;
  final bool allowGmSecretContext;
  final bool allowPersonalDataToReviewer;
}

class MemoryRecord {
  MemoryRecord({
    required this.id,
    required this.ownerId,
    required this.authorId,
    required this.createdAt,
    required this.source,
    required this.content,
    required this.visibility,
    required this.approval,
    this.projectId,
    this.campaignId,
    this.confidence = 0,
    this.version = 1,
    this.personalData = false,
    Set<String> sharedWith = const {},
    List<String> links = const [],
  })  : sharedWith = Set.unmodifiable(sharedWith),
        links = List.unmodifiable(links) {
    if (id.isEmpty ||
        ownerId.isEmpty ||
        authorId.isEmpty ||
        version < 1 ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1) {
      throw ArgumentError('Nieprawidłowe metadane pamięci.');
    }
    if ((visibility == MemoryVisibility.gmSecret ||
            visibility == MemoryVisibility.campaign) &&
        (campaignId == null || campaignId!.isEmpty)) {
      throw ArgumentError('Treść kampanii wymaga identyfikatora kampanii.');
    }
  }

  final String id;
  final String ownerId;
  final String authorId;
  final DateTime createdAt;
  final String source;
  final String content;
  final MemoryVisibility visibility;
  final MemoryApproval approval;
  final String? projectId;
  final String? campaignId;
  final double confidence;
  final int version;
  final bool personalData;
  final Set<String> sharedWith;
  final List<String> links;
}

class MemoryAccessPolicy {
  const MemoryAccessPolicy();

  bool permits(
    MemoryRecord record,
    AccessContext context,
    MemoryPurpose purpose,
  ) {
    if (context.principalId.isEmpty) return false;
    // Scope is checked before role/ownership; an owner must select the campaign.
    if (record.projectId != context.projectId ||
        record.campaignId != context.campaignId) {
      return false;
    }
    if (record.visibility == MemoryVisibility.gmSecret) {
      if (purpose == MemoryPurpose.reviewerContext ||
          purpose == MemoryPurpose.retrievalIndex ||
          purpose == MemoryPurpose.export) {
        return false;
      }
      return context.role == AccessRole.gameMaster &&
          context.principalId == record.ownerId &&
          context.allowGmSecretContext &&
          record.approval == MemoryApproval.approved;
    }
    if (purpose != MemoryPurpose.localView &&
        record.approval != MemoryApproval.approved) {
      return false;
    }
    if (record.approval == MemoryApproval.rejected) return false;
    if (record.personalData &&
        purpose == MemoryPurpose.reviewerContext &&
        !context.allowPersonalDataToReviewer) {
      return false;
    }
    if (context.principalId == record.ownerId) return true;
    if (record.approval != MemoryApproval.approved) return false;
    if (record.visibility == MemoryVisibility.private) return false;
    return record.sharedWith.contains(context.principalId);
  }

  /// Filter BEFORE retrieval/scoring, prompt building, logging or serialization.
  List<MemoryRecord> select(
    Iterable<MemoryRecord> records,
    AccessContext context,
    MemoryPurpose purpose,
  ) =>
      List.unmodifiable(
        records.where((record) => permits(record, context, purpose)),
      );
}

/// A channel identity is resolved only from a transport-authenticated subject.
/// Display names and user-supplied IDs never participate in authorization.
class ChannelIdentityDirectory {
  ChannelIdentityDirectory(Map<String, String> verifiedMappings)
      : _verifiedMappings = Map.unmodifiable(verifiedMappings);

  final Map<String, String> _verifiedMappings;

  static String mappingKey(String channel, String authenticatedSubject) =>
      '${channel.length}:$channel${authenticatedSubject.length}:$authenticatedSubject';

  String? resolve({
    required String channel,
    required String authenticatedSubject,
  }) {
    if (channel.isEmpty || authenticatedSubject.isEmpty) return null;
    return _verifiedMappings[mappingKey(channel, authenticatedSubject)];
  }
}

/// Retrieved text is data; it cannot grant a role, consent or a tool capability.
class UntrustedSource {
  const UntrustedSource(this.text, {required this.sourceId});
  final String text;
  final String sourceId;
  bool get mayGrantPermissions => false;
}
