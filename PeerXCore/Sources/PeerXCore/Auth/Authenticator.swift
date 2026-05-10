import Foundation

public struct Profile: Codable, Sendable, Equatable {
    public let id: Int?
    public let email: String?
    public let sub: String?
    public let ldapLogin: String?
    public let state: String?
    public let campusId: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case sub
        case ldapLogin = "ldap_login"
        case state
        case campusId = "campus_id"
    }
}

public enum AuthError: Error, Sendable {
    case noCredentials
    case invalidCredentials
    case network(URLError)
    case unexpected(status: Int)
    case encoding
    case decoding
    case jwt(JWTError)
    case missingToken
}

public actor Authenticator {
    private let session: URLSession
    private var cachedJWT: JWT?
    private var inFlight: Task<JWT, any Error>?

    public init(session: URLSession = NetworkClient.session) {
        self.session = session
    }

    public func signIn(email: String, password: String) async throws(AuthError) -> JWT {
        AppLog.auth.info("signIn start email=\(email, privacy: .private)")

        struct Body: Encodable {
            struct ApiUser: Encodable {
                let email: String
                let password: String
            }
            let apiUser: ApiUser
            let captchaToken: String
        }

        let body = Body(
            apiUser: .init(email: email, password: password),
            captchaToken: "captchaToken"
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData: Data
        do {
            bodyData = try encoder.encode(body)
        } catch {
            AppLog.auth.error("signIn encode failed: \(String(describing: error), privacy: .public)")
            throw .encoding
        }

        let req = APIRequest.build(
            path: "api/v3/signin",
            method: "POST",
            body: bodyData
        )

        let (data, response) = try await Self.send(req, session: session)

        // 302/303 is the server's post-redirect-after-auth pattern. The JWT
        // is returned in the `Authorization` header regardless of redirect:
        // 200 (json body) for parent app, 302 (Location: /) for App Clip.
        switch response.statusCode {
        case 200..<300, 302, 303: break
        case 401, 403, 422:
            AppLog.auth.error("signIn rejected status=\(response.statusCode, privacy: .public)")
            throw .invalidCredentials
        default:
            AppLog.auth.error("signIn unexpected status=\(response.statusCode, privacy: .public)")
            throw .unexpected(status: response.statusCode)
        }

        let raw = try Self.extractJWT(from: response, body: data)

        let jwt: JWT
        do {
            jwt = try JWT(string: raw)
        } catch let e as JWTError {
            AppLog.auth.error("signIn JWT parse failed: \(String(describing: e), privacy: .public)")
            throw .jwt(e)
        }

        do {
            try KeychainStore.saveJWT(raw)
        } catch {
            AppLog.auth.error("saveJWT failed: \(String(describing: error), privacy: .public)")
        }
        do {
            try KeychainStore.saveCredentials(.init(email: email, password: password))
        } catch {
            AppLog.auth.error("saveCredentials failed: \(String(describing: error), privacy: .public)")
        }

        cachedJWT = jwt
        AppLog.auth.info("signIn ok sub=\(jwt.sub, privacy: .public) exp=\(jwt.exp.description, privacy: .public)")
        return jwt
    }

    public func signOut() async {
        AppLog.auth.info("signOut start")
        let bearer = cachedJWT?.raw
        let req = APIRequest.build(
            path: "api/v3/signout",
            method: "DELETE",
            bearer: bearer
        )
        _ = try? await Self.send(req, session: session)
        cachedJWT = nil
        try? KeychainStore.clearAll()
        AppLog.auth.info("signOut done")
    }

    public func me() async throws(AuthError) -> Profile {
        let jwt = try await currentJWT()
        let req = APIRequest.build(
            path: "api/v3/me",
            method: "GET",
            bearer: jwt.raw
        )

        let (data, response) = try await Self.send(req, session: session)

        switch response.statusCode {
        case 200..<300: break
        case 401: throw .invalidCredentials
        default: throw .unexpected(status: response.statusCode)
        }

        struct Envelope: Decodable { let user: Profile }
        do {
            return try JSONDecoder().decode(Envelope.self, from: data).user
        } catch {
            AppLog.auth.error("me decode failed: \(String(describing: error), privacy: .public)")
            throw .decoding
        }
    }

    public func currentJWT() async throws(AuthError) -> JWT {
        if let jwt = cachedJWT, !jwt.isExpiringSoon {
            return jwt
        }

        if cachedJWT == nil,
           let raw = try? KeychainStore.loadJWTRaw(),
           let parsed = try? JWT(string: raw),
           !parsed.isExpiringSoon
        {
            cachedJWT = parsed
            return parsed
        }

        if let inFlight {
            do {
                return try await inFlight.value
            } catch let e as AuthError {
                throw e
            } catch {
                throw .invalidCredentials
            }
        }

        let creds: KeychainStore.Credentials
        do {
            guard let loaded = try KeychainStore.loadCredentials() else {
                throw AuthError.noCredentials
            }
            creds = loaded
        } catch let e as AuthError {
            throw e
        } catch {
            throw .noCredentials
        }

        let task = Task<JWT, any Error> {
            try await self.signIn(email: creds.email, password: creds.password)
        }
        inFlight = task
        defer { inFlight = nil }

        do {
            return try await task.value
        } catch let e as AuthError {
            throw e
        } catch {
            throw .invalidCredentials
        }
    }

    // MARK: - Internals

    private static func send(_ req: URLRequest, session: URLSession) async throws(AuthError) -> (Data, HTTPURLResponse) {
        do {
            return try await NetworkClient.send(req, session: session)
        } catch let error as URLError {
            throw .network(error)
        } catch {
            throw .network(URLError(.unknown))
        }
    }

    private static func extractJWT(from response: HTTPURLResponse, body: Data) throws(AuthError) -> String {
        // 1. Direct Authorization response header (server exposes it via
        //    `access-control-expose-headers: Authorization`). Works for both 200 and 302.
        if let auth = response.value(forHTTPHeaderField: "Authorization"), !auth.isEmpty {
            return auth.hasPrefix("Bearer ") ? String(auth.dropFirst("Bearer ".count)) : auth
        }

        // 2. Set-Cookie: Authorization=Bearer%20<jwt> (browser path).
        if let setCookie = response.value(forHTTPHeaderField: "Set-Cookie") {
            for piece in setCookie.split(separator: ",") {
                let trimmed = piece.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("Authorization=") else { continue }
                guard let eq = trimmed.firstIndex(of: "=") else { continue }
                var raw = String(trimmed[trimmed.index(after: eq)...])
                if let semi = raw.firstIndex(of: ";") { raw = String(raw[..<semi]) }
                if let decoded = raw.removingPercentEncoding { raw = decoded }
                if raw.hasPrefix("Bearer ") { return String(raw.dropFirst("Bearer ".count)) }
                return raw
            }
        }

        // 3. JSON body (200 path, parent app).
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            for key in ["Authorization", "token", "jwt", "access_token"] {
                if let value = json[key] as? String {
                    return value.hasPrefix("Bearer ") ? String(value.dropFirst("Bearer ".count)) : value
                }
            }
            if let dataObj = json["data"] as? [String: Any] {
                for key in ["Authorization", "token", "jwt", "access_token"] {
                    if let value = dataObj[key] as? String {
                        return value.hasPrefix("Bearer ") ? String(value.dropFirst("Bearer ".count)) : value
                    }
                }
            }
        }
        throw .missingToken
    }
}
