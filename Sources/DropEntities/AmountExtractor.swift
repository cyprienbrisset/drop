import Foundation

/// Extraction déterministe des montants (§5.3.1). Uniquement le déterministe produit des
/// montants — jamais le modèle de langage (ADR-09, EF-43).
public struct AmountExtractor: Sendable {
    public init() {}

    public func extract(from text: String, pageNo: Int? = nil) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []
        entities.append(contentsOf: extractCurrencyAnchored(text, pageNo: pageNo))
        entities.append(contentsOf: extractKeywordAnchored(text, excluding: entities, pageNo: pageNo))
        return entities
    }

    /// Heuristique de sélection du montant principal (§5.3.1) : le montant précédé d'un mot-clé
    /// de type « total », « net à payer », « montant TTC », « à régler » l'emporte ; à défaut, le
    /// dernier montant du texte fourni (censé être la page dominante).
    public func principalAmount(among entities: [ExtractedEntity]) -> ExtractedEntity? {
        let amounts = entities.filter { $0.kind == .amount }
        if let keyworded = amounts.last(where: { $0.extractor == .regex && $0.confidence >= 1.0 && $0.rawText.lowercased().contains("keyword:") }) {
            return keyworded
        }
        return amounts.last
    }

    // MARK: - Montants ancrés à un symbole ou un code devise (haute confiance)

    private func extractCurrencyAnchored(_ text: String, pageNo: Int?) -> [ExtractedEntity] {
        let number = #"(?:\d{1,3}(?:[.,\s]\d{3})+(?:[.,]\d{2})?|\d+(?:[.,]\d{2})?)"#
        let pattern = #"(?:(€|\$|£)\s?(\#(number))|(\#(number))\s?(€|EUR|eur|USD|usd|\$|£|GBP|gbp))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsText = text as NSString
        var results: [ExtractedEntity] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let fullRange = match.range
            guard let fullTextRange = Range(fullRange, in: text) else { continue }
            let rawText = String(text[fullTextRange])

            let symbolBefore = Self.group(match, 1, in: text)
            let numberAfterSymbol = Self.group(match, 2, in: text)
            let numberBeforeCode = Self.group(match, 3, in: text)
            let codeAfter = Self.group(match, 4, in: text)

            let numberString = numberAfterSymbol ?? numberBeforeCode
            let currencyMarker = symbolBefore ?? codeAfter
            guard let numberString, let value = Self.normalizeAmount(numberString) else { continue }
            guard Self.isPlausibleAmount(value) else { continue }

            results.append(ExtractedEntity(
                kind: .amount, valueText: String(format: "%.2f", value), rawText: rawText, extractor: .regex,
                confidence: 1.0, valueNum: value, currency: Self.currencyCode(fromMarker: currencyMarker), pageNo: pageNo
            ))
        }
        return results
    }

    // MARK: - Montants ancrés à un mot-clé monétaire (contexte, sans symbole)

    private static let amountKeywords = ["total", "net à payer", "montant ttc", "montant", "à régler", "solde", "prix"]
    private static let nonMonetaryUnits = ["kg", "g", "m", "cm", "km", "%", "jours", "mois", "ans", "unités", "pcs"]

    private func extractKeywordAnchored(_ text: String, excluding existing: [ExtractedEntity], pageNo: Int?) -> [ExtractedEntity] {
        let number = #"(?:\d{1,3}(?:[.,\s]\d{3})+(?:[.,]\d{2})?|\d+[.,]\d{2})"#
        let pattern = #"(?i)\b(total|net à payer|montant ttc|montant|à régler|solde|prix)\b[^0-9€$£]{0,15}(\#(number))(?!\s?(?:kg|g|cm|km|%|jours?|mois|ans|unités|pcs)\b)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsText = text as NSString
        var results: [ExtractedEntity] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let fullTextRange = Range(match.range, in: text),
                  let numberString = Self.group(match, 2, in: text),
                  let value = Self.normalizeAmount(numberString), Self.isPlausibleAmount(value)
            else { continue }

            let rawText = String(text[fullTextRange])
            // Déjà capturé par un motif ancré à un symbole/code : éviter le doublon.
            if existing.contains(where: { $0.valueNum == value }) { continue }

            results.append(ExtractedEntity(
                kind: .amount, valueText: String(format: "%.2f", value), rawText: "keyword:\(rawText)", extractor: .regex,
                confidence: 1.0, valueNum: value, currency: "EUR", pageNo: pageNo
            ))
        }
        return results
    }

    // MARK: - Normalisation et rejet des faux positifs

    /// Retire les séparateurs de milliers, convertit la virgule décimale, à partir d'une chaîne
    /// numérique brute (§5.3.1). Le séparateur décimal est celui suivi d'exactement 2 chiffres.
    public static func normalizeAmount(_ raw: String) -> Double? {
        let decimalSeparator: String.Index?
        if let lastComma = raw.lastIndex(of: ","), raw.distance(from: lastComma, to: raw.endIndex) == 3 {
            decimalSeparator = lastComma
        } else if let lastDot = raw.lastIndex(of: "."), raw.distance(from: lastDot, to: raw.endIndex) == 3 {
            decimalSeparator = lastDot
        } else {
            decimalSeparator = nil
        }

        guard let decimalSeparator else {
            let digitsOnly = raw.filter(\.isNumber)
            return digitsOnly.isEmpty ? nil : Double(digitsOnly)
        }

        let integerPart = raw[raw.startIndex..<decimalSeparator].filter(\.isNumber)
        let decimalPart = raw[raw.index(after: decimalSeparator)...].filter(\.isNumber)
        guard !integerPart.isEmpty else { return nil }
        return Double("\(integerPart).\(decimalPart)")
    }

    /// Rejet des faux positifs évidents (§5.3.1) : années isolées, montants absurdement grands
    /// (probablement un numéro de référence mal filtré).
    static func isPlausibleAmount(_ value: Double) -> Bool {
        value > 0 && value < 100_000_000
    }

    static func currencyCode(fromMarker marker: String?) -> String {
        switch marker?.lowercased() {
        case "€", "eur": return "EUR"
        case "$", "usd": return "USD"
        case "£", "gbp": return "GBP"
        default: return "EUR"
        }
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound, let textRange = Range(range, in: text) else { return nil }
        return String(text[textRange])
    }
}
