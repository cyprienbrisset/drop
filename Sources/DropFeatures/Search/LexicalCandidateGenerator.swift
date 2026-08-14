import DropCore
import DropIndex
import DropSearch
import Foundation
import GRDB

/// Générateur de candidats lexicaux (§5.7) : `fts_docs` en BM25, pondération de colonnes
/// display_name ×3, issuer ×2, keywords ×2, body ×1 — dans cet ordre de déclaration du schéma.
public struct LexicalCandidateGenerator: CandidateGenerator {
    private let database: DropIndexDatabase

    public init(database: DropIndexDatabase) {
        self.database = database
    }

    public func candidates(for query: ParsedQuery, limit: Int) async throws -> [RankedDocument] {
        let text = query.freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let matchExpression = Self.ftsMatchExpression(for: text)
        let filter = QueryFilters.clause(for: query)
        let arguments: [any DatabaseValueConvertible & Sendable] = [matchExpression] + filter.arguments + [limit]

        return try await database.pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT fts_docs.document_id AS document_id
                FROM fts_docs
                JOIN documents ON documents.id = fts_docs.document_id
                WHERE fts_docs MATCH ? AND \(filter.sql)
                ORDER BY bm25(fts_docs, 3.0, 1.0, 2.0, 2.0)
                LIMIT ?
                """,
                arguments: StatementArguments(arguments)
            )
            return rows.enumerated().map { index, row in
                RankedDocument(documentID: row["document_id"], rank: index + 1)
            }
        }
    }

    /// Échappe la requête libre pour la syntaxe `MATCH` de FTS5 : chaque terme est mis entre
    /// guillemets (pour éviter qu'une ponctuation ou un opérateur ne casse la requête) et
    /// recherché en préfixe (`*`, sur les index `prefix = '2 3 4'` du schéma, §4.4). Sans cela,
    /// un mot collé à l'extension par le tokenizer (ex. `edf.pdf` reste un seul token à cause du
    /// `.` dans `tokenchars`) ne matcherait jamais une requête sur le seul mot « edf ».
    static func ftsMatchExpression(for text: String) -> String {
        text.split(separator: " ")
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
            .joined(separator: " ")
    }
}
