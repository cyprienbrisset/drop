import DropCore
import DropFeatures
import DropIndex
import DropSearch
import DropVault
import Foundation
import GRDB
import Testing

private func makeDatabase() throws -> DropIndexDatabase {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-search-engine-test-\(UUID().uuidString).sqlite").path
    return try DropIndexDatabase(path: dbPath)
}

private func insertDocument(
    _ database: DropIndexDatabase, id: String, displayName: String, filename: String, body: String,
    effectiveDate: String? = nil, addedAt: String = "2026-01-01T00:00:00Z"
) async throws {
    try await database.pool.write { db in
        let hash = "hash-\(id)"
        try db.execute(sql: "INSERT OR IGNORE INTO blobs (hash, size_bytes, stored_at) VALUES (?, 0, '2026-01-01T00:00:00Z')", arguments: [hash])
        try db.execute(
            sql: """
            INSERT INTO documents (id, blob_hash, display_name, original_filename, size_bytes, added_at, source, effective_date)
            VALUES (?, ?, ?, ?, 0, ?, 'drop', ?)
            """,
            arguments: [id, hash, displayName, filename, addedAt, effectiveDate]
        )
        try db.execute(
            sql: "INSERT INTO fts_docs (display_name, body, issuer, keywords, document_id) VALUES (?, ?, '', '', ?)",
            arguments: [displayName, body, id]
        )
        try db.execute(
            sql: "INSERT INTO fts_trigram (term, document_id) VALUES (?, ?)",
            arguments: [body, id]
        )
    }
}

@Test func searchEngineRanksLexicalMatchesByBM25() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-edf", displayName: "Facture EDF", filename: "facture-edf.pdf", body: "électricité edf facture janvier")
    try await insertDocument(database, id: "doc-other", displayName: "Autre document", filename: "autre.pdf", body: "sans rapport")

    let engine = SearchEngine(indexDatabase: database, vectorsDatabase: nil)
    var query = ParsedQuery()
    query.freeText = "edf"

    let results = try await engine.search(query, limit: 10)

    #expect(results.first?.documentID == "doc-edf")
    #expect(!results.map(\.documentID).contains("doc-other"))
}

@Test func searchEngineBoostsExactFilenameMatch() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-exact", displayName: "edf", filename: "edf.pdf", body: "edf facture électricité")
    try await insertDocument(database, id: "doc-loose", displayName: "Facture électricité EDF grand format", filename: "autre-nom.pdf", body: "edf facture électricité")

    let engine = SearchEngine(indexDatabase: database, vectorsDatabase: nil)
    var query = ParsedQuery()
    query.freeText = "edf"

    let results = try await engine.search(query, limit: 10)

    let exactScore = results.first { $0.documentID == "doc-exact" }?.score
    let looseScore = results.first { $0.documentID == "doc-loose" }?.score
    #expect(exactScore != nil && looseScore != nil)
    #expect(exactScore! > looseScore!)
}

@Test func searchEngineFallsBackToTrigramWhenLexicalIsSparse() async throws {
    let database = try makeDatabase()
    // Un seul document lexical (<5), le trigramme doit être activé et retrouver un second
    // document via une correspondance de sous-chaîne que le lexical seul ne verrait pas.
    try await insertDocument(database, id: "doc-lexical", displayName: "Facture", filename: "f.pdf", body: "assurance habitation contrat")
    try await insertDocument(database, id: "doc-trigram-only", displayName: "Document", filename: "d.pdf", body: "assurance habitation contrat")

    let engine = SearchEngine(indexDatabase: database, vectorsDatabase: nil)
    var query = ParsedQuery()
    query.freeText = "assurance"

    let results = try await engine.search(query, limit: 10)

    #expect(results.map(\.documentID).contains("doc-lexical"))
}

@Test func searchEngineHandlesFilterOnlyQueriesWithoutFreeText() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-2024", displayName: "facture 2024", filename: "f2024.pdf", body: "peu importe", effectiveDate: "2024-06-01")
    try await insertDocument(database, id: "doc-2023", displayName: "facture 2023", filename: "f2023.pdf", body: "peu importe", effectiveDate: "2023-06-01")

    let engine = SearchEngine(indexDatabase: database, vectorsDatabase: nil)
    var query = ParsedQuery()
    query.dateRange = DateInterval(
        start: ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!,
        end: ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!
    )

    let results = try await engine.search(query, limit: 10)

    #expect(results.map(\.documentID) == ["doc-2024"])
}

@Test func searchEngineReturnsNoResultsForEmptyQueryWithoutFilters() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1", displayName: "peu importe", filename: "x.pdf", body: "peu importe")

    let engine = SearchEngine(indexDatabase: database, vectorsDatabase: nil)
    let results = try await engine.search(ParsedQuery(), limit: 10)

    #expect(results.isEmpty)
}
