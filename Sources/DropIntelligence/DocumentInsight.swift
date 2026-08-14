import FoundationModels

/// Rôle strictement borné du modèle de langage (§5.4.1, §5.4.2) : type, émetteur si le
/// dictionnaire a échoué, résumé d'une phrase, mots-clés. Jamais de montant, de date, d'IBAN ni
/// de référence (ADR-09) — ces valeurs viennent exclusivement des extracteurs déterministes.
@Generable
public enum DocumentType: String, CaseIterable, Sendable {
    case facture, devis, contrat, releveBancaire, bulletinPaie
    case attestation, courrier, ordonnance, ticket, garantie
    case impots, cv, identite, captureEcran, photo, autre
}

@Generable
public struct DocumentInsight: Sendable {
    @Guide(description: "Type du document, choisi dans la liste. 'autre' si aucun ne convient.")
    public let type: DocumentType

    @Guide(description: "Organisation émettrice telle qu'elle apparaît dans le texte. nil si absente.")
    public let issuer: String?

    @Guide(description: "Une phrase factuelle de 25 mots maximum. Aucune formule d'introduction. Aucun montant, aucune date.")
    public let summary: String

    @Guide(description: "Trois à six mots-clés en minuscules, tirés du document.", .count(3...6))
    public let keywords: [String]

    @Guide(description: "Confiance globale entre 0 et 1.")
    public let confidence: Double
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
