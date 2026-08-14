import Foundation

/// Un segment de texte à vectoriser, avec ses bornes dans la page d'origine.
public struct TextChunk: Sendable, Equatable {
    public let pageNumber: Int
    public let charFrom: Int
    public let charTo: Int
    public let text: String
}

/// Découpage en segments (§5.5) : ~500 tokens, recouvrement de 80, jamais à cheval sur une
/// frontière de page sans marqueur — on découpe par page, jamais en fusionnant deux pages — et
/// jamais au milieu d'une phrase quand un point est disponible dans une fenêtre de 40 caractères.
///
/// Approximation ~4 caractères par token (comme `DropIntelligence.ContextSelector`), en l'absence
/// d'un tokenizer public exposé par le modèle d'embeddings.
public struct TextChunker: Sendable {
    private let charsPerToken = 4
    public let tokensPerChunk: Int
    public let tokenOverlap: Int

    public init(tokensPerChunk: Int = 500, tokenOverlap: Int = 80) {
        self.tokensPerChunk = tokensPerChunk
        self.tokenOverlap = tokenOverlap
    }

    public func chunks(forPage pageNumber: Int, text: String) -> [TextChunk] {
        guard !text.isEmpty else { return [] }
        let chunkSizeChars = tokensPerChunk * charsPerToken
        let overlapChars = tokenOverlap * charsPerToken
        let stride = max(1, chunkSizeChars - overlapChars)

        var chunks: [TextChunk] = []
        var start = 0
        while start < text.count {
            let naiveEnd = min(text.count, start + chunkSizeChars)
            let end = naiveEnd < text.count ? adjustedEnd(for: text, naiveEnd: naiveEnd) : naiveEnd
            guard end > start else { break }

            let startIndex = text.index(text.startIndex, offsetBy: start)
            let endIndex = text.index(text.startIndex, offsetBy: end)
            chunks.append(TextChunk(pageNumber: pageNumber, charFrom: start, charTo: end, text: String(text[startIndex..<endIndex])))

            if end >= text.count { break }
            start += stride
        }
        return chunks
    }

    /// Recule jusqu'à la fin de phrase la plus proche (« . » suivi d'un espace ou fin de texte) si
    /// elle se trouve dans les 40 derniers caractères de la fenêtre — sinon coupe net.
    private func adjustedEnd(for text: String, naiveEnd: Int) -> Int {
        let searchWindow = 40
        let searchStart = max(0, naiveEnd - searchWindow)
        let searchStartIndex = text.index(text.startIndex, offsetBy: searchStart)
        let naiveEndIndex = text.index(text.startIndex, offsetBy: naiveEnd)
        let window = text[searchStartIndex..<naiveEndIndex]

        if let periodRange = window.range(of: ".", options: .backwards) {
            let offsetInWindow = window.distance(from: window.startIndex, to: periodRange.lowerBound)
            return searchStart + offsetInWindow + 1
        }
        return naiveEnd
    }
}
