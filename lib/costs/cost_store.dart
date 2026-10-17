import 'package:sqflite/sqlite_api.dart';

/// Minimalny port polityki kosztów; niezależny od Fluttera i magazynu kluczy.
abstract interface class CostStore {
  Database get db;
  Future<T> setting<T>(String key, T fallback);
}
