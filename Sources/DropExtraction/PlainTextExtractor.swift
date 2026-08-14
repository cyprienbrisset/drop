import Foundation

/// TXT, MD, CSV : lecture directe avec détection d'encodage, pagination synthétique à 3 000
/// caractères (§5.2) — ces formats n'ont pas de notion native de page.
public struct PlainTextExtractor: Sendable {
    private static let syntheticPageSize = 3000

    public init() {}

    public func extract(fileAt url: URL) throws -> ExtractedDocument {
        guard let data = try? Data(contentsOf: url) else { throw ExtractionError.unreadable }
        guard let text = Self.decode(data) else { throw ExtractionError.unreadable }

        guard !text.isEmpty else {
            return ExtractedDocument(pages: [], pageCount: 0)
        }

        var pages: [PageText] = []
        var pageNumber = 0
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: Self.syntheticPageSize, limitedBy: text.endIndex) ?? text.endIndex
            pages.append(PageText(pageNumber: pageNumber, source: .plain, content: String(text[index..<end])))
            pageNumber += 1
            index = end
        }
        return ExtractedDocument(pages: pages)
    }

    /// Essaie l'UTF-8 d'abord, puis se rabat sur Latin-1 — couvre l'essentiel des fichiers texte
    /// produits par des outils plus anciens sans dépendre d'une bibliothèque de détection tierce.
    private static func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}
