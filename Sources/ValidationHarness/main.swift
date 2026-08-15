import Foundation

/// Point d'entrée du protocole de mesure des deux validations bloquantes de la Phase 0 (§9, DRO-16/17).
/// Cet exécutable n'est PAS livré dans Drop — il sert uniquement à produire les rapports qui
/// permettent de trancher avant d'engager la Phase 1.
///
/// Usage :
///   swift run ValidationHarness a [--minutes N]   Validation A — inférence en arrière-plan
///   swift run ValidationHarness b                 Validation B — qualité des embeddings FR
///   swift run ValidationHarness eval               drop-eval — recall@3 sur le corpus de référence (DRO-15/46)

let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    printUsage()
    exit(1)
}

switch command {
case "a":
    var minutes = 5
    if let index = arguments.firstIndex(of: "--minutes"), index + 1 < arguments.count,
       let parsed = Int(arguments[index + 1]) {
        minutes = parsed
    }
    try await runValidationA(durationMinutes: minutes)

case "b":
    try runValidationB()

case "eval":
    try await runDropEval()

case "demo":
    try await runDropDemo()

case "import":
    guard let path = arguments.dropFirst().first else {
        print("Usage: swift run ValidationHarness import <dossier>")
        exit(1)
    }
    try await runDropImportFolder(path: path)

case "corpus":
    let path = arguments.dropFirst().first
        ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!.appendingPathComponent("Drop-Demo-Corpus").path
    try runGenerateCorpus(outputPath: path)

case "inspect":
    try await runDropInspect()

default:
    printUsage()
    exit(1)
}

func printUsage() {
    print("""
    Usage:
      swift run ValidationHarness a [--minutes N]   Validation A — inférence en arrière-plan
      swift run ValidationHarness b                 Validation B — qualité des embeddings FR
      swift run ValidationHarness eval               drop-eval — recall@3 sur le corpus de référence (DRO-15/46)
      swift run ValidationHarness demo               drop-demo — peuple le vrai coffre par défaut avec un corpus de démonstration
      swift run ValidationHarness import <dossier>   drop-import — ingère et analyse tous les fichiers d'un dossier dans le vrai coffre
      swift run ValidationHarness corpus [dossier]   drop-corpus — génère ~100 PDF/XLSX/DOCX prêts à déposer soi-même (défaut : ~/Desktop/Drop-Demo-Corpus)
    """)
}
