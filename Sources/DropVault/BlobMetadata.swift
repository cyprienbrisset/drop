/// `meta.json` d'un blob (§4.3) : la garantie de dernier recours. Même sans base de données,
/// le coffre reste reconstructible et lisible par un humain à partir de ces fichiers seuls.
/// Un seul `meta.json` par blob, écrit une unique fois à la création (jamais réécrit en place —
/// un blob n'est jamais modifié, I4).
public struct BlobMetadata: Codable, Sendable, Equatable {
    public var originalFilename: String
    public var originalPath: String?
    public var mimeType: String?
    public var sizeBytes: Int64
    public var addedAt: String
    public var docType: String?
    public var issuer: String?

    public init(
        originalFilename: String, originalPath: String? = nil, mimeType: String? = nil,
        sizeBytes: Int64, addedAt: String, docType: String? = nil, issuer: String? = nil
    ) {
        self.originalFilename = originalFilename
        self.originalPath = originalPath
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.addedAt = addedAt
        self.docType = docType
        self.issuer = issuer
    }
}
