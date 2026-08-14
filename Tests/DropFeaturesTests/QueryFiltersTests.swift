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
        .appendingPathComponent("drop-filters-test-\(UUID().uuidString).sqlite").path
    return try DropIndexDatabase(path: dbPath)
}

/// Insère un document minimal directement en base (hors ingestion), avec un type/date/montant
/// donnés, pour tester les filtres indépendamment du reste du pipeline.
private func insertDocument(
    _ database: DropIndexDatabase, id: String, displayName: String, docType: String?,
    effectiveDate: String?, amount: Double?
) async throws {
    try await database.pool.write { db in
        let hash = "hash-\(id)"
        try db.execute(sql: "INSERT OR IGNORE INTO blobs (hash, size_bytes, stored_at) VALUES (?, 0, '2026-01-01T00:00:00Z')", arguments: [hash])
        try db.execute(
            sql: """
            INSERT INTO documents (id, blob_hash, display_name, original_filename, size_bytes, added_at, source, doc_type, effective_date)
            VALUES (?, ?, ?, ?, 0, '2026-01-01T00:00:00Z', 'drop', ?, ?)
            """,
            arguments: [id, hash, displayName, displayName, docType, effectiveDate]
        )
        try db.execute(sql: "INSERT INTO fts_docs (display_name, body, issuer, keywords, document_id) VALUES (?, '', '', '', ?)", arguments: [displayName, id])
        if let amount {
            try db.execute(
                sql: "INSERT INTO entities (document_id, kind, value_text, raw_text, value_num, extractor) VALUES (?, 'amount', ?, ?, ?, 'regex')",
                arguments: [id, String(amount), String(amount), amount]
            )
        }
    }
}

@Test func filterOnlyGeneratorReturnsDocumentsMatchingDateRangeWithoutFreeText() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-2024", displayName: "facture 2024", docType: "facture", effectiveDate: "2024-06-01", amount: nil)
    try await insertDocument(database, id: "doc-2023", displayName: "facture 2023", docType: "facture", effectiveDate: "2023-06-01", amount: nil)

    var query = ParsedQuery()
    query.dateRange = DateInterval(
        start: ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!,
        end: ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!
    )

    let generator = FilterOnlyCandidateGenerator(database: database)
    let results = try await generator.candidates(for: query, limit: 10)

    #expect(results.map(\.documentID) == ["doc-2024"])
}

@Test func filterOnlyGeneratorReturnsDocumentsMatchingAmountRange() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-expensive", displayName: "contrat cher", docType: "contrat", effectiveDate: nil, amount: 800)
    try await insertDocument(database, id: "doc-cheap", displayName: "contrat pas cher", docType: "contrat", effectiveDate: nil, amount: 50)

    var query = ParsedQuery()
    query.amountRange = 500...Double.greatestFiniteMagnitude
    query.docTypes = ["contrat"]

    let generator = FilterOnlyCandidateGenerator(database: database)
    let results = try await generator.candidates(for: query, limit: 10)

    #expect(results.map(\.documentID) == ["doc-expensive"])
}

@Test func filterOnlyGeneratorReturnsNothingWithoutAnyFilter() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-1", displayName: "peu importe", docType: nil, effectiveDate: nil, amount: nil)

    let generator = FilterOnlyCandidateGenerator(database: database)
    let results = try await generator.candidates(for: ParsedQuery(), limit: 10)

    #expect(results.isEmpty) // aucun filtre : ce générateur ne s'applique pas (laissé aux autres).
}

@Test func lexicalGeneratorCombinesFreeTextWithDateFilter() async throws {
    let database = try makeDatabase()
    try await insertDocument(database, id: "doc-edf-2024", displayName: "facture edf 2024", docType: "facture", effectiveDate: "2024-03-01", amount: nil)
    try await insertDocument(database, id: "doc-edf-2023", displayName: "facture edf 2023", docType: "facture", effectiveDate: "2023-03-01", amount: nil)

    var query = ParsedQuery()
    query.freeText = "edf"
    query.dateRange = DateInterval(
        start: ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!,
        end: ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!
    )

    let generator = LexicalCandidateGenerator(database: database)
    let results = try await generator.candidates(for: query, limit: 10)

    #expect(results.map(\.documentID) == ["doc-edf-2024"])
}
