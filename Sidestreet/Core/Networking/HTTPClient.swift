import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A minimal HTTP request description (keeps providers testable).
struct HTTPRequest: Sendable, Hashable {
    enum Method: String, Sendable { case get = "GET", post = "POST" }

    var url: URL
    var method: Method = .get
    var headers: [String: String] = [:]
    var body: Data?
    var timeout: TimeInterval = 20
    /// Responses larger than this are rejected (protects memory on mobile).
    var maxBytes: Int = 8 * 1024 * 1024
}

struct HTTPResponse: Sendable {
    var status: Int
    var headers: [String: String]
    var data: Data
    var url: URL

    func header(_ name: String) -> String? {
        let lower = name.lowercased()
        return headers.first { $0.key.lowercased() == lower }?.value
    }

    /// Seconds from a `Retry-After` header (delta-seconds form only).
    var retryAfter: TimeInterval? {
        header("Retry-After").flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
    }
}

enum NetworkError: Error, Equatable, Sendable, LocalizedError {
    case offline
    case timedOut
    case cancelled
    case rateLimited(retryAfter: TimeInterval?)
    case httpStatus(Int)
    case tooLarge
    case invalidResponse
    case decoding(String)
    case blockedByRobots
    case notConfigured(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .offline: return "No internet connection."
        case .timedOut: return "The server took too long to respond."
        case .cancelled: return "Cancelled."
        case .rateLimited: return "The service is busy (rate limited). Try again shortly."
        case .httpStatus(let code): return "Server error (HTTP \(code))."
        case .tooLarge: return "The response was too large."
        case .invalidResponse: return "Unexpected response."
        case .decoding(let detail): return "Could not read the data (\(detail))."
        case .blockedByRobots: return "The website does not allow automated access."
        case .notConfigured(let what): return "\(what) is not configured."
        case .transport(let detail): return "Network error: \(detail)"
        }
    }

    /// Whether retrying (possibly on another endpoint) can help.
    var isTransient: Bool {
        switch self {
        case .timedOut, .rateLimited, .transport: return true
        case .httpStatus(let code): return code == 502 || code == 503 || code == 504 || code == 429
        default: return false
        }
    }
}

protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

extension HTTPClient {
    /// Sends a request and throws for non-2xx statuses.
    func sendChecked(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response = try await send(request)
        switch response.status {
        case 200..<300:
            return response
        case 429:
            throw NetworkError.rateLimited(retryAfter: response.retryAfter)
        default:
            throw NetworkError.httpStatus(response.status)
        }
    }
}

/// Identifies the app to API operators, as required by the OpenStreetMap
/// Overpass and Wikimedia usage policies. Contains no personal data unless the
/// user explicitly adds a contact in Settings.
struct ClientIdentity: Sendable, Hashable {
    var appVersion: String
    /// Optional contact (e-mail or URL) chosen by the user.
    var contact: String?

    var userAgent: String {
        var details = "personal iOS urban-discovery app; non-commercial"
        if let contact, !contact.trimmingCharacters(in: .whitespaces).isEmpty {
            details += "; " + contact.trimmingCharacters(in: .whitespaces)
        }
        return "Sidestreet/\(appVersion) (\(details))"
    }

    static let `default` = ClientIdentity(appVersion: "1.0", contact: nil)
}

/// `URLSession`-backed client with per-host politeness limits.
final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    private let session: URLSession
    private let identity: ClientIdentity
    private let limiter: HostRateLimiter

    init(identity: ClientIdentity, limiter: HostRateLimiter = HostRateLimiter(), session: URLSession? = nil) {
        self.identity = identity
        self.limiter = limiter
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            config.httpMaximumConnectionsPerHost = 4
            config.requestCachePolicy = .useProtocolCachePolicy
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            self.session = URLSession(configuration: config)
        }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let scheme = request.url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw NetworkError.invalidResponse
        }
        let host = request.url.host ?? ""
        try await limiter.acquire(host: host)
        defer { Task { await limiter.release(host: host) } }

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = request.timeout
        urlRequest.httpBody = request.body
        urlRequest.setValue(identity.userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
            if data.count > request.maxBytes { throw NetworkError.tooLarge }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                headers[String(describing: key)] = String(describing: value)
            }
            if http.statusCode == 429 || http.statusCode == 503 {
                let retry = headers.first { $0.key.lowercased() == "retry-after" }.flatMap { TimeInterval($0.value) }
                await limiter.backOff(host: host, seconds: retry ?? 30)
            }
            return HTTPResponse(status: http.statusCode, headers: headers, data: data, url: http.url ?? request.url)
        } catch let error as NetworkError {
            throw error
        } catch is CancellationError {
            throw NetworkError.cancelled
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw NetworkError.offline
            case .timedOut: throw NetworkError.timedOut
            case .cancelled: throw NetworkError.cancelled
            default: throw NetworkError.transport(error.localizedDescription)
            }
        } catch {
            throw NetworkError.transport(error.localizedDescription)
        }
    }
}
