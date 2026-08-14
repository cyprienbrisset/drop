/// Erreur produit avec un code stable, affichable à l'utilisateur et consultable dans les journaux.
/// Les codes concrets (ex. `DROP-ING-004`) sont définis par chaque module métier.
public struct DropError: Error, Sendable, CustomStringConvertible {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { "[\(code)] \(message)" }
}
