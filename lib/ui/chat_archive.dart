import 'package:flutter/material.dart';
import '../storage/app_database.dart';
import '../storage/models.dart';

/// Archiwum jest stronicowane, niezależnie od wielkości rozmowy na dysku.
class ChatArchive extends StatefulWidget {
  const ChatArchive(
      {super.key,
      required this.store,
      required this.conversationId,
      required this.confidential});
  final AppDatabase store;
  final String conversationId;
  final bool confidential;
  @override
  State<ChatArchive> createState() => _ChatArchiveState();
}

class _ChatArchiveState extends State<ChatArchive> {
  int offset = 0;
  late Future<List<Message>> page;
  void load() {
    page =
        widget.store.messages(widget.conversationId, limit: 40, offset: offset);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Archiwum rozmowy')),
      body: FutureBuilder<List<Message>>(
          future: page,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                  child:
                      Text('Nie odczytano strony. Wróć i spróbuj ponownie.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final messages = snapshot.data!;
            return Column(children: [
              Wrap(spacing: 12, children: [
                TextButton(
                    onPressed: offset == 0
                        ? null
                        : () => setState(() {
                              offset -= 40;
                              load();
                            }),
                    child: const Text('Poprzednie')),
                Text('Od ${offset + 1}'),
                TextButton(
                    onPressed: messages.length < 40
                        ? null
                        : () => setState(() {
                              offset += 40;
                              load();
                            }),
                    child: const Text('Następne'))
              ]),
              Expanded(
                  child: ListView.builder(
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final m = messages[i];
                        return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${m.role} · ${m.provider} · ${m.status}'),
                                  if (widget.confidential)
                                    Text(m.text)
                                  else
                                    SelectableText(m.text)
                                ]));
                      }))
            ]);
          }));
}
