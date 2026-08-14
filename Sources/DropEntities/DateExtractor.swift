import Foundation

/// Extraction déterministe des dates (§5.3.2). Lecture `fr_FR` prioritaire : `03/04/2025` est le
/// 3 avril, jamais le 4 mars. Ambiguïté irréductible → confiance 0,6, deux lectures indexées.
public struct DateExtractor: Sendable {
    public init() {}

    public func extract(from text: String, pageNo: Int? = nil) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []
        entities.append(contentsOf: extractNumeric(text, pageNo: pageNo))
        entities.append(contentsOf: extractTextualMonth(text, pageNo: pageNo))
        return entities
    }

    // MARK: - Formats numériques : JJ/MM/AAAA, JJ-MM-AAAA, JJ.MM.AAAA, AAAA-MM-JJ

    private func extractNumeric(_ text: String, pageNo: Int?) -> [ExtractedEntity] {
        var results: [ExtractedEntity] = []

        // AAAA-MM-JJ (ISO) : jamais ambigu, l'année à 4 chiffres lève toute ambiguïté.
        results.append(contentsOf: matches(
            in: text, pattern: #"\b(\d{4})-(\d{2})-(\d{2})\b"#
        ) { groups, rawText in
            guard let year = Int(groups[1]), let month = Int(groups[2]), let day = Int(groups[3]),
                  Self.isValidDate(year: year, month: month, day: day)
            else { return [] }
            return [Self.entity(year: year, month: month, day: day, rawText: rawText, confidence: 1.0, pageNo: pageNo)]
        })

        // JJ/MM/AAAA, JJ-MM-AAAA, JJ.MM.AAAA — lecture fr_FR (jour en premier).
        results.append(contentsOf: matches(
            in: text, pattern: #"\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})\b"#
        ) { groups, rawText in
            guard let first = Int(groups[1]), let second = Int(groups[2]), let year = Int(groups[3]) else { return [] }
            return self.resolveDayMonthAmbiguity(first: first, second: second, year: year, rawText: rawText, pageNo: pageNo)
        })

        return results
    }

    /// `03/04/2025` : lu jour/mois (3 avril) en priorité (fr_FR). Si les deux nombres sont ≤ 12 et
    /// différents, l'ambiguïté est irréductible : les deux lectures sont indexées à confiance 0,6.
    private func resolveDayMonthAmbiguity(first: Int, second: Int, year: Int, rawText: String, pageNo: Int?) -> [ExtractedEntity] {
        let firstAsDayValid = Self.isValidDate(year: year, month: second, day: first)
        let secondAsDayValid = Self.isValidDate(year: year, month: first, day: second)

        switch (firstAsDayValid, secondAsDayValid, first == second) {
        case (true, true, true):
            // Même valeur des deux côtés (ex. 05/05) : aucune ambiguïté réelle.
            return [Self.entity(year: year, month: second, day: first, rawText: rawText, confidence: 1.0, pageNo: pageNo)]
        case (true, true, false):
            return [
                Self.entity(year: year, month: second, day: first, rawText: rawText, confidence: 0.6, pageNo: pageNo),
                Self.entity(year: year, month: first, day: second, rawText: rawText, confidence: 0.6, pageNo: pageNo),
            ]
        case (true, false, _):
            return [Self.entity(year: year, month: second, day: first, rawText: rawText, confidence: 1.0, pageNo: pageNo)]
        case (false, true, _):
            return [Self.entity(year: year, month: first, day: second, rawText: rawText, confidence: 1.0, pageNo: pageNo)]
        case (false, false, _):
            return []
        }
    }

    // MARK: - Formats textuels : "12 mars 2025", "mars 2025"

    private func extractTextualMonth(_ text: String, pageNo: Int?) -> [ExtractedEntity] {
        let monthNames = Self.monthNames.keys.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")

        var results: [ExtractedEntity] = []
        results.append(contentsOf: matches(
            in: text, pattern: #"\b(\d{1,2})\s+(\#(monthNames))\s+(\d{4})\b"#, caseInsensitive: true
        ) { groups, rawText in
            guard let day = Int(groups[1]), let month = Self.monthNames[groups[2].lowercased()], let year = Int(groups[3]),
                  Self.isValidDate(year: year, month: month, day: day)
            else { return [] }
            return [Self.entity(year: year, month: month, day: day, rawText: rawText, confidence: 1.0, pageNo: pageNo)]
        })

        results.append(contentsOf: matches(
            in: text, pattern: #"(?<!\d\s)\b(\#(monthNames))\s+(\d{4})\b"#, caseInsensitive: true
        ) { groups, rawText in
            guard let month = Self.monthNames[groups[1].lowercased()], let year = Int(groups[2]) else { return [] }
            return [Self.entity(year: year, month: month, day: 1, rawText: rawText, confidence: 1.0, pageNo: pageNo)]
        })

        return results
    }

    // MARK: - Utilitaires

    private func matches(
        in text: String, pattern: String, caseInsensitive: Bool = false,
        _ body: ([String], String) -> [ExtractedEntity]
    ) -> [ExtractedEntity] {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }

        let nsText = text as NSString
        var results: [ExtractedEntity] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let fullRange = Range(match.range, in: text) else { continue }
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                let range = match.range(at: i)
                if range.location == NSNotFound { groups.append("") }
                else if let r = Range(range, in: text) { groups.append(String(text[r])) }
                else { groups.append("") }
            }
            results.append(contentsOf: body(groups, String(text[fullRange])))
        }
        return results
    }

    private static func isValidDate(year: Int, month: Int, day: Int) -> Bool {
        guard (1..<10000).contains(year), (1...12).contains(month), (1...31).contains(day) else { return false }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: components) else { return false }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == year && resolved.month == month && resolved.day == day
    }

    private static func entity(
        year: Int, month: Int, day: Int, rawText: String, confidence: Double, pageNo: Int?
    ) -> ExtractedEntity {
        let iso = String(format: "%04d-%02d-%02d", year, month, day)
        return ExtractedEntity(
            kind: .date, valueText: iso, rawText: rawText, extractor: .regex, confidence: confidence,
            valueDate: iso, pageNo: pageNo
        )
    }

    private static let monthNames: [String: Int] = [
        "janvier": 1, "février": 2, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6,
        "juillet": 7, "août": 8, "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11, "décembre": 12, "decembre": 12,
    ]
}
