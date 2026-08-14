// swift-tools-version:6.1
// Fork local de GRDB.swift (upstream: https://github.com/groue/GRDB.swift), vendorisé pour
// activer le commutateur SQLCipher documenté par le projet (voir les commentaires
// « GRDB+SQLCipher » dans le Package.swift amont) — SPM ne permet pas de basculer ce commutateur
// depuis un dépendant distant, il faut un fork (DRO-51, ADR-05). Toute mise à jour de GRDB doit
// être réappliquée manuellement sur cette copie : ce n'est plus une dépendance auto-mise à jour.
//
// Modifications par rapport à l'amont : commutateur SQLCipher activé (dépendance SQLCipher.swift,
// défines SQLITE_HAS_CODEC/SQLCipher), cible GRDBSQLite remplacée par GRDBSQLCipher, suites de
// tests et ressources annexes (SQLiteCustom, Documentation, projets Xcode) retirées — inutiles à
// un usage en dépendance SPM.

import Foundation
import PackageDescription

let package = Package(
    name: "GRDB",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v7),
    ],
    products: [
        .library(name: "GRDB", targets: ["GRDB"]),
        .library(name: "GRDB-dynamic", type: .dynamic, targets: ["GRDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sqlcipher/SQLCipher.swift.git", from: "4.17.0"),
    ],
    targets: [
        .target(
            name: "GRDBSQLCipher",
            dependencies: [.product(name: "SQLCipher", package: "SQLCipher.swift")]
        ),
        .target(
            name: "GRDB",
            dependencies: [
                .product(name: "SQLCipher", package: "SQLCipher.swift"),
                .target(name: "GRDBSQLCipher"),
            ],
            path: "GRDB",
            resources: [.copy("PrivacyInfo.xcprivacy")],
            cSettings: [
                .define("SQLITE_HAS_CODEC"),
            ],
            swiftSettings: [
                .define("SQLITE_ENABLE_FTS5"),
                .define("SQLITE_ENABLE_SNAPSHOT"),
                .define("SQLITE_HAS_CODEC"),
                .define("SQLCipher"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
