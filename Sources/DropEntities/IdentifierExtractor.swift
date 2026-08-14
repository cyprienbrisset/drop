import Foundation

/// Extraction déterministe des identifiants (§5.3.4) : IBAN, SIRET/SIREN, TVA intracommunautaire,
/// références de facture/commande, RIB, courriel, téléphone.
public struct IdentifierExtractor: Sendable {
    public init() {}

    public func extract(from text: String, pageNo: Int? = nil) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []
        entities.append(contentsOf: extractIBAN(text, pageNo: pageNo))
        entities.append(contentsOf: extractSIRETAndSIREN(text, pageNo: pageNo))
        entities.append(contentsOf: extractVAT(text, pageNo: pageNo))
        entities.append(contentsOf: extractInvoiceReference(text, pageNo: pageNo))
        entities.append(contentsOf: extractOrderReference(text, pageNo: pageNo))
        entities.append(contentsOf: extractEmail(text, pageNo: pageNo))
        entities.append(contentsOf: extractPhone(text, pageNo: pageNo))
        return entities
    }

    // MARK: - IBAN (FR + zone SEPA, validation mod-97)

    private func extractIBAN(_ text: String, pageNo: Int?) -> [ExtractedEntity] {
        let pattern = #"\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]{2,4}){3,8}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString

        var results: [ExtractedEntity] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let range = Range(match.range, in: text) else { continue }
            let rawText = String(text[range])
            let compact = rawText.replacingOccurrences(of: " ", with: "").uppercased()
            guard (15...34).contains(compact.count), Self.isValidIBAN(compact) else { continue }
            results.append(ExtractedEntity(kind: .iban, valueText: compact, rawText: rawText, extractor: .regex, pageNo: pageNo))
        }
        return results
    }

    /// Mod-97 (§5.3.4) : déplace les 4 premiers caractères en fin, convertit les lettres
    /// (A=10…Z=35), le nombre obtenu doit être congru à 1 modulo 97.
    static func isValidIBAN(_ iban: String) -> Bool {
        guard iban.count >= 15 else { return false }
        let rearranged = String(iban.dropFirst(4)) + String(iban.prefix(4))
        var digits = ""
        for character in rearranged {
            if let value = character.wholeNumberValue, character.isNumber {
                digits += String(value)
            } else if let ascii = character.asciiValue, character.isLetter {
                digits += String(Int(ascii) - 55) // A=10 ... Z=35
            } else {
                return false
            }
        }
        return mod97(ofNumericString: digits) == 1
    }

    private static func mod97(ofNumericString digits: String) -> Int {
        var remainder = 0
        for character in digits {
            guard let digit = character.wholeNumberValue else { return -1 }
            remainder = (remainder * 10 + digit) % 97
        }
        return remainder
    }

    // MARK: - SIRET (14 chiffres) et SIREN (9 chiffres), validation Luhn

    private func extractSIRETAndSIREN(_ text: String, pageNo: Int?) -> [ExtractedEntity] {
        var results: [ExtractedEntity] = []
        results.append(contentsOf: extractDigitSequences(text, length: 14, kind: .siret, pageNo: pageNo))
        // On évite de redétecter comme SIREN les 9 premiers chiffres d'un SIRET déjà validé.
        let sirets = Set(results.map { $0.valueText })
        let sirens = extractDigitSequences(text, length: 9, kind: .siren, pageNo: pageNo)
            .filter { siren in !sirets.contains { $0.hasPrefix(siren.valueText) } }
        results.append(contentsOf: sirens)
        return results
    }

    private func extractDigitSequences(_ text: String, length: Int, kind: ExtractedEntity.Kind, pageNo: Int?) -> [ExtractedEntity] {
        let pattern = "\\b(?:\\d[ ]?){\(length)}\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString

        var results: [ExtractedEntity] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let range = Range(match.range, in: text) else { continue }
            let rawText = String(text[range])
            let digits = rawText.filter(\.isNumber)
            guard digits.count == length, Self.isValidLuhn(digits) else { continue }
            results.append(ExtractedEntity(kind: kind, valueText: digits, rawText: rawText, extractor: .regex, pageNo: pageNo))
        }
        return results
    }

    static func isValidLuhn(_ digits: String) -> Bool {
        let numbers = digits.reversed().compactMap { $0.wholeNumberValue }
        guard numbers.count == digits.count else { return false }
        var sum = 0
        for (index, digit) in numbers.enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    // MARK: - TVA intracommunautaire

    private func extractVAT(_ text: String, pageNo: Int?) -> [ExtractedEntity] {
        let pattern = #"\bFR[ ]?[A-Z0-9]{2}[ ]?\d{9}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString

        var results: [ExtractedEntity] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let range = Range(match.range, in: text) else { continue }
            let rawText = String(text[range])
            let compact = rawText.replacingOccurrences(of: " ", with: "").uppercased()
            results.append(ExtractedEntity(kind: .vat, valueText: compact, rawText: rawText, extractor: .regex, pageNo: pageNo))
        }
        return results
    }

    // MARK: - Références facture / commande

    private func extractInvoiceReference(_ text: String, pageNo: Int?) -> [ExtractedEntity] {
        let pattern = #"(?i)\b(?:facture\s*n[°o]?\s*[:\s]?|FA[ -]?|F-)([A-Z0-9][A-Z0-9\-]{2,20})\b"#
        return extractReference(text, pattern: pattern, kind: .invoiceRef, pageNo: pageNo)
    }

    private func extractOrderReference(_ text: String, pageNo: Int?) -> [ExtractedEntity] {
        let pattern = #"(?i)\b(?:commande\s*n[°o]?\s*[:\s]?|réf(?:érence)?\.?\s*commande\s*[:\s]?)([A-Z0-9][A-Z0-9\-]{2,20})\b"#
        return extractReference(text, pattern: pattern, kind: .orderRef, pageNo: pageNo)
    }

    private func extractReference(_ text: String, pattern: String, kind: ExtractedEntity.Kind, pageNo: Int?) -> [ExtractedEntity] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString

        var results: [ExtractedEntity] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard match.numberOfRanges > 1, let fullRange = Range(match.range, in: text),
                  let refRange = Range(match.range(at: 1), in: text)
            else { continue }
            results.append(ExtractedEntity(
                kind: kind, valueText: String(text[refRange]), rawText: String(text[fullRange]), extractor: .regex, pageNo: pageNo
            ))
        }
        return results
    }

    // MARK: - Courriel

    private func extractEmail(_ text: String, pageNo: Int?) -> [ExtractedEntity] {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let nsText = text as NSString

        var results: [ExtractedEntity] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let range = Range(match.range, in: text) else { continue }
            let rawText = String(text[range])
            results.append(ExtractedEntity(kind: .email, valueText: rawText.lowercased(), rawText: rawText, extractor: .regex, pageNo: pageNo))
        }
        return results
    }

    // MARK: - Téléphone (FR et international)

    private func extractPhone(_ text: String, pageNo: Int?) -> [ExtractedEntity] {
        let pattern = #"(?:\+33[ .]?|0)[1-9](?:[ .]?\d{2}){4}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString

        var results: [ExtractedEntity] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let range = Range(match.range, in: text) else { continue }
            let rawText = String(text[range])
            let digits = rawText.filter(\.isNumber)
            let normalized = digits.hasPrefix("33") ? "+\(digits)" : digits
            results.append(ExtractedEntity(kind: .phone, valueText: normalized, rawText: rawText, extractor: .regex, pageNo: pageNo))
        }
        return results
    }
}
