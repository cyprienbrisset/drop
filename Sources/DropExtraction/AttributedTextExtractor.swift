import AppKit
import Foundation

/// RTF, RTFD, DOCX, HTML : mis à plat via `NSAttributedString(url:options:documentAttributes:)`
/// (§5.2). Ces formats n'ont pas de pagination native côté modèle — un seul « page 0 » logique.
public struct AttributedTextExtractor: Sendable {
    public init() {}

    public func extract(fileAt url: URL, documentType: NSAttributedString.DocumentType) throws -> ExtractedDocument {
        var attributes: NSDictionary?
        guard let attributed = try? NSAttributedString(
            url: url, options: [.documentType: documentType], documentAttributes: &attributes
        ) else {
            throw ExtractionError.unreadable
        }

        let text = attributed.string
        guard !text.isEmpty else { return ExtractedDocument(pages: [], pageCount: 0) }
        return ExtractedDocument(pages: [PageText(pageNumber: 0, source: .attributed, content: text)])
    }
}
