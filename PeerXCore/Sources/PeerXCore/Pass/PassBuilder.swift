import Foundation
import Crypto
import ZIPFoundation

public enum PassError: Error, Sendable {
    case templateMissing
    case templateMalformed
    case assetMissing(String)
    case zipFailed
    case signerInit(reason: String)
    case signing(reason: String)
}

public struct PassBuilder: Sendable {
    let qrToken: QRToken
    let serialNumber: String

    public init(qrToken: QRToken, serialNumber: String) {
        self.qrToken = qrToken
        self.serialNumber = serialNumber
    }

    public func build(signer: PassSigner) throws(PassError) -> Data {
        let passJSON = try buildPassJSON()

        var files: [String: Data] = ["pass.json": passJSON]
        let assetNames = [
            "icon.png", "icon@2x.png", "icon@3x.png",
            "logo.png", "logo@2x.png", "logo@3x.png",
        ]
        for name in assetNames {
            let split = name.split(separator: ".", maxSplits: 1)
            let baseName = String(split[0])
            let ext = split.count == 2 ? String(split[1]) : "png"
            guard let url = Bundle.module.url(forResource: baseName, withExtension: ext),
                  let data = try? Data(contentsOf: url)
            else {
                throw .assetMissing(name)
            }
            files[name] = data
        }

        // Wallet reads <lang>.lproj/pass.strings inside the .pkpass at display
        // time, independent of the device locale at build time.
        let localizations: [(lang: String, resource: String)] = [
            ("en", "pass-en"),
            ("ru", "pass-ru"),
        ]
        for entry in localizations {
            guard let url = Bundle.module.url(forResource: entry.resource, withExtension: "strings"),
                  let data = try? Data(contentsOf: url)
            else {
                throw .assetMissing("\(entry.resource).strings")
            }
            files["\(entry.lang).lproj/pass.strings"] = data
        }

        var manifest: [String: String] = [:]
        for (name, data) in files {
            let digest = Insecure.SHA1.hash(data: data)
            manifest[name] = digest.map { String(format: "%02x", $0) }.joined()
        }
        let manifestData: Data
        do {
            manifestData = try JSONSerialization.data(
                withJSONObject: manifest,
                options: [.sortedKeys]
            )
        } catch {
            throw .templateMalformed
        }
        files["manifest.json"] = manifestData

        let signatureData: Data
        do {
            signatureData = try signer.sign(manifestData)
        } catch let e as PassError {
            throw e
        } catch {
            throw .signing(reason: String(describing: error))
        }
        files["signature"] = signatureData

        guard let archive = Archive(accessMode: .create) else {
            throw .zipFailed
        }
        do {
            for (name, data) in files {
                try archive.addEntry(
                    with: name,
                    type: .file,
                    uncompressedSize: Int64(data.count),
                    provider: { position, size in
                        let start = Int(position)
                        let end = min(start + size, data.count)
                        return data.subdata(in: start..<end)
                    }
                )
            }
        } catch {
            throw .zipFailed
        }
        guard let archiveData = archive.data else {
            throw .zipFailed
        }
        return archiveData
    }

    private func buildPassJSON() throws(PassError) -> Data {
        guard let url = Bundle.module.url(forResource: "pass-base", withExtension: "json") else {
            throw .templateMissing
        }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            throw .templateMissing
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let expiresStr = isoFormatter.string(from: qrToken.expiresAt)

        // altText is baked at build time because pass.strings can't substitute
        // a dynamic date. Silent refresh rebuilds the pass, so a locale change
        // is reflected within the refresh interval.
        let dateInLocale = qrToken.expiresAt.formatted(date: .abbreviated, time: .shortened)
        let altText = String(localized: "Valid until \(dateInLocale)", bundle: .module)

        let substituted = raw
            .replacingOccurrences(of: "REPLACE_WITH_HEX_TOKEN", with: qrToken.hex)
            .replacingOccurrences(of: "REPLACE_WITH_EXPIRES_AT", with: expiresStr)
            .replacingOccurrences(of: "REPLACE_WITH_USER_SUB", with: serialNumber)
            .replacingOccurrences(of: "REPLACE_WITH_PASS_TYPE_ID", with: Constants.passTypeIdentifier)
            .replacingOccurrences(of: "REPLACE_WITH_TEAM_ID", with: Constants.teamIdentifier)
            .replacingOccurrences(of: "REPLACE_WITH_ORG_NAME", with: Constants.organizationName)
            .replacingOccurrences(of: "REPLACE_WITH_EXPIRATION_DATE", with: expiresStr)
            .replacingOccurrences(of: "REPLACE_WITH_ADAM_ID", with: Constants.parentAppADAMID)
            .replacingOccurrences(of: "REPLACE_WITH_ALT_TEXT", with: Self.jsonEscape(altText))

        guard let data = substituted.data(using: .utf8) else {
            throw .templateMalformed
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw .templateMalformed
        }
        return data
    }

    private static func jsonEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }
}
