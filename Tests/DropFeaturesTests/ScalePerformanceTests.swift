import DropIndex
import DropFeatures
import DropSearch
import Foundation
import GRDB
import Testing

/// Validation de passage à l'échelle (DRO-47, ENF-20) : la recherche doit rester dans la
/// dégradation admise (jusqu'à 2,5 s) une fois le coffre monté à 100 000 documents. Les lignes
/// sont insérées directement par SQL — reproduire un vrai dépôt+analyse de 100 000 fichiers (avec
/// le modèle de langage réel, jusqu'à 20-30 s par document ailleurs dans cette suite) prendrait des
/// dizaines d'heures et ne testerait rien de plus que ce que `AnalyzeDocument`/`AnalyzeDocumentTests`
/// couvrent déjà unitairement. Ce que ce test isole, c'est la seule question propre à l'échelle :
/// l'index (`fts_docs`, `documents`) se comporte-t-il encore correctement une fois rempli ?
private let documentCount = 100_000

private let issuers = ["EDF", "Orange", "Free", "SNCF Connect", "Impots.gouv", "CAF", "Banque Populaire", "Engie"]
private let docTypes = ["facture", "contrat", "relevé", "attestation"]
private let months = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]

private func makeSeededDatabase() throws -> (DropIndexDatabase, seedingSeconds: Double) {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-scale-test-\(UUID().uuidString).sqlite").path
    let database = try DropIndexDatabase(path: dbPath)

    let start = Date()
    try database.pool.write { db in
        let blobStatement = try db.makeStatement(sql: "INSERT INTO blobs (hash, size_bytes, stored_at) VALUES (?, 0, '2026-01-01T00:00:00Z')")
        let documentStatement = try db.makeStatement(
            sql: """
            INSERT INTO documents (id, blob_hash, display_name, original_filename, size_bytes, added_at, source)
            VALUES (?, ?, ?, ?, 0, '2026-01-01T00:00:00Z', 'drop')
            """
        )
        let ftsStatement = try db.makeStatement(
            sql: "INSERT INTO fts_docs (display_name, body, issuer, keywords, document_id) VALUES (?, ?, ?, '', ?)"
        )

        for i in 0..<documentCount {
            let id = "doc-\(i)"
            let hash = "hash-\(i)"
            let issuer = issuers[i % issuers.count]
            let docType = docTypes[i % docTypes.count]
            let month = months[i % months.count]
            let displayName = "\(docType.capitalized) \(issuer) \(month).pdf"
            // Une seule aiguille rare dans toute la botte de foin, pour vérifier une correspondance
            // sélective en plus de la correspondance large sur "EDF" (~1/8 des documents).
            let body = i == documentCount / 2
                ? "\(docType) \(issuer) \(month) référence ZZZQUERYNEEDLE12345"
                : "\(docType) \(issuer) \(month) référence \(i)"

            try blobStatement.execute(arguments: [hash])
            try documentStatement.execute(arguments: [id, hash, displayName, displayName])
            try ftsStatement.execute(arguments: [displayName, body, issuer, id])
        }
    }
    let seedingSeconds = Date().timeIntervalSince(start)

    return (database, seedingSeconds)
}

@Test func searchAt100kDocumentsStaysWithinTheAdmittedDegradationCeiling() async throws {
    let (database, seedingSeconds) = try makeSeededDatabase()
    let engine = SearchEngine(indexDatabase: database, vectorsDatabase: nil)

    let documentTotal = try await database.pool.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents") ?? 0
    }
    #expect(documentTotal == documentCount)

    // ENF-20 : dégradation admise jusqu'à 2,5 s — mesurée ici pour de vrai, pas simulée.
    let degradationCeilingSeconds = 2.5

    var commonQuery = ParsedQuery()
    commonQuery.freeText = "EDF"
    let commonStart = Date()
    let commonResults = try await engine.search(commonQuery, limit: 20)
    let commonSeconds = Date().timeIntervalSince(commonStart)

    #expect(!commonResults.isEmpty)
    #expect(commonSeconds < degradationCeilingSeconds)

    var rareQuery = ParsedQuery()
    rareQuery.freeText = "ZZZQUERYNEEDLE12345"
    let rareStart = Date()
    let rareResults = try await engine.search(rareQuery, limit: 20)
    let rareSeconds = Date().timeIntervalSince(rareStart)

    #expect(rareResults.count == 1)
    #expect(rareResults.first?.documentID == "doc-\(documentCount / 2)")
    #expect(rareSeconds < degradationCeilingSeconds)

    // Pas une assertion (l'ingestion réelle passe par un job en tâche de fond, jamais ce chemin) —
    // juste un repère chiffré laissé dans le rapport pour la revue humaine de ce ticket.
    print("[DRO-47] seeding \(documentCount) documents: \(String(format: "%.2f", seedingSeconds))s — search 'EDF': \(String(format: "%.3f", commonSeconds))s — search rare needle: \(String(format: "%.3f", rareSeconds))s")
}
