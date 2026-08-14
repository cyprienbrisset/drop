import DropCore
import DropIndex
import DropSearch
import Foundation
import GRDB

/// Générateur de candidats approximatifs (§5.7) : `fts_trigram`, pour absorber les fautes de
/// frappe — FTS5 n'a pas de stemmer français. Sa composition conditionnelle (activé seulement si
/// le lexical renvoie moins de 5 résultats) est décidée par le moteur qui orchestre les
/// générateurs (DRO-44, Phase 6), pas ici.
public struct TrigramCandidateGenerator: CandidateGenerator {
    private let database: DropIndexDatabase

    public init(database: DropIndexDatabase) {
        self.database = database
    }

    public func candidates(for query: ParsedQuery, limit: Int) async throws -> [RankedDocument] {
        let text = query.freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let matchExpression = LexicalCandidateGenerator.ftsMatchExpression(for: text)
        let filter = QueryFilters.clause(for: query)
        let arguments: [any DatabaseValueConvertible & Sendable] = [matchExpression] + filter.arguments + [limit]

        return try await database.pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT DISTINCT fts_trigram.document_id AS document_id
                FROM fts_trigram
                JOIN documents ON documents.id = fts_trigram.document_id
                WHERE fts_trigram MATCH ? AND \(filter.sql)
                LIMIT ?
                """,
                arguments: StatementArguments(arguments)
            )
            return rows.enumerated().map { index, row in
                RankedDocument(documentID: row["document_id"], rank: index + 1)
            }
        }
    }
}
