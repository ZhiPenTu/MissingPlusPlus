import XCTest
@testable import MissingPlusPlus

/// update-checker 相关字段 (v0.0.2+) 的 unit test。
/// 用 isolated UserDefaults suite, 避免污染真实 prefs。
@MainActor
final class AppPreferencesUpdateCheckTests: XCTestCase {
    var suiteName: String!
    var testDefaults: UserDefaults!
    var prefs: AppPreferences!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "AppPreferencesUpdateCheckTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        prefs = AppPreferences(defaults: testDefaults)
    }

    override func tearDown() async throws {
        testDefaults.removePersistentDomain(forName: suiteName)
        prefs = nil
        testDefaults = nil
        try await super.tearDown()
    }

    func test_updateCheckEnabled_defaultsToTrue() {
        XCTAssertTrue(prefs.updateCheckEnabled, "updateCheckEnabled should default to true")
    }

    func test_updateCheckEnabled_persistsAcrossInstances() {
        prefs.updateCheckEnabled = false
        let prefs2 = AppPreferences(defaults: testDefaults)
        XCTAssertFalse(prefs2.updateCheckEnabled, "should persist as false in same suite")
    }

    func test_lastDismissedVersion_startsNil() {
        XCTAssertNil(prefs.lastDismissedVersion)
    }

    func test_lastDismissedVersion_persists() {
        prefs.lastDismissedVersion = "0.0.2"
        let prefs2 = AppPreferences(defaults: testDefaults)
        XCTAssertEqual(prefs2.lastDismissedVersion, "0.0.2")
    }

    func test_transientFields_areNotPersisted() {
        prefs.lastCheckedAt = Date()
        prefs.lastKnownRemoteVersion = "0.0.99"
        let prefs2 = AppPreferences(defaults: testDefaults)
        XCTAssertNil(prefs2.lastCheckedAt, "lastCheckedAt is transient")
        XCTAssertNil(prefs2.lastKnownRemoteVersion, "lastKnownRemoteVersion is transient")
    }
}
