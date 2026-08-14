import DropCore
import DropIndex
import DropSearch
import GRDB

/// Générateur pour les requêtes entièrement satisfaites par les filtres (EF-63/64), sans texte
/// libre résiduel — ex. « factures de plus de 500 € en 2024 » où chaque mot est consommé par un
/// filtre. Sans ce générateur, une telle requête ne retournerait jamais rien : le lexical et le
/// trigramme exigent un texte libre non vide (§5.7).
public struct FilterOnlyCandidateGenerator: CandidateGenerator {
    private let database: DropIndexDatabase

    public init(database: DropIndexDatabase) {
        self.database = database
    }

    public func candidates(for query: ParsedQuery, limit: Int) async throws -> [RankedDocument] {
        guard query.freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let hasAnyFilter = query.dateRange != nil || query.amountRange != nil || !query.docTypes.isEmpty || !query.tags.isEmpty
        guard hasAnyFilter else { return [] }

        let filter = QueryFilters.clause(for: query)
        let arguments = filter.arguments + [limit]

        return try await database.pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT documents.id AS document_id FROM documents
                WHERE \(filter.sql)
                ORDER BY documents.effective_date DESC, documents.added_at DESC
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
