/// Codes d'erreur de l'ingestion (§5.1). Chacun est stable, journalisable et affichable à
/// l'utilisateur — jamais un message généré à la volée.
public enum IngestionError: Error, Sendable, Equatable {
    case unreadable // DROP-ING-001 : fichier illisible
    case lockedOrUnstable // DROP-ING-002 : verrouillé ou instable
    case tooLarge // DROP-ING-003 : taille excédée
    case hashMismatch // DROP-ING-004 : divergence de hash
    case insufficientDiskSpace // DROP-ING-005 : espace disque insuffisant
    case crossVolume // DROP-ING-006 : volume différent
    case transactionFailed // DROP-ING-007 : échec transaction
    case licenseCapReached // DROP-ING-008 : plafond de licence atteint

    public var code: String {
        switch self {
        case .unreadable: return "DROP-ING-001"
        case .lockedOrUnstable: return "DROP-ING-002"
        case .tooLarge: return "DROP-ING-003"
        case .hashMismatch: return "DROP-ING-004"
        case .insufficientDiskSpace: return "DROP-ING-005"
        case .crossVolume: return "DROP-ING-006"
        case .transactionFailed: return "DROP-ING-007"
        case .licenseCapReached: return "DROP-ING-008"
        }
    }
}
