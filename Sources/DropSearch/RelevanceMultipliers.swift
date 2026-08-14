import Foundation

/// Signaux d'un document pour un résultat donné (§5.7) — calculés par l'appelant (DropFeatures),
/// cette structure ne fait que combiner les multiplicateurs bornés.
public struct RelevanceSignals: Sendable, Equatable {
    public var exactFilenameMatch: Bool
    public var exactEntityMatch: Bool
    public var ageInDays: Double?
    public var openedRecently: Bool
    public var lowOCRConfidenceOnMatchedPage: Bool

    public init(
        exactFilenameMatch: Bool = false, exactEntityMatch: Bool = false, ageInDays: Double? = nil,
        openedRecently: Bool = false, lowOCRConfidenceOnMatchedPage: Bool = false
    ) {
        self.exactFilenameMatch = exactFilenameMatch
        self.exactEntityMatch = exactEntityMatch
        self.ageInDays = ageInDays
        self.openedRecently = openedRecently
        self.lowOCRConfidenceOnMatchedPage = lowOCRConfidenceOnMatchedPage
    }
}

/// Multiplicateurs bornés (§5.7), appliqués après la fusion RRF, produit plafonné à 2,0. Toute
/// modification passe obligatoirement par le harnais d'évaluation (§8.3) — ces constantes sont
/// celles du CDC, pas des réglages à l'intuition.
public enum RelevanceMultipliers {
    public static let productCap = 2.0

    public static func multiplier(for signals: RelevanceSignals) -> Double {
        var product = 1.0
        if signals.exactFilenameMatch { product *= 1.4 }
        if signals.exactEntityMatch { product *= 1.3 }
        if let age = signals.ageInDays {
            product *= 1 + 0.15 * exp(-age / 180)
        }
        if signals.openedRecently { product *= 1.10 }
        if signals.lowOCRConfidenceOnMatchedPage { product *= 0.85 }
        return min(product, productCap)
    }
}
