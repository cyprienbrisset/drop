import GRDB

/// Schéma v4 : `jobs.started_at`, posé une seule fois au passage à `running`
/// (§JobQueue.dequeueNext) et jamais réécrit ensuite — `updated_at`, lui, continue de refléter le
/// dernier événement quel qu'il soit. La différence entre les deux, pour un travail `done`, donne
/// la durée réelle de traitement (§ComputeVaultStats), sans avoir besoin d'une table séparée.
func createV4AddJobStartedAt(_ db: Database) throws {
    try db.execute(sql: "ALTER TABLE jobs ADD COLUMN started_at TEXT")
}
