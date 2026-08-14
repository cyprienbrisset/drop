import GRDB

/// Schéma v2 (Phase 9, V2, DRO-84) : ajoute la date d'échéance, distincte de `effective_date`
/// (§5.3.3) — sans rapport avec la date d'émission/prise d'effet, jamais migrée depuis elle.
func createV2AddDueDate(_ db: Database) throws {
    try db.execute(sql: "ALTER TABLE documents ADD COLUMN due_date TEXT")
    try db.execute(sql: "ALTER TABLE documents ADD COLUMN reminder_scheduled_at TEXT")
    try db.execute(sql: "CREATE INDEX idx_doc_due_date ON documents(due_date)")
}
