import GRDB

/// Schéma v1 de `index.db`, transcription exacte du CDC §4.4. Les données dérivables (FTS,
/// vignettes) restent reconstructibles à volonté : en cas de doute, on les régénère plutôt que de
/// les migrer (§4.6).
func createV1Schema(_ db: Database) throws {
    try db.execute(sql: """
        CREATE TABLE schema_meta (
          version      INTEGER NOT NULL,
          applied_at   TEXT    NOT NULL
        );
        """)

    try db.execute(sql: """
        CREATE TABLE blobs (
          hash             TEXT PRIMARY KEY,
          size_bytes       INTEGER NOT NULL,
          stored_at        TEXT    NOT NULL,
          encryption_mode  TEXT    NOT NULL DEFAULT 'standard',
          ref_count        INTEGER NOT NULL DEFAULT 0,
          last_verified_at TEXT,
          verify_status    TEXT    NOT NULL DEFAULT 'unknown'
        );
        """)

    try db.execute(sql: """
        CREATE TABLE documents (
          id                  TEXT PRIMARY KEY,
          blob_hash           TEXT NOT NULL REFERENCES blobs(hash),
          display_name        TEXT NOT NULL,
          original_filename   TEXT NOT NULL,
          original_path       TEXT,
          extension           TEXT,
          mime_type           TEXT,
          size_bytes          INTEGER NOT NULL,
          page_count          INTEGER,
          added_at            TEXT NOT NULL,
          content_created_at  TEXT,
          content_modified_at TEXT,
          effective_date      TEXT,
          effective_date_src  TEXT,
          source              TEXT NOT NULL,
          doc_type            TEXT,
          doc_type_conf       REAL,
          issuer              TEXT,
          summary             TEXT,
          language            TEXT,
          user_verified       INTEGER NOT NULL DEFAULT 0,
          analysis_state      TEXT NOT NULL DEFAULT 'pending',
          embedding_state     TEXT NOT NULL DEFAULT 'pending',
          last_error_code     TEXT,
          version_group_id    TEXT,
          version_number      INTEGER NOT NULL DEFAULT 1,
          trashed_at          TEXT
        );
        """)
    try db.execute(sql: "CREATE INDEX idx_doc_added ON documents(added_at DESC)")
    try db.execute(sql: "CREATE INDEX idx_doc_effdate ON documents(effective_date)")
    try db.execute(sql: "CREATE INDEX idx_doc_type ON documents(doc_type)")
    try db.execute(sql: "CREATE INDEX idx_doc_blob ON documents(blob_hash)")
    try db.execute(sql: "CREATE INDEX idx_doc_state ON documents(analysis_state, embedding_state)")
    try db.execute(sql: "CREATE INDEX idx_doc_trashed ON documents(trashed_at)")
    try db.execute(sql: "CREATE INDEX idx_doc_group ON documents(version_group_id, version_number)")

    try db.execute(sql: """
        CREATE TABLE page_texts (
          document_id     TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
          page_no         INTEGER NOT NULL,
          source          TEXT NOT NULL,
          content         TEXT NOT NULL,
          char_count      INTEGER NOT NULL,
          ocr_confidence  REAL,
          PRIMARY KEY (document_id, page_no)
        );
        """)

    try db.execute(sql: """
        CREATE TABLE entities (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          document_id  TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
          kind         TEXT NOT NULL,
          value_text   TEXT NOT NULL,
          raw_text     TEXT NOT NULL,
          value_num    REAL,
          value_date   TEXT,
          currency     TEXT,
          page_no      INTEGER,
          extractor    TEXT NOT NULL,
          confidence   REAL NOT NULL DEFAULT 1.0
        );
        """)
    try db.execute(sql: "CREATE INDEX idx_ent_doc ON entities(document_id, kind)")
    try db.execute(sql: "CREATE INDEX idx_ent_num ON entities(kind, value_num)")
    try db.execute(sql: "CREATE INDEX idx_ent_date ON entities(kind, value_date)")
    try db.execute(sql: "CREATE INDEX idx_ent_text ON entities(kind, value_text)")

    try db.execute(sql: """
        CREATE TABLE tags (
          id    INTEGER PRIMARY KEY AUTOINCREMENT,
          name  TEXT NOT NULL UNIQUE,
          kind  TEXT NOT NULL DEFAULT 'user'
        );
        """)
    try db.execute(sql: """
        CREATE TABLE document_tags (
          document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
          tag_id      INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
          PRIMARY KEY (document_id, tag_id)
        );
        """)

    try db.execute(sql: """
        CREATE VIRTUAL TABLE fts_docs USING fts5(
          display_name,
          body,
          issuer,
          keywords,
          document_id UNINDEXED,
          tokenize = "unicode61 remove_diacritics 2 tokenchars '-_@.'",
          prefix = '2 3 4'
        );
        """)

    try db.execute(sql: """
        CREATE VIRTUAL TABLE fts_trigram USING fts5(
          term,
          document_id UNINDEXED,
          tokenize = "trigram"
        );
        """)

    try db.execute(sql: """
        CREATE TABLE jobs (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          document_id     TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
          kind            TEXT NOT NULL,
          priority        INTEGER NOT NULL DEFAULT 100,
          state           TEXT NOT NULL DEFAULT 'queued',
          attempts        INTEGER NOT NULL DEFAULT 0,
          next_attempt_at TEXT,
          last_error      TEXT,
          created_at      TEXT NOT NULL,
          updated_at      TEXT NOT NULL,
          UNIQUE (document_id, kind)
        );
        """)
    try db.execute(sql: "CREATE INDEX idx_jobs_ready ON jobs(state, priority, next_attempt_at)")

    try db.execute(sql: """
        CREATE TABLE document_opens (
          document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
          opened_at   TEXT NOT NULL,
          query_hash  TEXT
        );
        """)
    try db.execute(sql: "CREATE INDEX idx_opens_doc ON document_opens(document_id, opened_at DESC)")

    try db.execute(sql: """
        CREATE TABLE settings (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        """)
}
