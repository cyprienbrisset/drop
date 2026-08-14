import DropCore
import DropIndex
import DropVault
import Foundation
import GRDB

/// Résumé d'un export intégral, avec la vérification post-export (§5.10) : nombre de fichiers et
/// somme des tailles comparés à la base.
public struct ExportSummary: Sendable, Equatable {
    public let rootURL: URL
    public let manifestURL: URL
    public let exportedFileCount: Int
    public let exportedTotalBytes: Int64
    public let expectedFileCount: Int
    public let expectedTotalBytes: Int64

    public var isConsistent: Bool {
        exportedFileCount == expectedFileCount && exportedTotalBytes == expectedTotalBytes
    }
}

/// Cas d'usage : export intégral et unitaire (§5.10). **Engagement de non-enfermement** : cette
/// fonction n'est jamais réservée au Pro, et ne requiert aucun format propriétaire pour récupérer
/// ses fichiers — arborescence lisible + `manifest.csv` ouvrable dans n'importe quel tableur.
public struct ExportDocuments: Sendable {
    private let vault: VaultService
    private let database: DropIndexDatabase

    public init(vault: VaultService, database: DropIndexDatabase) {
        self.vault = vault
        self.database = database
    }

    /// Export unitaire (EF-25) : copie un document vers un dossier de destination, sous son nom
    /// d'origine. Retourne le chemin final (suffixé en cas de collision).
    public func exportSingle(documentID: String, toFolder destinationFolder: URL) async throws -> URL {
        let entry = try await database.pool.read { db -> ExportEntry? in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM documents WHERE id = ?", arguments: [documentID]) else {
                return nil
            }
            return ExportEntry(row: row)
        }
        guard let entry else { throw IngestionError.transactionFailed }

        let destinationURL = try vault.uniqueDestinationURL(forName: entry.exportFilename, inDirectory: destinationFolder)
        try vault.exportBlob(hash: entry.blobHash, to: destinationURL)
        return destinationURL
    }

    /// Export intégral en un clic (EF-24) : `Export Drop AAAA-MM-JJ/<Type>/<AAAA>/<nom>`, plus un
    /// `manifest.csv`. Annulable coopérativement (`Task.cancel()`), sans doublon en cas de reprise
    /// puisque chaque nom de fichier est résolu par rapport à ce qui existe déjà sur disque.
    public func exportAll(toDirectory rootURL: URL, today: Date = Date()) async throws -> ExportSummary {
        let entries = try await database.pool.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM documents WHERE trashed_at IS NULL ORDER BY added_at")
                .map(ExportEntry.init)
        }

        let exportRoot = rootURL.appendingPathComponent("Export Drop \(Self.dayFormatter.string(from: today))")
        var manifestRows: [ExportEntry] = []
        var exportedFileCount = 0
        var exportedTotalBytes: Int64 = 0

        for entry in entries {
            try Task.checkCancellation()

            let directory = exportRoot
                .appendingPathComponent(entry.docType)
                .appendingPathComponent(entry.year)
            let expectedURL = directory.appendingPathComponent(entry.exportFilename)

            // Reprise après annulation, sans doublon (§5.10) : si le fichier attendu existe déjà
            // avec la bonne taille, on considère ce document déjà exporté et on ne le recopie pas.
            if vault.existingFileSize(at: expectedURL) != entry.sizeBytes {
                let destinationURL = try vault.uniqueDestinationURL(forName: entry.exportFilename, inDirectory: directory)
                try vault.exportBlob(hash: entry.blobHash, to: destinationURL)
            }

            exportedFileCount += 1
            exportedTotalBytes += entry.sizeBytes
            manifestRows.append(entry)
        }

        let manifestURL = exportRoot.appendingPathComponent("manifest.csv")
        try vault.writeExportManifest(manifestRows.map(\.manifestRow), to: manifestURL)

        let (expectedFileCount, expectedTotalBytes): (Int, Int64) = try await database.pool.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents WHERE trashed_at IS NULL") ?? 0
            let total = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(size_bytes), 0) FROM documents WHERE trashed_at IS NULL") ?? 0
            return (count, total)
        }

        return ExportSummary(
            rootURL: exportRoot, manifestURL: manifestURL,
            exportedFileCount: exportedFileCount, exportedTotalBytes: exportedTotalBytes,
            expectedFileCount: expectedFileCount, expectedTotalBytes: expectedTotalBytes
        )
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

/// Vue plate d'une ligne `documents`, pour la construction du chemin d'export et du manifeste.
private struct ExportEntry: Sendable {
    let documentID: String
    let blobHash: String
    let displayName: String
    let originalFilename: String
    let originalPath: String?
    let docType: String
    let issuer: String?
    let effectiveDate: String?
    let addedAt: String
    let sizeBytes: Int64

    init(row: Row) {
        documentID = row["id"]
        blobHash = row["blob_hash"]
        displayName = row["display_name"]
        originalFilename = row["original_filename"]
        originalPath = row["original_path"]
        docType = (row["doc_type"] as String?) ?? "autre"
        issuer = row["issuer"]
        effectiveDate = row["effective_date"]
        addedAt = row["added_at"]
        sizeBytes = row["size_bytes"]
    }

    var year: String {
        String((effectiveDate ?? addedAt).prefix(4))
    }

    /// Nom d'origine restauré ; si absent, `<type>-<émetteur>-<date>.<ext>` (§5.10).
    var exportFilename: String {
        guard originalFilename.isEmpty else { return originalFilename }
        let ext = (displayName as NSString).pathExtension
        let issuerPart = issuer ?? "inconnu"
        let datePart = effectiveDate ?? addedAt
        let base = "\(docType)-\(issuerPart)-\(datePart)"
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    var manifestRow: [String] {
        [displayName, docType, issuer ?? "", effectiveDate ?? "", "", blobHash, originalPath ?? ""]
    }
}
