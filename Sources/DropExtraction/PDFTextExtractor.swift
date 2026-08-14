import Foundation
import PDFKit

/// Extraction PDF, page par page (§5.2). Chaque page reçoit un verdict de densité textuelle
/// (EF-42) : l'OCR n'est déclenché que pour les pages qui en ont réellement besoin — jamais pour
/// un PDF entier à cause d'une seule page scannée.
public struct PDFTextExtractor: Sendable {
    /// Points par centimètre (72 dpi = 2.54 cm par pouce).
    private static let pointsPerCentimeter: Double = 72.0 / 2.54

    public init() {}

    public func extract(fileAt url: URL) throws -> ExtractedDocument {
        guard let document = PDFDocument(url: url) else { throw ExtractionError.unreadable }

        var pages: [PageText] = []
        var pagesNeedingOCR: Set<Int> = []

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = page.string ?? ""
            let charCount = text.count
            let bounds = page.bounds(for: .mediaBox)
            let areaCm2 = (Double(bounds.width) / Self.pointsPerCentimeter) * (Double(bounds.height) / Self.pointsPerCentimeter)
            let density = areaCm2 > 0 ? Double(charCount) / areaCm2 : 0

            // EF-42 : OCR déclenché si densité < 100 caractères OU < 0,15 caractère/cm².
            if charCount < 100 || density < 0.15 {
                pagesNeedingOCR.insert(index)
            }

            pages.append(PageText(pageNumber: index, source: .native, content: text))
        }

        return ExtractedDocument(pages: pages, pagesNeedingOCR: pagesNeedingOCR, pageCount: document.pageCount)
    }
}
