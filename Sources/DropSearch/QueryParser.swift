import DropCore
import Foundation

/// Grammaire déterministe (§5.6) : décompose une requête en langage naturel sans aucun appel au
/// modèle de langage — le budget de latence (EF-62) l'interdit, et cette contrainte a un bénéfice
/// second : les filtres restent opérationnels même en pipeline dégradé, sans Apple Intelligence.
public struct QueryParser: Sendable {
    private let clock: DropClock
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2 // lundi
        return calendar
    }

    public init(clock: DropClock = SystemClock()) {
        self.clock = clock
    }

    public func parse(_ rawQuery: String) -> ParsedQuery {
        var result = ParsedQuery()
        var text = rawQuery

        text = extractPhrases(from: text, into: &result)
        text = extractExclusions(from: text, into: &result)
        text = extractTags(from: text, into: &result)
        text = extractExplicitFilters(from: text, into: &result)
        text = extractAmounts(from: text, into: &result)
        text = extractDates(from: text, into: &result)
        text = extractDocTypes(from: text, into: &result)

        result.freeText = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    // MARK: - Phrases, exclusions, tags

    private func extractPhrases(from text: String, into result: inout ParsedQuery) -> String {
        replacing(#""([^"]+)""#, in: text) { match in
            result.phrases.append(match[1])
            return " "
        }
    }

    private func extractExclusions(from text: String, into result: inout ParsedQuery) -> String {
        replacing(#"(?<=^|\s)-(\S+)"#, in: text) { match in
            result.excluded.append(match[1])
            return " "
        }
    }

    private func extractTags(from text: String, into result: inout ParsedQuery) -> String {
        replacing(#"#(\S+)"#, in: text) { match in
            result.tags.append(match[1])
            return " "
        }
    }

    // MARK: - Syntaxe avancée (EF-66) : type:pdf, avant:2025-03-01, après:2025-01-01

    private func extractExplicitFilters(from text: String, into result: inout ParsedQuery) -> String {
        var text = replacing(#"type:(\S+)"#, in: text) { match in
            result.fileKinds.append(match[1].lowercased())
            return " "
        }
        text = replacing(#"avant:(\d{4}-\d{2}-\d{2})"#, in: text) { match in
            if let date = Self.isoDayFormatter.date(from: match[1]) {
                result.dateRange = Self.extend(result.dateRange, withEnd: date)
            }
            return " "
        }
        text = replacing(#"apr[eè]s:(\d{4}-\d{2}-\d{2})"#, in: text) { match in
            if let date = Self.isoDayFormatter.date(from: match[1]) {
                result.dateRange = Self.extend(result.dateRange, withStart: date)
            }
            return " "
        }
        return text
    }

    // MARK: - Montants (EF-64)

    private func extractAmounts(from text: String, into result: inout ParsedQuery) -> String {
        var text = text

        text = replacing(#"entre\s+(\d+(?:[.,]\d+)?)\s*(?:€|eur(?:os?)?)?\s+et\s+(\d+(?:[.,]\d+)?)\s*(€|eur(?:os?)?)?"#, in: text) { match in
            guard let low = Self.parseNumber(match[1]), let high = Self.parseNumber(match[2]) else { return match[0] }
            result.amountRange = min(low, high)...max(low, high)
            if !match[3].isEmpty { result.currency = "EUR" }
            return " "
        }
        text = replacing(#"(?:plus de|à partir de|au moins)\s+(\d+(?:[.,]\d+)?)\s*(€|eur(?:os?)?)?"#, in: text) { match in
            guard let value = Self.parseNumber(match[1]) else { return match[0] }
            result.amountRange = value...Double.greatestFiniteMagnitude
            if !match[2].isEmpty { result.currency = "EUR" }
            return " "
        }
        text = replacing(#"(?:moins de|au plus)\s+(\d+(?:[.,]\d+)?)\s*(€|eur(?:os?)?)?"#, in: text) { match in
            guard let value = Self.parseNumber(match[1]) else { return match[0] }
            result.amountRange = 0...value
            if !match[2].isEmpty { result.currency = "EUR" }
            return " "
        }
        text = replacing(#"environ\s+(\d+(?:[.,]\d+)?)\s*(€|eur(?:os?)?)?"#, in: text) { match in
            guard let value = Self.parseNumber(match[1]) else { return match[0] }
            let tolerance = value * 0.10
            result.amountRange = (value - tolerance)...(value + tolerance)
            if !match[2].isEmpty { result.currency = "EUR" }
            return " "
        }
        return text
    }

    // MARK: - Dates (EF-63)

    private func extractDates(from text: String, into result: inout ParsedQuery) -> String {
        let now = clock.now()
        var text = text

        text = replacing(#"\baujourd'hui\b"#, in: text) { _ in
            result.dateRange = self.dayInterval(containing: now)
            return " "
        }
        text = replacing(#"\bhier\b"#, in: text) { _ in
            result.dateRange = self.dayInterval(containing: self.calendar.date(byAdding: .day, value: -1, to: now)!)
            return " "
        }
        text = replacing(#"\bcette semaine\b"#, in: text) { _ in
            result.dateRange = self.weekInterval(containing: now)
            return " "
        }
        text = replacing(#"\bla semaine derni[eè]re\b"#, in: text) { _ in
            result.dateRange = self.weekInterval(containing: self.calendar.date(byAdding: .weekOfYear, value: -1, to: now)!)
            return " "
        }
        text = replacing(#"\ble mois dernier\b"#, in: text) { _ in
            result.dateRange = self.monthInterval(containing: self.calendar.date(byAdding: .month, value: -1, to: now)!)
            return " "
        }
        text = replacing(#"\bce mois\b"#, in: text) { _ in
            result.dateRange = self.monthInterval(containing: now)
            return " "
        }
        text = replacing(#"il y a\s+(\d+)\s+mois\b"#, in: text) { match in
            guard let count = Int(match[1]) else { return match[0] }
            result.dateRange = self.monthInterval(containing: self.calendar.date(byAdding: .month, value: -count, to: now)!)
            return " "
        }
        text = replacing(#"depuis\s+(\p{L}+)"#, in: text) { match in
            if let monthIndex = Self.monthIndex(forName: match[1]) {
                let year = self.calendar.component(.year, from: now)
                if let start = self.calendar.date(from: DateComponents(year: year, month: monthIndex, day: 1)) {
                    result.dateRange = DateInterval(start: start, end: now)
                }
                return " "
            }
            return match[0]
        }
        text = replacing(#"avant\s+(\d{4})\b"#, in: text) { match in
            guard let year = Int(match[1]),
                  let end = self.calendar.date(from: DateComponents(year: year, month: 1, day: 1))
            else { return match[0] }
            result.dateRange = DateInterval(start: .distantPast, end: end)
            return " "
        }
        text = replacing(#"entre\s+(\p{L}+)\s+et\s+(\p{L}+)\b"#, in: text) { match in
            guard let startMonth = Self.monthIndex(forName: match[1]), let endMonth = Self.monthIndex(forName: match[2])
            else { return match[0] }
            let year = self.calendar.component(.year, from: now)
            guard let start = self.calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)),
                  let endMonthStart = self.calendar.date(from: DateComponents(year: year, month: endMonth, day: 1)),
                  let end = self.calendar.date(byAdding: DateComponents(month: 1, day: -1), to: endMonthStart)
            else { return match[0] }
            result.dateRange = DateInterval(start: start, end: self.calendar.startOfDay(for: end).addingTimeInterval(86400))
            return " "
        }
        text = replacing(#"(?:en\s+)?(\p{L}+)\s+(\d{4})\b"#, in: text) { match in
            guard let monthIndex = Self.monthIndex(forName: match[1]), let year = Int(match[2]) else { return match[0] }
            result.dateRange = self.monthInterval(forYear: year, month: monthIndex)
            return " "
        }
        text = replacing(#"\b(?:en|de)\s+(\p{L}+)\b"#, in: text) { match in
            guard let monthIndex = Self.monthIndex(forName: match[1]) else { return match[0] }
            let year = self.calendar.component(.year, from: now)
            result.dateRange = self.monthInterval(forYear: year, month: monthIndex)
            return " "
        }
        text = replacing(#"\b(\d{4})\b"#, in: text) { match in
            guard let year = Int(match[1]) else { return match[0] }
            result.dateRange = self.yearInterval(forYear: year)
            return " "
        }

        return text
    }

    // MARK: - Types de documents (EF-65)

    private func extractDocTypes(from text: String, into result: inout ParsedQuery) -> String {
        var remaining = text
        for (keyword, canonical) in Self.docTypeKeywords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            let matched = replacing(pattern, in: remaining, caseInsensitive: true) { _ in
                if !result.docTypes.contains(canonical) { result.docTypes.append(canonical) }
                return " "
            }
            remaining = matched
        }
        return remaining
    }

    // MARK: - Aides temporelles

    private func dayInterval(containing date: Date) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
    }

    private func weekInterval(containing date: Date) -> DateInterval {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)!
        return interval
    }

    private func monthInterval(containing date: Date) -> DateInterval {
        let interval = calendar.dateInterval(of: .month, for: date)!
        return interval
    }

    private func monthInterval(forYear year: Int, month: Int) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }

    private func yearInterval(forYear year: Int) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        return DateInterval(start: start, end: end)
    }

    // MARK: - Utilitaires

    /// Applique un remplacement regex, en passant à la closure les groupes captés (`match[0]` =
    /// texte entier, `match[1...]` = groupes).
    private func replacing(
        _ pattern: String, in text: String, caseInsensitive: Bool = true, _ body: ([String]) -> String
    ) -> String {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if !caseInsensitive { options = [] }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }

        var result = ""
        var lastEnd = text.startIndex
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            result += text[lastEnd..<range.lowerBound]

            var groups: [String] = []
            for groupIndex in 0..<match.numberOfRanges {
                let groupRange = match.range(at: groupIndex)
                if groupRange.location == NSNotFound {
                    groups.append("")
                } else if let r = Range(groupRange, in: text) {
                    groups.append(String(text[r]))
                } else {
                    groups.append("")
                }
            }
            result += body(groups)
            lastEnd = range.upperBound
        }
        result += text[lastEnd...]
        return result
    }

    private static func parseNumber(_ raw: String) -> Double? {
        Double(raw.replacingOccurrences(of: ",", with: "."))
    }

    private static func extend(_ interval: DateInterval?, withStart start: Date) -> DateInterval {
        DateInterval(start: start, end: interval?.end ?? .distantFuture)
    }

    private static func extend(_ interval: DateInterval?, withEnd end: Date) -> DateInterval {
        DateInterval(start: interval?.start ?? .distantPast, end: end)
    }

    private static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let monthNames: [String: Int] = [
        "janvier": 1, "janv": 1, "février": 2, "fevrier": 2, "févr": 2, "fevr": 2,
        "mars": 3, "avril": 4, "avr": 4, "mai": 5,
        "juin": 6, "juillet": 7, "juil": 7, "août": 8, "aout": 8,
        "septembre": 9, "sept": 9, "octobre": 10, "oct": 10,
        "novembre": 11, "nov": 11, "décembre": 12, "decembre": 12, "déc": 12, "dec": 12,
    ]

    private static func monthIndex(forName name: String) -> Int? {
        monthNames[name.lowercased()]
    }

    /// Dictionnaire de types reconnus (EF-65), mappé vers la valeur canonique `DocumentType`
    /// (§5.4.2). Recensé ici plutôt que dans `DropIntelligence` pour ne pas introduire une
    /// dépendance croisée entre modules pairs (§4.2 règle 1).
    private static let docTypeKeywords: [(keyword: String, canonical: String)] = [
        ("factures", "facture"), ("facture", "facture"),
        ("devis", "devis"),
        ("contrats", "contrat"), ("contrat", "contrat"),
        ("relevés bancaires", "releveBancaire"), ("relevé bancaire", "releveBancaire"), ("relevés", "releveBancaire"), ("relevé", "releveBancaire"),
        ("bulletins de paie", "bulletinPaie"), ("bulletin de paie", "bulletinPaie"),
        ("attestations", "attestation"), ("attestation", "attestation"),
        ("courriers", "courrier"), ("courrier", "courrier"),
        ("ordonnances", "ordonnance"), ("ordonnance", "ordonnance"),
        ("tickets", "ticket"), ("ticket", "ticket"),
        ("garanties", "garantie"), ("garantie", "garantie"),
        ("impôts", "impots"), ("impots", "impots"),
        ("cv", "cv"),
        ("captures d'écran", "captureEcran"), ("capture d'écran", "captureEcran"),
        ("photos", "photo"), ("photo", "photo"),
    ]
}
