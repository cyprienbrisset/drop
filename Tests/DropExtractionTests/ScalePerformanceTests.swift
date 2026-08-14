import AppKit
import DropExtraction
import Foundation
import Testing

/// Validation de passage à l'échelle (DRO-47, ENF-22) : un document de 2 000 pages doit s'extraire
/// sans jamais échouer, l'analyse au-delà pouvant être plafonnée mais jamais en erreur. Génère un
/// vrai PDF de 2 000 pages via CoreGraphics — même technique que `DocumentTextExtractorTests`, pas
/// une fixture versionnée de plusieurs mégaoctets.
private func makeMultiPagePDF(pageCount: Int, at url: URL, pageSize: CGSize = CGSize(width: 300, height: 400)) throws {
    let pdfData = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
    guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else {
        throw ExtractionError.unreadable
    }

    for pageIndex in 0..<pageCount {
        context.beginPDFPage(nil)
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        // > 100 caractères par page (EF-42) : ce test isole le comportement à l'échelle, pas le
        // déclenchement de l'OCR, déjà couvert par `DocumentTextExtractorTests`.
        let text = """
        Relevé de compte, page \(pageIndex + 1) sur \(pageCount). Solde précédent : 1 204,56 euros.
        Opérations du mois : virement, prélèvement, carte bancaire. Solde final : 1 189,02 euros.
        """
        let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14)])
        attributed.draw(in: CGRect(x: 10, y: 10, width: pageSize.width - 20, height: pageSize.height - 20))
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
    }
    context.closePDF()

    try (pdfData as Data).write(to: url)
}

@Test func a2000PageDocumentExtractsCompletelyWithoutFailing() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("drop-scale-test-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }

    let pageCount = 2000
    let buildStart = Date()
    try makeMultiPagePDF(pageCount: pageCount, at: url)
    let buildSeconds = Date().timeIntervalSince(buildStart)

    let extractStart = Date()
    let extracted = try DocumentTextExtractor().extract(fileAt: url)
    let extractSeconds = Date().timeIntervalSince(extractStart)

    #expect(extracted.pageCount == pageCount)
    #expect(extracted.pages.count == pageCount)
    // Texte natif dense : aucune page ne doit réclamer l'OCR (EF-42) — confirmant que l'échelle
    // seule, sans contenu scanné, ne déclenche jamais le chemin OCR (et son plafond de 40 pages,
    // §DocumentTextExtractor.maxAutoOCRPages) par accident.
    #expect(extracted.pagesNeedingOCR.isEmpty)
    #expect(extracted.pages.first?.content.contains("page 1 sur 2000") == true)
    #expect(extracted.pages.last?.content.contains("page 2000 sur 2000") == true)

    print("[DRO-47] génération PDF \(pageCount) pages : \(String(format: "%.2f", buildSeconds))s — extraction : \(String(format: "%.2f", extractSeconds))s")
}
