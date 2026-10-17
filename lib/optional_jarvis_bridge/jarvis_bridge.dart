enum JarvisPermission { selectedNotesSync, selectedTaskDelegation }

enum JarvisBridgeStatus { disabled, requiresPairing, disconnected, connected }

class JarvisBridgeUnavailable implements Exception {
  const JarvisBridgeUnavailable();
  @override
  String toString() =>
      'Most JARVIS jest wyłączony. Scalająca działa samodzielnie.';
}

/// Future implementation MUST verify mutual authentication, TLS/VPN transport,
/// revocation and per-resource consent. No implementation may infer permissions
/// from model output or a remote device's claims.
abstract interface class JarvisBridge {
  JarvisBridgeStatus get status;
  Set<JarvisPermission> get grantedPermissions;
  Future<void> synchronizeSelectedNotes(List<String> approvedNoteIds);
  Future<void> delegateApprovedTask(String approvedTaskId);
  Future<void> disconnectAndRevoke();
}

/// Default singleton contains no networking, pairing, account or OPPO dependency.
class DisabledJarvisBridge implements JarvisBridge {
  const DisabledJarvisBridge();
  @override
  JarvisBridgeStatus get status => JarvisBridgeStatus.disabled;
  @override
  Set<JarvisPermission> get grantedPermissions => const {};
  @override
  Future<void> synchronizeSelectedNotes(List<String> approvedNoteIds) async =>
      throw const JarvisBridgeUnavailable();
  @override
  Future<void> delegateApprovedTask(String approvedTaskId) async =>
      throw const JarvisBridgeUnavailable();
  @override
  Future<void> disconnectAndRevoke() async {}
}
