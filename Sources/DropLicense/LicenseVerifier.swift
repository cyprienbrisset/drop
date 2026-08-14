import CryptoKit
import Foundation

public enum LicenseVerificationError: Error, Sendable, Equatable {
    case malformedEnvelope
    case invalidSignature
    case malformedPayload
}

/// Vérification hors ligne de `license.drop` (§5.11, EF-80/EF-83) : aucun appel réseau, aucune
/// activation, aucun compte — la clé publique est embarquée dans l'application. Une licence
/// absente, illisible ou mal signée n'est jamais fatale : l'appelant retombe systématiquement sur
/// `LicenseState.free` (voir `LicenseGate`), jamais sur un blocage du coffre.
public enum LicenseVerifier {
    public static func verify(envelopeData: Data, publicKey: Curve25519.Signing.PublicKey) throws -> LicensePayload {
        let envelope: LicenseEnvelope
        do {
            envelope = try JSONDecoder().decode(LicenseEnvelope.self, from: envelopeData)
        } catch {
            throw LicenseVerificationError.malformedEnvelope
        }

        guard let payloadBytes = Base64URL.decode(envelope.payload),
              let signatureBytes = Base64URL.decode(envelope.signature)
        else {
            throw LicenseVerificationError.malformedEnvelope
        }

        guard publicKey.isValidSignature(signatureBytes, for: payloadBytes) else {
            throw LicenseVerificationError.invalidSignature
        }

        do {
            return try JSONDecoder().decode(LicensePayload.self, from: payloadBytes)
        } catch {
            throw LicenseVerificationError.malformedPayload
        }
    }

    /// Utilitaire de test/outillage (§5.11) : signe un payload et produit l'enveloppe attendue.
    /// N'a pas vocation à tourner dans l'app — la clé privée n'existe jamais côté client.
    public static func makeEnvelope(payload: LicensePayload, privateKey: Curve25519.Signing.PrivateKey) throws -> LicenseEnvelope {
        let payloadBytes = try JSONEncoder().encode(payload)
        let signature = try privateKey.signature(for: payloadBytes)
        return LicenseEnvelope(payload: Base64URL.encode(payloadBytes), signature: Base64URL.encode(signature))
    }
}
