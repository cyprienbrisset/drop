import DropCore
import DropVault
import Foundation
import Testing

/// §8.4 : à chaque point de coupure, l'original doit rester intact (I1), et le pire résultat
/// possible est un fichier temporaire ou un blob orphelin — jamais une perte, jamais un état
/// incohérent (I5).
private func writeBlobAndFail(
    at point: VaultFaultPoint
) -> (fileSystem: InMemoryFileSystem, faulty: FaultInjectingFileSystem, vault: VaultService, source: URL, originalContent: Data) {
    let base = InMemoryFileSystem()
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    let content = Data("contenu original".utf8)
    base.seed(source.path, contents: content)

    let faulty = FaultInjectingFileSystem(wrapping: base, failAt: point)
    let vault = VaultService(vaultRoot: URL(fileURLWithPath: "/vault-root"), fileSystem: faulty)
    return (base, faulty, vault, source, content)
}

@Test func failureDuringSourceHashingLeavesOriginalUntouchedAndNoBlob() throws {
    let (fileSystem, _, vault, source, originalContent) = writeBlobAndFail(at: .duringSourceHashing)

    #expect(throws: (any Error).self) {
        try vault.writeBlob(fromFileAt: source)
    }

    #expect(try fileSystem.read(at: source) == originalContent) // I1
    #expect(try fileSystem.contentsOfDirectory(at: URL(fileURLWithPath: "/vault-root/vault")).isEmpty)
}

@Test func failureDuringTemporaryCopyLeavesOriginalUntouchedAndNoBlob() throws {
    let (fileSystem, _, vault, source, originalContent) = writeBlobAndFail(at: .duringTemporaryCopy)

    #expect(throws: (any Error).self) {
        try vault.writeBlob(fromFileAt: source)
    }

    #expect(try fileSystem.read(at: source) == originalContent) // I1
    #expect((try? fileSystem.contentsOfDirectory(at: URL(fileURLWithPath: "/vault-root/vault")))?.isEmpty ?? true)
}

@Test func failureDuringVerificationHashingRemovesTheTemporaryAndLeavesNoBlob() throws {
    let (fileSystem, _, vault, source, originalContent) = writeBlobAndFail(at: .duringVerificationHashing)

    #expect(throws: (any Error).self) {
        try vault.writeBlob(fromFileAt: source)
    }

    #expect(try fileSystem.read(at: source) == originalContent) // I1
    // La vérification de hash échoue avant tout rename : aucun blob ne doit exister (I4).
    let vaultEntries = (try? fileSystem.contentsOfDirectory(at: URL(fileURLWithPath: "/vault-root/vault"))) ?? []
    #expect(vaultEntries.isEmpty)
}

@Test func failureDuringSyncLeavesAtWorstATemporaryOrphan() throws {
    let (fileSystem, _, vault, source, originalContent) = writeBlobAndFail(at: .duringSync)

    #expect(throws: (any Error).self) {
        try vault.writeBlob(fromFileAt: source)
    }

    #expect(try fileSystem.read(at: source) == originalContent) // I1
    // I5 : au pire un résidu dans tmp/, jamais dans vault/ (le rename n'a pas eu lieu).
    let vaultEntries = (try? fileSystem.contentsOfDirectory(at: URL(fileURLWithPath: "/vault-root/vault"))) ?? []
    #expect(vaultEntries.isEmpty)
}

@Test func failureDuringRenameLeavesAtWorstATemporaryOrphanNeverAPartialBlob() throws {
    let (fileSystem, _, vault, source, originalContent) = writeBlobAndFail(at: .duringRename)

    #expect(throws: (any Error).self) {
        try vault.writeBlob(fromFileAt: source)
    }

    #expect(try fileSystem.read(at: source) == originalContent) // I1
    // Un rename qui échoue ne laisse jamais de blob partiel (I4) : soit il existe intact, soit il
    // n'existe pas du tout — jamais un fichier tronqué à son emplacement final.
    let vaultEntries = (try? fileSystem.contentsOfDirectory(at: URL(fileURLWithPath: "/vault-root/vault"))) ?? []
    #expect(vaultEntries.isEmpty)
}

@Test func failureDuringMetadataWriteLeavesAnOrphanBlobButNeverCorruptsIt() throws {
    let (fileSystem, _, vault, source, originalContent) = writeBlobAndFail(at: .duringMetadataWrite)

    #expect(throws: (any Error).self) {
        try vault.writeBlob(fromFileAt: source)
    }

    #expect(try fileSystem.read(at: source) == originalContent) // I1
    // Le rename a réussi avant l'échec du .json : le blob existe, intact — orphelin mais bénin
    // (I3), puisqu'aucune ligne `documents` ne le référencera (l'appelant n'atteint jamais la
    // transaction SQL si writeBlob a levé une erreur).
    let vaultEntries = (try? fileSystem.contentsOfDirectory(at: URL(fileURLWithPath: "/vault-root/vault"))) ?? []
    #expect(vaultEntries.count == 1)
}

@Test func successfulWriteLeavesNoTemporaryResidue() throws {
    let (fileSystem, _, vault, source, _) = writeBlobAndFail(at: .none)

    let result = try vault.writeBlob(fromFileAt: source)

    #expect(fileSystem.fileExists(at: result.blobURL))
    let tmpEntries = (try? fileSystem.contentsOfDirectory(at: URL(fileURLWithPath: "/vault-root/tmp"))) ?? []
    #expect(tmpEntries.isEmpty) // pas de résidu après un succès (I5).
}
