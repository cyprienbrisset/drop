import AppKit
import Foundation
import PDFKit

/// Point d'entrée du module (§5.2) : sélectionne la méthode d'extraction selon l'extension du
/// fichier. Un format non reconnu lève `unsupportedFormat` — l'appelant (Phase 3, DropFeatures)
/// retombe alors sur les métadonnées seules (EF-07), jamais un échec de l'ingestion.
public struct DocumentTextExtractor: Sendable {
    private let pdf = PDFTextExtractor()
    private let plainText = PlainTextExtractor()
    private let attributed = AttributedTextExtractor()
    private let image = ImageTextExtractor()
    private let rasterizer = PDFPageRasterizer()
    private let ocr = VisionOCR()
    private let ooxml = OOXMLTextExtractor()

    /// Plafond de pages OCRisées automatiquement par document (§5.2) ; l'extension manuelle au-delà
    /// est une action utilisateur explicite, pas encore câblée ici.
    private let maxAutoOCRPages: Int

    public init(maxAutoOCRPages: Int = 40) {
        self.maxAutoOCRPages = maxAutoOCRPages
    }

    /// `extensionHint` permet de préciser le format quand l'URL elle-même n'a pas d'extension
    /// exploitable — c'est le cas des blobs du coffre, nommés par leur hash (§4.3) : l'appelant
    /// (Phase 4, `AnalyzeDocument`) transmet alors l'extension d'origine du document.
    public func extract(fileAt url: URL, extensionHint: String? = nil) throws -> ExtractedDocument {
        let fileExtension = (extensionHint ?? url.pathExtension).lowercased()
        switch fileExtension {
        case "pdf":
            return try extractPDFWithOCR(fileAt: url)
        case "txt", "md", "csv":
            return try plainText.extract(fileAt: url)
        case "rtf":
            return try attributed.extract(fileAt: url, documentType: .rtf)
        case "rtfd":
            return try attributed.extract(fileAt: url, documentType: .rtfd)
        case "html", "htm":
            return try attributed.extract(fileAt: url, documentType: .html)
        case "docx":
            return try attributed.extract(fileAt: url, documentType: .officeOpenXML)
        case "xlsx":
            return try ooxml.extract(fileAt: url, kind: .xlsx)
        case "pptx":
            return try ooxml.extract(fileAt: url, kind: .pptx)
        case "png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp":
            return try image.extract(fileAt: url)
        default:
            throw ExtractionError.unsupportedFormat
        }
    }

    /// Combine l'extraction native (§5.2) et l'OCR conditionnel (EF-42) : seules les pages dont
    /// la densité textuelle est insuffisante sont rasterisées puis passées à Vision — jamais le
    /// document entier pour une seule page scannée.
    private func extractPDFWithOCR(fileAt url: URL) throws -> ExtractedDocument {
        let native = try pdf.extract(fileAt: url)
        guard !native.pagesNeedingOCR.isEmpty, let document = PDFDocument(url: url) else { return native }

        var pages = native.pages
        let sortedPages = native.pagesNeedingOCR.sorted()
        let toProcess = sortedPages.prefix(maxAutoOCRPages)
        var stillNeeding = Set(sortedPages.dropFirst(maxAutoOCRPages))

        for pageIndex in toProcess {
            guard let page = document.page(at: pageIndex), let cgImage = rasterizer.image(for: page),
                  let ocrResult = try? ocr.recognizeText(in: cgImage)
            else {
                stillNeeding.insert(pageIndex)
                continue
            }
            if let arrayIndex = pages.firstIndex(where: { $0.pageNumber == pageIndex }) {
                pages[arrayIndex] = PageText(
                    pageNumber: pageIndex, source: .ocr, content: ocrResult.text, ocrConfidence: ocrResult.confidence
                )
            }
        }

        return ExtractedDocument(pages: pages, pagesNeedingOCR: stillNeeding, pageCount: native.pageCount)
    }
}
