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
        // Fork local (DRO-51, ADR-05) : le commutateur SQLCipher de GRDB.swift ne peut être activé
        // que depuis le Package.swift de GRDB lui-même, pas depuis un dépendant distant — voir
        // `Vendor/GRDB.swift/Package.swift` pour le détail. GRDB reste la seule couche SQL du projet.
        .package(path: "Vendor/GRDB.swift"),
        // Binaire officiel SQLCipher (checksums vérifiés par SPM), même dépendance que celle
        // utilisée par le fork GRDB — `CSQLiteVec` doit lier exactement le même moteur SQLite que
        // GRDB, jamais une seconde copie (symboles dupliqués au link).
        .package(url: "https://github.com/sqlcipher/SQLCipher.swift.git", from: "4.17.0"),
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
        // Amalgamation vendorisée de `sqlite-vec` (§4.1, dépendance tierce autorisée). `SQLITE_CORE`
        // : compilé pour un lien statique direct contre le moteur SQLite (comme `GRDBSQLCipher`),
        // pas comme extension chargée dynamiquement — les symboles `sqlite3_*` sont résolus au
        // link, sans passer par la table `sqlite3_api_routines`. Depuis DRO-51, ce moteur est
        // SQLCipher (même binaire que celui lié par GRDB, §4.3 — `vectors.db` reste non chiffré,
        // mais doit tourner sur le même moteur que `index.db`, jamais une seconde copie de SQLite).
        .target(
            name: "CSQLiteVec",
            dependencies: [.product(name: "SQLCipher", package: "SQLCipher.swift")],
            cSettings: [.define("SQLITE_CORE"), .define("SQLITE_HAS_CODEC")]
        ),
        .target(
            name: "DropEmbeddings",
            dependencies: ["DropCore", "CSQLiteVec", .product(name: "GRDB", package: "GRDB.swift")],
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
        .executableTarget(name: "DropApp", dependencies: ["DropFeatures", "DropIntelligence", "DropLicense"], swiftSettings: [.swiftLanguageMode(.v6)]),

        // Protocole de mesure pour les validations bloquantes de Phase 0 (DRO-16, DRO-17) et le
        // harnais d'évaluation de la qualité de recherche (drop-eval, DRO-15/46). Exécutable
        // séparé : ne fait partie du produit, jamais embarqué dans DropApp.
        .executableTarget(
            name: "ValidationHarness",
            dependencies: ["DropCore", "DropFeatures", "DropVault", "DropIndex", "DropSearch", "DropEmbeddings"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // Tests — cibles prioritaires de couverture (§8.1) : DropCore, DropSearch, DropLicense.
        .testTarget(name: "DropCoreTests", dependencies: ["DropCore"]),
        .testTarget(name: "DropVaultTests", dependencies: ["DropVault"]),
        .testTarget(
            name: "DropIndexTests",
            dependencies: ["DropIndex", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "DropExtractionTests", dependencies: ["DropExtraction"]),
        .testTarget(name: "DropEntitiesTests", dependencies: ["DropEntities"]),
        .testTarget(name: "DropIntelligenceTests", dependencies: ["DropIntelligence"]),
        .testTarget(name: "DropEmbeddingsTests", dependencies: ["DropEmbeddings"]),
        .testTarget(name: "DropSearchTests", dependencies: ["DropSearch"]),
        .testTarget(name: "DropLicenseTests", dependencies: ["DropLicense"]),
        .testTarget(name: "DropJobsTests", dependencies: ["DropJobs"]),
        .testTarget(
            name: "DropFeaturesTests",
            dependencies: ["DropFeatures", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "DropAppTests", dependencies: ["DropApp"]),
    ]
)
