import DropExtraction
import Foundation
import Testing

/// Construit une vraie archive ZIP (via `/usr/bin/zip`, comme l'extracteur utilise
/// `/usr/bin/unzip` en miroir) à partir d'un ensemble de fichiers relatifs — un vrai `.xlsx`/
/// `.pptx` minimal mais structurellement correct, pas un fichier de test factice.
private func makeArchive(named name: String, files: [String: String]) throws -> URL {
    let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

    for (relativePath, content) in files {
        let fileURL = workDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: archiveURL)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = workDir
    process.arguments = ["-r", archiveURL.path, "."]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()

    return archiveURL
}

@Test func extractsSharedStringsAndInlineStringsFromAnXlsxWorkbook() throws {
    let sharedStrings = """
    <?xml version="1.0" encoding="UTF-8"?>
    <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="2" uniqueCount="2">
      <si><t>Facture EDF</t></si>
      <si><t>Montant total</t></si>
    </sst>
    """
    let sheet1 = """
    <?xml version="1.0" encoding="UTF-8"?>
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <sheetData>
        <row r="1"><c r="A1" t="inlineStr"><is><t>Référence client 123456</t></is></c></row>
      </sheetData>
    </worksheet>
    """
    let archive = try makeArchive(named: "\(UUID().uuidString).xlsx", files: [
        "xl/sharedStrings.xml": sharedStrings,
        "xl/worksheets/sheet1.xml": sheet1,
    ])

    let extracted = try OOXMLTextExtractor().extract(fileAt: archive, kind: .xlsx)
    let fullText = extracted.pages.map(\.content).joined(separator: "\n")

    #expect(fullText.contains("Facture EDF"))
    #expect(fullText.contains("Montant total"))
    #expect(fullText.contains("Référence client 123456"))
}

@Test func extractsTextRunsFromEachSlideOfAPptxPresentationInOrder() throws {
    let slide1 = """
    <?xml version="1.0" encoding="UTF-8"?>
    <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
      <p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>Bienvenue chez Drop</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld>
    </p:sld>
    """
    let slide2 = """
    <?xml version="1.0" encoding="UTF-8"?>
    <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
      <p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>Deuxième diapositive</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld>
    </p:sld>
    """
    let archive = try makeArchive(named: "\(UUID().uuidString).pptx", files: [
        "ppt/slides/slide1.xml": slide1,
        "ppt/slides/slide2.xml": slide2,
    ])

    let extracted = try OOXMLTextExtractor().extract(fileAt: archive, kind: .pptx)

    #expect(extracted.pages.count == 2)
    #expect(extracted.pages[0].content.contains("Bienvenue chez Drop"))
    #expect(extracted.pages[1].content.contains("Deuxième diapositive"))
}

@Test func extractingAnArchiveWithoutTheExpectedEntriesThrowsUnreadable() throws {
    let archive = try makeArchive(named: "\(UUID().uuidString).xlsx", files: ["[Content_Types].xml": "<Types/>"])

    #expect(throws: ExtractionError.unreadable) {
        _ = try OOXMLTextExtractor().extract(fileAt: archive, kind: .xlsx)
    }
}

@Test func documentTextExtractorRoutesXlsxAndPptxToTheOOXMLExtractor() throws {
    let sheet1 = """
    <?xml version="1.0" encoding="UTF-8"?>
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Devis maison</t></is></c></row></sheetData>
    </worksheet>
    """
    let archive = try makeArchive(named: "\(UUID().uuidString).xlsx", files: ["xl/worksheets/sheet1.xml": sheet1])

    let extracted = try DocumentTextExtractor().extract(fileAt: archive)
    #expect(extracted.pages.contains { $0.content.contains("Devis maison") })
}
