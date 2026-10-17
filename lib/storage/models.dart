class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.updated,
    this.draft = '',
    this.pinned = false,
  });
  final String id, title, draft;
  final DateTime updated;
  final bool pinned;
}

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.text,
    this.provider = 'demo',
    this.model = 'demo-local',
    this.status = 'complete',
    this.inputTokens,
    this.outputTokens,
  });
  final String id, conversationId, role, text, provider, model, status;
  final int? inputTokens, outputTokens;
  Message copyWith({
    String? text,
    String? status,
    int? inputTokens,
    int? outputTokens,
  }) =>
      Message(
        id: id,
        conversationId: conversationId,
        role: role,
        text: text ?? this.text,
        provider: provider,
        model: model,
        status: status ?? this.status,
        inputTokens: inputTokens ?? this.inputTokens,
        outputTokens: outputTokens ?? this.outputTokens,
      );
}

class LocalNote {
  const LocalNote({
    required this.id,
    required this.title,
    required this.text,
    required this.folder,
    required this.updated,
  });
  final String id, title, text, folder;
  final DateTime updated;
}

String newId() => '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
int _sequence = 0;

const memoryFolders = [
  'SYSTEM',
  'INBOX',
  'PERSONAL',
  'RESEARCH',
  'TECH',
  'FINANCE',
  'GAMING',
  'RPG',
  'COMMUNICATIONS',
  'REVIEWS',
  'ARCHIVE',
];
