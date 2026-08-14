/// Rôle strictement borné du modèle de langage (§5.4.1) : type, émetteur si le dictionnaire a échoué,
/// résumé d'une phrase, mots-clés. Jamais de montant, de date, d'IBAN ni de référence (ADR-09).
/// Deviendra un `@Generable` (FoundationModels) dès l'intégration réelle en Phase 5 (DRO-38).
public enum DocumentType: String, CaseIterable, Sendable {
    case facture, devis, contrat, releveBancaire, bulletinPaie
    case attestation, courrier, ordonnance, ticket, garantie
    case impots, cv, identite, captureEcran, photo, autre
}

public struct DocumentInsight: Sendable {
    public let type: DocumentType
    public let issuer: String?
    public let summary: String
    public let keywords: [String]
    public let confidence: Double

    public init(type: DocumentType, issuer: String?, summary: String, keywords: [String], confidence: Double) {
        self.type = type
        self.issuer = issuer
        self.summary = summary
        self.keywords = keywords
        self.confidence = confidence
    }
}

/// Chaque état a un comportement et un message définis (§5.4.4). Le produit reste utilisable
/// sans Apple Intelligence : seuls le résumé et la classification fine sont indisponibles.
public enum IntelligenceAvailability: Sendable {
    case available
    case unavailableDeviceNotEligible
    case unavailableAppleIntelligenceNotEnabled
    case unavailableModelNotReady
    case inferenceError
}
