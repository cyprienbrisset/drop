import DropIndex
import Foundation
import GRDB
import Testing

private func makePath() -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent("drop-encryption-test-\(UUID().uuidString).sqlite").path
}

/// Preuve réelle du chiffrement SQLCipher (§4.4, ADR-05, DRO-51) : un fichier créé avec une
/// passphrase n'est lisible par personne d'autre que quelqu'un connaissant cette passphrase — pas
/// seulement « la classe compile », mais un comportement observé sur un vrai fichier sur disque.
@Test func aDatabaseCreatedWithAPassphraseIsUnreadableWithoutIt() throws {
    let path = makePath()
    let passphrase = Data("correct horse battery staple".utf8)

    let writer = try DropIndexDatabase(path: path, passphrase: passphrase)
    try writer.pool.write { db in
        try db.execute(sql: "INSERT INTO settings (key, value) VALUES ('secret', 'valeur-confidentielle')")
    }

    // Ouverture sans passphrase : le schéma n'est pas lisible (fichier chiffré dès la première
    // page) — GRDB valide le schéma dès l'ouverture du pool, l'échec survient donc à la
    // construction elle-même, pas seulement à la première lecture explicite.
    var config = Configuration()
    #expect(throws: (any Error).self) {
        let wrongKeyPool = try DatabasePool(path: path, configuration: config)
        try wrongKeyPool.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM settings")
        }
    }

    // Ouverture avec la bonne passphrase : lisible normalement.
    config.prepareDatabase { db in try db.usePassphrase(passphrase) }
    let rightKeyPool = try DatabasePool(path: path, configuration: config)
    let value: String? = try rightKeyPool.read { db in
        try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'secret'")
    }
    #expect(value == "valeur-confidentielle")
}

@Test func aDatabaseCreatedWithoutAPassphraseStaysAnOrdinaryReadableSQLiteFile() throws {
    let path = makePath()
    let database = try DropIndexDatabase(path: path)
    try database.pool.write { db in
        try db.execute(sql: "INSERT INTO settings (key, value) VALUES ('k', 'v')")
    }

    // §4.3 : `vectors.db` reste volontairement non chiffré — une base sans passphrase doit rester
    // un fichier SQLite ordinaire, lisible sans aucune clé.
    let plainPool = try DatabasePool(path: path)
    let value: String? = try plainPool.read { db in
        try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'k'")
    }
    #expect(value == "v")
}

@Test func migratingTwiceWithTheSamePassphraseSucceeds() throws {
    let path = makePath()
    let passphrase = Data("un mot de passe robuste".utf8)

    _ = try DropIndexDatabase(path: path, passphrase: passphrase)
    // Réouverture (ex. redémarrage de l'app) : la migration ne doit pas re-échouer sur un schéma
    // déjà en place, et la passphrase doit continuer à fonctionner.
    let reopened = try DropIndexDatabase(path: path, passphrase: passphrase)
    let tableNames: Set<String> = try reopened.pool.read { db in
        try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
    }
    #expect(tableNames.contains("documents"))
}
