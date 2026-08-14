import GRDB

/// Schéma v3 (Phase 10, V3) : règles d'automatisation type Hazel (§5, backlog V2+ — « règles
/// d'automatisation type Hazel » explicitement différée en V1/V2, reprise ici). Une règle reste
/// volontairement simple — une condition, une action — plutôt qu'un moteur de règles composées ;
/// la complexité peut toujours croître plus tard sans casser ce schéma (colonnes additives).
func createV3AddAutomationRules(_ db: Database) throws {
    try db.execute(sql: """
        CREATE TABLE automation_rules (
          id               TEXT PRIMARY KEY,
          name             TEXT NOT NULL,
          is_enabled       INTEGER NOT NULL DEFAULT 1,
          condition_kind   TEXT NOT NULL,
          condition_value  TEXT NOT NULL,
          action_tag       TEXT NOT NULL,
          created_at       TEXT NOT NULL
        );
        """)
    try db.execute(sql: "CREATE INDEX idx_automation_rules_enabled ON automation_rules(is_enabled)")
}
