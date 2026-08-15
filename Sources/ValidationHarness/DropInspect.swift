import DropCore
import DropIndex
import Foundation
import GRDB

/// Diagnostic en lecture seule du vrai coffre par défaut — jamais d'écriture, jamais de
/// modification d'état ; sert uniquement à comprendre ce qui s'est réellement passé après un
/// dépôt (compteurs par état d'analyse, file de travaux, documents les plus récents).
func runDropInspect() async throws {
    let vaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Drop")
    let passphrase = try VaultEncryptionKey.getOrCreate(store: SecKeychainKeyStore(), account: vaultRoot.path)
    let indexDatabase = try DropIndexDatabase(path: vaultRoot.appendingPathComponent("index.db").path, passphrase: passphrase)

    print("=== drop-inspect — \(vaultRoot.path) ===\n")

    try await indexDatabase.pool.read { db in
        let totalDocuments = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents") ?? 0
        let trashed = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents WHERE trashed_at IS NOT NULL") ?? 0
        print("Documents totaux : \(totalDocuments) (dont \(trashed) dans la corbeille)")

        print("\nRépartition par analysis_state :")
        let analysisStates = try Row.fetchAll(db, sql: "SELECT analysis_state, COUNT(*) AS n FROM documents GROUP BY analysis_state")
        for row in analysisStates {
            print("  \(row["analysis_state"] as String) : \(row["n"] as Int)")
        }

        print("\nFile de travaux (jobs) par état :")
        let jobStates = try Row.fetchAll(db, sql: "SELECT state, kind, COUNT(*) AS n FROM jobs GROUP BY state, kind")
        if jobStates.isEmpty { print("  (vide)") }
        for row in jobStates {
            print("  \(row["state"] as String) / \(row["kind"] as String) : \(row["n"] as Int)")
        }

        print("\n10 documents les plus récents (added_at) :")
        let recent = try Row.fetchAll(
            db,
            sql: """
            SELECT display_name, doc_type, analysis_state, added_at, last_error_code
            FROM documents ORDER BY added_at DESC LIMIT 10
            """
        )
        for row in recent {
            let name: String = row["display_name"]
            let docType: String? = row["doc_type"]
            let state: String = row["analysis_state"]
            let addedAt: String = row["added_at"]
            let errorCode: String? = row["last_error_code"]
            print("  [\(state)] \(name) — type=\(docType ?? "nil") — ajouté \(addedAt)" + (errorCode.map { " — erreur: \($0)" } ?? ""))
        }

        print("\nDernières erreurs de jobs (le cas échéant) :")
        let jobErrors = try Row.fetchAll(
            db,
            sql: "SELECT document_id, kind, attempts, last_error FROM jobs WHERE last_error IS NOT NULL ORDER BY id DESC LIMIT 10"
        )
        if jobErrors.isEmpty { print("  (aucune)") }
        for row in jobErrors {
            print("  doc=\(row["document_id"] as String) kind=\(row["kind"] as String) tentatives=\(row["attempts"] as Int) — \(row["last_error"] as String)")
        }
    }
}
