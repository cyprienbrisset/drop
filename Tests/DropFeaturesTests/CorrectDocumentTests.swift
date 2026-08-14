import AppKit
import DropCore
import DropFeatures
import DropIndex
import DropVault
import Foundation
import GRDB
import Testing

private func makeTestPDF(text: String, at url: URL, pageSize: CGSize = CGSize(width: 300, height: 400)) throws {
    let pdfData = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
    guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else { return }
    context.beginPDFPage(nil)
    let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsContext
    let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 16)])
    attributed.draw(in: CGRect(x: 10, y: 10, width: pageSize.width - 20, height: pageSize.height - 20))
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    try (pdfData as Data).write(to: url)
}

@Test func correctingTheIssuerSurvivesReanalysis() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("drop-correct-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempRoot) }
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    let sourcePDF = tempRoot.appendingPathComponent("facture edf.pdf")
    try makeTestPDF(text: "Facture EDF. Montant à régler 84,20 €. Référence 1234567890.", at: sourcePDF)

    let vault = VaultService(vaultRoot: tempRoot.appendingPathComponent("vault-root"), fileSystem: LiveFileSystem())
    let database = try DropIndexDatabase(path: tempRoot.appendingPathComponent("index.sqlite").path)

    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())
    guard case .created(let documentID) = try await ingest.ingest(fileAt: sourcePDF) else {
        Issue.record("expected a created document"); return
    }

    let analyze = AnalyzeDocument(vault: vault, database: database)
    try await analyze.analyze(documentID: documentID)

    // Le pipeline a détecté "EDF" comme émetteur ; l'utilisateur corrige vers un autre nom.
    let correct = CorrectDocument(database: database)
    try await correct.correctIssuer(documentID: documentID, to: "EDF Entreprises")

    // Une ré-analyse ne doit jamais écraser la correction (EF-48).
    try await analyze.analyze(documentID: documentID)

    let (issuer, userVerified, ftsIssuer): (String?, Int, String) = try await database.pool.read { db in
        let row = try Row.fetchOne(db, sql: "SELECT issuer, user_verified FROM documents WHERE id = ?", arguments: [documentID])!
        let ftsIssuer: String = try String.fetchOne(db, sql: "SELECT issuer FROM fts_docs WHERE document_id = ?", arguments: [documentID]) ?? ""
        return (row["issuer"], row["user_verified"], ftsIssuer)
    }

    #expect(issuer == "EDF Entreprises")
    #expect(userVerified & VerifiedField.issuer.rawValue != 0)
    #expect(ftsIssuer == "EDF Entreprises") // la recherche reflète la correction, pas le pipeline.
}

@Test func correctingTheEffectiveDateSurvivesReanalysis() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("drop-correct-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempRoot) }
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    let sourcePDF = tempRoot.appendingPathComponent("contrat.pdf")
    try makeTestPDF(text: "Contrat signé le 14/07/2025. Référence CT-2025-001.", at: sourcePDF)

    let vault = VaultService(vaultRoot: tempRoot.appendingPathComponent("vault-root"), fileSystem: LiveFileSystem())
    let database = try DropIndexDatabase(path: tempRoot.appendingPathComponent("index.sqlite").path)

    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())
    guard case .created(let documentID) = try await ingest.ingest(fileAt: sourcePDF) else {
        Issue.record("expected a created document"); return
    }

    let analyze = AnalyzeDocument(vault: vault, database: database)
    try await analyze.analyze(documentID: documentID)

    let correct = CorrectDocument(database: database)
    try await correct.correctEffectiveDate(documentID: documentID, to: "2025-08-01")
    try await analyze.analyze(documentID: documentID)

    let (effectiveDate, effectiveDateSrc, userVerified): (String?, String?, Int) = try await database.pool.read { db in
        let row = try Row.fetchOne(db, sql: "SELECT effective_date, effective_date_src, user_verified FROM documents WHERE id = ?", arguments: [documentID])!
        return (row["effective_date"], row["effective_date_src"], row["user_verified"])
    }

    #expect(effectiveDate == "2025-08-01")
    #expect(effectiveDateSrc == "user")
    #expect(userVerified & VerifiedField.effectiveDate.rawValue != 0)
}

@Test func correctingTheTypeSetsTheVerifiedBit() async throws {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-correct-test-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let database = try DropIndexDatabase(path: dbPath)

    try await database.pool.write { db in
        try db.execute(sql: "INSERT INTO blobs (hash, size_bytes, stored_at) VALUES ('h', 0, '2026-01-01T00:00:00Z')")
        try db.execute(
            sql: "INSERT INTO documents (id, blob_hash, display_name, original_filename, size_bytes, added_at, source) VALUES ('doc-1', 'h', 'x', 'x', 0, '2026-01-01T00:00:00Z', 'drop')"
        )
    }

    let correct = CorrectDocument(database: database)
    try await correct.correctType(documentID: "doc-1", to: "devis")

    let (docType, userVerified): (String?, Int) = try await database.pool.read { db in
        let row = try Row.fetchOne(db, sql: "SELECT doc_type, user_verified FROM documents WHERE id = 'doc-1'")!
        return (row["doc_type"], row["user_verified"])
    }
    #expect(docType == "devis")
    #expect(userVerified & VerifiedField.type.rawValue != 0)
}
