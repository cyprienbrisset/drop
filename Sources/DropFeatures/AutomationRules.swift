import DropCore
import DropIndex
import Foundation
import GRDB

/// Règles d'automatisation type Hazel (§5, backlog V3) : « si condition, alors tag ». Volontairement
/// une seule condition et une seule action par règle — un moteur composé (ET/OU, actions multiples)
/// n'a jamais été demandé, et l'ajouter maintenant serait de la complexité spéculative (§principes).
/// Toujours une action additive (ajouter un tag) : jamais de renommage, déplacement ou suppression
/// automatique — Drop n'a pas de hiérarchie de dossiers, et une automatisation destructive sans
/// confirmation contredirait EX-05 (vocabulaire de réversibilité) autant que le bon sens.
public struct AutomationRules: Sendable {
    public enum Condition: Sendable, Equatable {
        case issuerEquals(String)
        case docTypeEquals(String)
        case amountGreaterThan(Double)
        case keywordContains(String)

        var kind: String {
            switch self {
            case .issuerEquals: return "issuer_equals"
            case .docTypeEquals: return "doc_type_equals"
            case .amountGreaterThan: return "amount_greater_than"
            case .keywordContains: return "keyword_contains"
            }
        }

        var storedValue: String {
            switch self {
            case .issuerEquals(let value): return value
            case .docTypeEquals(let value): return value
            case .amountGreaterThan(let value): return String(value)
            case .keywordContains(let value): return value
            }
        }

        static func from(kind: String, value: String) -> Condition? {
            switch kind {
            case "issuer_equals": return .issuerEquals(value)
            case "doc_type_equals": return .docTypeEquals(value)
            case "amount_greater_than": return Double(value).map { .amountGreaterThan($0) }
            case "keyword_contains": return .keywordContains(value)
            default: return nil
            }
        }
    }

    public struct Rule: Sendable, Equatable, Identifiable {
        public let id: String
        public var name: String
        public var isEnabled: Bool
        public var condition: Condition
        public var actionTag: String
    }

    private struct DocumentSnapshot: Sendable {
        let docType: String?
        let issuer: String?
        let amount: Double?
        let keywords: [String]
    }

    private let database: DropIndexDatabase
    private let manageTags: ManageTags
    private let clock: DropClock

    public init(database: DropIndexDatabase, manageTags: ManageTags, clock: DropClock = SystemClock()) {
        self.database = database
        self.manageTags = manageTags
        self.clock = clock
    }

    public func listRules() async throws -> [Rule] {
        try await database.pool.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM automation_rules ORDER BY created_at")
            return rows.compactMap { row -> Rule? in
                guard let condition = Condition.from(kind: row["condition_kind"], value: row["condition_value"]) else { return nil }
                return Rule(
                    id: row["id"], name: row["name"], isEnabled: (row["is_enabled"] as Int) != 0,
                    condition: condition, actionTag: row["action_tag"]
                )
            }
        }
    }

    @discardableResult
    public func addRule(name: String, condition: Condition, actionTag: String) async throws -> Rule {
        let id = UUID().uuidString
        // `ManageTags.addTag` normalise déjà à l'application de la règle (§ManageTags) — cette
        // normalisation ne sert qu'à stocker/afficher une valeur propre dans la règle elle-même.
        let normalizedTag = actionTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try await database.pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO automation_rules (id, name, is_enabled, condition_kind, condition_value, action_tag, created_at)
                VALUES (?, ?, 1, ?, ?, ?, ?)
                """,
                arguments: [id, name, condition.kind, condition.storedValue, normalizedTag, Self.isoString(from: clock.now())]
            )
        }
        return Rule(id: id, name: name, isEnabled: true, condition: condition, actionTag: normalizedTag)
    }

    public func removeRule(id: String) async throws {
        try await database.pool.write { db in
            try db.execute(sql: "DELETE FROM automation_rules WHERE id = ?", arguments: [id])
        }
    }

    public func setEnabled(id: String, isEnabled: Bool) async throws {
        try await database.pool.write { db in
            try db.execute(sql: "UPDATE automation_rules SET is_enabled = ? WHERE id = ?", arguments: [isEnabled, id])
        }
    }

    /// Appelé après chaque analyse réussie (§AnalyzeDocument) : applique toutes les règles actives
    /// dont la condition correspond à l'état — déterministe, jamais un second passage par le
    /// modèle de langage pour évaluer une condition.
    public func applyRules(documentID: String) async throws {
        let rules = try await listRules().filter(\.isEnabled)
        guard !rules.isEmpty else { return }

        guard let snapshot = try await documentSnapshot(documentID: documentID) else { return }

        for rule in rules where Self.matches(rule.condition, snapshot: snapshot) {
            try await manageTags.addTag(documentID: documentID, name: rule.actionTag)
        }
    }

    private func documentSnapshot(documentID: String) async throws -> DocumentSnapshot? {
        try await database.pool.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT doc_type, issuer FROM documents WHERE id = ?", arguments: [documentID]
            ) else { return nil }

            let keywordsRaw: String? = try String.fetchOne(
                db, sql: "SELECT keywords FROM fts_docs WHERE document_id = ?", arguments: [documentID]
            )
            let keywords = keywordsRaw.map { $0.split(separator: " ").map(String.init) } ?? []

            let amount = try Double.fetchOne(
                db,
                sql: """
                SELECT value_num FROM entities WHERE document_id = ? AND kind = 'amount'
                ORDER BY confidence DESC LIMIT 1
                """,
                arguments: [documentID]
            )

            return DocumentSnapshot(docType: row["doc_type"], issuer: row["issuer"], amount: amount, keywords: keywords)
        }
    }

    private static func matches(_ condition: Condition, snapshot: DocumentSnapshot) -> Bool {
        switch condition {
        case .issuerEquals(let value):
            return snapshot.issuer?.caseInsensitiveCompare(value) == .orderedSame
        case .docTypeEquals(let value):
            return snapshot.docType?.caseInsensitiveCompare(value) == .orderedSame
        case .amountGreaterThan(let threshold):
            guard let amount = snapshot.amount else { return false }
            return amount > threshold
        case .keywordContains(let value):
            let normalized = value.lowercased()
            return snapshot.keywords.contains { $0.lowercased().contains(normalized) }
        }
    }

    private static func isoString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
