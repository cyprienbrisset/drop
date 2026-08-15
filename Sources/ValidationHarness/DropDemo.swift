import DropCore
import DropFeatures
import DropIndex
import DropVault
import Foundation

/// Peuple le vrai coffre par défaut (`~/Library/Application Support/Drop`, le même que celui
/// ouvert par l'application) avec un corpus de démonstration réel, ingéré et analysé par le vrai
/// pipeline — jamais des lignes SQL insérées directement, contrairement au harnais `eval`, qui n'a
/// besoin que d'un index cohérent, pas d'un coffre présentable à l'écran. Contenu générique, jamais
/// un document utilisateur réel.
func runDropDemo() async throws {
    let vaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Drop")
    try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)

    print("=== drop-demo — coffre : \(vaultRoot.path) ===\n")

    let vault = VaultService(vaultRoot: vaultRoot)
    try vault.clearTemporaryFiles()
    // Même clé que l'application réelle (§DRO-51) : sans elle, l'app ne pourrait plus déchiffrer
    // ce que ce script vient d'écrire.
    let passphrase = try VaultEncryptionKey.getOrCreate(store: SecKeychainKeyStore(), account: vaultRoot.path)
    let indexDatabase = try DropIndexDatabase(path: vaultRoot.appendingPathComponent("index.db").path, passphrase: passphrase)
    // `vectors.db` : créé paresseusement par l'application elle-même au prochain lancement
    // (§AppEnvironment.init) — inutile de le construire ici, ce script n'écrit aucun embedding.

    let ingestFiles = IngestFiles(vault: vault, database: indexDatabase, sleeper: ImmediateSleeper(), stabilityWindowSeconds: 0)
    let analyzeDocument = AnalyzeDocument(vault: vault, database: indexDatabase)

    var created = 0
    var duplicates = 0

    for (index, testCase) in demoCorpus.enumerated() {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(testCase.filename)
        try testCase.content.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let start = Date()
        switch try await ingestFiles.ingest(fileAt: fileURL) {
        case .created(let documentID):
            try await analyzeDocument.analyze(documentID: documentID)
            created += 1
            print("[\(index + 1)/\(demoCorpus.count)] \(testCase.filename) — analysé en \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
        case .exactDuplicate:
            duplicates += 1
            print("[\(index + 1)/\(demoCorpus.count)] \(testCase.filename) — déjà présent, ignoré")
        }
    }

    print("\n=== Rapport drop-demo ===")
    print("Documents créés : \(created)")
    print("Doublons ignorés : \(duplicates)")
    print("Coffre prêt à l'emploi : \(vaultRoot.path)")
}

private struct DemoCase {
    let filename: String
    let content: String
}

/// Corpus de démonstration : générique, jamais un document utilisateur réel — variété volontaire
/// de types (factures, contrats, relevés, attestations, administratif, santé, voyage, véhicule,
/// éducation) pour donner un aperçu représentatif de ce que Drop sait retrouver.
private let demoCorpus: [DemoCase] = [
    DemoCase(filename: "facture-edf-juillet.txt", content: "Facture d'électricité EDF — juillet 2026. Référence client 4471928. Montant à régler : 84,20 euros TTC, avant le 30 août 2026. Consommation : 210 kWh sur la période."),
    DemoCase(filename: "facture-edf-aout.txt", content: "Facture d'électricité EDF — août 2026. Référence client 4471928. Montant à régler : 91,50 euros TTC, avant le 30 septembre 2026. Consommation : 230 kWh sur la période."),
    DemoCase(filename: "facture-edf-septembre.txt", content: "Facture d'électricité EDF — septembre 2026. Référence client 4471928. Montant à régler : 78,90 euros TTC, avant le 31 octobre 2026."),
    DemoCase(filename: "facture-orange-mobile.txt", content: "Facture Orange mobile — juin 2026. Ligne 06 12 34 56 78. Forfait 100 Go. Montant : 19,99 euros. Prélèvement le 5 juillet 2026."),
    DemoCase(filename: "facture-free-internet.txt", content: "Facture Free — abonnement Freebox, mai 2026. Montant mensuel : 29,99 euros. Référence d'abonnement FBX-88213."),
    DemoCase(filename: "facture-engie-gaz.txt", content: "Facture de gaz naturel Engie — mars 2026. Point de livraison PDL-9012374. Montant dû : 112,40 euros, à régler avant le 15 avril 2026."),
    DemoCase(filename: "contrat-assurance-habitation.txt", content: "Contrat d'assurance habitation MAIF, numéro de police 778213AH. Souscrit le 1er janvier 2026 pour un appartement de 65 m². Cotisation annuelle : 186 euros."),
    DemoCase(filename: "contrat-assurance-auto.txt", content: "Contrat d'assurance automobile Maaf, numéro de police AUTO-55210. Véhicule Renault Clio, immatriculation AB-123-CD. Cotisation annuelle : 420 euros."),
    DemoCase(filename: "contrat-mutuelle-sante.txt", content: "Contrat de mutuelle santé Harmonie Mutuelle, formule Confort. Adhérent numéro 55219087. Cotisation mensuelle : 68 euros, prélevée le 3 de chaque mois."),
    DemoCase(filename: "contrat-salle-de-sport.txt", content: "Contrat d'abonnement Basic Fit, formule illimitée. Adhérent depuis le 12 février 2026. Prélèvement mensuel : 29,99 euros."),
    DemoCase(filename: "contrat-abonnement-streaming.txt", content: "Confirmation d'abonnement Netflix, formule Standard. Montant mensuel : 13,49 euros, prélevé le 10 de chaque mois depuis janvier 2026."),
    DemoCase(filename: "contrat-travail-cdi.txt", content: "Contrat de travail à durée indéterminée entre la société Kalixo SAS et Jean Dupont, poste d'ingénieur logiciel, signé le 15 mars 2022. Rémunération annuelle brute : 48 000 euros."),
    DemoCase(filename: "releve-bancaire-janvier.txt", content: "Relevé de compte Banque Populaire, janvier 2026. Solde précédent : 1 204,56 euros. Virement salaire reçu : 2 100 euros. Solde final : 1 987,32 euros."),
    DemoCase(filename: "releve-bancaire-fevrier.txt", content: "Relevé de compte Banque Populaire, février 2026. Solde précédent : 1 987,32 euros. Prélèvements divers : 640 euros. Solde final : 1 347,32 euros."),
    DemoCase(filename: "releve-bancaire-mars.txt", content: "Relevé de compte Banque Populaire, mars 2026. Solde précédent : 1 347,32 euros. Virement salaire reçu : 2 100 euros. Solde final : 3 200,12 euros."),
    DemoCase(filename: "attestation-employeur.txt", content: "Attestation employeur — établie par la société Kalixo SAS le 4 mars 2026. Confirme que Jean Dupont est salarié en contrat à durée indéterminée depuis le 1er avril 2022."),
    DemoCase(filename: "attestation-securite-sociale.txt", content: "Attestation de droits Sécurité sociale — CPAM de Paris, éditée le 10 janvier 2026. Numéro d'assuré 1 85 03 75 108 042. Droits ouverts jusqu'au 31 décembre 2026."),
    DemoCase(filename: "quittance-loyer-janvier.txt", content: "Quittance de loyer — appartement 12 rue des Lilas, janvier 2026. Loyer et charges réglés : 780 euros. Émise par l'agence Immo Plus."),
    DemoCase(filename: "quittance-loyer-fevrier.txt", content: "Quittance de loyer — appartement 12 rue des Lilas, février 2026. Loyer et charges réglés : 780 euros. Émise par l'agence Immo Plus."),
    DemoCase(filename: "devis-travaux-cuisine.txt", content: "Devis de rénovation de cuisine — entreprise Bâti Rénov. Montant total : 8 450 euros TTC. Validité du devis : 30 jours à compter du 5 mai 2026."),
    DemoCase(filename: "facture-electricien.txt", content: "Facture de l'électricien Volt Services — remplacement du tableau électrique, 2 juin 2026. Montant : 1 340 euros, réglé en deux fois."),
    DemoCase(filename: "ordonnance-medicale.txt", content: "Ordonnance médicale — Dr Martin Lefèvre, cabinet de médecine générale. Prescription du 20 avril 2026 : paracétamol 1g, amoxicilline 500mg pendant 7 jours."),
    DemoCase(filename: "facture-veterinaire.txt", content: "Facture du cabinet vétérinaire Les Quatre Pattes — consultation et vaccin, 8 avril 2026. Animal : chat, Minou. Montant : 65 euros."),
    DemoCase(filename: "bulletin-paie-mars.txt", content: "Bulletin de paie — Kalixo SAS, mars 2026. Salaire net versé : 2 850 euros, viré le 28 mars 2026."),
    DemoCase(filename: "bulletin-paie-avril.txt", content: "Bulletin de paie — Kalixo SAS, avril 2026. Salaire net versé : 2 850 euros, viré le 28 avril 2026."),
    DemoCase(filename: "declaration-impots-2025.txt", content: "Déclaration de revenus 2025, transmise en ligne le 22 mai 2026. Revenu fiscal de référence : 34 200 euros. Impôt sur le revenu dû : 1 890 euros."),
    DemoCase(filename: "carte-grise-vehicule.txt", content: "Certificat d'immatriculation — Renault Clio, immatriculée le 3 juin 2026. Numéro d'immatriculation AB-123-CD. Puissance fiscale : 5 CV."),
    DemoCase(filename: "facture-garage-entretien.txt", content: "Facture du garage Autopro — révision et vidange, 12 février 2026. Véhicule Renault Clio, immatriculation AB-123-CD. Montant : 210 euros."),
    DemoCase(filename: "pv-controle-technique.txt", content: "Procès-verbal de contrôle technique — Renault Clio, immatriculation AB-123-CD, effectué le 20 mai 2026 chez Dekra. Résultat : favorable sans contre-visite."),
    DemoCase(filename: "billet-avion-lisbonne.txt", content: "Confirmation de réservation TAP Air Portugal — vol Paris-Lisbonne, départ le 14 juillet 2026. Référence de réservation LX92QK. Montant payé : 320 euros."),
    DemoCase(filename: "reservation-hotel-porto.txt", content: "Confirmation de réservation d'hôtel — Porto Riverside, du 15 au 18 juillet 2026. Numéro de réservation HTL-77291. Montant total : 240 euros."),
    DemoCase(filename: "reservation-location-voiture.txt", content: "Confirmation de location de voiture — Europcar, aéroport de Porto, du 15 au 18 juillet 2026. Référence LOC-33982. Montant : 95 euros."),
    DemoCase(filename: "diplome-master.txt", content: "Diplôme de master en informatique, délivré par l'Université de Lyon le 30 septembre 2020 à Jean Dupont, mention très bien."),
    DemoCase(filename: "releve-notes-lycee.txt", content: "Relevé de notes du baccalauréat, série générale, session 2018, académie de Lyon. Mention : assez bien."),
    DemoCase(filename: "attestation-formation-secourisme.txt", content: "Attestation de formation aux premiers secours (PSC1), délivrée le 14 mars 2026 par la Croix-Rouge française."),
    DemoCase(filename: "pv-assemblee-copropriete.txt", content: "Procès-verbal de l'assemblée générale de copropriété du 18 mars 2026, syndic Foncia. Résolution votée : ravalement de façade, budget 45 000 euros."),
    DemoCase(filename: "facture-plombier.txt", content: "Facture du plombier Aqua Services — réparation d'une fuite, 22 janvier 2026. Montant : 180 euros."),
    DemoCase(filename: "contrat-energie-verte.txt", content: "Contrat d'électricité verte Ekwateur, offre 100 % renouvelable. Souscrit le 2 février 2026. Prix du kWh : 0,21 euros."),
    DemoCase(filename: "facture-photographe-mariage.txt", content: "Facture du photographe Studio Lumière — prestation mariage du 6 juin 2026. Montant : 1 800 euros, acompte de 600 euros déjà versé."),
    DemoCase(filename: "attestation-donation.txt", content: "Attestation de donation manuelle, enregistrée le 3 mai 2026 auprès du service des impôts de Lyon. Montant : 5 000 euros."),
]
