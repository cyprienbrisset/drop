import DropCore
import DropVault
import Foundation
import Testing

@Test func vaultServiceInitializesWithGivenRoot() {
    let root = URL(fileURLWithPath: "/tmp/drop-vault-test")
    _ = VaultService(vaultRoot: root, fileSystem: LiveFileSystem(), clock: SystemClock())
}

@Test func writeBlobCopiesContentAndWritesMetadata() throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    fileSystem.seed(source.path, contents: Data("contenu de test".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem, clock: SystemClock())
    let result = try vault.writeBlob(fromFileAt: source, originalPath: source.path)

    #expect(result.isNewBlob)
    #expect(fileSystem.fileExists(at: result.blobURL))
    #expect(fileSystem.fileExists(at: result.metadataURL))
    #expect(result.sizeBytes == Int64("contenu de test".utf8.count))

    let storedBlob = try fileSystem.read(at: result.blobURL)
    #expect(storedBlob == Data("contenu de test".utf8))
}

@Test func writeBlobIsIdempotentForIdenticalContent() throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    fileSystem.seed(source.path, contents: Data("même contenu".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem, clock: SystemClock())
    let first = try vault.writeBlob(fromFileAt: source, originalPath: source.path)
    let second = try vault.writeBlob(fromFileAt: source, originalPath: source.path)

    #expect(first.hash == second.hash)
    #expect(first.isNewBlob)
    #expect(!second.isNewBlob) // EF-05 : aucune copie la seconde fois.
}

@Test func writeBlobRejectsFilesAboveTheSizeLimit() throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/huge.bin")
    fileSystem.seed(source.path, contents: Data(repeating: 0, count: 2048))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem, maxFileSizeBytes: 1024)

    #expect(throws: IngestionError.tooLarge) {
        try vault.writeBlob(fromFileAt: source)
    }
}

@Test func writeBlobFailsCleanlyOnUnreadableSource() throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/missing.pdf")

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)

    #expect(throws: IngestionError.unreadable) {
        try vault.writeBlob(fromFileAt: source)
    }
}
