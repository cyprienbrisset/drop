import DropEmbeddings
import DropIndex
import DropSearch
import Foundation
import GRDB

/// Résultat de recherche final (§5.7) : score post-fusion RRF, après application des
/// multiplicateurs bornés et du seuil de pertinence (EF-68). L'ordre de tri est décroissant sur
/// `score`. `explanation` (EF-69) donne les raisons de la remontée, en langage clair.
public struct SearchResult: Sendable, Equatable {
    public let documentID: String
    public let score: Double
    public let explanation: [String]
}

/// Orchestrateur de la recherche (§5.6-5.7) : parse la requête, interroge les générateurs de
/// candidats pertinents, fusionne par RRF, applique les multiplicateurs de pertinence puis élague
/// au seuil EF-68 (35 % du meilleur score, plancher absolu). L'affichage progressif (EF-68) et le
/// non-réordonnancement sous le focus clavier restent la responsabilité de l'appelant UI
/// (`DropApp/SearchView`, cf. sa note de portée) — ce moteur renvoie un instantané complet.
public struct SearchEngine: Sendable {
    private let indexDatabase: DropIndexDatabase
    private let lexical: LexicalCandidateGenerator
    private let trigram: TrigramCandidateGenerator
    private let filterOnly: FilterOnlyCandidateGenerator
    private let semantic: SemanticCandidateGenerator?
    private let fusion: ReciprocalRankFusion
    private let now: @Sendable () -> Date

    /// Sous ce nombre de résultats lexicaux, le trigramme est activé en complément (§5.7) —
    /// il absorbe les fautes de frappe mais son bruit dégraderait un résultat lexical déjà riche.
    private static let trigramActivationThreshold = 5

    public init(
        indexDatabase: DropIndexDatabase,
        vectorsDatabase: VectorsDatabase?,
        fusion: ReciprocalRankFusion = ReciprocalRankFusion(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.indexDatabase = indexDatabase
        self.lexical = LexicalCandidateGenerator(database: indexDatabase)
        self.trigram = TrigramCandidateGenerator(database: indexDatabase)
        self.filterOnly = FilterOnlyCandidateGenerator(database: indexDatabase)
        self.semantic = vectorsDatabase.flatMap { SemanticCandidateGenerator(vectorsDatabase: $0) }
        self.fusion = fusion
        self.now = now
    }

    public func search(_ query: ParsedQuery, limit: Int = 20) async throws -> [SearchResult] {
        let candidateLimit = max(limit * 3, 30)

        var rankedLists: [String: [RankedDocument]] = [:]

        let lexicalResults = try await lexical.candidates(for: query, limit: candidateLimit)
        rankedLists["lexical"] = lexicalResults

        if lexicalResults.count < Self.trigramActivationThreshold {
            rankedLists["trigram"] = try await trigram.candidates(for: query, limit: candidateLimit)
        }

        if let semantic {
            rankedLists["semantic"] = try await semantic.candidates(for: query, limit: candidateLimit)
        }

        let exactResults = try await filterOnly.candidates(for: query, limit: candidateLimit)
        if !exactResults.isEmpty { rankedLists["exact"] = exactResults }

        let fused = fusion.fuse(rankedLists: rankedLists)
        guard !fused.isEmpty else { return [] }

        let documentIDs = Array(fused.keys)
        let signals = try await relevanceSignals(for: documentIDs, queryText: query.freeText)

        let matchedGenerators: [String: Set<String>] = documentIDs.reduce(into: [:]) { result, documentID in
            result[documentID] = Set(rankedLists.compactMap { generator, documents in
                documents.contains { $0.documentID == documentID } ? generator : nil
            })
        }

        var scores: [String: Double] = [:]
        for (documentID, rrfScore) in fused {
            let multiplier = RelevanceMultipliers.multiplier(for: signals[documentID] ?? RelevanceSignals())
            scores[documentID] = rrfScore * multiplier
        }

        let thresholded = RelevanceThreshold.apply(to: scores)

        let results = thresholded.map { documentID, score -> SearchResult in
            let explanation = RelevanceExplanation.describe(
                signals: signals[documentID] ?? RelevanceSignals(),
                matchedGenerators: matchedGenerators[documentID] ?? []
            )
            return SearchResult(documentID: documentID, score: score, explanation: explanation)
        }

        return results.sorted { $0.score > $1.score }.prefix(limit).map { $0 }
    }

    /// Calcule les signaux §5.7 pour chaque document candidat en un minimum de requêtes.
    private func relevanceSignals(for documentIDs: [String], queryText: String) async throws -> [String: RelevanceSignals] {
        let normalizedQuery = queryText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !documentIDs.isEmpty else { return [:] }

        return try await indexDatabase.pool.read { db in
            let placeholders = documentIDs.map { _ in "?" }.joined(separator: ", ")

            let documentRows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, display_name, original_filename, effective_date, added_at
                FROM documents WHERE id IN (\(placeholders))
                """,
                arguments: StatementArguments(documentIDs)
            )

            let recentOpenThreshold = self.now().addingTimeInterval(-30 * 24 * 3600)
            let openedDocumentIDs: Set<String> = normalizedQuery.isEmpty
                ? []
                : try Set(String.fetchAll(
                    db,
                    sql: """
                    SELECT DISTINCT document_id FROM document_opens
                    WHERE document_id IN (\(placeholders)) AND opened_at >= ?
                    """,
                    arguments: StatementArguments(documentIDs + [Self.isoString(from: recentOpenThreshold)])
                ))

            var entityMatchedDocumentIDs: Set<String> = []
            var lowOCRDocumentIDs: Set<String> = []
            if !normalizedQuery.isEmpty {
                entityMatchedDocumentIDs = try Set(String.fetchAll(
                    db,
                    sql: """
                    SELECT DISTINCT document_id FROM entities
                    WHERE document_id IN (\(placeholders)) AND LOWER(value_text) = ?
                    """,
                    arguments: StatementArguments(documentIDs + [normalizedQuery])
                ))

                lowOCRDocumentIDs = try Set(String.fetchAll(
                    db,
                    sql: """
                    SELECT DISTINCT document_id FROM page_texts
                    WHERE document_id IN (\(placeholders)) AND ocr_confidence IS NOT NULL
                      AND ocr_confidence < 0.5 AND LOWER(content) LIKE ?
                    """,
                    arguments: StatementArguments(documentIDs + ["%\(normalizedQuery)%"])
                ))
            }

            var signals: [String: RelevanceSignals] = [:]
            for row in documentRows {
                let documentID: String = row["id"]
                let displayName: String = row["display_name"]
                let originalFilename: String = row["original_filename"]
                let filenameStem = (originalFilename as NSString).deletingPathExtension

                let exactFilenameMatch = !normalizedQuery.isEmpty && (
                    displayName.lowercased() == normalizedQuery || filenameStem.lowercased() == normalizedQuery
                )

                let referenceDateString: String? = row["effective_date"] ?? row["added_at"]
                let ageInDays = referenceDateString
                    .flatMap { Self.parseDate($0) }
                    .map { self.now().timeIntervalSince($0) / (24 * 3600) }

                signals[documentID] = RelevanceSignals(
                    exactFilenameMatch: exactFilenameMatch,
                    exactEntityMatch: entityMatchedDocumentIDs.contains(documentID),
                    ageInDays: ageInDays,
                    openedRecently: openedDocumentIDs.contains(documentID),
                    lowOCRConfidenceOnMatchedPage: lowOCRDocumentIDs.contains(documentID)
                )
            }
            return signals
        }
    }

    /// Formatteurs Foundation non `Sendable` : instances fraîches par appel plutôt que globales
    /// statiques mutables, pour rester conforme à la concurrence stricte de Swift 6.
    private static func isoString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func parseDate(_ string: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: string) { return date }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        return dayFormatter.date(from: string)
    }
}
