import Foundation

/// Modèle de présentation d'un résultat de recherche (EX-03). Alimenté par le moteur de recherche
/// une fois le bootstrap applicatif câblé (cf. note de portée dans `PreferencesView`) — pour
/// l'instant, ce type n'a aucune dépendance vers `DropFeatures`/`DropIndex` : c'est une vue pure.
struct DocumentSearchResult: Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String
    // Correctibles par l'utilisateur (EF-48) : `var` pour permettre à `AppEnvironment` de
    // refléter une correction immédiatement dans `searchResults`/`detailResult`, sans nouvelle
    // recherche complète.
    var docType: String?
    var issuer: String?
    var effectiveDate: Date?
    let amount: Double?
    let keywords: [String]
    let summary: String?
    var tags: [String]
    let originalPath: String?
    let sizeBytes: Int64
    let hash: String
    let previewURL: URL?

    var shortHash: String { String(hash.prefix(8)) }

    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
