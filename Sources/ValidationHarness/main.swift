import Foundation

/// Point d'entrée du protocole de mesure des deux validations bloquantes de la Phase 0 (§9, DRO-16/17).
/// Cet exécutable n'est PAS livré dans Drop — il sert uniquement à produire les rapports qui
/// permettent de trancher avant d'engager la Phase 1.
///
/// Usage :
///   swift run ValidationHarness a [--minutes N]   Validation A — inférence en arrière-plan
///   swift run ValidationHarness b                 Validation B — qualité des embeddings FR

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

default:
    printUsage()
    exit(1)
}

func printUsage() {
    print("""
    Usage:
      swift run ValidationHarness a [--minutes N]   Validation A — inférence en arrière-plan
      swift run ValidationHarness b                 Validation B — qualité des embeddings FR
    """)
}
