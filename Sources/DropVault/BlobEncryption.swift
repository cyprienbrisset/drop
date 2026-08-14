import CryptoKit
import Foundation

/// Mode de chiffrement d'un blob (§4.3, §5.11) : `standard` (défaut, fichier en clair, permissions
/// 0600) ou `renforce` (Pro, AES-256-GCM par fichier). Persisté par blob dans `blobs.encryption_mode`
/// — une décision prise une fois à l'écriture, jamais changée en place (I4).
public enum EncryptionMode: String, Sendable, Equatable {
    case standard
    case renforce
}

public enum BlobEncryptionError: Error, Sendable, Equatable {
    case sealingFailed
    case openingFailed
}

/// Chiffrement par blob, mode Renforcé (§5.11, DRO-51). Chaque blob a sa propre clé, dérivée par
/// HKDF de la clé maîtresse du coffre avec le hash du blob comme `info` : compromettre la clé
/// symétrique d'un blob (par ex. fuite mémoire) n'expose jamais les autres blobs, et la clé
/// maîtresse elle-même n'est jamais utilisée directement pour chiffrer du contenu.
public enum BlobEncryption {
    private static let salt = Data("drop-vault-blob-encryption-v1".utf8)

    public static func derivedKey(masterKey: Data, blobHash: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: masterKey),
            salt: salt,
            info: Data(blobHash.utf8),
            outputByteCount: 32
        )
    }

    /// Chiffre en mémoire (les blobs restent sous la limite de taille du coffre, §5.1 — jamais
    /// streamé chunk par chunk). Le nonce et le tag d'authentification sont inclus dans la sortie
    /// (`combined`) : aucun état à gérer séparément côté appelant.
    public static func encrypt(_ plaintext: Data, masterKey: Data, blobHash: String) throws -> Data {
        let key = derivedKey(masterKey: masterKey, blobHash: blobHash)
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else {
            throw BlobEncryptionError.sealingFailed
        }
        return combined
    }

    /// Déchiffre et vérifie l'authenticité (tag GCM) en une seule opération — un blob altéré
    /// échoue ici avant même qu'un octet de contenu ne soit rendu à l'appelant.
    public static func decrypt(_ ciphertext: Data, masterKey: Data, blobHash: String) throws -> Data {
        let key = derivedKey(masterKey: masterKey, blobHash: blobHash)
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw BlobEncryptionError.openingFailed
        }
    }
}
