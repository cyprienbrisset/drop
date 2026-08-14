import CryptoKit
import DropCore
import Foundation

/// Hachage SHA-256 en flux, par blocs de 1 Mio, sans jamais charger le fichier entier en
/// mémoire — indispensable pour les fichiers jusqu'à 2 Go (§5.1 étape 3, EF-08).
public enum VaultHashing {
    public static func sha256(ofFileAt url: URL, fileSystem: FileSystem, chunkSize: Int = 1_048_576) throws -> String {
        var hasher = SHA256()
        try fileSystem.forEachChunk(at: url, chunkSize: chunkSize) { chunk in
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
