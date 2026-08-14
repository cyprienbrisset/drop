import Foundation

/// Enregistrement de restauration écrit dans `trash/<document-id>/record.json` (§4.3). Le blob
/// physique n'est **pas** copié ici : il reste à sa place dans `vault/`, adressé par son hash,
/// tant qu'au moins un document (actif ou encore dans sa fenêtre de rétention) le référence.
/// Seule cette fiche JSON permet de restaurer le document sans toucher au blob partagé.
public struct TrashRecord: Codable, Sendable, Equatable {
    public let documentID: String
    public let blobHash: String
    public let trashedAt: String
    /// Copie des colonnes de `documents` nécessaires à la restauration, sous forme texte.
    public let documentFields: [String: String?]

    public init(documentID: String, blobHash: String, trashedAt: String, documentFields: [String: String?]) {
        self.documentID = documentID
        self.blobHash = blobHash
        self.trashedAt = trashedAt
        self.documentFields = documentFields
    }
}
