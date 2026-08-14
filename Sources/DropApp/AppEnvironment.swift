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
    private let jobWorker: JobWorker
    private let correctDocument: CorrectDocument
    private let verifyVaultIntegrity: VerifyVaultIntegrity
    private let queryParser = QueryParser()

    /// Cadence de la boucle d'entretien (purge de la corbeille échue, EF-23) — la vérification
    /// d'intégrité (EF-27) est hebdomadaire et gérée séparément via `lastIntegrityCheckKey`.
    private static let maintenanceIntervalSeconds: Double = 86400
    private static let integrityCheckIntervalSeconds: TimeInterval = 7 * 86400
    private var lastIntegrityCheckKey: String { "lastIntegrityCheckAt-\(vaultRoot.path)" }

    var dropZoneState: DropZoneState = .idle
    var searchResults: [DocumentSearchResult] = []
    var isSearching = false
    var trashedDocuments: [ManageTrash.TrashedDocument] = []

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
        self.correctDocument = CorrectDocument(database: indexDatabase)
        self.verifyVaultIntegrity = VerifyVaultIntegrity(database: indexDatabase, vault: vault)
        self.jobWorker = JobWorker(jobQueue: jobQueue, analyzeDocument: analyzeDocument)
        Task { await self.jobWorker.start() }
        Task { await self.runMaintenanceLoop() }
    }

    // MARK: - Entretien (purge corbeille EF-23, intégrité EF-27)

    /// Boucle continue tant que l'app tourne : purge la corbeille échue toutes les 24 h, et
    /// vérifie l'intégrité par échantillonnage une fois par semaine (jamais plus souvent — le
    /// coût de ré-hachage grandit avec la taille du coffre, §5.9).
    private func runMaintenanceLoop() async {
        while !Task.isCancelled {
            await runMaintenanceOnce()
            try? await Task.sleep(for: .seconds(Self.maintenanceIntervalSeconds))
        }
    }

    /// Une passe d'entretien, exposée séparément de la boucle pour rester testable sans attendre
    /// un cycle de 24 h.
    func runMaintenanceOnce() async {
        _ = try? await manageTrash.purgeExpired()

        let defaults = UserDefaults.standard
        let key = lastIntegrityCheckKey
        let lastCheck = defaults.object(forKey: key) as? Date
        let dueForCheck = lastCheck.map { Date().timeIntervalSince($0) >= Self.integrityCheckIntervalSeconds } ?? true
        guard dueForCheck else { return }

        // Ne marque « vérifié » que si un échantillon a réellement été examiné (§5.9) : au tout
        // premier lancement, le coffre est vide et `sampledCount == 0` — marquer quand même la
        // date déclarerait à tort le coffre « vérifié » et repousserait le premier vrai contrôle
        // d'une semaine complète après le dépôt des premiers documents.
        guard let report = try? await verifyVaultIntegrity.run(), report.sampledCount > 0 else { return }
        defaults.set(Date(), forKey: key)
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
                // L'analyse (y compris l'appel au modèle de langage, parfois 20-30 s) tourne en
                // tâche de fond via `jobWorker` — le dépôt reste instantané, le document est déjà
                // cherchable sur ses métadonnées et devient pleinement enrichi peu après (EF-40).
                _ = try? await jobQueue.enqueue(documentID: documentID, kind: .extract)
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
    /// type de contenu — le blob lui-même est nommé par son seul hash (§4.3). Une vraie copie
    /// jetable dans `tmp/` (pas un lien symbolique : Finder et QuickLookUI ne les traitent pas
    /// toujours comme le fichier réel — l'utilisateur voit alors un simple alias illisible et
    /// sans aperçu) — mise en cache par hash+nom pour ne copier qu'une fois par document.
    private func previewURL(forHash hash: String, displayName: String) -> URL? {
        let (blobURL, _) = vault.paths(forHash: hash)
        guard FileManager.default.fileExists(atPath: blobURL.path) else { return nil }
        let copyURL = vaultRoot.appendingPathComponent("tmp/preview-\(hash)-\(displayName)")
        if !FileManager.default.fileExists(atPath: copyURL.path) {
            try? FileManager.default.createDirectory(at: copyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: blobURL, to: copyURL)
        }
        return copyURL
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

    /// EF-24 : export unitaire, choix du dossier de destination via un panneau système standard.
    func export(_ result: DocumentSearchResult) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Exporter ici"
        panel.message = "Choisissez un dossier de destination pour « \(result.displayName) »"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task { try? await exportDocuments.exportSingle(documentID: result.id, toFolder: folder) }
    }

    // MARK: - Corrections (EF-48)

    /// Corrige le type ; verrouille définitivement le champ contre toute réécriture automatique
    /// (`user_verified`, §4.4) et répercute le changement dans les vues déjà chargées.
    func correctType(_ result: DocumentSearchResult, to docType: String) {
        Task { try? await correctDocument.correctType(documentID: result.id, to: docType) }
        applyLocalCorrection(documentID: result.id) { $0.docType = docType }
    }

    func correctIssuer(_ result: DocumentSearchResult, to issuer: String) {
        Task { try? await correctDocument.correctIssuer(documentID: result.id, to: issuer) }
        applyLocalCorrection(documentID: result.id) { $0.issuer = issuer }
    }

    func correctEffectiveDate(_ result: DocumentSearchResult, to date: Date) {
        let dayString = Self.isoDayFormatter.string(from: date)
        Task { try? await correctDocument.correctEffectiveDate(documentID: result.id, to: dayString) }
        applyLocalCorrection(documentID: result.id) { $0.effectiveDate = date }
    }

    private func applyLocalCorrection(documentID: String, mutate: (inout DocumentSearchResult) -> Void) {
        guard let index = searchResults.firstIndex(where: { $0.id == documentID }) else { return }
        mutate(&searchResults[index])
    }

    private static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // MARK: - Corbeille (EF-23, §5.9)

    func loadTrash() async {
        trashedDocuments = (try? await manageTrash.listTrashed()) ?? []
    }

    func restoreFromTrash(_ document: ManageTrash.TrashedDocument) {
        trashedDocuments.removeAll { $0.id == document.id }
        Task {
            try? await manageTrash.restore(documentID: document.id)
        }
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
