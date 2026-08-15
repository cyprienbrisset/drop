import DropCore
import DropEmbeddings
import DropFeatures
import DropIndex
import DropSearch
import DropVault
import Foundation

/// Harnais d'évaluation de la qualité de recherche (§9, DRO-15/46) : un corpus de référence,
/// ingéré et analysé par le vrai pipeline (extraction, entités, modèle de langage embarqué s'il
/// est disponible, embeddings sémantiques), puis interrogé par 30 requêtes en langage naturel
/// dont la bonne réponse est connue à l'avance. Le critère de décision du CDC est recall@3 ≥ 0,85
/// : pour au moins 85 % des requêtes, le document attendu doit apparaître dans les 3 premiers
/// résultats.
///
/// Le corpus n'est jamais un document utilisateur réel (comme pour la Validation B, DRO-17) —
/// seulement du contenu généré pour ce test, jetable, jamais versionné comme fixture binaire.
struct EvalCase {
    let filename: String
    let content: String
    /// Requête en langage naturel censée retrouver ce document — volontairement diverse : mots
    /// exacts, paraphrase, montant/date, ou légère faute de frappe — pour exercer tour à tour le
    /// chemin lexical, sémantique, les filtres et le repli trigramme, pas un seul chemin à la fois.
    let query: String
}

func runDropEval() async throws {
    let vaultRoot = FileManager.default.temporaryDirectory.appendingPathComponent("drop-eval-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: vaultRoot) }

    let vault = VaultService(vaultRoot: vaultRoot)
    let indexDatabase = try DropIndexDatabase(path: vaultRoot.appendingPathComponent("index.db").path)
    let vectorsDatabase = try? VectorsDatabase(path: vaultRoot.appendingPathComponent("vectors.db").path)

    let ingestFiles = IngestFiles(vault: vault, database: indexDatabase, sleeper: ImmediateSleeper(), stabilityWindowSeconds: 0)
    let analyzeDocument = AnalyzeDocument(vault: vault, database: indexDatabase)
    let searchEngine = SearchEngine(indexDatabase: indexDatabase, vectorsDatabase: vectorsDatabase)
    let queryParser = QueryParser()

    print("=== drop-eval — ingestion et analyse réelle de \(evalCorpus.count) documents ===")
    print("(chaque document passe par le vrai pipeline — extraction, entités, modèle de langage sur l'appareil s'il est disponible — jusqu'à plusieurs dizaines de secondes chacun)\n")

    var documentIDs: [String: String] = [:]

    for (index, testCase) in evalCorpus.enumerated() {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("drop-eval-\(UUID().uuidString)-\(testCase.filename)")
        try testCase.content.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let start = Date()
        guard case .created(let documentID) = try await ingestFiles.ingest(fileAt: fileURL) else {
            print("[\(index + 1)/\(evalCorpus.count)] \(testCase.filename) — doublon inattendu (ignoré)")
            continue
        }
        try await analyzeDocument.analyze(documentID: documentID)
        documentIDs[testCase.filename] = documentID
        print("[\(index + 1)/\(evalCorpus.count)] \(testCase.filename) — analysé en \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
    }

    print("\n=== drop-eval — mesure recall@3 sur \(evalCorpus.count) requêtes ===\n")

    var hits = 0
    var misses: [String] = []

    for testCase in evalCorpus {
        guard let targetID = documentIDs[testCase.filename] else { continue }
        let parsed = queryParser.parse(testCase.query)
        let results = try await searchEngine.search(parsed, limit: 3)
        let hit = results.prefix(3).contains { $0.documentID == targetID }

        if hit {
            hits += 1
        } else {
            misses.append("« \(testCase.query) » → attendu « \(testCase.filename) », obtenu \(results.map(\.documentID))")
        }
        print("\(hit ? "✔" : "✘") « \(testCase.query) » → \(testCase.filename)")
    }

    let recall = evalCorpus.isEmpty ? 0 : Double(hits) / Double(evalCorpus.count)

    print("\n=== Rapport drop-eval ===")
    print("Documents ingérés et analysés : \(documentIDs.count)/\(evalCorpus.count)")
    print("Requêtes réussies (recall@3) : \(hits)/\(evalCorpus.count)")
    print(String(format: "recall@3 = %.3f", recall))
    print(recall >= 0.85 ? "→ Seuil DRO-46 (≥ 0,85) atteint." : "→ Seuil DRO-46 (≥ 0,85) NON atteint.")

    if !misses.isEmpty {
        print("\nÉchecs :")
        for miss in misses { print("  - \(miss)") }
    }
}

/// 30 documents de référence, jamais un document utilisateur réel. Contenu et requête choisis à la
/// main pour rester lisibles et vérifiables — pas de génération programmatique qui masquerait ce
/// que chaque cas teste réellement.
private let evalCorpus: [EvalCase] = [
    EvalCase(
        filename: "facture-edf-juillet.txt",
        content: "Facture d'électricité EDF — juillet 2026. Référence client 4471928. Montant à régler : 84,20 euros TTC, avant le 30 août 2026. Consommation : 210 kWh sur la période.",
        query: "facture edf juillet"
    ),
    EvalCase(
        filename: "facture-edf-aout.txt",
        content: "Facture d'électricité EDF — août 2026. Référence client 4471928. Montant à régler : 91,50 euros TTC, avant le 30 septembre 2026. Consommation : 230 kWh sur la période.",
        query: "combien j'ai payé à EDF en août"
    ),
    EvalCase(
        filename: "facture-orange-mobile.txt",
        content: "Facture Orange mobile — juin 2026. Ligne 06 12 34 56 78. Forfait 100 Go. Montant : 19,99 euros. Prélèvement le 5 juillet 2026.",
        query: "facture téléphone orange"
    ),
    EvalCase(
        filename: "facture-free-internet.txt",
        content: "Facture Free — abonnement Freebox, mai 2026. Montant mensuel : 29,99 euros. Référence d'abonnement FBX-88213.",
        query: "abonnement internet free"
    ),
    EvalCase(
        filename: "facture-engie-gaz.txt",
        content: "Facture de gaz naturel Engie — mars 2026. Point de livraison PDL-9012374. Montant dû : 112,40 euros, à régler avant le 15 avril 2026.",
        query: "ma facture de gaz"
    ),
    EvalCase(
        filename: "contrat-assurance-habitation.txt",
        content: "Contrat d'assurance habitation MAIF, numéro de police 778213AH. Souscrit le 1er janvier 2026 pour un appartement de 65 m². Cotisation annuelle : 186 euros.",
        query: "assurance de mon appartement"
    ),
    EvalCase(
        filename: "contrat-mutuelle-sante.txt",
        content: "Contrat de mutuelle santé Harmonie Mutuelle, formule Confort. Adhérent numéro 55219087. Cotisation mensuelle : 68 euros, prélevée le 3 de chaque mois.",
        query: "ma complémentaire santé"
    ),
    EvalCase(
        filename: "contrat-salle-de-sport.txt",
        content: "Contrat d'abonnement Basic Fit, formule illimitée. Adhérent depuis le 12 février 2026. Prélèvement mensuel : 29,99 euros.",
        query: "abonnement salle de sport"
    ),
    EvalCase(
        filename: "releve-bancaire-janvier.txt",
        content: "Relevé de compte Banque Populaire, janvier 2026. Solde précédent : 1 204,56 euros. Virement salaire reçu : 2 100 euros. Solde final : 1 987,32 euros.",
        query: "relevé bancaire de janvier"
    ),
    EvalCase(
        filename: "releve-bancaire-fevrier.txt",
        content: "Relevé de compte Banque Populaire, février 2026. Solde précédent : 1 987,32 euros. Prélèvements divers : 640 euros. Solde final : 1 347,32 euros.",
        query: "quel était mon solde en février"
    ),
    EvalCase(
        filename: "attestation-employeur.txt",
        content: "Attestation employeur — établie par la société Kalixo SAS le 4 mars 2026. Confirme que Jean Dupont est salarié en contrat à durée indéterminée depuis le 1er avril 2022.",
        query: "attestation de mon employeur"
    ),
    EvalCase(
        filename: "attestation-securite-sociale.txt",
        content: "Attestation de droits Sécurité sociale — CPAM de Paris, éditée le 10 janvier 2026. Numéro d'assuré 1 85 03 75 108 042. Droits ouverts jusqu'au 31 décembre 2026.",
        query: "attestation carte vitale"
    ),
    EvalCase(
        filename: "quittance-loyer-janvier.txt",
        content: "Quittance de loyer — appartement 12 rue des Lilas, janvier 2026. Loyer et charges réglés : 780 euros. Émise par l'agence Immo Plus.",
        query: "quittance de loyer janvier"
    ),
    EvalCase(
        filename: "quittance-loyer-fevrier.txt",
        content: "Quittance de loyer — appartement 12 rue des Lilas, février 2026. Loyer et charges réglés : 780 euros. Émise par l'agence Immo Plus.",
        query: "j'ai payé mon loyer de février ?"
    ),
    EvalCase(
        filename: "devis-travaux-cuisine.txt",
        content: "Devis de rénovation de cuisine — entreprise Bâti Rénov. Montant total : 8 450 euros TTC. Validité du devis : 30 jours à compter du 5 mai 2026.",
        query: "devis pour la cuisine"
    ),
    EvalCase(
        filename: "ordonnance-medicale.txt",
        content: "Ordonnance médicale — Dr Martin Lefèvre, cabinet de médecine générale. Prescription du 20 avril 2026 : paracétamol 1g, amoxicilline 500mg pendant 7 jours.",
        query: "ordonnance du docteur"
    ),
    EvalCase(
        filename: "contrat-travail-cdi.txt",
        content: "Contrat de travail à durée indéterminée entre la société Kalixo SAS et Jean Dupont, poste d'ingénieur logiciel, signé le 15 mars 2022. Rémunération annuelle brute : 48 000 euros.",
        query: "mon contrat de travail"
    ),
    EvalCase(
        filename: "bulletin-paie-mars.txt",
        content: "Bulletin de paie — Kalixo SAS, mars 2026. Salaire net versé : 2 850 euros, viré le 28 mars 2026.",
        query: "combien j'ai touché en mars"
    ),
    EvalCase(
        filename: "declaration-impots-2025.txt",
        content: "Déclaration de revenus 2025, transmise en ligne le 22 mai 2026. Revenu fiscal de référence : 34 200 euros. Impôt sur le revenu dû : 1 890 euros.",
        query: "ma déclaration d'impôts"
    ),
    EvalCase(
        filename: "carte-grise-vehicule.txt",
        content: "Certificat d'immatriculation — Renault Clio, immatriculée le 3 juin 2026. Numéro d'immatriculation AB-123-CD. Puissance fiscale : 5 CV.",
        query: "carte grise de la voiture"
    ),
    EvalCase(
        filename: "facture-garage-entretien.txt",
        content: "Facture du garage Autopro — révision et vidange, 12 février 2026. Véhicule Renault Clio, immatriculation AB-123-CD. Montant : 210 euros.",
        query: "entretien de la voiture au garage"
    ),
    EvalCase(
        filename: "billet-avion-lisbonne.txt",
        content: "Confirmation de réservation TAP Air Portugal — vol Paris-Lisbonne, départ le 14 juillet 2026. Référence de réservation LX92QK. Montant payé : 320 euros.",
        query: "billet d'avion pour lisbonne"
    ),
    EvalCase(
        filename: "reservation-hotel-porto.txt",
        content: "Confirmation de réservation d'hôtel — Porto Riverside, du 15 au 18 juillet 2026. Numéro de réservation HTL-77291. Montant total : 240 euros.",
        query: "réservation hôtel à porto"
    ),
    EvalCase(
        filename: "facture-veterinaire.txt",
        content: "Facture du cabinet vétérinaire Les Quatre Pattes — consultation et vaccin, 8 avril 2026. Animal : chat, Minou. Montant : 65 euros.",
        query: "facture véto pour le chat"
    ),
    EvalCase(
        filename: "diplome-master.txt",
        content: "Diplôme de master en informatique, délivré par l'Université de Lyon le 30 septembre 2020 à Jean Dupont, mention très bien.",
        query: "mon diplôme d'informatique"
    ),
    EvalCase(
        filename: "releve-notes-lycee.txt",
        content: "Relevé de notes du baccalauréat, série générale, session 2018, académie de Lyon. Mention : assez bien.",
        query: "relevé de notes du bac"
    ),
    EvalCase(
        filename: "facture-electricien.txt",
        content: "Facture de l'électricien Volt Services — remplacement du tableau électrique, 2 juin 2026. Montant : 1 340 euros, réglé en deux fois.",
        query: "travaux électricité maison"
    ),
    EvalCase(
        filename: "pv-assemblee-copropriete.txt",
        content: "Procès-verbal de l'assemblée générale de copropriété du 18 mars 2026, syndic Foncia. Résolution votée : ravalement de façade, budget 45 000 euros.",
        query: "assemblée générale copropriété"
    ),
    EvalCase(
        filename: "facture-edf-septembre.txt",
        content: "Facture d'électricité EDF — septembre 2026. Référence client 4471928. Montant à régler : 78,90 euros TTC, avant le 31 octobre 2026.",
        query: "facture elec de septmbre"
    ),
    EvalCase(
        filename: "contrat-abonnement-streaming.txt",
        content: "Confirmation d'abonnement Netflix, formule Standard. Montant mensuel : 13,49 euros, prélevé le 10 de chaque mois depuis janvier 2026.",
        query: "abonnement netflix"
    ),
]
