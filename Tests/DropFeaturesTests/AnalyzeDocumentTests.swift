import AppKit
import DropCore
import DropFeatures
import DropIndex
import DropVault
import Foundation
import GRDB
import Testing

/// `AnalyzeDocument` s'appuie sur PDFKit/NSAttributedString/ImageIO, qui lisent toujours le vrai
/// système de fichiers quelle que soit l'abstraction `FileSystem` injectée dans `VaultService` —
/// contrairement aux autres suites `DropFeatures`, ces tests utilisent donc `LiveFileSystem` sur
/// un vrai répertoire temporaire, pas `InMemoryFileSystem`.
private func makeTestPDF(text: String, at url: URL, pageSize: CGSize = CGSize(width: 300, height: 400)) throws {
    let pdfData = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
    guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else {
        Issue.record("failed to create PDF context"); return
    }
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

@Test func analyzeDocumentPersistsEntitiesAndUpdatesTheDocumentAndFTS() async throws {
    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("drop-analyze-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempRoot) }
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    let sourcePDF = tempRoot.appendingPathComponent("facture edf.pdf")
    let longText = """
    Facture EDF. Client : Jean Dupont, 12 rue des Lilas, 75000 Paris.
    Date d'émission : 14/07/2025. Montant : net à payer 84,20 €.
    Merci de votre confiance. Référence client 1234567890.
    """
    try makeTestPDF(text: longText, at: sourcePDF)

    let vaultRoot = tempRoot.appendingPathComponent("vault-root")
    let vault = VaultService(vaultRoot: vaultRoot, fileSystem: LiveFileSystem())
    let dbPath = tempRoot.appendingPathComponent("index.sqlite").path
    let database = try DropIndexDatabase(path: dbPath)

    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())
    guard case .created(let documentID) = try await ingest.ingest(fileAt: sourcePDF) else {
        Issue.record("expected a created document"); return
    }

    let analyze = AnalyzeDocument(vault: vault, database: database)
    try await analyze.analyze(documentID: documentID)

    let (issuer, effectiveDate, effectiveDateSrc, ftsBody, amountCount, dateCount): (String?, String?, String?, String, Int, Int) =
        try await database.pool.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT issuer, effective_date, effective_date_src FROM documents WHERE id = ?", arguments: [documentID])!
            let ftsBody: String = try String.fetchOne(db, sql: "SELECT body FROM fts_docs WHERE document_id = ?", arguments: [documentID]) ?? ""
            let amountCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entities WHERE document_id = ? AND kind = 'amount'", arguments: [documentID]) ?? 0
            let dateCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entities WHERE document_id = ? AND kind = 'date'", arguments: [documentID]) ?? 0
            return (row["issuer"], row["effective_date"], row["effective_date_src"], ftsBody, amountCount, dateCount)
        }

    #expect(issuer == "EDF")
    #expect(effectiveDate != nil)
    #expect(effectiveDateSrc == "mostFrequent")
    #expect(ftsBody.contains("EDF"))
    #expect(amountCount >= 1)
    #expect(dateCount >= 1)
}
