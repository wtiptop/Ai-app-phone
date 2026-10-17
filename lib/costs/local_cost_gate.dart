import 'dart:convert';

import '../storage/models.dart';
import 'cost_store.dart';

class RequestPermit {
  RequestPermit._(this.provider, this.model);
  final String provider, model;
  bool _used = false;
  void consume(String provider, String model) {
    if (_used || provider != this.provider || model != this.model) {
      throw StateError('Brak ważnego zatwierdzenia tego zapytania.');
    }
    _used = true;
  }
}

/// Trwałe rezerwy konserwatywne: anulowanie/błąd nie zwraca rezerwy.
/// Cennik podaje właściciel. To nie jest gwarancja limitu na rachunku dostawcy.
class LocalCostGate {
  LocalCostGate(this.store);
  final CostStore store;
  Future<bool> _freeMiniCpm() async =>
      await store.setting('minicpm_self_hosted_free', false) &&
      await store.setting<double>('input_rate_minicpm', -1) == 0 &&
      await store.setting<double>('output_rate_minicpm', -1) == 0;
  Future<double> estimate(String provider, String model, String context) async {
    if (provider == 'demo') return 0;
    final configuredModel = await store.setting('model_$provider', '');
    if (model.isEmpty || configuredModel != model) {
      throw StateError('Ustaw model i jego cennik w Dostawcach.');
    }
    final input = await store.setting<double>('input_rate_$provider', -1);
    final output = await store.setting<double>('output_rate_$provider', -1);
    if (provider == 'minicpm' && await _freeMiniCpm()) return 0;
    if (!input.isFinite ||
        !output.isFinite ||
        input < 0 ||
        output < 0 ||
        input + output <= 0) {
      throw StateError(
        'Brak zweryfikowanego cennika tego modelu. Uzupełnij stawki USD / 1 mln tokenów.',
      );
    }
    return ((utf8.encode(context).length + 8192) * input + 1024 * output) /
        1000000;
  }

  Future<void> reserve(String provider, double amount) async {
    if (provider == 'demo') return;
    await _reserveGroup({provider: amount});
  }

  Future<void> _reserveGroup(Map<String, double> amounts) async {
    if (amounts.containsKey('minicpm') && amounts['minicpm'] == 0) {
      if (!await _freeMiniCpm()) {
        throw StateError('Potwierdź własny serwer MiniCPM bez opłat za API.');
      }
      amounts = Map.of(amounts)..remove('minicpm');
    }
    if (amounts.isEmpty) return;
    if (!await store.setting('paid_enabled', false)) {
      throw StateError('Płatne API jest wyłączone w ustawieniach.');
    }
    final daily = await store.setting<double>('daily_budget', 1);
    final monthly = await store.setting<double>('monthly_budget', 5);
    if (!daily.isFinite || !monthly.isFinite || daily <= 0 || monthly <= 0) {
      throw StateError('Nieprawidłowe lokalne budżety.');
    }
    final now = DateTime.now().toUtc();
    final day = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).millisecondsSinceEpoch;
    final month = DateTime.utc(now.year, now.month).millisecondsSinceEpoch;
    await store.db.transaction((tx) async {
      final rows = await tx.query('cost_reservations');
      double sum(int since) => rows
          .where((r) => (r['created'] as int) >= since)
          .fold(0, (total, r) => total + (r['amount'] as num).toDouble());
      final amount = amounts.values.fold<double>(
        0,
        (total, value) => total + value,
      );
      if (amounts.values.any((v) => !v.isFinite || v <= 0) ||
          !amount.isFinite ||
          !sum(day).isFinite ||
          !sum(month).isFinite ||
          sum(day) + amount > daily ||
          sum(month) + amount > monthly) {
        throw StateError('Przekroczono lokalny budżet dnia lub miesiąca.');
      }
      for (final entry in amounts.entries) {
        await tx.insert('cost_reservations', {
          'id': newId(),
          'amount': entry.value,
          'created': now.millisecondsSinceEpoch,
          'provider': entry.key,
        });
      }
    });
  }

  Future<RequestPermit> authorize(
    String provider,
    String model,
    double amount,
  ) async {
    if (provider == 'minicpm' &&
        amount == 0 &&
        (model.isEmpty || model != await store.setting('model_minicpm', ''))) {
      throw StateError('Skonfiguruj model MiniCPM przed zatwierdzeniem.');
    }
    await reserve(provider, amount);
    return RequestPermit._(provider, model);
  }

  Future<Map<String, RequestPermit>> authorizeMany(
    Map<String, ({String model, double amount})> requests,
  ) async {
    final miniCpm = requests['minicpm'];
    if (miniCpm != null &&
        miniCpm.amount == 0 &&
        (miniCpm.model.isEmpty ||
            miniCpm.model != await store.setting('model_minicpm', ''))) {
      throw StateError('Skonfiguruj model MiniCPM przed zatwierdzeniem.');
    }
    await _reserveGroup({
      for (final e in requests.entries)
        if (e.key != 'demo') e.key: e.value.amount,
    });
    return {
      for (final e in requests.entries)
        e.key: RequestPermit._(e.key, e.value.model),
    };
  }
}
