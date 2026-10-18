import 'package:sqflite/sqflite.dart';

class MemorySchema {
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute(
        'CREATE TABLE memory_collections(id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, name TEXT NOT NULL, vault_id TEXT, created INTEGER NOT NULL)');
    await db.execute(
        'CREATE TABLE memory_documents(id TEXT PRIMARY KEY, collection_id TEXT NOT NULL REFERENCES memory_collections(id) ON DELETE CASCADE, source_key TEXT NOT NULL, path TEXT NOT NULL, hash TEXT NOT NULL, revision INTEGER NOT NULL, approval TEXT NOT NULL, restricted INTEGER NOT NULL, bytes INTEGER NOT NULL, updated INTEGER NOT NULL, UNIQUE(collection_id,source_key))');
    await db.execute(
        'CREATE TABLE memory_versions(document_id TEXT NOT NULL REFERENCES memory_documents(id) ON DELETE CASCADE, revision INTEGER NOT NULL, hash TEXT NOT NULL, path TEXT NOT NULL, restricted INTEGER NOT NULL, bytes INTEGER NOT NULL, created INTEGER NOT NULL, PRIMARY KEY(document_id,revision))');
    await db.execute(
        'CREATE TABLE memory_chunks(id TEXT PRIMARY KEY, document_id TEXT NOT NULL REFERENCES memory_documents(id) ON DELETE CASCADE, revision INTEGER NOT NULL, ordinal INTEGER NOT NULL, start_line INTEGER NOT NULL, end_line INTEGER NOT NULL, body TEXT NOT NULL, UNIQUE(document_id,revision,ordinal))');
    await db.execute(
        'CREATE TABLE memory_terms(term TEXT NOT NULL, chunk_id TEXT NOT NULL REFERENCES memory_chunks(id) ON DELETE CASCADE, PRIMARY KEY(term,chunk_id)) WITHOUT ROWID');
    await db.execute(
        'CREATE INDEX memory_chunks_doc ON memory_chunks(document_id,revision,ordinal)');
    await db.execute(
        'CREATE INDEX memory_documents_scope ON memory_documents(collection_id,approval,restricted)');
    await db
        .execute('CREATE INDEX memory_terms_chunk ON memory_terms(chunk_id)');
    await db.execute(
        'CREATE TABLE memory_import_jobs(collection_id TEXT PRIMARY KEY REFERENCES memory_collections(id) ON DELETE CASCADE, cursor TEXT, page_offset INTEGER NOT NULL DEFAULT 0, processed INTEGER NOT NULL DEFAULT 0, failed INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL, updated INTEGER NOT NULL)');
    await db.execute(
        'CREATE TABLE analysis_checkpoints(id TEXT PRIMARY KEY, collection_id TEXT NOT NULL REFERENCES memory_collections(id) ON DELETE CASCADE, revision INTEGER NOT NULL, goal TEXT NOT NULL, findings TEXT NOT NULL, next_step TEXT NOT NULL, sources TEXT NOT NULL, updated INTEGER NOT NULL)');
    await db.execute(
        'CREATE TABLE chat_context_receipts(message_id TEXT PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE, digest TEXT NOT NULL, evidence TEXT NOT NULL, omitted INTEGER NOT NULL, created INTEGER NOT NULL)');
    await db.execute(
        'CREATE TABLE chat_scopes(conversation_id TEXT PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE, scope_key TEXT NOT NULL, confidential INTEGER NOT NULL)');
  }
}
