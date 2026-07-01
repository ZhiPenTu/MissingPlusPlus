import XCTest
@testable import MissingPlusPlus

/// Mock URLSession so tests don't hit the network.
final class MockURLSession: URLSessionProtocol {
    var stubbedData: Data?
    var stubbedResponse: URLResponse?
    var stubbedError: Error?
    var dataCallCount = 0

    func data(from url: URL) async throws -> (Data, URLResponse) {
        dataCallCount += 1
        if let error = stubbedError { throw error }
        let resp = stubbedResponse ?? HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        return (stubbedData ?? Data(), resp)
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    var mockSession: MockURLSession!
    var testDefaults: UserDefaults!
    var suiteName: String!
    var prefs: AppPreferences!
    var checker: UpdateChecker!

    override func setUp() async throws {
        try await super.setUp()
        mockSession = MockURLSession()
        suiteName = "UpdateCheckerTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        prefs = AppPreferences(defaults: testDefaults)
    }

    override func tearDown() async throws {
        testDefaults.removePersistentDomain(forName: suiteName)
        prefs = nil
        testDefaults = nil
        mockSession = nil
        checker = nil
        try await super.tearDown()
    }

    /// Smoke: UpdateCheckResult is Equatable (verifies enum compiles).
    func test_resultEquatable() {
        let r1: UpdateCheckResult = .upToDate(localVersion: "0.0.1")
        let r2: UpdateCheckResult = .upToDate(localVersion: "0.0.1")
        XCTAssertEqual(r1, r2)
    }

    // MARK: - compareSemver

    func test_semverRemoteGreater() {
        XCTAssertGreaterThan(UpdateChecker.compareSemver(remote: "0.0.2", local: "0.0.1"), 0)
    }

    func test_semverEqual() {
        XCTAssertEqual(UpdateChecker.compareSemver(remote: "0.0.1", local: "0.0.1"), 0)
    }

    func test_semverRemoteLesser() {
        XCTAssertLessThan(UpdateChecker.compareSemver(remote: "0.0.1", local: "0.0.2"), 0)
    }

    func test_semverMajorJump() {
        // 1.0.0 > 0.99.99 (a known sharp edge in naive string compare)
        XCTAssertGreaterThan(UpdateChecker.compareSemver(remote: "1.0.0", local: "0.99.99"), 0)
    }

    func test_semverHandlesMissingSegments() {
        // "0.1" should equal "0.1.0" (missing trailing segment treated as 0)
        XCTAssertEqual(UpdateChecker.compareSemver(remote: "0.1", local: "0.1.0"), 0)
    }

    // MARK: - performCheck happy path

    func test_performCheck_updateAvailable() async {
        // GitHub stub returns v0.0.99 which is way above any local version
        stubGitHub(tag: "v0.0.99", url: "https://github.com/ZhiPenTu/MissingPlusPlus/releases/tag/v0.0.99")
        let result = await makeChecker().checkNow()
        XCTAssertEqual(result, .updateAvailable(version: "0.0.99",
                                                url: URL(string: "https://github.com/ZhiPenTu/MissingPlusPlus/releases/tag/v0.0.99")!))
    }

    func test_performCheck_callDoesNotFail() async {
        // Smoke: just assert the call completes without returning .failed.
        // (Whether it returns .upToDate or .updateAvailable depends on the
        // test target's CFBundleShortVersionString, which we can't override.)
        stubGitHub(tag: "v0.0.1", url: "https://x")
        let result = await makeChecker().checkNow()
        switch result {
        case .upToDate, .updateAvailable: break  // OK
        case .failed(let reason): XCTFail("Unexpected failure: \(reason)")
        }
    }

    // MARK: - Test helpers

    private func makeChecker(
        githubURL: URL = URL(string: "https://api.github.com/repos/ZhiPenTu/MissingPlusPlus/releases/latest")!
    ) -> UpdateChecker {
        checker = UpdateChecker(
            session: mockSession,
            prefs: prefs,
            githubURL: githubURL
        )
        return checker!
    }

    private func stubGitHub(tag: String, url: String) {
        let json: [String: Any] = ["tag_name": tag, "html_url": url]
        mockSession.stubbedData = try! JSONSerialization.data(withJSONObject: json)
    }

    // MARK: - performCheck edge cases

    func test_performCheck_prereleaseTreatedAsUpToDate() async {
        // 9.9.9-alpha would be newer than 0.0.1, but '-alpha' marks it prerelease
        // — we skip prereleases so user doesn't get false positive.
        stubGitHub(tag: "v9.9.9-alpha", url: "https://x")
        let result = await makeChecker().checkNow()
        if case .upToDate = result {
            // pass
        } else {
            XCTFail("prerelease should be .upToDate, got \(result)")
        }
    }

    func test_performCheck_httpError() async {
        mockSession.stubbedData = Data()
        mockSession.stubbedResponse = HTTPURLResponse(
            url: URL(string: "https://api.github.com/x")!,
            statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        let result = await makeChecker().checkNow()
        XCTAssertEqual(result, .failed(reason: "GitHub 返回 HTTP 403"))
    }

    func test_performCheck_networkFailure() async {
        mockSession.stubbedError = URLError(.notConnectedToInternet)
        let result = await makeChecker().checkNow()
        if case .failed = result {
            // pass — exact reason comes from URLError.localizedDescription
        } else {
            XCTFail("network error should be .failed, got \(result)")
        }
    }

    func test_performCheck_malformedJSON() async {
        mockSession.stubbedData = "not json".data(using: .utf8)!
        mockSession.stubbedResponse = HTTPURLResponse(
            url: URL(string: "https://api.github.com/x")!,
            statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        let result = await makeChecker().checkNow()
        XCTAssertEqual(result, .failed(reason: "响应格式不符"))
    }

    // MARK: - startBackgroundCheck throttle + disable

    func test_startBackgroundCheck_respectsDisabled() async {
        prefs.updateCheckEnabled = false
        let c = makeChecker()
        c.startBackgroundCheck()
        // Give any potential fire-and-forget Task a moment.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(mockSession.dataCallCount, 0, "should not call network when disabled")
    }

    func test_startBackgroundCheck_respectsThrottle() async {
        // lastCheckedAt = now → 6h 内 throttle 生效
        prefs.lastCheckedAt = Date()
        let c = makeChecker()
        c.startBackgroundCheck()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(mockSession.dataCallCount, 0, "should throttle within 6h")
    }

    func test_checkNow_bypassesThrottle() async {
        prefs.lastCheckedAt = Date()
        stubGitHub(tag: "v0.0.1", url: "https://x")
        _ = await makeChecker().checkNow()
        XCTAssertEqual(mockSession.dataCallCount, 1, "manual check should bypass throttle")
    }
}
