import DropCore
import DropFeatures
import DropIndex
import DropVault
import Foundation
import GRDB
import Testing

private func makeDatabase() throws -> DropIndexDatabase {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("drop-export-test-\(UUID().uuidString).sqlite").path
    return try DropIndexDatabase(path: dbPath)
}

@Test func exportSingleCopiesTheDocumentUnderItsOriginalName() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture-edf.pdf")
    fileSystem.seed(source.path, contents: Data("facture EDF".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)
    let database = try makeDatabase()
    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())
    guard case .created(let documentID) = try await ingest.ingest(fileAt: source) else {
        Issue.record("expected a created document"); return
    }

    let export = ExportDocuments(vault: vault, database: database)
    let destinationFolder = URL(fileURLWithPath: "/Desktop")
    let exportedURL = try await export.exportSingle(documentID: documentID, toFolder: destinationFolder)

    #expect(exportedURL.lastPathComponent == "facture-edf.pdf")
    #expect(fileSystem.fileExists(at: exportedURL))
    #expect(try fileSystem.read(at: exportedURL) == Data("facture EDF".utf8))
}

@Test func exportAllProducesAConsistentTreeAndManifest() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let sourceA = URL(fileURLWithPath: "/incoming/facture-edf.pdf")
    let sourceB = URL(fileURLWithPath: "/incoming/contrat-location.pdf")
    fileSystem.seed(sourceA.path, contents: Data("facture".utf8))
    fileSystem.seed(sourceB.path, contents: Data("contrat plus long".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)
    let database = try makeDatabase()
    let ingest = IngestFiles(vault: vault, database: database, sleeper: ImmediateSleeper())
    _ = try await ingest.ingest(fileAt: sourceA)
    _ = try await ingest.ingest(fileAt: sourceB)

    let export = ExportDocuments(vault: vault, database: database)
    let destination = URL(fileURLWithPath: "/Desktop")
    let summary = try await export.exportAll(toDirectory: destination, today: Date(timeIntervalSince1970: 1_755_100_800))

    #expect(summary.isConsistent)
    #expect(summary.exportedFileCount == 2)
    #expect(summary.rootURL.lastPathComponent == "Export Drop 2025-08-13")

    let manifestContent = try fileSystem.read(at: summary.manifestURL)
    #expect(manifestContent.prefix(3) == Data([0xEF, 0xBB, 0xBF])) // BOM UTF-8
    // `String(data:encoding:.utf8)` consomme silencieusement le BOM à la lecture — normal.
    let manifestText = String(data: manifestContent, encoding: .utf8)!
    #expect(manifestText.hasPrefix("nom,type,"))
    #expect(manifestText.contains("facture-edf.pdf"))
    #expect(manifestText.contains("contrat-location.pdf"))
}

@Test func exportAllResolvesFilenameCollisionsWithASuffix() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let sourceA = URL(fileURLWithPath: "/incoming/a/facture.pdf")
    let sourceB = URL(fileURLWithPath: "/incoming/b/facture.pdf")
    fileSystem.seed(sourceA.path, contents: Data("contenu A".utf8))
    fileSystem.seed(sourceB.path, contents: Data("contenu B, plus long pour un hash différent".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)
    let database = try makeDatabase()
    let epoch = FixedClock(date: Date(timeIntervalSince1970: 0))
    let ingest = IngestFiles(vault: vault, database: database, clock: epoch, sleeper: ImmediateSleeper())
    _ = try await ingest.ingest(fileAt: sourceA)
    _ = try await ingest.ingest(fileAt: sourceB)

    let export = ExportDocuments(vault: vault, database: database)
    let summary = try await export.exportAll(toDirectory: URL(fileURLWithPath: "/Desktop"))

    #expect(summary.isConsistent)
    #expect(summary.exportedFileCount == 2)

    let directory = summary.rootURL.appendingPathComponent("autre/1970")
    let entries = try fileSystem.contentsOfDirectory(at: directory)
    let names = Set(entries.map(\.lastPathComponent))
    #expect(names.contains("facture.pdf"))
    #expect(names.contains("facture (2).pdf"))
}

@Test func exportAllResumeSkipsAlreadyExportedFiles() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = URL(fileURLWithPath: "/vault-root")
    let source = URL(fileURLWithPath: "/incoming/facture.pdf")
    fileSystem.seed(source.path, contents: Data("facture".utf8))

    let vault = VaultService(vaultRoot: root, fileSystem: fileSystem)
    let database = try makeDatabase()
    let epoch = FixedClock(date: Date(timeIntervalSince1970: 0))
    let ingest = IngestFiles(vault: vault, database: database, clock: epoch, sleeper: ImmediateSleeper())
    _ = try await ingest.ingest(fileAt: source)

    let export = ExportDocuments(vault: vault, database: database)
    let destination = URL(fileURLWithPath: "/Desktop")
    let today = Date(timeIntervalSince1970: 1_755_100_800)
    _ = try await export.exportAll(toDirectory: destination, today: today)
    let second = try await export.exportAll(toDirectory: destination, today: today)

    // Reprise : le fichier déjà exporté est reconnu par nom+taille, jamais dupliqué en " (2)".
    let directory = second.rootURL.appendingPathComponent("autre/1970")
    let entries = try fileSystem.contentsOfDirectory(at: directory)
    #expect(entries.map(\.lastPathComponent) == ["facture.pdf"])
    #expect(second.isConsistent)
}
