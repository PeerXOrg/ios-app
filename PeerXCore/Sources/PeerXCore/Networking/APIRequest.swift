import Foundation

public enum APIRequest {
    /// applicant.21-school.ru's CDN/WAF returns 502 for the default
    /// URLSession User-Agent. Pin to a recent Safari UA.
    public static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/26.4 Safari/605.1.15"

    public static let origin  = "https://applicant.21-school.ru"
    public static let referer = "https://applicant.21-school.ru/no-referrer"

    public static func build(
        path: String,
        method: String,
        body: Data? = nil,
        bearer: String? = nil,
        contentType: String? = "application/json"
    ) -> URLRequest {
        var req = URLRequest(url: Constants.apiBaseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.httpBody = body

        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(origin, forHTTPHeaderField: "Origin")
        req.setValue(referer, forHTTPHeaderField: "Referer")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("ru, ru;q=0.9, en;q=0.8", forHTTPHeaderField: "Accept-Language")
        req.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.setValue("max-age=0", forHTTPHeaderField: "Cache-Control")
        req.setValue("u=1, i", forHTTPHeaderField: "Priority")

        if let body {
            req.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
            if let contentType {
                req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        } else if method == "PUT" || method == "POST" {
            req.setValue("0", forHTTPHeaderField: "Content-Length")
            if let contentType {
                req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        if let bearer {
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }

        return req
    }
}
