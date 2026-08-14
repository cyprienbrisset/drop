import DropSearch
import Foundation
import GRDB

/// Traduit un `ParsedQuery` en clauses SQL sur `documents`/`entities` (§5.6), appliquées avant
/// les générateurs de candidats afin de réduire l'espace de recherche.
public enum QueryFilters {
    public struct Clause: Sendable {
        public let sql: String
        public let arguments: [any DatabaseValueConvertible & Sendable]
    }

    private static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Toujours non vide : au minimum `documents.trashed_at IS NULL`.
    public static func clause(for query: ParsedQuery) -> Clause {
        var conditions: [String] = ["documents.trashed_at IS NULL"]
        var arguments: [any DatabaseValueConvertible & Sendable] = []

        if let dateRange = query.dateRange {
            conditions.append("documents.effective_date >= ? AND documents.effective_date < ?")
            arguments.append(isoDayFormatter.string(from: dateRange.start))
            arguments.append(isoDayFormatter.string(from: dateRange.end))
        }

        if !query.docTypes.isEmpty {
            let placeholders = query.docTypes.map { _ in "?" }.joined(separator: ", ")
            conditions.append("documents.doc_type IN (\(placeholders))")
            arguments.append(contentsOf: query.docTypes)
        }

        if let amountRange = query.amountRange {
            conditions.append("""
            EXISTS (
              SELECT 1 FROM entities
              WHERE entities.document_id = documents.id AND entities.kind = 'amount'
                AND entities.value_num BETWEEN ? AND ?
            )
            """)
            arguments.append(amountRange.lowerBound)
            arguments.append(amountRange.upperBound)
        }

        if !query.tags.isEmpty {
            let placeholders = query.tags.map { _ in "?" }.joined(separator: ", ")
            conditions.append("""
            EXISTS (
              SELECT 1 FROM document_tags
              JOIN tags ON tags.id = document_tags.tag_id
              WHERE document_tags.document_id = documents.id AND tags.name IN (\(placeholders))
            )
            """)
            arguments.append(contentsOf: query.tags)
        }

        return Clause(sql: conditions.joined(separator: " AND "), arguments: arguments)
    }
}
