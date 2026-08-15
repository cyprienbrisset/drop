import AppKit
import Foundation

/// Génère un corpus de démonstration prêt à déposer soi-même dans l'app (PDF, XLSX, DOCX) —
/// contrairement à `drop-demo`/`drop-import`, ce mode n'ingère rien : il produit uniquement des
/// fichiers réels sur disque, dans un dossier destiné à un glisser-déposer manuel pendant une
/// démo. Contenu générique, jamais un document utilisateur réel.
func runGenerateCorpus(outputPath: String) throws {
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    print("=== drop-corpus — génération dans \(outputURL.path) ===\n")

    var pdfCount = 0
    var xlsxCount = 0
    var docxCount = 0
    var copiedCount = 0

    // Les vrais PDF déjà téléchargés depuis des sources publiques (relevés bancaires, bulletins
    // de paie, contrats de bail, ordonnance, facture) rejoignent le corpus généré s'ils sont
    // présents — jamais recréés ici, cette responsabilité reste à `drop-import`.
    let realCorpusURL = URL(fileURLWithPath: "/tmp/drop-real-corpus")
    if let realFiles = try? FileManager.default.contentsOfDirectory(at: realCorpusURL, includingPropertiesForKeys: nil) {
        for file in realFiles where file.pathExtension.lowercased() == "pdf" {
            let dest = outputURL.appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: file, to: dest)
            copiedCount += 1
            print("• \(file.lastPathComponent) (vrai PDF, téléchargé)")
        }
    }

    for entry in pdfEntries {
        let dest = outputURL.appendingPathComponent(entry.filename)
        try makePDF(pages: entry.pages, at: dest)
        pdfCount += 1
        print("• \(entry.filename)")
    }

    for entry in xlsxEntries {
        let dest = outputURL.appendingPathComponent(entry.filename)
        try makeXLSX(headers: entry.headers, rows: entry.rows, at: dest)
        xlsxCount += 1
        print("• \(entry.filename)")
    }

    for entry in docxEntries {
        let dest = outputURL.appendingPathComponent(entry.filename)
        try makeDOCX(paragraphs: entry.paragraphs, at: dest)
        docxCount += 1
        print("• \(entry.filename)")
    }

    let total = pdfCount + xlsxCount + docxCount + copiedCount
    print("\n=== Rapport drop-corpus ===")
    print("PDF générés : \(pdfCount) (+ \(copiedCount) PDF réels copiés)")
    print("XLSX générés : \(xlsxCount)")
    print("DOCX générés : \(docxCount)")
    print("Total : \(total) fichiers dans \(outputURL.path)")
}

// MARK: - Génération PDF (CoreGraphics, comme les tests DropExtraction)

private func makePDF(pages: [String], at url: URL) throws {
    let pdfData = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
    guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else { throw CorpusError.generationFailed(url.lastPathComponent) }

    for pageText in pages {
        context.beginPDFPage(nil)
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        let attributed = NSAttributedString(string: pageText, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        attributed.draw(in: CGRect(x: 44, y: 44, width: 507, height: 754))
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
    }
    context.closePDF()
    try (pdfData as Data).write(to: url)
}

// MARK: - Génération XLSX (paquet OOXML minimal, réellement ouvrable dans Excel/Numbers)

private func makeXLSX(headers: [String], rows: [[String]], at url: URL) throws {
    let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workDir) }

    try write(xlsxContentTypesXML, to: workDir.appendingPathComponent("[Content_Types].xml"))
    try write(rootRelsXML, to: workDir.appendingPathComponent("_rels/.rels"))
    try write(workbookXML, to: workDir.appendingPathComponent("xl/workbook.xml"))
    try write(workbookRelsXML, to: workDir.appendingPathComponent("xl/_rels/workbook.xml.rels"))
    try write(sheetXML(headers: headers, rows: rows), to: workDir.appendingPathComponent("xl/worksheets/sheet1.xml"))

    try zipDirectory(workDir, to: url)
}

private func sheetXML(headers: [String], rows: [[String]]) -> String {
    let columnLetters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    var xmlRows = ""

    func rowXML(_ values: [String], rowNumber: Int) -> String {
        let cells = values.enumerated().map { index, value in
            cellXML(column: columnLetters[index], row: rowNumber, value: value)
        }.joined()
        return "<row r=\"\(rowNumber)\">\(cells)</row>"
    }

    xmlRows += rowXML(headers, rowNumber: 1)
    for (index, row) in rows.enumerated() {
        xmlRows += rowXML(row, rowNumber: index + 2)
    }

    return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(xmlRows)</sheetData></worksheet>
    """
}

private func cellXML(column: String, row: Int, value: String) -> String {
    let numeric = Double(value.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: ""))
    if let numeric {
        return "<c r=\"\(column)\(row)\"><v>\(numeric)</v></c>"
    }
    return "<c r=\"\(column)\(row)\" t=\"inlineStr\"><is><t>\(escapeXML(value))</t></is></c>"
}

private let xlsxContentTypesXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>
"""

private let rootRelsXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
"""

private let workbookXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Feuille1" sheetId="1" r:id="rId1"/></sheets>
</workbook>
"""

private let workbookRelsXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>
"""

// MARK: - Génération DOCX (paquet OOXML minimal, réellement ouvrable dans Word/Pages)

private func makeDOCX(paragraphs: [String], at url: URL) throws {
    let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workDir) }

    try write(docxContentTypesXML, to: workDir.appendingPathComponent("[Content_Types].xml"))
    try write(rootRelsXML.replacingOccurrences(of: "xl/workbook.xml", with: "word/document.xml"), to: workDir.appendingPathComponent("_rels/.rels"))
    try write(documentXML(paragraphs: paragraphs), to: workDir.appendingPathComponent("word/document.xml"))

    try zipDirectory(workDir, to: url)
}

private func documentXML(paragraphs: [String]) -> String {
    let body = paragraphs.map { "<w:p><w:r><w:t xml:space=\"preserve\">\(escapeXML($0))</w:t></w:r></w:p>" }.joined()
    return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)</w:body></w:document>
    """
}

private let docxContentTypesXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
"""

// MARK: - Utilitaires communs

private enum CorpusError: Error {
    case generationFailed(String)
}

private func write(_ content: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try content.write(to: url, atomically: true, encoding: .utf8)
}

private func escapeXML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

/// Même technique que `OOXMLTextExtractorTests` : `/usr/bin/zip`, jamais un shell, jamais
/// d'arguments interpolés dans une chaîne de commande.
private func zipDirectory(_ directory: URL, to destination: URL) throws {
    try? FileManager.default.removeItem(at: destination)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = directory
    process.arguments = ["-r", "-q", destination.path, "."]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CorpusError.generationFailed(destination.lastPathComponent)
    }
}

// MARK: - Contenu du corpus

private struct PDFEntry {
    let filename: String
    let pages: [String]
}

private struct XLSXEntry {
    let filename: String
    let headers: [String]
    let rows: [[String]]
}

private struct DOCXEntry {
    let filename: String
    let paragraphs: [String]
}

private let months = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]

/// ~50 PDF : 20 documents distincts + 30 générés par récurrence mensuelle (factures, relevés,
/// bulletins de paie) — le genre de volume réel qu'un utilisateur accumule sur un an.
private let pdfEntries: [PDFEntry] = {
    var entries: [PDFEntry] = [
        PDFEntry(filename: "contrat-assurance-habitation.pdf", pages: ["Contrat d'assurance habitation MAIF, numéro de police 778213AH.\nSouscrit le 1er janvier 2026 pour un appartement de 65 m².\nCotisation annuelle : 186 euros."]),
        PDFEntry(filename: "contrat-assurance-auto.pdf", pages: ["Contrat d'assurance automobile Maaf, numéro de police AUTO-55210.\nVéhicule Renault Clio, immatriculation AB-123-CD.\nCotisation annuelle : 420 euros."]),
        PDFEntry(filename: "contrat-mutuelle-sante.pdf", pages: ["Contrat de mutuelle santé Harmonie Mutuelle, formule Confort.\nAdhérent numéro 55219087.\nCotisation mensuelle : 68 euros, prélevée le 3 de chaque mois."]),
        PDFEntry(filename: "contrat-travail-cdi.pdf", pages: ["Contrat de travail à durée indéterminée entre la société Kalixo SAS et Jean Dupont.\nPoste d'ingénieur logiciel, signé le 15 mars 2022.\nRémunération annuelle brute : 48 000 euros."]),
        PDFEntry(filename: "contrat-bail-appartement.pdf", pages: ["Contrat de bail — appartement 12 rue des Lilas, 75000 Paris.\nLoyer mensuel : 780 euros charges comprises.\nDurée : 3 ans à compter du 1er janvier 2025."]),
        PDFEntry(filename: "devis-travaux-cuisine.pdf", pages: ["Devis de rénovation de cuisine — entreprise Bâti Rénov.\nMontant total : 8 450 euros TTC.\nValidité du devis : 30 jours à compter du 5 mai 2026."]),
        PDFEntry(filename: "devis-toiture.pdf", pages: ["Devis de réfection de toiture — entreprise Couverture Plus.\nMontant total : 12 300 euros TTC.\nValidité du devis : 45 jours à compter du 10 mars 2026."]),
        PDFEntry(filename: "attestation-employeur.pdf", pages: ["Attestation employeur — établie par la société Kalixo SAS le 4 mars 2026.\nConfirme que Jean Dupont est salarié en CDI depuis le 1er avril 2022."]),
        PDFEntry(filename: "attestation-securite-sociale.pdf", pages: ["Attestation de droits Sécurité sociale — CPAM de Paris, éditée le 10 janvier 2026.\nNuméro d'assuré 1 85 03 75 108 042.\nDroits ouverts jusqu'au 31 décembre 2026."]),
        PDFEntry(filename: "declaration-impots-2025.pdf", pages: ["Déclaration de revenus 2025, transmise en ligne le 22 mai 2026.\nRevenu fiscal de référence : 34 200 euros.\nImpôt sur le revenu dû : 1 890 euros."]),
        PDFEntry(filename: "carte-grise-vehicule.pdf", pages: ["Certificat d'immatriculation — Renault Clio, immatriculée le 3 juin 2026.\nNuméro d'immatriculation AB-123-CD. Puissance fiscale : 5 CV."]),
        PDFEntry(filename: "pv-controle-technique.pdf", pages: ["Procès-verbal de contrôle technique — Renault Clio, immatriculation AB-123-CD.\nEffectué le 20 mai 2026 chez Dekra. Résultat : favorable sans contre-visite."]),
        PDFEntry(filename: "billet-avion-lisbonne.pdf", pages: ["Confirmation de réservation TAP Air Portugal — vol Paris-Lisbonne.\nDépart le 14 juillet 2026. Référence LX92QK. Montant payé : 320 euros."]),
        PDFEntry(filename: "reservation-hotel-porto.pdf", pages: ["Confirmation de réservation d'hôtel — Porto Riverside, du 15 au 18 juillet 2026.\nNuméro de réservation HTL-77291. Montant total : 240 euros."]),
        PDFEntry(filename: "diplome-master.pdf", pages: ["Diplôme de master en informatique, délivré par l'Université de Lyon le 30 septembre 2020.\nDécerné à Jean Dupont, mention très bien."]),
        PDFEntry(filename: "releve-notes-lycee.pdf", pages: ["Relevé de notes du baccalauréat, série générale, session 2018, académie de Lyon.\nMention : assez bien."]),
        PDFEntry(filename: "pv-assemblee-copropriete.pdf", pages: ["Procès-verbal de l'assemblée générale de copropriété du 18 mars 2026, syndic Foncia.\nRésolution votée : ravalement de façade, budget 45 000 euros."]),
        PDFEntry(filename: "ordonnance-medicale.pdf", pages: ["Ordonnance médicale — Dr Martin Lefèvre, cabinet de médecine générale.\nPrescription du 20 avril 2026 : paracétamol 1g, amoxicilline 500mg pendant 7 jours."]),
        PDFEntry(filename: "facture-veterinaire.pdf", pages: ["Facture du cabinet vétérinaire Les Quatre Pattes — consultation et vaccin, 8 avril 2026.\nAnimal : chat, Minou. Montant : 65 euros."]),
        PDFEntry(filename: "contrat-freelance-conseil.pdf", pages: ["Contrat de prestation de conseil entre Kalixo SAS et Julie Martin, consultante indépendante.\nMission de 20 jours, taux journalier : 550 euros. Signé le 2 février 2026."]),
    ]

    for (index, month) in months.enumerated() {
        entries.append(PDFEntry(
            filename: "facture-edf-\(month).pdf",
            pages: ["Facture d'électricité EDF — \(month) 2026.\nRéférence client 4471928.\nMontant à régler : \(70 + index * 3),\(20 + index) euros TTC."]
        ))
    }
    for (index, month) in months.enumerated() {
        entries.append(PDFEntry(
            filename: "releve-bancaire-\(month).pdf",
            pages: ["Relevé de compte Banque Populaire — \(month) 2026.\nSolde précédent : \(1200 + index * 80),00 euros.\nSolde final : \(1250 + index * 90),00 euros."]
        ))
    }
    for (index, month) in months.prefix(10).enumerated() {
        entries.append(PDFEntry(
            filename: "bulletin-paie-\(month).pdf",
            pages: ["Bulletin de paie — Kalixo SAS, \(month) 2026.\nSalaire net versé : \(2800 + index * 10) euros, viré le 28 \(month) 2026."]
        ))
    }
    return entries
}()

/// ~25 XLSX : suivis budgétaires et tableurs administratifs, réellement ouvrables dans Excel/Numbers.
private let xlsxEntries: [XLSXEntry] = {
    var entries: [XLSXEntry] = [
        XLSXEntry(filename: "comparatif-devis-travaux.xlsx", headers: ["Entreprise", "Montant TTC", "Délai (semaines)"], rows: [
            ["Bâti Rénov", "8450", "4"], ["ProConstruct", "9200", "3"], ["Artisans Réunis", "7800", "6"],
        ]),
        XLSXEntry(filename: "inventaire-materiel-bureau.xlsx", headers: ["Article", "Quantité", "Valeur unitaire"], rows: [
            ["Ordinateur portable", "3", "1200"], ["Écran 27 pouces", "3", "280"], ["Chaise ergonomique", "5", "220"],
        ]),
        XLSXEntry(filename: "planning-vacances-ete.xlsx", headers: ["Date", "Activité", "Lieu"], rows: [
            ["14/07/2026", "Vol aller", "Lisbonne"], ["15/07/2026", "Arrivée hôtel", "Porto"], ["18/07/2026", "Vol retour", "Paris"],
        ]),
        XLSXEntry(filename: "comparatif-fournisseurs-energie.xlsx", headers: ["Fournisseur", "Prix kWh", "Abonnement annuel"], rows: [
            ["EDF", "0.2062", "120"], ["Engie", "0.1980", "115"], ["Ekwateur", "0.2100", "110"],
        ]),
        XLSXEntry(filename: "suivi-heures-freelance.xlsx", headers: ["Date", "Client", "Heures", "Taux"], rows: [
            ["03/02/2026", "Kalixo SAS", "8", "68.75"], ["04/02/2026", "Kalixo SAS", "7", "68.75"], ["10/02/2026", "Autre Client", "5", "60"],
        ]),
        XLSXEntry(filename: "budget-mariage.xlsx", headers: ["Poste", "Budget", "Réel"], rows: [
            ["Traiteur", "4500", "4650"], ["Photographe", "1800", "1800"], ["Lieu", "3200", "3200"], ["Fleurs", "600", "540"],
        ]),
        XLSXEntry(filename: "releve-notes-semestre.xlsx", headers: ["Matière", "Note", "Coefficient"], rows: [
            ["Algorithmique", "16", "3"], ["Bases de données", "14", "2"], ["Anglais", "17", "1"],
        ]),
        XLSXEntry(filename: "suivi-candidatures-emploi.xlsx", headers: ["Entreprise", "Poste", "Statut"], rows: [
            ["Kalixo SAS", "Ingénieur logiciel", "Accepté"], ["DataCorp", "Développeur backend", "En attente"], ["Nova Tech", "Lead dev", "Refusé"],
        ]),
        XLSXEntry(filename: "inventaire-cave-a-vin.xlsx", headers: ["Nom", "Millésime", "Quantité"], rows: [
            ["Bordeaux Supérieur", "2019", "6"], ["Côtes du Rhône", "2021", "4"], ["Chablis", "2022", "3"],
        ]),
        XLSXEntry(filename: "suivi-abonnements.xlsx", headers: ["Service", "Montant mensuel", "Renouvellement"], rows: [
            ["Netflix", "13.49", "10 du mois"], ["Free mobile", "19.99", "5 du mois"], ["Basic Fit", "29.99", "12 du mois"],
        ]),
    ]

    for (index, month) in months.enumerated() {
        entries.append(XLSXEntry(
            filename: "budget-mensuel-\(month).xlsx",
            headers: ["Catégorie", "Budget", "Dépensé"],
            rows: [
                ["Logement", "900", "900"],
                ["Alimentation", "400", "\(370 + index * 2)"],
                ["Transport", "150", "\(110 + index)"],
                ["Loisirs", "100", "\(80 + index * 3)"],
                ["Épargne", "300", "300"],
            ]
        ))
    }
    return entries
}()

/// ~25 DOCX : courriers, comptes-rendus et documents administratifs courants, réellement
/// ouvrables dans Word/Pages.
private let docxEntries: [DOCXEntry] = {
    var entries: [DOCXEntry] = [
        DOCXEntry(filename: "lettre-motivation-poste-ingenieur.docx", paragraphs: [
            "Madame, Monsieur,",
            "Je vous adresse ma candidature pour le poste d'ingénieur logiciel au sein de votre société.",
            "Fort de cinq années d'expérience en développement backend, je serais ravi de mettre mes compétences à votre service.",
            "Je reste à votre disposition pour un entretien.",
            "Cordialement, Jean Dupont",
        ]),
        DOCXEntry(filename: "cv-jean-dupont.docx", paragraphs: [
            "Jean Dupont — Ingénieur logiciel",
            "Expérience : Kalixo SAS, ingénieur logiciel, depuis avril 2022.",
            "Formation : Master informatique, Université de Lyon, 2020.",
            "Compétences : Swift, Python, bases de données, architecture logicielle.",
        ]),
        DOCXEntry(filename: "compte-rendu-reunion-mars.docx", paragraphs: [
            "Compte-rendu de réunion — 12 mars 2026",
            "Participants : Jean Dupont, Julie Martin, Paul Bernard.",
            "Sujets abordés : avancement du projet, budget du trimestre, prochaines échéances.",
            "Décision : validation du budget de 45 000 euros pour le ravalement de façade.",
        ]),
        DOCXEntry(filename: "contrat-prestation-freelance.docx", paragraphs: [
            "Contrat de prestation de services",
            "Entre Kalixo SAS et Julie Martin, consultante indépendante.",
            "Mission : conseil en architecture logicielle, 20 jours, taux journalier 550 euros.",
            "Signé le 2 février 2026.",
        ]),
        DOCXEntry(filename: "rapport-stage-ete.docx", paragraphs: [
            "Rapport de stage — été 2026",
            "Stage effectué chez Kalixo SAS du 1er juin au 31 août 2026.",
            "Missions : développement d'un module de recherche, tests unitaires, documentation.",
            "Conclusion : stage très formateur, proposition de CDI à l'issue.",
        ]),
        DOCXEntry(filename: "lettre-resiliation-abonnement.docx", paragraphs: [
            "Madame, Monsieur,",
            "Je vous informe de ma volonté de résilier mon abonnement à compter du 1er avril 2026.",
            "Merci de m'confirmer la bonne prise en compte de cette demande.",
            "Cordialement, Jean Dupont",
        ]),
        DOCXEntry(filename: "compte-rendu-entretien-annuel.docx", paragraphs: [
            "Compte-rendu d'entretien annuel — Jean Dupont, 15 janvier 2026",
            "Objectifs atteints : livraison du module de recherche, mentorat de deux stagiaires.",
            "Axes de progression : gestion de projet, prise de parole en public.",
            "Décision : augmentation de 4 % à compter du 1er mars 2026.",
        ]),
        DOCXEntry(filename: "note-de-frais-deplacement.docx", paragraphs: [
            "Note de frais — déplacement professionnel, 20 février 2026",
            "Trajet : Paris - Lyon, train, 89 euros.",
            "Hébergement : une nuit, 110 euros.",
            "Repas : 35 euros. Total : 234 euros.",
        ]),
        DOCXEntry(filename: "reglement-interieur-association.docx", paragraphs: [
            "Règlement intérieur de l'association Les Amis du Quartier",
            "Article 1 : l'association a pour objet l'animation locale.",
            "Article 2 : les cotisations sont fixées annuellement par le bureau.",
            "Article 3 : l'assemblée générale se réunit une fois par an.",
        ]),
        DOCXEntry(filename: "proces-verbal-conseil-syndical.docx", paragraphs: [
            "Procès-verbal du conseil syndical — 5 avril 2026",
            "Présents : syndic Foncia, trois copropriétaires.",
            "Ordre du jour : suivi des travaux de ravalement, point sur les charges.",
            "Prochaine réunion : 5 juillet 2026.",
        ]),
        DOCXEntry(filename: "lettre-preavis-demenagement.docx", paragraphs: [
            "Madame, Monsieur,",
            "Je vous informe de mon intention de quitter le logement situé 12 rue des Lilas.",
            "Conformément au bail, je respecte un préavis de trois mois à compter de ce jour.",
            "Cordialement, Jean Dupont",
        ]),
        DOCXEntry(filename: "attestation-sur-honneur-domicile.docx", paragraphs: [
            "Attestation sur l'honneur",
            "Je soussigné Jean Dupont, né le 4 mars 1990, atteste sur l'honneur résider au 12 rue des Lilas, 75000 Paris.",
            "Fait pour valoir ce que de droit.",
        ]),
        DOCXEntry(filename: "lettre-reclamation-service-client.docx", paragraphs: [
            "Madame, Monsieur,",
            "Je vous contacte au sujet d'une facturation erronée constatée sur mon dernier relevé.",
            "Je vous remercie de bien vouloir procéder à une régularisation dans les meilleurs délais.",
            "Cordialement, Jean Dupont",
        ]),
        DOCXEntry(filename: "compte-rendu-visite-medicale.docx", paragraphs: [
            "Compte-rendu de visite médicale — 20 avril 2026",
            "Motif : consultation de suivi.",
            "Prescription : paracétamol 1g, amoxicilline 500mg pendant 7 jours.",
            "Prochain rendez-vous : dans un mois.",
        ]),
        DOCXEntry(filename: "guide-accueil-nouvel-employe.docx", paragraphs: [
            "Guide d'accueil — Kalixo SAS",
            "Bienvenue dans l'équipe. Ce document résume les informations essentielles pour votre première semaine.",
            "Horaires, accès aux locaux, contacts utiles et outils internes sont détaillés ci-dessous.",
        ]),
    ]

    for month in months.prefix(10) {
        entries.append(DOCXEntry(
            filename: "compte-rendu-mensuel-\(month).docx",
            paragraphs: [
                "Compte-rendu mensuel — \(month) 2026",
                "Avancement du projet et points bloquants du mois.",
                "Budget suivi, prochaines échéances rappelées à l'équipe.",
            ]
        ))
    }
    return entries
}()
