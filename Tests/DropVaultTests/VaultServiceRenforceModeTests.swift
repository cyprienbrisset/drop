import DropCore
import DropVault
import Foundation
import Testing

private func randomKey() -> Data {
    Data((0..<32).map { _ in UInt8.random(in: 0...255) })
}

@Test func writingInRenforceModeStoresCiphertextOnDiskNotPlaintext() throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    let plaintext = Data("contenu confidentiel de la facture".utf8)
    fileSystem.seed(source.path, contents: plaintext)

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem, clock: SystemClock())
    let key = randomKey()
    let result = try vault.writeBlob(fromFileAt: source, encryptionMode: .renforce, masterKey: key)

    let onDisk = try fileSystem.read(at: result.blobURL)
    #expect(onDisk != plaintext) // jamais le clair sur disque en mode Renforcé.

    // Le hash content-addressé reste celui du CLAIR (déduplication indépendante du mode) : en
    // déchiffrant le fichier stocké avec la même clé, on doit retrouver exactement le clair d'origine.
    let decrypted = try BlobEncryption.decrypt(onDisk, masterKey: key, blobHash: result.hash)
    #expect(decrypted == plaintext)
}

@Test func writingInRenforceModeWithoutAMasterKeyThrows() throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    fileSystem.seed(source.path, contents: Data("contenu".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem, clock: SystemClock())

    #expect(throws: (any Error).self) {
        _ = try vault.writeBlob(fromFileAt: source, encryptionMode: .renforce, masterKey: nil)
    }
}

@Test func readBlobDecryptsARenforceModeBlobBackToItsPlaintext() throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    let plaintext = Data("contenu confidentiel".utf8)
    fileSystem.seed(source.path, contents: plaintext)

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem, clock: SystemClock())
    let key = randomKey()
    let result = try vault.writeBlob(fromFileAt: source, encryptionMode: .renforce, masterKey: key)

    let read = try vault.readBlob(hash: result.hash, encryptionMode: .renforce, masterKey: key)
    #expect(read == plaintext)
}

@Test func readBlobWithTheWrongKeyThrowsInsteadOfReturningGarbage() throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    fileSystem.seed(source.path, contents: Data("contenu".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem, clock: SystemClock())
    let result = try vault.writeBlob(fromFileAt: source, encryptionMode: .renforce, masterKey: randomKey())

    #expect(throws: (any Error).self) {
        _ = try vault.readBlob(hash: result.hash, encryptionMode: .renforce, masterKey: randomKey())
    }
}

@Test func standardModeBlobsAreUnaffectedAndStayPlaintext() throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    let plaintext = Data("contenu public".utf8)
    fileSystem.seed(source.path, contents: plaintext)

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem, clock: SystemClock())
    let result = try vault.writeBlob(fromFileAt: source)

    let onDisk = try fileSystem.read(at: result.blobURL)
    #expect(onDisk == plaintext)
    #expect(try vault.readBlob(hash: result.hash) == plaintext)
}

@Test func verifyBlobDetectsATamperedRenforceModeBlobViaTheGCMTag() throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    fileSystem.seed(source.path, contents: Data("contenu".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem, clock: SystemClock())
    let key = randomKey()
    let result = try vault.writeBlob(fromFileAt: source, encryptionMode: .renforce, masterKey: key)

    #expect(vault.verifyBlob(hash: result.hash, encryptionMode: .renforce, masterKey: key) == .ok)

    var tampered = try fileSystem.read(at: result.blobURL)
    tampered[0] ^= 0xFF
    fileSystem.seed(result.blobURL.path, contents: tampered)

    #expect(vault.verifyBlob(hash: result.hash, encryptionMode: .renforce, masterKey: key) == .corrupt)
}

@Test func exportBlobDecryptsARenforceModeBlobToAPlaintextDestination() throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    let plaintext = Data("contenu à exporter".utf8)
    fileSystem.seed(source.path, contents: plaintext)

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem, clock: SystemClock())
    let key = randomKey()
    let result = try vault.writeBlob(fromFileAt: source, encryptionMode: .renforce, masterKey: key)

    let destination = URL(fileURLWithPath: "/exports/facture.pdf")
    try vault.exportBlob(hash: result.hash, to: destination, encryptionMode: .renforce, masterKey: key)

    #expect(try fileSystem.read(at: destination) == plaintext)
}

@Test func materializedFileURLReturnsTheRealPathForStandardBlobsWithoutCopying() throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    fileSystem.seed(source.path, contents: Data("contenu".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem, clock: SystemClock())
    let result = try vault.writeBlob(fromFileAt: source)

    let materialized = try vault.materializedFileURL(hash: result.hash)
    #expect(materialized == result.blobURL)
}

@Test func materializedFileURLWritesAPlaintextTemporaryFileForRenforceBlobs() throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    let plaintext = Data("contenu".utf8)
    fileSystem.seed(source.path, contents: plaintext)

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem, clock: SystemClock())
    let key = randomKey()
    let result = try vault.writeBlob(fromFileAt: source, encryptionMode: .renforce, masterKey: key)

    let materialized = try vault.materializedFileURL(hash: result.hash, encryptionMode: .renforce, masterKey: key, suggestedExtension: "pdf")

    #expect(materialized != result.blobURL)
    #expect(materialized.path.hasPrefix(root.appendingPathComponent("tmp").path))
    #expect(try fileSystem.read(at: materialized) == plaintext)
}
