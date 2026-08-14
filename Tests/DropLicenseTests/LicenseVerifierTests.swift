import CryptoKit
import DropLicense
import Foundation
import Testing

private func makePayload(sku: String = "drop-pro-v1") -> LicensePayload {
    LicensePayload(v: 1, sku: sku, orderID: "order-123", issuedAt: "2026-01-01T00:00:00Z", buyerHash: "abc123", seats: 1)
}

@Test func verifyAcceptsAnEnvelopeSignedByTheMatchingPrivateKey() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let envelope = try LicenseVerifier.makeEnvelope(payload: makePayload(), privateKey: privateKey)
    let data = try JSONEncoder().encode(envelope)

    let payload = try LicenseVerifier.verify(envelopeData: data, publicKey: privateKey.publicKey)

    #expect(payload.sku == "drop-pro-v1")
    #expect(payload.orderID == "order-123")
}

@Test func verifyRejectsAnEnvelopeSignedByADifferentPrivateKey() throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let embeddedKey = Curve25519.Signing.PrivateKey() // clé différente, comme une falsification.
    let envelope = try LicenseVerifier.makeEnvelope(payload: makePayload(), privateKey: signingKey)
    let data = try JSONEncoder().encode(envelope)

    #expect(throws: LicenseVerificationError.invalidSignature) {
        try LicenseVerifier.verify(envelopeData: data, publicKey: embeddedKey.publicKey)
    }
}

@Test func verifyRejectsATamperedPayloadEvenWithAValidSignatureFormat() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let envelope = try LicenseVerifier.makeEnvelope(payload: makePayload(), privateKey: privateKey)

    // On altère le payload après signature (ex. changer le SKU en "pro") sans re-signer.
    guard var payloadBytes = Base64URL.decode(envelope.payload), var payloadText = String(data: payloadBytes, encoding: .utf8) else {
        Issue.record("payload should decode as UTF-8 JSON")
        return
    }
    payloadText = payloadText.replacingOccurrences(of: "drop-pro-v1", with: "drop-pro-v2")
    payloadBytes = Data(payloadText.utf8)
    let tampered = LicenseEnvelope(payload: Base64URL.encode(payloadBytes), signature: envelope.signature)
    let data = try JSONEncoder().encode(tampered)

    #expect(throws: LicenseVerificationError.invalidSignature) {
        try LicenseVerifier.verify(envelopeData: data, publicKey: privateKey.publicKey)
    }
}

@Test func verifyRejectsMalformedJSON() {
    let data = Data("not json".utf8)
    let privateKey = Curve25519.Signing.PrivateKey()

    #expect(throws: LicenseVerificationError.malformedEnvelope) {
        try LicenseVerifier.verify(envelopeData: data, publicKey: privateKey.publicKey)
    }
}

@Test func base64URLRoundTripsArbitraryBytes() {
    let bytes = Data((0..<64).map { UInt8($0 * 3 % 256) })
    let encoded = Base64URL.encode(bytes)
    #expect(!encoded.contains("+"))
    #expect(!encoded.contains("/"))
    #expect(!encoded.contains("="))
    #expect(Base64URL.decode(encoded) == bytes)
}
