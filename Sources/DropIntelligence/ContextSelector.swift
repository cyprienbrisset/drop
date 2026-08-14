import Foundation

/// Une page de texte, telle qu'extraite par `DropExtraction` (§5.2).
public struct PageContent: Sendable, Equatable {
    public let pageNumber: Int
    public let text: String

    public init(pageNumber: Int, text: String) {
        self.pageNumber = pageNumber
        self.text = text
    }
}

/// Sélection du contexte envoyé au modèle (§5.4.3) : un PDF de 15 pages n'entre pas dans la
/// fenêtre du modèle on-device. On tronque, on n'appelle pas le modèle en boucle — le coût
/// énergétique et la latence de N appels sur un corpus de 10 000 documents sont rédhibitoires.
///
/// Ordre de sélection, plafond ~2 500 tokens :
/// 1. Intégralité de la première page (jusqu'à 1 200 tokens).
/// 2. Fenêtres de ±300 caractères autour des zones les plus denses en entités déterministes.
/// 3. Derniers 400 tokens de la dernière page (totaux, signatures, mentions légales).
/// 4. Nom de fichier et étiquettes visuelles éventuelles.
///
/// Le nombre de tokens n'est qu'approché (aucun tokenizer du modèle n'est exposé publiquement) :
/// ~4 caractères par token, une heuristique usuelle pour du texte français/anglais courant.
public struct ContextSelector: Sendable {
    public let tokenBudget: Int
    private let charsPerToken = 4

    public init(tokenBudget: Int = 2500) {
        self.tokenBudget = tokenBudget
    }

    public func select(
        pages: [PageContent], denseEntityOffsets: [Int: [Int]] = [:], filename: String, visualLabels: [String] = []
    ) -> String {
        guard !pages.isEmpty else { return filename }

        var remainingBudget = tokenBudget
        var parts: [String] = []

        if let first = pages.first {
            let piece = truncate(first.text, toTokens: min(1200, remainingBudget))
            if !piece.isEmpty {
                parts.append(piece)
                remainingBudget -= tokenCount(of: piece)
            }
        }

        for page in pages {
            guard remainingBudget > 0 else { break }
            guard let offsets = denseEntityOffsets[page.pageNumber] else { continue }
            for offset in offsets {
                guard remainingBudget > 0 else { break }
                let window = window(around: offset, in: page.text, radius: 300)
                guard !window.isEmpty else { continue }
                let windowTokens = tokenCount(of: window)
                guard windowTokens <= remainingBudget else { continue }
                parts.append(window)
                remainingBudget -= windowTokens
            }
        }

        if let last = pages.last, remainingBudget > 0 {
            let piece = lastTokens(of: last.text, count: min(400, remainingBudget))
            if !piece.isEmpty {
                parts.append(piece)
                remainingBudget -= tokenCount(of: piece)
            }
        }

        var footer = filename
        if !visualLabels.isEmpty {
            footer += " " + visualLabels.joined(separator: " ")
        }
        parts.append(footer)

        return parts.joined(separator: "\n---\n")
    }

    // MARK: - Approximation de tokenisation

    func tokenCount(of text: String) -> Int {
        max(1, text.count / charsPerToken)
    }

    private func truncate(_ text: String, toTokens tokens: Int) -> String {
        guard tokens > 0 else { return "" }
        let maxChars = tokens * charsPerToken
        guard text.count > maxChars else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[text.startIndex..<endIndex])
    }

    private func lastTokens(of text: String, count tokens: Int) -> String {
        guard tokens > 0 else { return "" }
        let maxChars = tokens * charsPerToken
        guard text.count > maxChars else { return text }
        let startIndex = text.index(text.endIndex, offsetBy: -maxChars)
        return String(text[startIndex...])
    }

    private func window(around charOffset: Int, in text: String, radius: Int) -> String {
        guard charOffset >= 0, charOffset < text.count else { return "" }
        let start = max(0, charOffset - radius)
        let end = min(text.count, charOffset + radius)
        guard start < end else { return "" }
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(text.startIndex, offsetBy: end)
        return String(text[startIndex..<endIndex])
    }
}
