import Foundation

/// Abstraction de tout accès au système de fichiers, pour permettre l'injection de pannes en test (§8.4 du CDC).
/// Aucun module ne doit appeler `FileManager` directement — tout passe par ce protocole.
public protocol FileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func fileSize(at url: URL) throws -> Int64
    func modificationDate(at url: URL) throws -> Date
    func createDirectory(at url: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
    func read(at url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func syncFile(at url: URL) throws
    func syncDirectory(at url: URL) throws
}

/// Implémentation réelle, adossée à `FileManager`. Utilisée en production uniquement.
public struct LiveFileSystem: FileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? Int64) ?? 0
    }

    public func modificationDate(at url: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.modificationDate] as? Date) ?? .distantPast
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func read(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func syncFile(at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    public func syncDirectory(at url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }
}
