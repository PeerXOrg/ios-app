import Foundation
import CoreImage

public struct QRToken: Sendable, Equatable {
    public let hex: String
    public let expiresAt: Date
}

public enum QRError: Error, Sendable {
    case network(URLError)
    case unexpected(status: Int)
    case decoding
    case dataURLMalformed
    case pngDecodeFailed
    case qrNotFound
}

public enum QRRefresher {
    public static func refresh(jwt: JWT, session: URLSession = NetworkClient.session) async throws(QRError) -> QRToken {
        AppLog.qr.info("refresh start")

        let req = APIRequest.build(
            path: "api/v3/pacses_user/qr_code",
            method: "PUT",
            bearer: jwt.raw
        )

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await NetworkClient.send(req, session: session)
        } catch let e as URLError {
            throw .network(e)
        } catch {
            throw .network(URLError(.unknown))
        }

        guard (200..<300).contains(response.statusCode) else {
            AppLog.qr.error("refresh unexpected status=\(response.statusCode, privacy: .public)")
            throw .unexpected(status: response.statusCode)
        }

        struct Envelope: Decodable {
            let qrCode: String
            let expiresAt: Date
            enum CodingKeys: String, CodingKey {
                case qrCode = "qr_code"
                case expiresAt = "expires_at"
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = Self.iso8601Fractional.date(from: raw) { return date }
            if let date = Self.iso8601Plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601: \(raw)")
        }

        let env: Envelope
        do {
            env = try decoder.decode(Envelope.self, from: data)
        } catch {
            AppLog.qr.error("refresh decode failed: \(String(describing: error), privacy: .public)")
            throw .decoding
        }

        let hex = try extractHex(fromDataURL: env.qrCode)
        AppLog.qr.info("refresh ok hex=\(hex.count, privacy: .public)ch expiresAt=\(env.expiresAt.description, privacy: .public)")
        return QRToken(hex: hex, expiresAt: env.expiresAt)
    }

    static func extractHex(fromDataURL dataURL: String) throws(QRError) -> String {
        guard let comma = dataURL.firstIndex(of: ",") else { throw .dataURLMalformed }
        let base64 = String(dataURL[dataURL.index(after: comma)...])
        guard let pngData = Data(base64Encoded: base64) else { throw .pngDecodeFailed }
        guard let image = CIImage(data: pngData) else { throw .pngDecodeFailed }

        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: image) ?? []
        guard let qr = features.first as? CIQRCodeFeature, let message = qr.messageString else {
            throw .qrNotFound
        }
        return message
    }

    nonisolated(unsafe) private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let iso8601Plain = ISO8601DateFormatter()
}
