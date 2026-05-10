import Foundation

public struct JWT: Sendable, Equatable {
    public let raw: String
    public let email: String?
    public let sub: String
    public let exp: Date
    public let iat: Date
    public let jti: String?

    public init(string: String) throws(JWTError) {
        let parts = string.split(separator: ".")
        guard parts.count == 3 else { throw .malformedStructure }

        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }

        guard let payload = Data(base64Encoded: b64) else { throw .base64DecodeFailed }

        let claims: Claims
        do {
            claims = try JSONDecoder().decode(Claims.self, from: payload)
        } catch {
            throw .decodingFailed
        }

        self.raw = string
        self.email = claims.email
        self.sub = claims.sub
        self.exp = Date(timeIntervalSince1970: claims.exp)
        self.iat = Date(timeIntervalSince1970: claims.iat)
        self.jti = claims.jti
    }

    public var isExpired: Bool {
        Date() >= exp
    }

    public var isExpiringSoon: Bool {
        Date().distance(to: exp) < 5 * 60
    }

    private struct Claims: Decodable {
        let email: String?
        let sub: String
        let exp: TimeInterval
        let iat: TimeInterval
        let jti: String?
    }
}

public enum JWTError: Error, Sendable {
    case malformedStructure
    case base64DecodeFailed
    case decodingFailed
}
