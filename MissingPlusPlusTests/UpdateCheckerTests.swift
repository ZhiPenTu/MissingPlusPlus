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
}
