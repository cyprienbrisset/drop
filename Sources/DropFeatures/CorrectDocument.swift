import DropCore
import DropIndex
import Foundation
import GRDB

/// Masque de bits `documents.user_verified` (§4.4) : type|issuer|date. Une valeur corrigée n'est
/// plus jamais écrasée par le pipeline (EF-48).
public enum VerifiedField: Int, Sendable {
    case type = 1
    case issuer = 2
    case effectiveDate = 4
}

/// Cas d'usage : correction manuelle du type, de l'émetteur ou de la date par l'utilisateur
/// (EF-48). Pose le bit correspondant dans `user_verified` — `AnalyzeDocument` (Phase 4/5) le
/// respecte et ne réécrit jamais un champ dont le bit est posé.
public struct CorrectDocument: Sendable {
    private let database: DropIndexDatabase

    public init(database: DropIndexDatabase) {
        self.database = database
    }

    public func correctType(documentID: String, to docType: String) async throws {
        try await setVerified(
            documentID: documentID, field: .type,
            sql: "UPDATE documents SET doc_type = ?, user_verified = user_verified | ? WHERE id = ?",
            value: docType
        )
    }

    public func correctIssuer(documentID: String, to issuer: String) async throws {
        try await setVerified(
            documentID: documentID, field: .issuer,
            sql: "UPDATE documents SET issuer = ?, user_verified = user_verified | ? WHERE id = ?",
            value: issuer
        )
    }

    /// `date` au format ISO 8601 `yyyy-MM-dd`. Devient la source de vérité pour la date effective
    /// (§5.3.3 point 1) : la valeur corrigée gagne sur toute règle automatique.
    public func correctEffectiveDate(documentID: String, to date: String) async throws {
        _ = try await database.pool.write { db in
            try db.execute(
                sql: """
                UPDATE documents
                SET effective_date = ?, effective_date_src = 'user', user_verified = user_verified | ?
                WHERE id = ?
                """,
                arguments: [date, VerifiedField.effectiveDate.rawValue, documentID]
            )
        }
    }

    private func setVerified(documentID: String, field: VerifiedField, sql: String, value: String) async throws {
        _ = try await database.pool.write { db in
            try db.execute(sql: sql, arguments: [value, field.rawValue, documentID])
        }
    }
}
