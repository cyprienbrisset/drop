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
    /// Rappel non modal (EF-84) : jamais une alerte système, juste un message inline dans la
    /// zone de dépôt — l'utilisateur reste libre de continuer sans interruption.
    case reminder(message: String)
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
    private let manageTags: ManageTags
    private let verifyVaultIntegrity: VerifyVaultIntegrity
    private let importVaultUseCase: ImportVault
    private let scheduleReminders: ScheduleReminders
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
        let indexPath = vaultRoot.appendingPathComponent("index.db").path
        let indexDatabase = try Self.openOrRepairIndex(vaultRoot: vaultRoot, indexPath: indexPath, passphrase: passphrase)
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
        self.manageTags = ManageTags(database: indexDatabase)
        self.verifyVaultIntegrity = VerifyVaultIntegrity(database: indexDatabase, vault: vault)
        self.importVaultUseCase = ImportVault(vault: vault, database: indexDatabase)
        self.scheduleReminders = ScheduleReminders(database: indexDatabase, scheduler: SystemNotificationScheduler())
        self.jobWorker = JobWorker(jobQueue: jobQueue, analyzeDocument: analyzeDocument, scheduleReminders: scheduleReminders)
        Task { await self.jobWorker.start() }
        Task { await self.runMaintenanceLoop() }
    }

    /// EF-28 : un schéma illisible ne doit jamais faire planter l'app au démarrage — le coffre
    /// reste reconstructible depuis `meta.json` et les blobs (garantie de dernier recours, §4.3).
    /// L'ancien fichier est mis de côté (I3 : jamais perdu) plutôt que supprimé.
    private static func openOrRepairIndex(vaultRoot: URL, indexPath: String, passphrase: Data) throws -> DropIndexDatabase {
        if let database = try? DropIndexDatabase(path: indexPath, passphrase: passphrase) {
            return database
        }

        let brokenURL = URL(fileURLWithPath: indexPath)
        let quarantineURL = brokenURL.deletingLastPathComponent()
            .appendingPathComponent("index-corrupted-\(ISO8601DateFormatter().string(from: Date())).db")
        try? FileManager.default.moveItem(at: brokenURL, to: quarantineURL)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: indexPath + suffix))
        }

        let freshDatabase = try DropIndexDatabase(path: indexPath, passphrase: passphrase)

        // `RepairVault.rebuildIndex` est asynchrone ; cette réparation, elle, ne peut arriver que
        // pendant l'initialisation synchrone de l'app (avant toute UI) — le pont par sémaphore
        // reste local à ce seul chemin de secours, jamais utilisé sur le chemin normal.
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            _ = try? await RepairVault(vaultRoot: vaultRoot).rebuildIndex(into: freshDatabase)
            semaphore.signal()
        }
        semaphore.wait()

        return freshDatabase
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

        let documentCountBefore = (try? await activeDocumentCount()) ?? 0
        let stateBefore = LicenseGate.state(forVerifiedPayload: nil, documentCount: documentCountBefore)
        guard LicenseGate.canIngestNewDocument(state: stateBefore) else {
            dropZoneState = .failure(
                fileName: fileName,
                message: "Plafond de \(LicenseGate.freeCap) documents atteint (version gratuite)."
            )
            try? await Task.sleep(for: .seconds(3))
            dropZoneState = .idle
            return
        }

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

                // EF-84 : rappel unique et non modal au premier franchissement de 80 documents.
                if LicenseGate.shouldShowCapReminder(documentCount: documentCountBefore + 1, alreadyShown: hasShownCapReminder) {
                    hasShownCapReminder = true
                    try? await Task.sleep(for: .seconds(2.5))
                    dropZoneState = .reminder(
                        message: "\(documentCountBefore + 1)/\(LicenseGate.freeCap) documents — pensez à la version Pro."
                    )
                }
            case .exactDuplicate:
                dropZoneState = .duplicate(fileName: fileName)
            }
        } catch {
            dropZoneState = .failure(fileName: fileName, message: Self.describe(error))
        }

        try? await Task.sleep(for: .seconds(2.5))
        dropZoneState = .idle
    }

    /// Nombre de documents actifs (hors corbeille) — utilisé pour le plafond gratuit (EF-81) et
    /// son affichage dans les préférences.
    func activeDocumentCount() async throws -> Int {
        try await indexDatabase.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documents WHERE trashed_at IS NULL") ?? 0
        }
    }

    private var hasShownCapReminderKey: String { "hasShownCapReminder-\(vaultRoot.path)" }
    private var hasShownCapReminder: Bool {
        get { UserDefaults.standard.bool(forKey: hasShownCapReminderKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasShownCapReminderKey) }
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
        let keywords: [String]
        let amount: Double?
        let tags: [String]
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

            let keywordRows = try Row.fetchAll(
                db, sql: "SELECT document_id, keywords FROM fts_docs WHERE document_id IN (\(placeholders))",
                arguments: StatementArguments(documentIDs)
            )
            var keywordsByID: [String: [String]] = [:]
            for row in keywordRows {
                let raw: String = row["keywords"]
                keywordsByID[row["document_id"]] = raw.split(separator: " ").map(String.init)
            }

            // Le montant le plus digne de confiance par document (§5.3.1) : un document peut
            // porter plusieurs montants (sous-total, TVA, net à payer) — on affiche celui que
            // l'extracteur a jugé le plus fiable, à défaut le premier détecté.
            let amountRows = try Row.fetchAll(
                db,
                sql: """
                SELECT document_id, value_num FROM entities
                WHERE document_id IN (\(placeholders)) AND kind = 'amount'
                ORDER BY confidence DESC
                """,
                arguments: StatementArguments(documentIDs)
            )
            var amountByID: [String: Double] = [:]
            for row in amountRows {
                let documentID: String = row["document_id"]
                if amountByID[documentID] == nil { amountByID[documentID] = row["value_num"] }
            }

            let tagRows = try Row.fetchAll(
                db,
                sql: """
                SELECT document_tags.document_id AS document_id, tags.name AS name
                FROM document_tags JOIN tags ON tags.id = document_tags.tag_id
                WHERE document_tags.document_id IN (\(placeholders))
                ORDER BY tags.name
                """,
                arguments: StatementArguments(documentIDs)
            )
            var tagsByID: [String: [String]] = [:]
            for row in tagRows {
                tagsByID[row["document_id"], default: []].append(row["name"])
            }

            return fetched.map { row in
                let documentID: String = row["id"]
                return DocumentRow(
                    id: documentID, displayName: row["display_name"], originalFilename: row["original_filename"],
                    docType: row["doc_type"], issuer: row["issuer"], effectiveDate: row["effective_date"],
                    summary: row["summary"], originalPath: row["original_path"], sizeBytes: row["size_bytes"],
                    blobHash: row["blob_hash"], keywords: keywordsByID[documentID] ?? [], amount: amountByID[documentID],
                    tags: tagsByID[documentID] ?? []
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
                amount: row.amount,
                keywords: row.keywords,
                summary: row.summary,
                tags: row.tags,
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

    /// Import assisté d'un coffre existant (Q-08, DRO-85) : choix du dossier racine du coffre
    /// source via un panneau système, puis fusion des blobs pas encore connus dans le coffre
    /// courant — jamais de tentative de transfert de la clé Keychain source (§4.1, la clé Mode
    /// Standard reste propre à cette machine).
    func importVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Importer"
        panel.message = "Choisissez le dossier racine du coffre Drop à importer"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let sourceRoot = panel.url else { return }

        Task {
            let alert = NSAlert()
            do {
                let report = try await importVaultUseCase.importVault(from: sourceRoot)
                for documentID in report.importedDocumentIDs {
                    _ = try? await jobQueue.enqueue(documentID: documentID, kind: .extract)
                }
                alert.messageText = "Import terminé"
                alert.informativeText = report.importedDocumentIDs.isEmpty
                    ? "Aucun nouveau document : tout le contenu de ce coffre était déjà présent."
                    : "\(report.importedDocumentIDs.count) document(s) importé(s), \(report.skippedAlreadyPresentCount) déjà présent(s) et ignoré(s)."
            } catch {
                alert.messageText = "Import impossible"
                alert.informativeText = "Le dossier choisi ne semble pas être un coffre Drop valide."
            }
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: - Rappels d'échéance (DRO-84)

    func remindersEnabled() async -> Bool {
        (try? await scheduleReminders.remindersEnabled()) ?? false
    }

    /// Jamais appelé automatiquement (§CDC) : seule une action explicite de l'utilisateur dans
    /// les Préférences déclenche l'activation, et donc la demande d'autorisation système qui suit.
    func setRemindersEnabled(_ enabled: Bool) {
        Task { try? await scheduleReminders.setRemindersEnabled(enabled) }
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

    // MARK: - Tags (EF-66)

    func addTag(_ result: DocumentSearchResult, name: String) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        Task { try? await manageTags.addTag(documentID: result.id, name: normalized) }
        applyLocalCorrection(documentID: result.id) { current in
            if !current.tags.contains(normalized) { current.tags.append(normalized); current.tags.sort() }
        }
    }

    func removeTag(_ result: DocumentSearchResult, name: String) {
        Task { try? await manageTags.removeTag(documentID: result.id, name: name) }
        applyLocalCorrection(documentID: result.id) { $0.tags.removeAll { $0 == name } }
    }

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
