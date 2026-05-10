@_spi(CMS) import X509
import _CryptoExtras
import Foundation

/// PKCS#7 detached signature for `.pkpass` manifest, with the Apple WWDR
/// intermediate certificate. `CMS.sign` is `@_spi(CMS)` — Package.swift pins
/// swift-certificates to `.upToNextMinor` to mitigate API breakage.
public struct PassSigner: Sendable {
    let passCert: Certificate
    let wwdrCert: Certificate
    let passKey: Certificate.PrivateKey

    public init() throws(PassError) {
        let bundle = Bundle.module
        guard let passURL = bundle.url(forResource: "pass", withExtension: "pem") else {
            throw .signerInit(reason: "missing pass.pem")
        }
        guard let wwdrURL = bundle.url(forResource: "wwdr", withExtension: "pem") else {
            throw .signerInit(reason: "missing wwdr.pem")
        }
        guard let keyURL = bundle.url(forResource: "pass", withExtension: "key") else {
            throw .signerInit(reason: "missing pass.key")
        }

        let passPEM: String
        let wwdrPEM: String
        let keyPEM: String
        do {
            passPEM = try String(contentsOf: passURL, encoding: .utf8)
            wwdrPEM = try String(contentsOf: wwdrURL, encoding: .utf8)
            keyPEM = try String(contentsOf: keyURL, encoding: .utf8)
        } catch {
            throw .signerInit(reason: "PEM read failed: \(error)")
        }

        let passCert: Certificate
        let wwdrCert: Certificate
        do {
            passCert = try Certificate(pemEncoded: passPEM)
            wwdrCert = try Certificate(pemEncoded: wwdrPEM)
        } catch {
            throw .signerInit(reason: "Certificate parse failed: \(error)")
        }

        let rsaKey: _RSA.Signing.PrivateKey
        do {
            rsaKey = try _RSA.Signing.PrivateKey(pemRepresentation: keyPEM)
        } catch {
            throw .signerInit(reason: "RSA private key parse failed: \(error)")
        }

        self.passCert = passCert
        self.wwdrCert = wwdrCert
        self.passKey = Certificate.PrivateKey(rsaKey)
    }

    public func sign(_ manifest: Data) throws(PassError) -> Data {
        let bytes: [UInt8]
        do {
            bytes = try CMS.sign(
                manifest,
                signatureAlgorithm: .sha256WithRSAEncryption,
                additionalIntermediateCertificates: [wwdrCert],
                certificate: passCert,
                privateKey: passKey,
                signingTime: Date(),
                detached: true
            )
        } catch {
            throw .signing(reason: "CMS.sign failed: \(error)")
        }
        return Data(bytes)
    }
}
