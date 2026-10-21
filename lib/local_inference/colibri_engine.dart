import 'dart:convert';

import 'package:flutter/services.dart';
import '../provider_registry/provider_adapter.dart';
import 'android_local_engine.dart';
import 'local_adapter.dart';
import 'local_engine.dart';

ProviderException colibriError(String code) {
  final message = switch (code) {
    'missing_model' =>
      'Zainstaluj paczkę Colibri w Ustawienia → Dostawcy → Colibri offline.',
    'invalid_package' =>
      'Nieprawidłowa lub niepełna paczka Colibri. Wymagany ZIP z manifestem i sumami plików.',
    'unsupported_model' =>
      'Port obsługuje OLMoE Instruct w scalonym formacie Colibri. GGUF MiniCPM i inne rodziny wymagają osobnych silników.',
    'file_too_large' => 'Paczka przekracza limit 10 GiB rozpakowanych danych.',
    'storage_space' =>
      'Brak miejsca na model i 512 MiB rezerwy. Oryginalny ZIP także zajmuje miejsce.',
    'memory' =>
      'Colibri wymaga co najmniej 4 GiB wolnego RAM przed startem. To próg wstępny, nie gwarancja działania.',
    'model_load' ||
    'protocol' ||
    'interrupted' =>
      'Proces Colibri zakończył pracę lub odrzucił model. Sprawdź zgodność plików. Nie uruchomiono chmury.',
    'reserved_marker' =>
      'Treść zawiera zastrzeżone znaczniki OLMoE. Ten port nie może bezpiecznie przesłać ich jako tekstu. Wybierz inny silnik lokalny.',
    _ => localError(code).message,
  };
  return ProviderException(code, message);
}

/// Szablon aplikacji zgodny z OLMoE Instruct; nie wykonuje kodu z modelu.
Uint8List renderOlmoe(List<ChatTurn> turns) {
  for (final turn in turns) {
    if (['|||IP_ADDRESS|||', '<|system|>', '<|user|>', '<|assistant|>']
        .any(turn.text.contains)) {
      throw colibriError('reserved_marker');
    }
  }
  final out = StringBuffer('|||IP_ADDRESS|||');
  for (var i = 0; i < turns.length; i++) {
    final turn = turns[i];
    out.write('<|${turn.role.name}|>\n${turn.text}');
    if (turn.role == ChatRole.assistant) {
      out.write('|||IP_ADDRESS|||');
      if (i != turns.length - 1) out.write('\n');
    } else {
      out.write('\n');
    }
  }
  out.write('<|assistant|>\n');
  return Uint8List.fromList(utf8.encode(out.toString()));
}

class AndroidColibriEngine extends AndroidLocalEngine {
  AndroidColibriEngine({MethodChannel? channel})
      : super(
            channel: channel ?? const MethodChannel('pl.scalajaca/colibri'),
            errorForCode: colibriError);
  @override
  Map<String, Object?> generateArguments(List<ChatTurn> turns) =>
      {'prompt': renderOlmoe(turns)};
}

class ColibriAdapter extends LocalModelAdapter {
  ColibriAdapter({required super.engine})
      : super(readContext: () async => 4096);
  @override
  String get id => 'colibri_local';
  @override
  String get label => 'Colibri • offline • eksperymentalny port';
}
