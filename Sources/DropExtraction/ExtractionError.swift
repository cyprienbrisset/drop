/// Erreurs d'extraction (§5.2). Un format non supporté n'est jamais fatal pour l'ingestion :
/// l'appelant retombe sur les métadonnées seules (EF-07) plutôt que de faire échouer le document.
public enum ExtractionError: Error, Sendable, Equatable {
    case unsupportedFormat
    case unreadable
}
