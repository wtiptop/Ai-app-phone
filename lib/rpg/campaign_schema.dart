import 'package:sqflite/sqflite.dart';

/// Treści i tytuły szyfruje ContentCipher. Indeksy obejmują tylko metadane.
class CampaignSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS rpg_campaigns(
      id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, edition TEXT NOT NULL,
      name TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 0,
      created INTEGER NOT NULL, updated INTEGER NOT NULL)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS rpg_campaign_owner
      ON rpg_campaigns(owner_id, updated DESC, id)''');
    for (final table in ['rpg_records', 'rpg_versions']) {
      await db.execute('''CREATE TABLE IF NOT EXISTS $table(
        campaign_id TEXT NOT NULL REFERENCES rpg_campaigns(id),
        record_id TEXT NOT NULL, revision INTEGER NOT NULL,
        kind TEXT NOT NULL, visibility TEXT NOT NULL, approved INTEGER NOT NULL,
        authority INTEGER NOT NULL, edition TEXT NOT NULL,
        payload TEXT NOT NULL,
        PRIMARY KEY(campaign_id, record_id${table == 'rpg_versions' ? ', revision' : ''}))''');
    }
    await db.execute('''CREATE INDEX IF NOT EXISTS rpg_record_scope
      ON rpg_records(campaign_id, visibility, approved, authority, record_id)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS rpg_version_history
      ON rpg_versions(campaign_id, revision, record_id)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS rpg_terms(
      campaign_id TEXT NOT NULL, record_id TEXT NOT NULL, term TEXT NOT NULL,
      PRIMARY KEY(campaign_id, record_id, term),
      FOREIGN KEY(campaign_id, record_id) REFERENCES rpg_records(campaign_id, record_id)
        ON DELETE CASCADE)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS rpg_term_lookup
      ON rpg_terms(campaign_id, term, record_id)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS rpg_events(
      campaign_id TEXT NOT NULL REFERENCES rpg_campaigns(id),
      revision INTEGER NOT NULL, kind TEXT NOT NULL, created INTEGER NOT NULL,
      payload TEXT NOT NULL, PRIMARY KEY(campaign_id, revision))''');
    // Nawet pomyłka w późniejszej wersji store nie może nadpisać audytu.
    for (final table in ['rpg_versions', 'rpg_events']) {
      for (final action in ['UPDATE', 'DELETE']) {
        await db.execute(
            '''CREATE TRIGGER IF NOT EXISTS ${table}_${action.toLowerCase()}_deny
          BEFORE $action ON $table BEGIN
          SELECT RAISE(ABORT, 'Dziennik kampanii jest dopisywany wyłącznie.'); END''');
      }
    }
  }
}
