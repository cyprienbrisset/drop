import Foundation

/// Sortie du parser de requête déterministe (§5.6). Aucun appel au modèle de langage : le budget
/// de latence l'interdit, et les filtres restent opérationnels même en pipeline dégradé.
public struct ParsedQuery: Sendable, Equatable {
    public var freeText: String = ""
    public var phrases: [String] = []
    public var excluded: [String] = []
    public var dateRange: DateInterval?
    public var amountRange: ClosedRange<Double>?
    public var currency: String?
    public var docTypes: [String] = []
    public var fileKinds: [String] = []
    public var tags: [String] = []
    public var issuerHints: [String] = []

    public init() {}
}

/// Générateur de candidats (§5.7). Chaque implémentation (lexical, trigramme, sémantique, exact)
/// tourne sur le sous-ensemble déjà filtré par `ParsedQuery` et retourne des rangs, jamais des scores
/// d'échelles hétérogènes — la fusion se fait exclusivement par RRF (ADR-04).
public protocol CandidateGenerator: Sendable {
    func candidates(for query: ParsedQuery, limit: Int) async throws -> [RankedDocument]
}

public struct RankedDocument: Sendable {
    public let documentID: String
    public let rank: Int

    public init(documentID: String, rank: Int) {
        self.documentID = documentID
        self.rank = rank
    }
}
