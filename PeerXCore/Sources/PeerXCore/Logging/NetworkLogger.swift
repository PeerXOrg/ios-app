import Foundation
import os

public enum AppLog {
    public static let subsystem = "me.nickaroot.peerx"

    public static let auth     = Logger(subsystem: subsystem, category: "auth")
    public static let qr       = Logger(subsystem: subsystem, category: "qr")
    public static let pass     = Logger(subsystem: subsystem, category: "pass")
    public static let flow     = Logger(subsystem: subsystem, category: "flow")
    public static let network  = Logger(subsystem: subsystem, category: "network")
    public static let keychain = Logger(subsystem: subsystem, category: "keychain")
}

public enum NetworkLogger {
    private static let sensitiveHeaders: Set<String> = [
        "authorization",
        "cookie",
        "set-cookie",
        "x-csrf-token",
    ]

    private static let sensitiveBodyKeys: Set<String> = [
        "password",
        "captcha_token",
        "token",
        "jwt",
        "access_token",
    ]

    private static let counter = OSAllocatedUnfairLock(initialState: UInt64(0))

    public static func nextID() -> UInt64 {
        counter.withLock { value in
            value &+= 1
            return value
        }
    }

    public static func logRequest(_ req: URLRequest, id: UInt64) {
        let method = req.httpMethod ?? "GET"
        let url = req.url?.absoluteString ?? "<nil>"
        AppLog.network.info("→ #\(id, privacy: .public) \(method, privacy: .public) \(url, privacy: .public)")

        if let headers = req.allHTTPHeaderFields, !headers.isEmpty {
            let dump = redactedHeaders(headers)
            AppLog.network.debug("  headers #\(id, privacy: .public): \(dump, privacy: .public)")
        }

        if let body = req.httpBody {
            let preview = redactedBodyPreview(body, contentType: req.value(forHTTPHeaderField: "Content-Type"))
            AppLog.network.debug("  body #\(id, privacy: .public) (\(body.count) B): \(preview, privacy: .public)")
        }
    }

    public static func logResponse(_ response: URLResponse?, body: Data, id: UInt64, elapsedMS: Double) {
        guard let http = response as? HTTPURLResponse else {
            AppLog.network.error("← #\(id, privacy: .public) non-HTTP response in \(String(format: "%.0f", elapsedMS), privacy: .public) ms")
            return
        }
        let status = http.statusCode
        let level: OSLogType = (200..<400).contains(status) ? .info : .error
        AppLog.network.log(level: level, "← #\(id, privacy: .public) \(status, privacy: .public) \(http.url?.absoluteString ?? "", privacy: .public) in \(String(format: "%.0f", elapsedMS), privacy: .public) ms (\(body.count) B)")

        let headers = http.allHeaderFields.reduce(into: [String: String]()) { acc, kv in
            if let k = kv.key as? String, let v = kv.value as? String { acc[k] = v }
        }
        if !headers.isEmpty {
            let dump = redactedHeaders(headers)
            AppLog.network.debug("  resp-headers #\(id, privacy: .public): \(dump, privacy: .public)")
        }

        let preview = redactedBodyPreview(body, contentType: http.value(forHTTPHeaderField: "Content-Type"))
        AppLog.network.debug("  resp-body #\(id, privacy: .public) (\(body.count) B): \(preview, privacy: .public)")
    }

    public static func logError(_ error: Error, id: UInt64, elapsedMS: Double) {
        AppLog.network.error("✗ #\(id, privacy: .public) \(String(describing: error), privacy: .public) after \(String(format: "%.0f", elapsedMS), privacy: .public) ms")
    }

    // MARK: - Redaction

    private static func redactedHeaders(_ headers: [String: String]) -> String {
        let pairs = headers.map { (k, v) -> String in
            if sensitiveHeaders.contains(k.lowercased()) {
                return "\(k): \(redact(v))"
            }
            return "\(k): \(v)"
        }.sorted()
        return "{ " + pairs.joined(separator: ", ") + " }"
    }

    private static func redactedBodyPreview(_ data: Data, contentType: String?) -> String {
        guard !data.isEmpty else { return "<empty>" }
        let limit = 2048
        let isJSON = (contentType ?? "").lowercased().contains("json")

        if isJSON, let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            let redacted = redactJSON(obj)
            if let pretty = try? JSONSerialization.data(withJSONObject: redacted, options: [.prettyPrinted, .fragmentsAllowed]),
               let s = String(data: pretty, encoding: .utf8) {
                return truncate(s, limit: limit)
            }
        }

        if let s = String(data: data, encoding: .utf8) {
            return truncate(s, limit: limit)
        }
        return "<\(data.count) bytes binary>"
    }

    private static func redactJSON(_ obj: Any) -> Any {
        if let dict = obj as? [String: Any] {
            return dict.reduce(into: [String: Any]()) { acc, kv in
                if sensitiveBodyKeys.contains(kv.key.lowercased()) {
                    acc[kv.key] = redact(String(describing: kv.value))
                } else {
                    acc[kv.key] = redactJSON(kv.value)
                }
            }
        }
        if let arr = obj as? [Any] {
            return arr.map(redactJSON)
        }
        return obj
    }

    private static func redact(_ value: String) -> String {
        guard !value.isEmpty else { return "<empty>" }
        if value.count <= 8 { return "***" }
        let prefix = value.prefix(4)
        let suffix = value.suffix(4)
        return "\(prefix)…\(suffix) (\(value.count) chars)"
    }

    private static func truncate(_ s: String, limit: Int) -> String {
        if s.count <= limit { return s }
        return String(s.prefix(limit)) + "…[+\(s.count - limit) chars]"
    }
}

public enum NetworkClient {
    /// Shared session that does not auto-follow redirects. The API uses 30x
    /// responses as protocol-level signals (sign-in returns the JWT in the
    /// 302 `Authorization` header), so redirects must be inspected, not chased.
    public static let session: URLSession = {
        let config = URLSessionConfiguration.default
        let delegate = NoRedirectDelegate()
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()

    public static func send(_ req: URLRequest, session: URLSession = NetworkClient.session) async throws -> (Data, HTTPURLResponse) {
        let id = NetworkLogger.nextID()
        NetworkLogger.logRequest(req, id: id)
        let start = Date()
        do {
            let (data, response) = try await session.data(for: req)
            let elapsedMS = Date().timeIntervalSince(start) * 1000
            NetworkLogger.logResponse(response, body: data, id: id, elapsedMS: elapsedMS)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, http)
        } catch {
            let elapsedMS = Date().timeIntervalSince(start) * 1000
            NetworkLogger.logError(error, id: id, elapsedMS: elapsedMS)
            throw error
        }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let from = task.originalRequest?.url?.absoluteString ?? "?"
        let to = request.url?.absoluteString ?? "?"
        AppLog.network.notice("redirect refused: \(response.statusCode, privacy: .public) \(from, privacy: .public) → \(to, privacy: .public)")
        completionHandler(nil)
    }
}
