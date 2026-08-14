import Foundation

/// Format OOXML moderne à extraire — hors périmètre V1 (§5 : « extraction du contenu xlsx/pptx »
/// explicitement exclue), ajouté en V2.
public enum OOXMLKind: Sendable {
    case xlsx
    case pptx
}

/// Extraction de texte pour `.xlsx`/`.pptx` (Phase 9, V2). Ce sont des archives ZIP contenant du
/// XML ; Foundation n'offre pas de lecteur ZIP, on délègue à `/usr/bin/unzip` (livré avec macOS,
/// pas une dépendance tierce) plutôt que de réimplémenter l'inflation DEFLATE et le format de
/// répertoire central — les arguments passés à `Process` ne traversent jamais un shell, aucun
/// risque d'injection.
///
/// Simplification assumée pour `.xlsx` : les chaînes partagées du classeur (`sharedStrings.xml`)
/// sont regroupées sur une page unique plutôt que résolues cellule par cellule contre chaque
/// feuille — la mise en page exacte n'a pas d'importance pour la recherche plein texte, seule la
/// présence des mots compte.
public struct OOXMLTextExtractor: Sendable {
    public init() {}

    public func extract(fileAt url: URL, kind: OOXMLKind) throws -> ExtractedDocument {
        let entries = try Self.listEntries(in: url)
        guard !entries.isEmpty else { throw ExtractionError.unreadable }

        switch kind {
        case .xlsx: return try extractWorkbook(fileAt: url, entries: entries)
        case .pptx: return try extractPresentation(fileAt: url, entries: entries)
        }
    }

    private func extractWorkbook(fileAt url: URL, entries: [String]) throws -> ExtractedDocument {
        var pages: [PageText] = []

        if entries.contains("xl/sharedStrings.xml"), let data = try? Self.readEntry("xl/sharedStrings.xml", from: url) {
            let text = Self.extractText(fromXML: data, elementNames: ["t"])
            if !text.isEmpty {
                pages.append(PageText(pageNumber: 0, source: .native, content: text))
            }
        }

        let sheetEntries = entries
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted { Self.numericSuffix($0) < Self.numericSuffix($1) }

        for entry in sheetEntries {
            guard let data = try? Self.readEntry(entry, from: url) else { continue }
            // `<is><t>…</t></is>` : chaînes inline (par opposition aux chaînes partagées) —
            // le seul contenu textuel qu'une feuille porte directement.
            let text = Self.extractText(fromXML: data, elementNames: ["t"])
            if !text.isEmpty {
                pages.append(PageText(pageNumber: pages.count, source: .native, content: text))
            }
        }

        guard !pages.isEmpty else { throw ExtractionError.unreadable }
        return ExtractedDocument(pages: pages)
    }

    private func extractPresentation(fileAt url: URL, entries: [String]) throws -> ExtractedDocument {
        let slideEntries = entries
            .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted { Self.numericSuffix($0) < Self.numericSuffix($1) }
        guard !slideEntries.isEmpty else { throw ExtractionError.unreadable }

        var pages: [PageText] = []
        for (index, entry) in slideEntries.enumerated() {
            guard let data = try? Self.readEntry(entry, from: url) else { continue }
            let text = Self.extractText(fromXML: data, elementNames: ["a:t"])
            pages.append(PageText(pageNumber: index, source: .native, content: text))
        }
        return ExtractedDocument(pages: pages)
    }

    // MARK: - Lecture du conteneur ZIP

    private static func listEntries(in url: URL) throws -> [String] {
        let output = try run(arguments: ["-Z1", url.path])
        return output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private static func readEntry(_ entry: String, from url: URL) throws -> Data {
        try runData(arguments: ["-p", url.path, entry])
    }

    private static func run(arguments: [String]) throws -> String {
        let data = try runData(arguments: arguments)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func runData(arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe() // `unzip` écrit des avertissements bénins sur certaines archives.

        do {
            try process.run()
        } catch {
            throw ExtractionError.unreadable
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // 0 = succès, 1 = avertissement non bloquant (ex. commentaire de fin d'archive) — au-delà,
        // l'archive est réellement illisible.
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            throw ExtractionError.unreadable
        }
        return data
    }

    // MARK: - Extraction de texte XML

    private static func extractText(fromXML data: Data, elementNames: Set<String>) -> String {
        let delegate = OOXMLTextCollectingDelegate(elementNames: elementNames)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.collected.joined(separator: " ")
    }

    private static func numericSuffix(_ name: String) -> Int {
        Int(name.filter(\.isNumber)) ?? 0
    }
}

/// `shouldProcessNamespaces` reste `false` (valeur par défaut) : les noms d'éléments arrivent
/// donc préfixés tels qu'écrits dans le XML (`a:t` pour PowerPoint), sans résolution d'espace de
/// noms — exactement ce dont `elementNames` a besoin ci-dessus.
private final class OOXMLTextCollectingDelegate: NSObject, XMLParserDelegate {
    private let elementNames: Set<String>
    private(set) var collected: [String] = []
    private var isInsideTargetElement = false
    private var buffer = ""

    init(elementNames: Set<String>) {
        self.elementNames = elementNames
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String]
    ) {
        guard elementNames.contains(elementName) else { return }
        isInsideTargetElement = true
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideTargetElement else { return }
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementNames.contains(elementName) else { return }
        if !buffer.isEmpty { collected.append(buffer) }
        isInsideTargetElement = false
    }
}
