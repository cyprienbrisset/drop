import FoundationModels

/// Comportement à adopter pour un état donné d'`Apple Intelligence` (§5.4.4). Chaque état a un
/// comportement et un message définis — le produit reste utilisable sans Apple Intelligence.
public enum DegradationBehavior: Sendable, Equatable {
    /// Pipeline complet : type/émetteur/résumé/mots-clés générés par le modèle.
    case fullPipeline
    /// Type par heuristiques + dictionnaire, pas de résumé. `message` est affiché à l'utilisateur.
    case heuristicsAndDictionaryOnly(message: String)
    /// Travaux `insight` remis en file, réessai différé automatique.
    case retryLater(message: String)
    /// Après épuisement des tentatives : aucun message, l'état est visible dans la fiche document.
    case skippedAfterRetries
}

/// §5.4.4 : matrice de dégradation. Sans Apple Intelligence, restent pleinement fonctionnels —
/// métadonnées, OCR, recherche lexicale/temporelle/numérique, heuristiques de type, émetteurs par
/// dictionnaire. Manquent le résumé et la classification fine. C'est ce qui rend le produit
/// viable : la promesse minimale ne dépend pas d'une capacité que l'utilisateur peut désactiver.
public enum DegradationPolicy {
    /// Erreur d'inférence, garde-fous, dépassement : 3 tentatives avec backoff, puis `skipped`.
    public static let maxInferenceAttempts = 3

    public static func behavior(for availability: SystemLanguageModel.Availability) -> DegradationBehavior {
        switch availability {
        case .available:
            return .fullPipeline
        case .unavailable(let reason):
            return behavior(forUnavailableReason: reason)
        }
    }

    private static func behavior(
        forUnavailableReason reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> DegradationBehavior {
        switch reason {
        case .deviceNotEligible:
            return .heuristicsAndDictionaryOnly(
                message: "Ce Mac ne prend pas en charge Apple Intelligence. Drop fonctionne, sans résumé automatique."
            )
        case .appleIntelligenceNotEnabled:
            return .heuristicsAndDictionaryOnly(
                message: "Activez Apple Intelligence pour les résumés et la classification fine."
            )
        case .modelNotReady:
            return .retryLater(
                message: "Modèle en cours de préparation par le système. Analyse reprise automatiquement."
            )
        @unknown default:
            return .heuristicsAndDictionaryOnly(
                message: "Apple Intelligence n'est pas disponible sur cette machine pour le moment."
            )
        }
    }

    /// À appeler après un échec d'inférence (erreur, garde-fous, dépassement) — distinct d'une
    /// indisponibilité connue de la plateforme.
    public static func behaviorAfterInferenceFailure(attempts: Int) -> DegradationBehavior {
        attempts >= maxInferenceAttempts
            ? .skippedAfterRetries
            : .retryLater(message: "Nouvelle tentative d'analyse en cours.")
    }
}
