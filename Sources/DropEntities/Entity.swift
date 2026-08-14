/// Entité déterministe extraite d'un document (§5.3) : montant, date, IBAN, SIRET, organisation...
/// Toujours issue d'un extracteur regex/métadonnée — jamais du modèle de langage (ADR-09).
public struct ExtractedEntity: Sendable {
    public enum Kind: String, Sendable {
        case amount, date, iban, siret, vat, invoiceRef, orderRef, org, email, phone, person
    }

    public enum Extractor: String, Sendable {
        case regex, metadata, model, user
    }

    public let kind: Kind
    public let valueText: String
    public let rawText: String
    public let extractor: Extractor
    public let confidence: Double

    public init(kind: Kind, valueText: String, rawText: String, extractor: Extractor, confidence: Double = 1.0) {
        self.kind = kind
        self.valueText = valueText
        self.rawText = rawText
        self.extractor = extractor
        self.confidence = confidence
    }
}
