import AppKit
import Foundation

/// Point d'entrée du module (§5.2) : sélectionne la méthode d'extraction selon l'extension du
/// fichier. Un format non reconnu lève `unsupportedFormat` — l'appelant (Phase 3, DropFeatures)
/// retombe alors sur les métadonnées seules (EF-07), jamais un échec de l'ingestion.
public struct DocumentTextExtractor: Sendable {
    private let pdf = PDFTextExtractor()
    private let plainText = PlainTextExtractor()
    private let attributed = AttributedTextExtractor()

    public init() {}

    public func extract(fileAt url: URL) throws -> ExtractedDocument {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return try pdf.extract(fileAt: url)
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
        default:
            throw ExtractionError.unsupportedFormat
        }
    }
}
