/// États de licence (§5.11, EF-83). Aucun appel réseau, aucune activation, aucun compte.
/// Une licence invalide ou illisible retombe toujours sur `free` — jamais de blocage du coffre.
public enum LicenseState: Sendable, Equatable {
    case free(documentCount: Int, cap: Int)
    case pro
    case invalid
}

public struct LicensePayload: Sendable, Codable {
    public let v: Int
    public let sku: String
    public let orderID: String
    public let issuedAt: String
    public let buyerHash: String
    public let seats: Int
}
