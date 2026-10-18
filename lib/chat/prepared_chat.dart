import 'dart:convert';
import '../memory/context_packet.dart';
import '../provider_registry/provider_adapter.dart';

class PreparedChat {
  PreparedChat(
      {required this.provider,
      required this.model,
      required this.userText,
      required Iterable<ChatTurn> turns,
      required this.digest,
      required this.sessionVersion,
      required this.omitted,
      required this.maxOutputTokens,
      this.attachment})
      : turns = List.unmodifiable(turns);
  final String provider, model, userText, digest;
  final List<ChatTurn> turns;
  final int sessionVersion, omitted, maxOutputTokens;
  final ContextAttachment? attachment;
  Future<String> calculateDigest(String? scope) => contentDigest(jsonEncode({
        'provider': provider,
        'model': model,
        'scope': scope,
        'output': maxOutputTokens,
        'turns': [
          for (final t in turns) {'role': t.role.name, 'text': t.text}
        ]
      }));
  String get preview =>
      turns.map((t) => '${t.role.name}: ${t.text}').join('\n\n');
  String get receipt => jsonEncode({
        'format': 'scalajaca.context-receipt.v1',
        'digest': digest,
        'omittedMessages': omitted,
        'attachment': attachment?.receipt,
        'sourceSnapshot': attachment?.text
      });
}
