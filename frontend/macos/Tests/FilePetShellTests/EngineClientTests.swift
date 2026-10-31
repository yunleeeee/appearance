import Foundation
import XCTest
@testable import FilePetShell

final class EngineClientTests: XCTestCase {
    func testHealthAndCategoriesDecodeActualContract() async throws {
        try await withClient({ request in
            if request.url!.path == "/health" {
                return (200, #"{"status":"ok","version":"0.1.0"}"#)
            }
            XCTAssertEqual(request.url!.path, "/categories")
            return (200, #"[{"id":"recruitment","label":"招聘项目","description":"招聘与岗位"}]"#)
        }) { client in
            let health = try await client.health()
            XCTAssertEqual(health, EngineHealth(status: "ok", version: "0.1.0"))
            let categories = try await client.categories()
            XCTAssertEqual(categories, [EngineCategory(id: "recruitment", label: "招聘项目", description: "招聘与岗位")])
        }
    }

    func testCreateJobSendsExactPathWithoutLocalClassification() async throws {
        let path = "/Users/example/待分类/岗位 招聘.txt"
        try await withClient({ request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url!.path, "/jobs")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let json = try JSONSerialization.jsonObject(with: Self.requestBody(request)) as! [String: String]
            XCTAssertEqual(json, ["path": path])
            return (202, #"{"job_id":"job-1","status":"queued"}"#)
        }) { client in
            let accepted = try await client.createJob(path: path)
            XCTAssertEqual(accepted, EngineJobAccepted(jobID: "job-1", status: "queued"))
        }
    }

    func testCompletedJobDecodesAllResultFields() async throws {
        try await withClient({ request in
            XCTAssertEqual(request.url!.path, "/jobs/job-1")
            return (200, #"{"job_id":"job-1","status":"completed","result":{"path":"/tmp/recruitment.txt","file_name":"recruitment.txt","status":"classified","category_id":"recruitment","category_label":"招聘项目","confidence":0.9,"matched_keywords":["招聘","岗位"],"reason":"根据内容","extraction_chars":55},"error":null}"#)
        }) { client in
            let job = try await client.job(id: "job-1")
            XCTAssertEqual(job.jobID, "job-1")
            XCTAssertEqual(job.status, "completed")
            XCTAssertNil(job.error)
            XCTAssertEqual(job.result, EngineClassificationResult(path: "/tmp/recruitment.txt", fileName: "recruitment.txt", status: "classified", categoryID: "recruitment", categoryLabel: "招聘项目", confidence: 0.9, matchedKeywords: ["招聘", "岗位"], reason: "根据内容", extractionChars: 55))
        }
    }

    func testNeedsReviewKeepsNullCategoryAndFutureStagesDecode() async throws {
        try await withClient({ _ in
            (200, #"{"job_id":"job-2","status":"needs_review","result":{"path":"/tmp/unknown.txt","file_name":"unknown.txt","status":"needs_review","category_id":null,"category_label":null,"confidence":0,"matched_keywords":[],"reason":"线索不足","extraction_chars":3},"error":null}"#)
        }) { client in
            let job = try await client.job(id: "job-2")
            XCTAssertEqual(job.status, "needs_review")
            XCTAssertNil(job.result!.categoryID)
            XCTAssertNil(job.result!.categoryLabel)
        }
        try await withClient({ _ in
            (200, #"{"job_id":"job-2","status":"future_stage","result":null,"error":null}"#)
        }) { client in
            let job = try await client.job(id: "job-2")
            XCTAssertEqual(job.status, "future_stage")
        }
    }

    func testCompletedDeadlineOnlyJobDecodesActualCoreContract() async throws {
        try await withClient({ request in
            XCTAssertEqual(request.url!.path, "/jobs/ddl-job")
            return (200, #"{"job_id":"ddl-job","status":"completed","result":{"path":"/tmp/notice.txt","file_name":"notice.txt","status":"needs_review","category_id":null,"category_label":null,"confidence":0,"matched_keywords":[],"reason":"有效内容线索不足","extraction_chars":88,"deadlines":[{"id":"stable-first","title":"提交实验报告","project":"软件工程","due_date":"2026-11-03","due_time":"23:59","year_inferred":false,"status":"needs_confirmation","signal":"date_before_action","raw_date":"2026年11月3日","evidence":"请于2026年11月3日23:59前提交实验报告"},{"id":"stable-second","title":"上传演示材料","project":"软件工程","due_date":"2026-11-05","due_time":null,"year_inferred":true,"status":"needs_confirmation","signal":"explicit_deadline","raw_date":"11月5日","evidence":"演示材料截止：11月5日"}]},"error":null}"#)
        }) { client in
            let job = try await client.job(id: "ddl-job")
            XCTAssertEqual(job.status, "completed")
            let result = try XCTUnwrap(job.result)
            XCTAssertEqual(result.status, "needs_review")
            XCTAssertNil(result.categoryID)
            XCTAssertEqual(result.deadlines, [
                EngineDeadline(id: "stable-first", title: "提交实验报告", project: "软件工程",
                               dueDate: "2026-11-03", dueTime: "23:59", yearInferred: false,
                               evidence: "请于2026年11月3日23:59前提交实验报告", signal: "date_before_action", status: "needs_confirmation"),
                EngineDeadline(id: "stable-second", title: "上传演示材料", project: "软件工程",
                               dueDate: "2026-11-05", dueTime: nil, yearInferred: true,
                               evidence: "演示材料截止：11月5日", signal: "explicit_deadline", status: "needs_confirmation"),
            ])
        }
    }

    func testFailedJobDecodesRootAuthorizationFailure() async throws {
        try await withClient({ _ in
            (200, #"{"job_id":"denied","status":"failed","result":null,"error":{"status_code":403,"detail":"文件不在授权的 root 文件夹内"}}"#)
        }) { client in
            let job = try await client.job(id: "denied")
            XCTAssertEqual(job.status, "failed")
            XCTAssertNil(job.result)
            XCTAssertEqual(job.error, EngineJobFailure(detail: "文件不在授权的 root 文件夹内", statusCode: 403))
        }
    }

    func testHTTPFailuresExposeBoundedEngineMessage() async throws {
        for (status, payload, expected) in [
            (403, #"{"detail":"文件不在授权的 root 文件夹内"}"#, "文件不在授权的 root 文件夹内"),
            (404, #"{"detail":"任务不存在或已过期"}"#, "任务不存在或已过期"),
            (422, #"{"detail":[{"loc":["body","path"],"msg":"String should have at least 1 character","type":"string_too_short"}]}"#, "String should have at least 1 character"),
            (502, "<html>upstream error</html>", ""),
        ] {
            try await withClient({ _ in (status, payload) }) { client in
                do {
                    _ = try await client.job(id: "missing")
                    XCTFail("Expected HTTP failure")
                } catch let error as EngineClientError {
                    XCTAssertEqual(error, .httpStatus(status, expected))
                }
            }
        }
        let payload = try JSONSerialization.data(withJSONObject: ["detail": String(repeating: "长", count: 1_000)])
        try await withClient({ _ in (400, String(data: payload, encoding: .utf8)!) }) { client in
            do { _ = try await client.health(); XCTFail("Expected HTTP failure") }
            catch let EngineClientError.httpStatus(_, message) { XCTAssertEqual(message.count, 300) }
        }
    }

    func testNetworkFailurePropagatesWithoutCreatingFakeResult() async throws {
        try await withClient({ _ in throw URLError(.cannotConnectToHost) }) { client in
            do { _ = try await client.health(); XCTFail("Expected network failure") }
            catch let error as URLError { XCTAssertEqual(error.code, .cannotConnectToHost) }
        }
    }

    func testCancelledTaskDoesNotStartRequest() async throws {
        try await withClient({ _ in XCTFail("Cancelled work must not send a request"); return (200, "{}") }) { client in
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await client.health()
            }
            do { _ = try await task.value; XCTFail("Expected cancellation") }
            catch is CancellationError { }
        }
    }

    func testRemoteOrDecoratedEndpointsAreRejected() throws {
        for endpoint in [
            "https://127.0.0.1:8765", "http://example.com", "http://127.0.0.2:8765",
            "http://user:password@127.0.0.1:8765", "http://127.0.0.1:8765/other",
            "http://127.0.0.1:8765?token=secret", "http://127.0.0.1:8765#fragment", "http://127.0.0.1:0",
        ] {
            XCTAssertThrowsError(try EngineClient(baseURL: URL(string: endpoint)!)) { error in
                XCTAssertEqual(error as? EngineClientError, .invalidEndpoint, endpoint)
            }
        }
        XCTAssertNoThrow(try EngineClient())
        XCTAssertNoThrow(try EngineClient(baseURL: URL(string: "http://localhost:8765/")!))
        XCTAssertNoThrow(try EngineClient(baseURL: URL(string: "http://[::1]:8765")!))
    }

    private func withClient(
        _ response: @escaping EngineURLProtocol.Response,
        operation: (EngineClient) async throws -> Void
    ) async throws {
        let token = UUID().uuidString
        EngineURLProtocol.register(token: token, response: response)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EngineURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Engine-Test": token]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            EngineURLProtocol.remove(token: token)
        }
        let client = try EngineClient(session: session)
        try await operation(client)
    }

    private static func requestBody(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var bytes = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }
            result.append(contentsOf: bytes.prefix(count))
        }
        return result
    }
}

private final class EngineURLProtocol: URLProtocol {
    typealias Response = (URLRequest) throws -> (Int, String)
    private static let lock = NSLock()
    private static var responses: [String: Response] = [:]

    static func register(token: String, response: @escaping Response) {
        lock.lock(); defer { lock.unlock() }
        responses[token] = response
    }
    static func remove(token: String) {
        lock.lock(); defer { lock.unlock() }
        responses.removeValue(forKey: token)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let response = Self.responses[request.value(forHTTPHeaderField: "X-Engine-Test") ?? ""]
        Self.lock.unlock()
        guard let response else { return client!.urlProtocol(self, didFailWithError: URLError(.badServerResponse)) }
        do {
            let (status, payload) = try response(request)
            let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client!.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client!.urlProtocol(self, didLoad: Data(payload.utf8))
            client!.urlProtocolDidFinishLoading(self)
        } catch {
            client!.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() { }
}
