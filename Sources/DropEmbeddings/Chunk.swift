/// Segment de texte vectorisé (§5.5), ~500 tokens, recouvrement 80. `modelVersion` est non
/// négociable : sans lui, un changement de moteur d'embeddings rend l'index silencieusement
/// incohérent — la panne la plus coûteuse à diagnostiquer du projet (§4.5).
public struct Chunk: Sendable {
    public let documentID: String
    public let pageFrom: Int
    public let pageTo: Int
    public let charFrom: Int
    public let charTo: Int
    public let tokenCount: Int
    public let modelVersion: String

    public init(
        documentID: String, pageFrom: Int, pageTo: Int, charFrom: Int, charTo: Int,
        tokenCount: Int, modelVersion: String
    ) {
        self.documentID = documentID
        self.pageFrom = pageFrom
        self.pageTo = pageTo
        self.charFrom = charFrom
        self.charTo = charTo
        self.tokenCount = tokenCount
        self.modelVersion = modelVersion
    }
}
