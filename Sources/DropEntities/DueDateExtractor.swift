import Foundation

/// Détection d'une échéance explicite (§5, backlog V2, DRO-84). Contrairement à `DateExtractor`,
/// qui trouve toute date sans distinction de rôle, celle-ci n'accepte une date que si elle suit de
/// près une formule de contexte sans ambiguïté — jamais une date isolée, qui resterait indécidable
/// entre émission, prise d'effet et échéance (§5.3.3, la même prudence que `EffectiveDate`).
public struct DueDateExtractor: Sendable {
    private let dateExtractor = DateExtractor()

    public init() {}

    public func extract(from text: String, pageNo: Int? = nil) -> [ExtractedEntity] {
        var seenDates = Set<String>()
        var results: [ExtractedEntity] = []
        for keyword in Self.contextKeywords {
            for entity in matches(forKeyword: keyword, in: text, pageNo: pageNo) {
                guard let valueDate = entity.valueDate, seenDates.insert(valueDate).inserted else { continue }
                results.append(entity)
            }
        }
        return results
    }

    /// La date recherchée doit apparaître dans une fenêtre courte après le mot-clé (§5.3.2, même
    /// principe que le contexte d'émission) — une formule à une extrémité du document et une date
    /// sans rapport à l'autre bout ne doivent jamais être associées.
    private func matches(forKeyword keyword: String, in text: String, pageNo: Int?) -> [ExtractedEntity] {
        guard let regex = try? NSRegularExpression(
            pattern: NSRegularExpression.escapedPattern(for: keyword), options: .caseInsensitive
        ) else { return [] }

        let nsText = text as NSString
        var results: [ExtractedEntity] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let windowStart = match.range.location + match.range.length
            let windowLength = min(Self.contextWindowLength, nsText.length - windowStart)
            guard windowLength > 0 else { continue }
            let window = nsText.substring(with: NSRange(location: windowStart, length: windowLength))

            for dateEntity in dateExtractor.extract(from: window, pageNo: pageNo).sorted(by: { $0.confidence > $1.confidence }) {
                results.append(ExtractedEntity(
                    kind: .dueDate, valueText: dateEntity.valueText, rawText: "\(keyword)\(window)",
                    extractor: .regex, confidence: dateEntity.confidence, valueDate: dateEntity.valueDate,
                    pageNo: pageNo
                ))
            }
        }
        return results
    }

    private static let contextWindowLength = 30

    private static let contextKeywords = [
        "date limite de paiement", "date limite de règlement", "date limite",
        "à régler avant le", "à payer avant le", "avant le",
        "date d'échéance", "échéance le", "échéance :", "expire le", "valable jusqu'au",
    ]
}
