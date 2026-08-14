import DropVault
import Foundation
import Testing

private func randomKey() -> Data {
    Data((0..<32).map { _ in UInt8.random(in: 0...255) })
}

@Test func encryptDecryptRoundTripsTheOriginalPlaintext() throws {
    let key = randomKey()
    let plaintext = Data("facture EDF juillet 2026, 84,20 €".utf8)

    let ciphertext = try BlobEncryption.encrypt(plaintext, masterKey: key, blobHash: "abc123")
    let decrypted = try BlobEncryption.decrypt(ciphertext, masterKey: key, blobHash: "abc123")

    #expect(decrypted == plaintext)
    #expect(ciphertext != plaintext)
}

@Test func decryptFailsWithTheWrongMasterKey() throws {
    let plaintext = Data("contenu confidentiel".utf8)
    let ciphertext = try BlobEncryption.encrypt(plaintext, masterKey: randomKey(), blobHash: "abc123")

    #expect(throws: BlobEncryptionError.self) {
        _ = try BlobEncryption.decrypt(ciphertext, masterKey: randomKey(), blobHash: "abc123")
    }
}

@Test func decryptFailsIfTheBlobHashDoesNotMatchTheOneUsedToEncrypt() throws {
    let key = randomKey()
    let plaintext = Data("contenu".utf8)
    let ciphertext = try BlobEncryption.encrypt(plaintext, masterKey: key, blobHash: "hash-a")

    // La clé dérivée dépend du hash (info HKDF) — un mauvais hash équivaut à une mauvaise clé.
    #expect(throws: BlobEncryptionError.self) {
        _ = try BlobEncryption.decrypt(ciphertext, masterKey: key, blobHash: "hash-b")
    }
}

@Test func decryptFailsOnATamperedCiphertext() throws {
    let key = randomKey()
    var ciphertext = try BlobEncryption.encrypt(Data("contenu".utf8), masterKey: key, blobHash: "abc123")
    ciphertext[ciphertext.count / 2] ^= 0xFF // un seul octet altéré au milieu.

    #expect(throws: BlobEncryptionError.self) {
        _ = try BlobEncryption.decrypt(ciphertext, masterKey: key, blobHash: "abc123")
    }
}

@Test func distinctBlobHashesProduceDistinctDerivedKeys() {
    let key = randomKey()
    let keyA = BlobEncryption.derivedKey(masterKey: key, blobHash: "hash-a")
    let keyB = BlobEncryption.derivedKey(masterKey: key, blobHash: "hash-b")
    #expect(keyA != keyB)
}

@Test func sameInputsAlwaysProduceTheSameDerivedKey() {
    let key = randomKey()
    let first = BlobEncryption.derivedKey(masterKey: key, blobHash: "hash-a")
    let second = BlobEncryption.derivedKey(masterKey: key, blobHash: "hash-a")
    #expect(first == second)
}
