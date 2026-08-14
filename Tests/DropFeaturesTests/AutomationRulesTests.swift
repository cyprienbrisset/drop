import DropCore
import DropFeatures
import DropIndex
import Foundation
import GRDB
import Testing

private func makeDatabase() throws -> DropIndexDatabase {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-automation-test-\(UUID().uuidString).sqlite").path
    return try DropIndexDatabase(path: dbPath)
}

private func insertAnalyzedDocument(
    _ database: DropIndexDatabase, id: String, docType: String? = nil, issuer: String? = nil,
    amount: Double? = nil, keywords: String = ""
) async throws {
    try await database.pool.write { db in
        let hash = "hash-\(id)"
        try db.execute(sql: "INSERT OR IGNORE INTO blobs (hash, size_bytes, stored_at) VALUES (?, 0, '2026-01-01T00:00:00Z')", arguments: [hash])
        try db.execute(
            sql: """
            INSERT INTO documents (id, blob_hash, display_name, original_filename, size_bytes, added_at, source, doc_type, issuer)
            VALUES (?, ?, ?, ?, 0, '2026-01-01T00:00:00Z', 'drop', ?, ?)
            """,
            arguments: [id, hash, "doc.pdf", "doc.pdf", docType, issuer]
        )
        try db.execute(
            sql: "INSERT INTO fts_docs (display_name, body, issuer, keywords, document_id) VALUES (?, '', ?, ?, ?)",
            arguments: ["doc.pdf", issuer ?? "", keywords, id]
        )
        if let amount {
            try db.execute(
                sql: """
                INSERT INTO entities (document_id, kind, value_text, raw_text, value_num, extractor, confidence)
                VALUES (?, 'amount', ?, ?, ?, 'regex', 1.0)
                """,
                arguments: [id, String(amount), String(amount), amount]
            )
        }
    }
}

private func makeEngine(_ database: DropIndexDatabase) -> AutomationRules {
    AutomationRules(database: database, manageTags: ManageTags(database: database))
}

@Test func addingARuleMakesItListable() async throws {
    let database = try makeDatabase()
    let engine = makeEngine(database)

    let rule = try await engine.addRule(name: "EDF", condition: .issuerEquals("EDF"), actionTag: "Énergie")
    let rules = try await engine.listRules()

    #expect(rules.count == 1)
    #expect(rules.first?.id == rule.id)
    #expect(rules.first?.condition == .issuerEquals("EDF"))
    #expect(rules.first?.actionTag == "énergie") // normalisé en minuscules à l'ajout.
    #expect(rules.first?.isEnabled == true)
}

@Test func applyingRulesTagsADocumentMatchingAnIssuerCondition() async throws {
    let database = try makeDatabase()
    let engine = makeEngine(database)
    try await insertAnalyzedDocument(database, id: "doc-1", issuer: "EDF")
    _ = try await engine.addRule(name: "EDF", condition: .issuerEquals("EDF"), actionTag: "energie")

    try await engine.applyRules(documentID: "doc-1")

    let tags = try await ManageTags(database: database).tags(forDocumentID: "doc-1")
    #expect(tags == ["energie"])
}

@Test func applyingRulesTagsADocumentMatchingADocTypeCondition() async throws {
    let database = try makeDatabase()
    let engine = makeEngine(database)
    try await insertAnalyzedDocument(database, id: "doc-1", docType: "facture")
    _ = try await engine.addRule(name: "Factures", condition: .docTypeEquals("facture"), actionTag: "a-classer")

    try await engine.applyRules(documentID: "doc-1")

    let tags = try await ManageTags(database: database).tags(forDocumentID: "doc-1")
    #expect(tags == ["a-classer"])
}

@Test func applyingRulesTagsADocumentAboveAnAmountThreshold() async throws {
    let database = try makeDatabase()
    let engine = makeEngine(database)
    try await insertAnalyzedDocument(database, id: "doc-cheap", amount: 20)
    try await insertAnalyzedDocument(database, id: "doc-expensive", amount: 500)
    _ = try await engine.addRule(name: "Gros montants", condition: .amountGreaterThan(100), actionTag: "important")

    try await engine.applyRules(documentID: "doc-cheap")
    try await engine.applyRules(documentID: "doc-expensive")

    let cheapTags = try await ManageTags(database: database).tags(forDocumentID: "doc-cheap")
    let expensiveTags = try await ManageTags(database: database).tags(forDocumentID: "doc-expensive")
    #expect(cheapTags.isEmpty)
    #expect(expensiveTags == ["important"])
}

@Test func applyingRulesTagsADocumentMatchingAKeywordCondition() async throws {
    let database = try makeDatabase()
    let engine = makeEngine(database)
    try await insertAnalyzedDocument(database, id: "doc-1", keywords: "électricité facture edf")
    _ = try await engine.addRule(name: "Électricité", condition: .keywordContains("électricité"), actionTag: "energie")

    try await engine.applyRules(documentID: "doc-1")

    let tags = try await ManageTags(database: database).tags(forDocumentID: "doc-1")
    #expect(tags == ["energie"])
}

@Test func aDisabledRuleNeverApplies() async throws {
    let database = try makeDatabase()
    let engine = makeEngine(database)
    try await insertAnalyzedDocument(database, id: "doc-1", issuer: "EDF")
    let rule = try await engine.addRule(name: "EDF", condition: .issuerEquals("EDF"), actionTag: "energie")
    try await engine.setEnabled(id: rule.id, isEnabled: false)

    try await engine.applyRules(documentID: "doc-1")

    let tags = try await ManageTags(database: database).tags(forDocumentID: "doc-1")
    #expect(tags.isEmpty)
}

@Test func removingARuleStopsItFromApplying() async throws {
    let database = try makeDatabase()
    let engine = makeEngine(database)
    try await insertAnalyzedDocument(database, id: "doc-1", issuer: "EDF")
    let rule = try await engine.addRule(name: "EDF", condition: .issuerEquals("EDF"), actionTag: "energie")
    try await engine.removeRule(id: rule.id)

    try await engine.applyRules(documentID: "doc-1")

    let rules = try await engine.listRules()
    let tags = try await ManageTags(database: database).tags(forDocumentID: "doc-1")
    #expect(rules.isEmpty)
    #expect(tags.isEmpty)
}

@Test func applyingRulesTwiceNeverDuplicatesTheTag() async throws {
    let database = try makeDatabase()
    let engine = makeEngine(database)
    try await insertAnalyzedDocument(database, id: "doc-1", issuer: "EDF")
    _ = try await engine.addRule(name: "EDF", condition: .issuerEquals("EDF"), actionTag: "energie")

    try await engine.applyRules(documentID: "doc-1")
    try await engine.applyRules(documentID: "doc-1")

    let tags = try await ManageTags(database: database).tags(forDocumentID: "doc-1")
    #expect(tags == ["energie"])
}

@Test func aNonMatchingConditionNeverAppliesTheTag() async throws {
    let database = try makeDatabase()
    let engine = makeEngine(database)
    try await insertAnalyzedDocument(database, id: "doc-1", issuer: "Orange")
    _ = try await engine.addRule(name: "EDF", condition: .issuerEquals("EDF"), actionTag: "energie")

    try await engine.applyRules(documentID: "doc-1")

    let tags = try await ManageTags(database: database).tags(forDocumentID: "doc-1")
    #expect(tags.isEmpty)
}
