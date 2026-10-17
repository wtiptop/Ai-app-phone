import 'dart:convert';

class SseEvent {
  const SseEvent({required this.data, this.event = 'message'});
  final String data;
  final String event;
}

/// Parser SSE zgodny z granicami wierszy, nie z granicami pakietów HTTP.
/// Obsługuje rozcięte UTF-8, CR/LF, komentarze, BOM i wielowierszowe data.
Stream<SseEvent> decodeSse(Stream<List<int>> bytes) async* {
  var event = 'message';
  final data = <String>[];
  var firstLine = true;
  var size = 0;
  await for (var line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (firstLine) {
      if (line.startsWith('\uFEFF')) {
        line = line.substring(1);
      }
      firstLine = false;
    }
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        yield SseEvent(data: data.join('\n'), event: event);
      }
      data.clear();
      event = 'message';
      size = 0;
      continue;
    }
    if (line.startsWith(':')) {
      continue;
    }
    final separator = line.indexOf(':');
    final field = separator < 0 ? line : line.substring(0, separator);
    var value = separator < 0 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    if (field == 'data') {
      size += value.length;
      if (size > 2 * 1024 * 1024) {
        throw const FormatException('Zbyt duże zdarzenie SSE.');
      }
      data.add(value);
    } else if (field == 'event') {
      event = value;
    }
  }
  // Bez pustego wiersza zdarzenie jest niekompletne i nie jest emitowane.
}
