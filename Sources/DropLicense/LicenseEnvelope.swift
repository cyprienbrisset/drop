import Foundation

/// Format sur disque de `license.drop` (§5.11, EF-80) : enveloppe JSON à deux champs, chacun en
/// base64url sans remplissage. La signature Ed25519 porte sur les octets bruts du payload décodé,
/// jamais sur sa représentation JSON textuelle (dont l'ordre des clés n'est pas garanti stable).
public struct LicenseEnvelope: Codable, Sendable, Equatable {
    public let payload: String
    public let signature: String

    public init(payload: String, signature: String) {
        self.payload = payload
        self.signature = signature
    }
}

public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }
}
