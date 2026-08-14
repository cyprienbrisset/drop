// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Drop",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "DropCore", targets: ["DropCore"]),
        .library(name: "DropVault", targets: ["DropVault"]),
        .library(name: "DropIndex", targets: ["DropIndex"]),
        .library(name: "DropExtraction", targets: ["DropExtraction"]),
        .library(name: "DropEntities", targets: ["DropEntities"]),
        .library(name: "DropIntelligence", targets: ["DropIntelligence"]),
        .library(name: "DropEmbeddings", targets: ["DropEmbeddings"]),
        .library(name: "DropSearch", targets: ["DropSearch"]),
        .library(name: "DropJobs", targets: ["DropJobs"]),
        .library(name: "DropLicense", targets: ["DropLicense"]),
        .library(name: "DropFeatures", targets: ["DropFeatures"]),
        .executable(name: "DropApp", targets: ["DropApp"]),
        .executable(name: "ValidationHarness", targets: ["ValidationHarness"]),
    ],
    dependencies: [
        // Dépendance tierce autorisée (§4.1). SQLCipher sera substitué au SQLite système en
        // Phase 8 (DRO-51) sans changement de DAO — GRDB reste la seule couche SQL du projet.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        // Socle : aucune dépendance. Types, erreurs, journalisation, horloge injectable, FS abstrait.
        .target(name: "DropCore", swiftSettings: [.swiftLanguageMode(.v6)]),

        // Modules métier, dépendance unique sur DropCore. Strictement pairs entre eux (§4.2 règle 1).
        .target(name: "DropVault", dependencies: ["DropCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "DropIndex",
            dependencies: ["DropCore", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(name: "DropExtraction", dependencies: ["DropCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "DropEntities", dependencies: ["DropCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "DropIntelligence", dependencies: ["DropCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "DropEmbeddings",
            dependencies: ["DropCore", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(name: "DropSearch", dependencies: ["DropCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "DropJobs", dependencies: ["DropCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "DropLicense", dependencies: ["DropCore"], swiftSettings: [.swiftLanguageMode(.v6)]),

        // Cas d'usage : seul endroit où les modules métier sont orchestrés ensemble (§4.2 règle 1).
        .target(
            name: "DropFeatures",
            dependencies: [
                "DropCore", "DropVault", "DropIndex", "DropExtraction", "DropEntities",
                "DropIntelligence", "DropEmbeddings", "DropSearch", "DropJobs", "DropLicense",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // Application : menu bar, Drop Zone, Search, Préférences.
        .executableTarget(name: "DropApp", dependencies: ["DropFeatures"], swiftSettings: [.swiftLanguageMode(.v6)]),

        // Protocole de mesure pour les validations bloquantes de Phase 0 (DRO-16, DRO-17).
        // Exécutable séparé : ne fait pas partie du produit, jamais embarqué dans DropApp.
        .executableTarget(name: "ValidationHarness", dependencies: ["DropCore"], swiftSettings: [.swiftLanguageMode(.v6)]),

        // Tests — cibles prioritaires de couverture (§8.1) : DropCore, DropSearch, DropLicense.
        .testTarget(name: "DropCoreTests", dependencies: ["DropCore"]),
        .testTarget(name: "DropVaultTests", dependencies: ["DropVault"]),
        .testTarget(name: "DropIndexTests", dependencies: ["DropIndex"]),
        .testTarget(name: "DropEmbeddingsTests", dependencies: ["DropEmbeddings"]),
        .testTarget(name: "DropSearchTests", dependencies: ["DropSearch"]),
        .testTarget(name: "DropLicenseTests", dependencies: ["DropLicense"]),
        .testTarget(
            name: "DropFeaturesTests",
            dependencies: ["DropFeatures", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ]
)
