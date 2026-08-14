import AppKit
import DropCore
import DropEmbeddings
import DropFeatures
import DropIndex
import DropLicense
import DropSearch
import DropVault
import Foundation
import GRDB
import Observation

/// État visuel de la Drop Zone (§EX-01), piloté par les événements réels d'ingestion — jamais
/// une simulation locale à la vue.
enum DropZoneState: Equatable {
    case idle
    case hovering
    case ingesting(fileName: String)
    case success(fileName: String)
    case duplicate(fileName: String)
    case failure(fileName: String, message: String)
}

/// Bootstrap applicatif (§4.2) : point unique où les cas d'usage de `DropFeatures` sont
/// instanciés contre un vrai coffre sur disque. Avant ce type, chaque vue affichait des données
/// passées en paramètre sans jamais interroger un moteur réel (cf. les notes de portée devenues
/// obsolètes dans `SearchView`/`PreferencesView`/`DropApp`).
@MainActor
@Observable
final class AppEnvironment {
    let vaultRoot: URL
    let vault: VaultService
    let indexDatabase: DropIndexDatabase
    private let vectorsDatabase: VectorsDatabase?
    private let ingestFiles: IngestFiles
    private let searchEngine: SearchEngine
    private let analyzeDocument: AnalyzeDocument
    let manageTrash: ManageTrash
    let exportDocuments: ExportDocuments
    private let jobQueue: JobQueue
    private let queryParser = QueryParser()

    var dropZoneState: DropZoneState = .idle
    var searchResults: [DocumentSearchResult] = []
    var isSearching = false

    /// Emplacement par défaut (§EF-20) : Application Support, jamais iCloud Drive ni un dossier
    /// synchronisé — le choix d'un autre emplacement avec migration vérifiée reste à câbler.
    static var defaultVaultLocation: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Drop")
    }

    init(vaultRoot: URL) throws {
        self.vaultRoot = vaultRoot
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)

        let vault = VaultService(vaultRoot: vaultRoot)
        try vault.clearTemporaryFiles()

        // Mode Standard (DRO-51) : la clé vit au Keychain, jamais sur disque en clair. Un coffre
        // est identifié par son chemin — deux coffres à deux emplacements ont deux clés distinctes.
        let passphrase = try VaultEncryptionKey.getOrCreate(store: SecKeychainKeyStore(), account: vaultRoot.path)
        let indexDatabase = try DropIndexDatabase(
            path: vaultRoot.appendingPathComponent("index.db").path, passphrase: passphrase
        )
        // `vectors.db` reste non chiffré par exception documentée (§4.3) ; son absence ne doit
        // jamais empêcher le reste de l'app de fonctionner (recherche lexicale seule en repli).
        let vectorsDatabase = try? VectorsDatabase(path: vaultRoot.appendingPathComponent("vectors.db").path)

        self.vault = vault
        self.indexDatabase = indexDatabase
        self.vectorsDatabase = vectorsDatabase
        self.ingestFiles = IngestFiles(vault: vault, database: indexDatabase)
        self.searchEngine = SearchEngine(indexDatabase: indexDatabase, vectorsDatabase: vectorsDatabase)
        self.analyzeDocument = AnalyzeDocument(vault: vault, database: indexDatabase)
        self.manageTrash = ManageTrash(vault: vault, database: indexDatabase)
        self.exportDocuments = ExportDocuments(vault: vault, database: indexDatabase)
        self.jobQueue = JobQueue(database: indexDatabase)
    }

    // MARK: - Ingestion (Drop Zone, EF-01 à EF-13)

    func handleDrop(of urls: [URL]) {
        for url in urls {
            Task { await ingest(fileAt: url) }
        }
    }

    private func ingest(fileAt url: URL) async {
        let fileName = url.lastPathComponent
        dropZoneState = .ingesting(fileName: fileName)

        do {
            let outcome = try await ingestFiles.ingest(fileAt: url)
            switch outcome {
            case .created(let documentID):
                dropZoneState = .success(fileName: fileName)
                // Note de portée : aucun worker ne draine encore la file en tâche de fond
                // (DRO-31 pose la structure, pas le worker) — l'analyse tourne donc en ligne ici
                // pour que le document soit exploitable tout de suite, tout en restant enfilée
                // pour la traçabilité (`jobs`) en vue du futur worker.
                _ = try? await jobQueue.enqueue(documentID: documentID, kind: .extract)
                try? await analyzeDocument.analyze(documentID: documentID)
            case .exactDuplicate:
                dropZoneState = .duplicate(fileName: fileName)
            }
        } catch {
            dropZoneState = .failure(fileName: fileName, message: Self.describe(error))
        }

        try? await Task.sleep(for: .seconds(2.5))
        dropZoneState = .idle
    }

    private static func describe(_ error: any Error) -> String {
        if let dropError = error as? DropError { return dropError.message }
        return String(describing: error)
    }

    // MARK: - Recherche (§5.6-5.7)

    func search(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }

        let query = queryParser.parse(text)
        do {
            let results = try await searchEngine.search(query)
            searchResults = try await hydrate(results)
        } catch {
            searchResults = []
        }
    }

    /// Sous-ensemble de `documents` nécessaire à l'affichage — un `struct` `Sendable` plutôt que
    /// des `Row` GRDB, qui ne traversent pas la frontière `async` de `DatabasePool.read` (§4.2).
    private struct DocumentRow: Sendable {
        let id: String
        let displayName: String
        let originalFilename: String?
        let docType: String?
        let issuer: String?
        let effectiveDate: String?
        let summary: String?
        let originalPath: String?
        let sizeBytes: Int64
        let blobHash: String
    }

    private func hydrate(_ results: [SearchResult]) async throws -> [DocumentSearchResult] {
        guard !results.isEmpty else { return [] }
        let documentIDs = results.map(\.documentID)

        let rows = try await indexDatabase.pool.read { db -> [DocumentRow] in
            let placeholders = documentIDs.map { _ in "?" }.joined(separator: ", ")
            let fetched = try Row.fetchAll(
                db,
                sql: """
                SELECT id, display_name, original_filename, doc_type, issuer, effective_date, summary,
                       original_path, size_bytes, blob_hash
                FROM documents WHERE id IN (\(placeholders))
                """,
                arguments: StatementArguments(documentIDs)
            )
            return fetched.map { row in
                DocumentRow(
                    id: row["id"], displayName: row["display_name"], originalFilename: row["original_filename"],
                    docType: row["doc_type"], issuer: row["issuer"], effectiveDate: row["effective_date"],
                    summary: row["summary"], originalPath: row["original_path"], sizeBytes: row["size_bytes"],
                    blobHash: row["blob_hash"]
                )
            }
        }
        var rowsByID: [String: DocumentRow] = [:]
        for row in rows { rowsByID[row.id] = row }

        return results.compactMap { result -> DocumentSearchResult? in
            guard let row = rowsByID[result.documentID] else { return nil }

            return DocumentSearchResult(
                id: result.documentID,
                displayName: row.displayName,
                docType: row.docType,
                issuer: row.issuer,
                effectiveDate: row.effectiveDate.flatMap(Self.parseDay),
                amount: nil,
                keywords: [],
                summary: row.summary,
                tags: [],
                originalPath: row.originalPath,
                sizeBytes: row.sizeBytes,
                hash: row.blobHash,
                previewURL: previewURL(forHash: row.blobHash, displayName: row.originalFilename ?? row.displayName)
            )
        }
    }

    /// Quick Look et « Ouvrir » ont besoin d'un chemin avec le bon nom/extension pour détecter le
    /// type de contenu — le blob lui-même est nommé par son seul hash (§4.3). Un lien symbolique
    /// jetable dans `tmp/` évite toute copie tout en donnant ce nom correct.
    private func previewURL(forHash hash: String, displayName: String) -> URL? {
        let (blobURL, _) = vault.paths(forHash: hash)
        guard FileManager.default.fileExists(atPath: blobURL.path) else { return nil }
        let linkURL = vaultRoot.appendingPathComponent("tmp/preview-\(hash)-\(displayName)")
        if !FileManager.default.fileExists(atPath: linkURL.path) {
            try? FileManager.default.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: blobURL)
        }
        return linkURL
    }

    private static func parseDay(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)
    }

    // MARK: - Actions sur un résultat

    func open(_ result: DocumentSearchResult) {
        guard let url = result.previewURL else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ result: DocumentSearchResult) {
        guard let url = result.previewURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func remove(_ result: DocumentSearchResult) {
        searchResults.removeAll { $0.id == result.id }
        Task { try? await manageTrash.moveToTrash(documentID: result.id) }
    }

    // MARK: - Budget disque (EF-26)

    func computeBudget() async -> VaultBudget {
        let compute = ComputeVaultBudget(
            database: indexDatabase,
            indexPath: vaultRoot.appendingPathComponent("index.db"),
            vectorsPath: vectorsDatabase != nil ? vaultRoot.appendingPathComponent("vectors.db") : nil
        )
        return (try? await compute.compute()) ?? VaultBudget(vaultSizeBytes: 0, dedupSavingsBytes: 0, indexSizeBytes: 0, vectorsSizeBytes: 0)
    }
}
