import Foundation

/// The shell depends on this protocol, never on a classifier or filesystem importer.
protocol EngineServing: Sendable {
    func health() async throws -> EngineHealth
    func categories() async throws -> [EngineCategory]
    func createJob(path: String) async throws -> EngineJobAccepted
    func job(id: String) async throws -> EngineJob
}

struct EngineHealth: Codable, Equatable, Sendable {
    let status: String
    let version: String
}

struct EngineCategory: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let description: String
}

struct EngineJobAccepted: Codable, Equatable, Sendable {
    let jobID: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
    }
}

struct EngineClassificationResult: Codable, Equatable, Sendable {
    let path: String
    let fileName: String
    let status: String
    let categoryID: String?
    let categoryLabel: String?
    let confidence: Double
    let matchedKeywords: [String]
    let reason: String
    let extractionChars: Int
    var deadlines: [EngineDeadline] = []

    enum CodingKeys: String, CodingKey {
        case path, status, confidence, reason
        case fileName = "file_name"
        case categoryID = "category_id"
        case categoryLabel = "category_label"
        case matchedKeywords = "matched_keywords"
        case extractionChars = "extraction_chars"
        case deadlines
    }
}

extension EngineClassificationResult {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        path = try values.decode(String.self, forKey: .path)
        fileName = try values.decode(String.self, forKey: .fileName)
        status = try values.decode(String.self, forKey: .status)
        categoryID = try values.decodeIfPresent(String.self, forKey: .categoryID)
        categoryLabel = try values.decodeIfPresent(String.self, forKey: .categoryLabel)
        confidence = try values.decode(Double.self, forKey: .confidence)
        matchedKeywords = try values.decode([String].self, forKey: .matchedKeywords)
        reason = try values.decode(String.self, forKey: .reason)
        extractionChars = try values.decode(Int.self, forKey: .extractionChars)
        deadlines = try values.decodeIfPresent([EngineDeadline].self, forKey: .deadlines) ?? []
    }
}

struct EngineDeadline: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let project: String
    let dueDate: String
    let dueTime: String?
    let yearInferred: Bool
    let evidence: String
    var signal: String? = nil
    var status: String? = nil
    var confirmationRequired: Bool? = nil
    var sourcePath: String? = nil

    var requiresConfirmation: Bool {
        confirmationRequired == true || yearInferred || signal == "ocr_deadline"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, project, evidence, signal, status
        case confirmationRequired = "confirmation_required"
        case sourcePath = "source_path"
        case dueDate = "due_date"
        case dueTime = "due_time"
        case yearInferred = "year_inferred"
    }
}

struct EngineJobFailure: Codable, Equatable, Sendable {
    let detail: String
    let statusCode: Int?

    enum CodingKeys: String, CodingKey {
        case detail
        case statusCode = "status_code"
    }
}

struct EngineJob: Codable, Equatable, Sendable {
    let jobID: String
    /// Preserve unknown future stages instead of silently treating them as success.
    let status: String
    let result: EngineClassificationResult?
    let error: EngineJobFailure?

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status, result, error
    }
}

enum EngineClientError: Error, LocalizedError, Equatable, Sendable {
    case invalidEndpoint
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "分类引擎地址必须是本机 HTTP 地址，且不能包含账号、路径或查询参数。"
        case .invalidResponse:
            return "分类引擎返回了无效响应。"
        case let .httpStatus(code, detail):
            return detail.isEmpty ? "分类引擎请求失败（\(code)）。" : detail
        }
    }
}

/// All traffic stays on loopback. The Python service owns authorization and classification.
actor EngineClient: EngineServing {
    static let defaultBaseURL = URL(string: "http://127.0.0.1:8765")!
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = EngineClient.defaultBaseURL, session: URLSession? = nil) throws {
        guard let parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "http",
              let host = parts.host?.lowercased(),
              ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host),
              parts.user == nil, parts.password == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true else {
            throw EngineClientError.invalidEndpoint
        }
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 15
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            self.session = URLSession(configuration: configuration, delegate: LocalEngineSessionDelegate(), delegateQueue: nil)
        }
    }

    func health() async throws -> EngineHealth {
        try await request("health")
    }

    func categories() async throws -> [EngineCategory] {
        try await request("categories")
    }

    func createJob(path: String) async throws -> EngineJobAccepted {
        struct JobRequest: Encodable { let path: String }
        return try await request("jobs", method: "POST", body: JSONEncoder().encode(JobRequest(path: path)))
    }

    func job(id: String) async throws -> EngineJob {
        // A returned job ID is a single URL path component, not a relative URL.
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#")
        guard !id.isEmpty, let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw EngineClientError.invalidResponse
        }
        return try await request("jobs/" + encoded)
    }

    private func request<Response: Decodable>(
        _ path: String, method: String = "GET", body: Data? = nil
    ) async throws -> Response {
        try Task.checkCancellation()
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = "/" + path
        guard let url = components.url else { throw EngineClientError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw EngineClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw EngineClientError.httpStatus(http.statusCode, Self.failureDetail(data))
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func failureDetail(_ data: Data) -> String {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        let detail: String
        if let message = envelope["detail"] as? String {
            detail = message
        } else if let validation = envelope["detail"] as? [[String: Any]] {
            detail = validation.prefix(3).compactMap { $0["msg"] as? String }.joined(separator: "；")
        } else {
            return ""
        }
        // Error pages and large validation payloads never become an unbounded UI message.
        let oneLine = detail.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
        return String(oneLine.prefix(300))
    }
}

private final class LocalEngineSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // The engine has no redirecting endpoints. Never forward file paths elsewhere.
        completionHandler(nil)
    }
}
