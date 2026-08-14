/// Entité déterministe extraite d'un document (§5.3) : montant, date, IBAN, SIRET, organisation...
/// Toujours issue d'un extracteur regex/métadonnée — jamais du modèle de langage (ADR-09).
public struct ExtractedEntity: Sendable {
    public enum Kind: String, Sendable {
        case amount, date, iban, siret, siren, vat, invoiceRef, orderRef, org, email, phone, person
        /// Date d'échéance (§5, backlog V2, DRO-84) : distincte de `date`, qui ne porte aucune
        /// indication de rôle sémantique — celle-ci ne provient que d'un contexte explicite
        /// (« à régler avant le », « date limite », « échéance le »...).
        case dueDate
    }

    public enum Extractor: String, Sendable {
        case regex, metadata, model, user
    }

    public let kind: Kind
    public let valueText: String
    public let rawText: String
    public let extractor: Extractor
    public let confidence: Double
    /// Montant normalisé (kind == .amount).
    public let valueNum: Double?
    /// Date normalisée ISO 8601 `yyyy-MM-dd` (kind == .date).
    public let valueDate: String?
    /// Code devise ISO (kind == .amount), ex. "EUR".
    public let currency: String?
    public let pageNo: Int?

    public init(
        kind: Kind, valueText: String, rawText: String, extractor: Extractor, confidence: Double = 1.0,
        valueNum: Double? = nil, valueDate: String? = nil, currency: String? = nil, pageNo: Int? = nil
    ) {
        self.kind = kind
        self.valueText = valueText
        self.rawText = rawText
        self.extractor = extractor
        self.confidence = confidence
        self.valueNum = valueNum
        self.valueDate = valueDate
        self.currency = currency
        self.pageNo = pageNo
    }
}
