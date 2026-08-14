import AppKit
import DropExtraction
import Foundation
import Testing

/// Génère un vrai PDF (texte réel, pas une image) via CoreGraphics — sans dépendre d'un fichier
/// fixture versionné.
private func makeTestPDF(text: String, at url: URL, pageSize: CGSize = CGSize(width: 300, height: 400)) throws {
    let pdfData = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
    guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else {
        throw ExtractionError.unreadable
    }

    context.beginPDFPage(nil)
    let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsContext
    if !text.isEmpty {
        let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18)])
        // `draw(in:)` avec un rectangle couvrant toute la page : garantit que le texte multi-ligne
        // est intégralement mis en page (et donc extractible), sans dépendre d'un point de départ
        // approximatif qui pourrait le faire déborder hors de la page en contexte non retourné.
        attributed.draw(in: CGRect(x: 10, y: 10, width: pageSize.width - 20, height: pageSize.height - 20))
    }
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()

    try (pdfData as Data).write(to: url)
}

@Test func extractsNativeTextFromARealPDF() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("drop-test-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    // Volontairement > 100 caractères : une phrase courte déclencherait l'OCR par construction
    // (EF-42, seuil de densité), ce qui est le comportement attendu, pas celui testé ici.
    let text = """
    Facture EDF juillet 2026. Client : Jean Dupont, 12 rue des Lilas, 75000 Paris.
    Montant à régler : 84,20 euros TTC, avant le 30 septembre 2026.
    Référence client : 1234567890. Merci de votre fidélité.
    """
    try makeTestPDF(text: text, at: url)

    let extractor = DocumentTextExtractor()
    let result = try extractor.extract(fileAt: url)

    #expect(result.pages.count == 1)
    #expect(result.pages[0].source == .native)
    #expect(result.pages[0].content.contains("EDF"))
    #expect(result.pagesNeedingOCR.isEmpty) // assez de texte natif, pas besoin d'OCR.
}

@Test func flagsASparsePDFPageForOCR() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("drop-test-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    try makeTestPDF(text: "", at: url) // page blanche : aucun texte natif → densité nulle.

    let extractor = DocumentTextExtractor()
    let result = try extractor.extract(fileAt: url)

    #expect(result.pagesNeedingOCR == [0]) // EF-42 : densité insuffisante, l'OCR doit prendre le relais.
}

@Test func extractsPlainTextAndPaginatesSyntheticallyAtThreeThousandCharacters() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("drop-test-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    let content = String(repeating: "a", count: 7000)
    try content.write(to: url, atomically: true, encoding: .utf8)

    let extractor = DocumentTextExtractor()
    let result = try extractor.extract(fileAt: url)

    #expect(result.pages.count == 3) // 3000 + 3000 + 1000
    #expect(result.pages[0].source == .plain)
    #expect(result.pages[0].content.count == 3000)
    #expect(result.pages[2].content.count == 1000)
}

@Test func extractsAttributedTextFromRTF() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("drop-test-\(UUID().uuidString).rtf")
    defer { try? FileManager.default.removeItem(at: url) }

    let attributed = NSAttributedString(string: "Contrat de location signé le 1er août.")
    let rtfData = try attributed.data(
        from: NSRange(location: 0, length: attributed.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
    try rtfData.write(to: url)

    let extractor = DocumentTextExtractor()
    let result = try extractor.extract(fileAt: url)

    #expect(result.pages.count == 1)
    #expect(result.pages[0].source == .attributed)
    #expect(result.pages[0].content.contains("Contrat de location"))
}

@Test func throwsUnsupportedFormatForAnUnknownExtension() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("drop-test-\(UUID().uuidString).xyz")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data().write(to: url)

    let extractor = DocumentTextExtractor()
    #expect(throws: ExtractionError.unsupportedFormat) {
        try extractor.extract(fileAt: url)
    }
}
