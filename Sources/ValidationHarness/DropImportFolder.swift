import DropCore
import DropFeatures
import DropIndex
import DropVault
import Foundation

/// Ingère et analyse, par le vrai pipeline, tous les fichiers d'un dossier dans le vrai coffre
/// par défaut — utilisé pour compléter `drop-demo` (contenu généré) avec de vrais fichiers PDF
/// téléchargés depuis des sources publiques (factures, contrats, relevés... jamais un document
/// utilisateur réel, seulement des exemples génériques publiés par des tiers à cet effet).
func runDropImportFolder(path: String) async throws {
    let folderURL = URL(fileURLWithPath: path)
    let fileURLs = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        .filter { !$0.lastPathComponent.hasPrefix(".") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    guard !fileURLs.isEmpty else {
        print("Aucun fichier trouvé dans \(folderURL.path)")
        return
    }

    let vaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Drop")
    try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)

    print("=== drop-import — \(fileURLs.count) fichier(s) de \(folderURL.path) → \(vaultRoot.path) ===\n")

    let vault = VaultService(vaultRoot: vaultRoot)
    try vault.clearTemporaryFiles()
    let passphrase = try VaultEncryptionKey.getOrCreate(store: SecKeychainKeyStore(), account: vaultRoot.path)
    let indexDatabase = try DropIndexDatabase(path: vaultRoot.appendingPathComponent("index.db").path, passphrase: passphrase)

    let ingestFiles = IngestFiles(vault: vault, database: indexDatabase, sleeper: ImmediateSleeper(), stabilityWindowSeconds: 0)
    let analyzeDocument = AnalyzeDocument(vault: vault, database: indexDatabase)

    var created = 0
    var duplicates = 0
    var failed = 0

    for (index, fileURL) in fileURLs.enumerated() {
        let start = Date()
        do {
            switch try await ingestFiles.ingest(fileAt: fileURL) {
            case .created(let documentID):
                try await analyzeDocument.analyze(documentID: documentID)
                created += 1
                print("[\(index + 1)/\(fileURLs.count)] \(fileURL.lastPathComponent) — analysé en \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
            case .exactDuplicate:
                duplicates += 1
                print("[\(index + 1)/\(fileURLs.count)] \(fileURL.lastPathComponent) — déjà présent, ignoré")
            }
        } catch {
            failed += 1
            print("[\(index + 1)/\(fileURLs.count)] \(fileURL.lastPathComponent) — échec : \(error)")
        }
    }

    print("\n=== Rapport drop-import ===")
    print("Documents créés : \(created)")
    print("Doublons ignorés : \(duplicates)")
    print("Échecs : \(failed)")
    print("Coffre : \(vaultRoot.path)")
}
