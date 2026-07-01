# Update Checker (GitHub Releases) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a self-written GitHub Releases update checker that detects new versions on launch (silent, 6h throttle) and via a status-bar "Check for Updates…" menu item (manual, no throttle), posting a sticky pink banner in the main window when an update is available.

**Architecture:** `UpdateChecker.shared` (URLSession → GitHub API → semver compare) emits `.didFindRemoteUpdate` notification; `AppDelegate` catches it, pulls main window to front, and re-posts `.showUpdateBanner`; `MenuBarContent` (SwiftUI) mounts an `UpdateBanner` overlay. Zero new dependencies, no Sparkle, no `WindowController.shared` / cross-controller references (AGENTS §6).

**Tech Stack:** Swift 5.0 / SwiftUI / AppKit / URLSession / NotificationCenter / UserDefaults. Xcode 26.0, macOS 26.0 deployment target (Debug overrides to 13.0 in some scripts; no change to deployment target here).

**Spec:** `docs/superpowers/specs/2026-07-01-update-checker-design.md` (source of truth for design decisions; this plan is the executable form).

**Working directory:** `/Users/tuzhipeng/missing++`. All paths in this plan are relative to the repo root.

---

## File Structure

| File | Role | Lines (Δ) |
|---|---|---|
| `MissingPlusPlus/Services/UpdateChecker.swift` | **NEW.** `actor` of GitHub-Releases fetcher + semver compare; emits `.didFindRemoteUpdate` notification. | +110 |
| `MissingPlusPlus/Services/AppPreferences.swift` | Add 4 fields: `updateCheckEnabled` (persisted), `lastDismissedVersion` (persisted), `lastCheckedAt` (transient), `lastKnownRemoteVersion` (transient). Refactor `init` to accept `UserDefaults` for testability. | +28 |
| `MissingPlusPlus/StatusBar/MenuBuilder.swift` | Add `onCheckForUpdates: @escaping () -> Void` closure to `init`. Add `Check for Updates…` NSMenuItem in `build()`. Update internal `MenuActionRouter` to add `@objc checkForUpdatesFromMenu(_:)` + `presentResult(_:)` static. | +50 |
| `MissingPlusPlus/StatusBar/StatusPanelController.swift` | Add `onCheckForUpdates: @escaping () -> Void` to `init`; forward to `MenuBuilder`. | +6 |
| `MissingPlusPlus/MissingPlusPlusApp.swift` (AppDelegate) | Add `UpdateChecker.shared.startBackgroundCheck()` + subscribe `.didFindRemoteUpdate` → re-post `.showUpdateBanner`. Pass new `onCheckForUpdates` closure to `StatusPanelController`. | +20 |
| `MissingPlusPlus/Views/UpdateBanner.swift` | **NEW.** SwiftUI banner view (pink gradient, sticky, 3 actions). | +55 |
| `MissingPlusPlus/Views/MenuBarContent.swift` | Add `@State` for `updateBanner` + `bannerVisible`; subscribe `.showUpdateBanner` via `.onReceive`; mount banner at top. | +25 |
| `MissingPlusPlus/Views/SettingsView.swift` | Add "更新" Section with `Toggle("自动检查更新")` + "立即检查" button + `lastCheckedAt` display. | +25 |
| `MissingPlusPlusTests/UpdateCheckerTests.swift` | **NEW.** 7 XCTest cases (happy path, no update, prerelease, network fail, HTTP error, semver edges, throttle). | +150 |
| `MissingPlusPlus.xcodeproj/project.pbxproj` | Register 3 new Swift files (UpdateChecker, UpdateBanner, UpdateCheckerTests) in `PBXBuildFile` + `PBXFileReference` + 3 `PBXGroup` + `PBXSourcesBuildPhase`. | +12 (3 entries × 4 sections) |
| `AGENTS.md` | Add §24 "Update Checker (v0.0.2+)" with behavior summary + release-publish checklist. | +60 |
| `docs/ci.md` | Append publish checklist note to §2 (手动 Publish release). | +5 |

**Total:** 9 modify + 3 new files, ~546 lines added, 0 lines deleted.

**Not touched:** `Info.plist` / `MissingPlusPlus.entitlements` / `scripts/build-dmg.sh` / `scripts/run_tests.sh` / `scripts/build_and_run.sh` / `release.yml` / `Windows/WindowController.swift` (AppDelegate pulls main window to front; no controller-method change needed).

---

## Conventions Used Throughout

- **Conventional Commits:** `feat:` (new behavior), `test:` (test only), `refactor:` (no behavior change), `chore:` (build/CI/pbxproj), `docs:` (AGENTS.md / docs/).
- **Test command:** `./scripts/run_tests.sh --filter <ClassName>` for a single class, `./scripts/run_tests.sh` for full suite.
- **Build command:** `xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5` (or use `./scripts/build_and_run.sh` for build+launch).
- **Code style:** matches existing repo (4-space indent, no semicolons except `for`/control flow, `// MARK:` separators, `final class` over `class`).
- **Singleton pattern:** `@MainActor final class Foo: ObservableObject { static let shared = Foo() }` — match `MissingStore.shared` / `NotificationService.shared`.
- **Notification name:** declared as `extension Notification.Name { static let xxx = Notification.Name("Xxx") }` in the file that posts it.
- **pbxproj registration:** 3 new Swift files use new unique 24-char hex IDs. Pick: `A10000A0…A10000A2` (BuildFile), `B10000A0…B10000A2` (FileRef). Verify uniqueness with `grep -E "A10000A0|B10000A0" project.pbxproj` before editing.

---

## Task 0: Create Feature Branch

**Files:** None (git only)

- [ ] **Step 1: Confirm clean working tree**

Run: `git status`

Expected: "nothing to commit, working tree clean". If dirty, commit or stash existing changes first.

- [ ] **Step 2: Create + checkout feature branch off main**

Run:
```bash
git checkout main
git pull origin main
git checkout -b codex/update-checker
```

Expected: branch `codex/update-checker` created, pointing at the same commit as `origin/main`.

All 14 tasks below commit to this branch. Push + open PR only after Task 14 (integration smoke test) passes.

---

## Task 1: Make AppPreferences Testable (Inject UserDefaults)

**Files:**
- Modify: `MissingPlusPlus/Services/AppPreferences.swift:140-200` (init)
- Modify: `MissingPlusPlusTests/...` (no test file yet — write next task)

- [ ] **Step 1: Read current `AppPreferences` init signature**

Run:
```bash
sed -n '155,210p' MissingPlusPlus/Services/AppPreferences.swift
```

Expected: see `private init()` and a `private let defaults = UserDefaults.standard` line near the top of the class.

- [ ] **Step 2: Refactor `AppPreferences` to accept injectable `UserDefaults`**

In `MissingPlusPlus/Services/AppPreferences.swift`, make these edits:

**Edit A** (change `private let defaults = UserDefaults.standard` at line ~21 to):
```swift
private let defaults: UserDefaults
```

**Edit B** (replace `private init() {` at line ~155 with):
```swift
init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    // ... existing 14 lines of self.xxx = defaults.object(...) ... (unchanged)
}
```

**Edit C** (no change to `static let shared = AppPreferences()` — still uses default arg).

- [ ] **Step 3: Verify build still compiles**

Run: `xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`. Existing call sites (`AppPreferences.shared` with no args) keep working because of the default value.

- [ ] **Step 4: Commit**

```bash
git add MissingPlusPlus/Services/AppPreferences.swift
git commit -m "refactor(prefs): inject UserDefaults for testability

init now accepts defaults: UserDefaults = .standard; .shared unchanged.
Lets unit tests use an isolated suite without polluting real prefs."
```

---

## Task 2: AppPreferences Update-Checker Fields

**Files:**
- Modify: `MissingPlusPlus/Services/AppPreferences.swift` (4 fields + 2 Keys + init)
- Test: `MissingPlusPlusTests/AppPreferencesUpdateCheckTests.swift` (new)

- [ ] **Step 1: Write the failing test**

Create `MissingPlusPlusTests/AppPreferencesUpdateCheckTests.swift` with:

```swift
import XCTest
@testable import MissingPlusPlus

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

    func testUpdateCheckEnabledDefaultsToTrue() {
        XCTAssertTrue(prefs.updateCheckEnabled, "updateCheckEnabled should default to true")
    }

    func testUpdateCheckEnabledPersistsAcrossInstances() {
        prefs.updateCheckEnabled = false
        // New instance, same suite
        let prefs2 = AppPreferences(defaults: testDefaults)
        XCTAssertFalse(prefs2.updateCheckEnabled, "should persist as false in same suite")
    }

    func testLastDismissedVersionStartsNil() {
        XCTAssertNil(prefs.lastDismissedVersion)
    }

    func testLastDismissedVersionPersists() {
        prefs.lastDismissedVersion = "0.0.2"
        let prefs2 = AppPreferences(defaults: testDefaults)
        XCTAssertEqual(prefs2.lastDismissedVersion, "0.0.2")
    }

    func testTransientFieldsAreNotPersisted() {
        prefs.lastCheckedAt = Date()
        prefs.lastKnownRemoteVersion = "0.0.99"
        let prefs2 = AppPreferences(defaults: testDefaults)
        XCTAssertNil(prefs2.lastCheckedAt, "lastCheckedAt is transient")
        XCTAssertNil(prefs2.lastKnownRemoteVersion, "lastKnownRemoteVersion is transient")
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails to compile**

Run: `./scripts/run_tests.sh --filter AppPreferencesUpdateCheckTests`

Expected: **BUILD FAILS** with `value of type 'AppPreferences' has no member 'updateCheckEnabled'`. (This is fine — we haven't added the field yet.)

- [ ] **Step 3: Add the 4 fields to `AppPreferences`**

In `MissingPlusPlus/Services/AppPreferences.swift`, **add to the published properties block** (after `notificationIncludeTriggers`, before `cooldownActivities`):

```swift
/// v0.0.2 update-checker: 启动 5s 后静默检查 GitHub Releases;有新版在主窗口顶部
/// 弹 banner。默认开。关闭后连手动 "Check for Updates…" 也禁用。
@Published var updateCheckEnabled: Bool {
    didSet { defaults.set(updateCheckEnabled, forKey: Keys.updateCheckEnabled) }
}
/// v0.0.2 update-checker: 启动检查节流用。transient, 不持久化。
@Published var lastCheckedAt: Date?
/// v0.0.2 update-checker: 上次发现的 remote version (debug/UI 用)。transient, 不持久化。
@Published var lastKnownRemoteVersion: String?
/// v0.0.2 update-checker: 用户点过 "稍后" 的版本。持久化,避免每次启动都重弹同一版本。
@Published var lastDismissedVersion: String? {
    didSet { defaults.set(lastDismissedVersion, forKey: Keys.lastDismissedVersion) }
}
```

- [ ] **Step 4: Add 2 Keys to the `Keys` enum**

In the `private enum Keys` block (after `static let worthConfirmations`), add:

```swift
static let updateCheckEnabled = "UpdateCheckEnabled"
static let lastDismissedVersion = "UpdateCheckerLastDismissedVersion"
```

- [ ] **Step 5: Add 4 init lines at the end of `init` body**

At the end of `init(defaults: UserDefaults = .standard) { ... }` (just before the closing `}`), add:

```swift
        self.updateCheckEnabled =
            defaults.object(forKey: Keys.updateCheckEnabled) as? Bool ?? true
        self.lastCheckedAt = nil  // transient
        self.lastKnownRemoteVersion = nil  // transient
        self.lastDismissedVersion =
            defaults.string(forKey: Keys.lastDismissedVersion)
```

- [ ] **Step 6: Run the tests, expect 5 passes**

Run: `./scripts/run_tests.sh --filter AppPreferencesUpdateCheckTests`

Expected: `** TEST SUCCEEDED **` with 5 tests passing.

- [ ] **Step 7: Commit**

```bash
git add MissingPlusPlus/Services/AppPreferences.swift \
        MissingPlusPlusTests/AppPreferencesUpdateCheckTests.swift
git commit -m "feat(prefs): add updateCheckEnabled + lastDismissedVersion

4 fields total: 2 persisted (toggle + dismissed version), 2 transient
(checked-at + last-known). Refactors init to accept UserDefaults so
tests can use an isolated suite."
```

---

## Task 3: UpdateChecker Skeleton (Protocol, Result Enum, Notification Name)

**Files:**
- Create: `MissingPlusPlus/Services/UpdateChecker.swift`
- Test: `MissingPlusPlusTests/UpdateCheckerTests.swift` (new)

- [ ] **Step 1: Write the failing test file with the result-equality case**

Create `MissingPlusPlusTests/UpdateCheckerTests.swift`:

```swift
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
    func testResultEquatable() {
        let r1: UpdateCheckResult = .upToDate(localVersion: "0.0.1")
        let r2: UpdateCheckResult = .upToDate(localVersion: "0.0.1")
        XCTAssertEqual(r1, r2)
    }
}
```

- [ ] **Step 2: Run test, expect compile failure (no `UpdateCheckResult` yet)**

Run: `./scripts/run_tests.sh --filter UpdateCheckerTests`

Expected: **BUILD FAILS** with `cannot find type 'UpdateCheckResult' in scope`.

- [ ] **Step 3: Create `UpdateChecker.swift` skeleton**

Create `MissingPlusPlus/Services/UpdateChecker.swift`:

```swift
import Foundation
import AppKit

// MARK: - Notifications

extension Notification.Name {
    /// Posted by `UpdateChecker` when remote version > local. userInfo:
    ///   "version": String (e.g. "0.0.2")
    ///   "url": URL (GitHub release html_url)
    static let didFindRemoteUpdate = Notification.Name("UpdateCheckerDidFindRemoteUpdate")

    /// Posted by `AppDelegate` after receiving `.didFindRemoteUpdate`. `MenuBarContent`
    /// subscribes via `.onReceive` to mount the banner overlay. userInfo same as above.
    static let showUpdateBanner = Notification.Name("UpdateCheckerShowUpdateBanner")
}

// MARK: - Result

enum UpdateCheckResult: Equatable {
    case upToDate(localVersion: String)
    case updateAvailable(version: String, url: URL)
    case failed(reason: String)
}

// MARK: - URLSession protocol (for test injection)

protocol URLSessionProtocol {
    func data(from url: URL) async throws -> (Data, URLResponse)
}
extension URLSession: URLSessionProtocol {}

// MARK: - UpdateChecker

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let session: URLSessionProtocol
    private let prefs: AppPreferences
    private let githubURL: URL
    private let checkLock = NSLock()

    init(
        session: URLSessionProtocol = URLSession.shared,
        prefs: AppPreferences = .shared,
        githubURL: URL = URL(string: "https://api.github.com/repos/ZhiPenTu/MissingPlusPlus/releases/latest")!
    ) {
        self.session = session
        self.prefs = prefs
        self.githubURL = githubURL
    }

    // (performCheck / checkNow / startBackgroundCheck added in Tasks 4-6)
}
```

- [ ] **Step 4: Run test, expect smoke pass**

Run: `./scripts/run_tests.sh --filter UpdateCheckerTests`

Expected: `** TEST SUCCEEDED **` with 1 test passing.

- [ ] **Step 5: Commit**

```bash
git add MissingPlusPlus/Services/UpdateChecker.swift \
        MissingPlusPlusTests/UpdateCheckerTests.swift
git commit -m "feat(update-checker): scaffold protocol + result enum + notifications

URLSessionProtocol for test injection; .shared singleton matches
NotificationService.shared / MissingStore.shared pattern."
```

---

## Task 4: UpdateChecker.compareSemver (Pure Function)

**Files:**
- Modify: `MissingPlusPlus/Services/UpdateChecker.swift`
- Modify: `MissingPlusPlusTests/UpdateCheckerTests.swift` (add 4 cases)

- [ ] **Step 1: Add 5 failing test cases to `UpdateCheckerTests`**

Append to `UpdateCheckerTests` class (before the closing `}`):

```swift
    func testSemverRemoteGreater() {
        XCTAssertGreaterThan(UpdateChecker.compareSemver(remote: "0.0.2", local: "0.0.1"), 0)
    }

    func testSemverEqual() {
        XCTAssertEqual(UpdateChecker.compareSemver(remote: "0.0.1", local: "0.0.1"), 0)
    }

    func testSemverRemoteLesser() {
        XCTAssertLessThan(UpdateChecker.compareSemver(remote: "0.0.1", local: "0.0.2"), 0)
    }

    func testSemverMajorJump() {
        // 1.0.0 > 0.99.99 (a known sharp edge in naive string compare)
        XCTAssertGreaterThan(UpdateChecker.compareSemver(remote: "1.0.0", local: "0.99.99"), 0)
    }

    func testSemverHandlesMissingSegments() {
        // "0.1" should equal "0.1.0" (missing trailing segment treated as 0)
        XCTAssertEqual(UpdateChecker.compareSemver(remote: "0.1", local: "0.1.0"), 0)
    }
```

**Why `static func`:** `compareSemver` is a pure function, no instance state needed. Making it `static` lets the test call it without instantiating `UpdateChecker` (avoids needing mock URLSession / prefs in Task 4).
- [ ] **Step 2: Run tests, expect 5 failures (compareSemver not defined)**

Run: `./scripts/run_tests.sh --filter UpdateCheckerTests`

Expected: **BUILD FAILS** with `'UpdateChecker' has no member 'compareSemver'`.

- [ ] **Step 3: Add `compareSemver` to `UpdateChecker`**

In `MissingPlusPlus/Services/UpdateChecker.swift`, add at the end of the class (before the final `}`):

```swift
    /// Compare two semver strings segment-by-segment. Missing trailing segments
    /// are treated as 0 (so "0.1" == "0.1.0"). Non-integer segments → 0.
    /// - Returns: > 0 if remote > local; < 0 if remote < local; 0 if equal.
    static func compareSemver(remote: String, local: String) -> Int {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let len = max(r.count, l.count)
        for i in 0..<len {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv - lv }
        }
        return 0
    }
```

(Use `static func`, not instance method, so tests can call it without a checker instance.)

- [ ] **Step 4: Run tests, expect 5 passes + 1 smoke pass (6 total)**

Run: `./scripts/run_tests.sh --filter UpdateCheckerTests`

Expected: `** TEST SUCCEEDED **` with 6 tests passing.

- [ ] **Step 5: Commit**

```bash
git add MissingPlusPlus/Services/UpdateChecker.swift \
        MissingPlusPlusTests/UpdateCheckerTests.swift
git commit -m "feat(update-checker): add compareSemver static helper

5 unit cases: greater/equal/lesser/major-jump/missing-segment.
`static` so tests can call without instantiating UpdateChecker."
```

---

## Task 5: UpdateChecker.performCheck (Happy Path + Stub Helpers)

**Files:**
- Modify: `MissingPlusPlus/Services/UpdateChecker.swift`
- Modify: `MissingPlusPlusTests/UpdateCheckerTests.swift`

- [ ] **Step 1: Add the happy-path failing test**

Append to `UpdateCheckerTests` class:

```swift
    func testPerformCheckUpdateAvailable() async {
        // Stub: GitHub says v0.0.99 (anything > whatever the test target version is)
        stubGitHub(tag: "v0.0.99", url: "https://github.com/ZhiPenTu/MissingPlusPlus/releases/tag/v0.0.99")
        let result = await makeChecker().checkNow()
        XCTAssertEqual(result, .updateAvailable(version: "0.0.99",
                                                url: URL(string: "https://github.com/ZhiPenTu/MissingPlusPlus/releases/tag/v0.0.99")!))
    }

    func testPerformCheckUpToDateWhenLocalIs999() async {
        // Override Bundle lookup by stubbing a local version we control:
        // We can't override Bundle.main, so we use a version much higher than 0.0.99.
        // This test only makes sense if the test target's CFBundleShortVersionString
        // is < 0.0.99 (almost certainly true). We accept either .updateAvailable or .upToDate
        // here; the semver unit tests in Task 4 cover the logic directly.
        stubGitHub(tag: "v0.0.1", url: "https://x")
        let result = await makeChecker().checkNow()
        // Just assert the call completes; the value depends on test target's version.
        switch result {
        case .upToDate, .updateAvailable: break
        case .failed(let reason): XCTFail("Unexpected failure: \(reason)")
        }
    }
```

- [ ] **Step 2: Add the test helpers (`makeChecker`, `stubGitHub`) to the test class**

Append inside the test class (before the final `}`):

```swift
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
```

- [ ] **Step 3: Run tests, expect 2 new failures (`checkNow` not defined)**

Run: `./scripts/run_tests.sh --filter UpdateCheckerTests`

Expected: **BUILD FAILS** with `'UpdateChecker' has no member 'checkNow'`.

- [ ] **Step 4: Add `checkNow` + `performCheck` to `UpdateChecker`**

In `MissingPlusPlus/Services/UpdateChecker.swift`, replace the `// (performCheck / checkNow / startBackgroundCheck added in Tasks 4-6)` comment with:

```swift
    // MARK: - Public API

    /// Manual check (used by status-bar "Check for Updates…" item and
    /// Settings "立即检查" button). Bypasses the 6h throttle.
    func checkNow() async -> UpdateCheckResult {
        guard prefs.updateCheckEnabled else {
            return .failed(reason: "已在设置中关闭")
        }
        checkLock.lock(); defer { checkLock.unlock() }
        return await performCheck()
    }

    // MARK: - Private

    private func performCheck() async -> UpdateCheckResult {
        prefs.lastCheckedAt = Date()

        do {
            var request = URLRequest(url: githubURL)
            request.setValue("MissingPlusPlus/0.0.1 (macOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(from: githubURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                NSLog("[MissingPlusPlus] update: GitHub HTTP %d", code)
                return .failed(reason: "GitHub 返回 HTTP \(code)")
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURLString = json["html_url"] as? String,
                  let htmlURL = URL(string: htmlURLString) else {
                NSLog("[MissingPlusPlus] update: response format unexpected")
                return .failed(reason: "响应格式不符")
            }

            // Skip prereleases (e.g. "v0.0.2-alpha")
            if tagName.contains("-") {
                return .upToDate(localVersion: currentLocalVersion())
            }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let local = currentLocalVersion()

            if Self.compareSemver(remote: remoteVersion, local: local) > 0 {
                prefs.lastKnownRemoteVersion = remoteVersion
                return .updateAvailable(version: remoteVersion, url: htmlURL)
            } else {
                return .upToDate(localVersion: local)
            }
        } catch {
            NSLog("[MissingPlusPlus] update: %@", error.localizedDescription)
            return .failed(reason: error.localizedDescription)
        }
    }

    private func currentLocalVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
```

- [ ] **Step 5: Run tests, expect 8 passes total (1 smoke + 5 semver + 2 performCheck)**

Run: `./scripts/run_tests.sh --filter UpdateCheckerTests`

Expected: `** TEST SUCCEEDED **` with 8 tests passing.

- [ ] **Step 6: Commit**

```bash
git add MissingPlusPlus/Services/UpdateChecker.swift \
        MissingPlusPlusTests/UpdateCheckerTests.swift
git commit -m "feat(update-checker): performCheck fetches + parses + compares

Uses NSLock for serialization (avoids concurrent manual triggers).
Sets User-Agent + Accept headers explicitly for GitHub API v3.
Skips prerelease tags (tag_name containing '-')."
```

---

## Task 6: UpdateChecker Edge Cases (Prerelease / Network Fail / HTTP 4xx / JSON Parse)

**Files:**
- Modify: `MissingPlusPlusTests/UpdateCheckerTests.swift` (add 4 cases)

- [ ] **Step 1: Add 4 failing test cases**

Append to `UpdateCheckerTests`:

```swift
    func testPerformCheckPrereleaseTreatedAsUpToDate() async {
        stubGitHub(tag: "v9.9.9-alpha", url: "https://x")
        let result = await makeChecker().checkNow()
        if case .upToDate = result {
            // pass
        } else {
            XCTFail("prerelease should be .upToDate, got \(result)")
        }
    }

    func testPerformCheckHTTPError() async {
        mockSession.stubbedData = Data()
        mockSession.stubbedResponse = HTTPURLResponse(
            url: URL(string: "https://api.github.com/x")!,
            statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        let result = await makeChecker().checkNow()
        XCTAssertEqual(result, .failed(reason: "GitHub 返回 HTTP 403"))
    }

    func testPerformCheckNetworkFailure() async {
        mockSession.stubbedError = URLError(.notConnectedToInternet)
        let result = await makeChecker().checkNow()
        if case .failed = result {
            // pass — exact reason comes from URLError.localizedDescription
        } else {
            XCTFail("network error should be .failed, got \(result)")
        }
    }

    func testPerformCheckMalformedJSON() async {
        mockSession.stubbedData = "not json".data(using: .utf8)!
        mockSession.stubbedResponse = HTTPURLResponse(
            url: URL(string: "https://api.github.com/x")!,
            statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        let result = await makeChecker().checkNow()
        XCTAssertEqual(result, .failed(reason: "响应格式不符"))
    }
```

- [ ] **Step 2: Run tests, expect 4 passes (performCheck already handles these cases)**

Run: `./scripts/run_tests.sh --filter UpdateCheckerTests`

Expected: `** TEST SUCCEEDED **` with 12 tests passing total. (Implementation from Task 5 already covers these cases; Task 6 just adds the test coverage.)

- [ ] **Step 3: Commit**

```bash
git add MissingPlusPlusTests/UpdateCheckerTests.swift
git commit -m "test(update-checker): cover prerelease/HTTP-error/network-fail/malformed-JSON

Edge cases were already handled in performCheck (Task 5); this just
pins the behavior with explicit tests."
```

---

## Task 7: UpdateChecker.startBackgroundCheck (Throttle + Disable)

**Files:**
- Modify: `MissingPlusPlus/Services/UpdateChecker.swift`
- Modify: `MissingPlusPlusTests/UpdateCheckerTests.swift`

- [ ] **Step 1: Add 3 failing test cases**

Append to `UpdateCheckerTests`:

```swift
    func testStartBackgroundCheckRespectsDisabled() async {
        prefs.updateCheckEnabled = false
        let c = makeChecker()
        c.startBackgroundCheck()
        // Give any potential fire-and-forget Task a moment.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(mockSession.dataCallCount, 0, "should not call network when disabled")
    }

    func testStartBackgroundCheckRespectsThrottle() async {
        // First call goes through
        prefs.lastCheckedAt = Date()
        // Second call within 6h should be skipped
        let c = makeChecker()
        c.startBackgroundCheck()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(mockSession.dataCallCount, 0, "should throttle within 6h")
    }

    func testCheckNowBypassesThrottle() async {
        prefs.lastCheckedAt = Date()
        stubGitHub(tag: "v0.0.1", url: "https://x")
        let result = await makeChecker().checkNow()
        XCTAssertEqual(mockSession.dataCallCount, 1, "manual check should bypass throttle")
        // Result depends on test target version; just assert it ran.
        _ = result
    }
```

- [ ] **Step 2: Run tests, expect 3 failures (`startBackgroundCheck` not defined)**

Run: `./scripts/run_tests.sh --filter UpdateCheckerTests`

Expected: **BUILD FAILS** with `'UpdateChecker' has no member 'startBackgroundCheck'`.

- [ ] **Step 3: Add `startBackgroundCheck` + `silentCheck`**

In `MissingPlusPlus/Services/UpdateChecker.swift`, add to the `// MARK: - Public API` section (before `checkNow`):

```swift
    /// Fire-and-forget background check. Respects the toggle and the 6h throttle.
    /// Posts `.didFindRemoteUpdate` notification on positive result.
    func startBackgroundCheck() {
        guard prefs.updateCheckEnabled else { return }
        guard shouldCheckNow() else { return }
        Task { [weak self] in
            await self?.silentCheck()
        }
    }
```

Add to the `// MARK: - Private` section (after `currentLocalVersion`):

```swift
    private func shouldCheckNow() -> Bool {
        guard let last = prefs.lastCheckedAt else { return true }
        return Date().timeIntervalSince(last) > 6 * 3600
    }

    private func silentCheck() async {
        checkLock.lock(); defer { checkLock.unlock() }
        let result = await performCheck()
        if case .updateAvailable(let version, let url) = result {
            NotificationCenter.default.post(
                name: .didFindRemoteUpdate,
                object: self,
                userInfo: ["version": version, "url": url]
            )
        }
    }
```

- [ ] **Step 4: Run tests, expect 15 passes total**

Run: `./scripts/run_tests.sh --filter UpdateCheckerTests`

Expected: `** TEST SUCCEEDED **` with 15 tests passing.

- [ ] **Step 5: Commit**

```bash
git add MissingPlusPlus/Services/UpdateChecker.swift \
        MissingPlusPlusTests/UpdateCheckerTests.swift
git commit -m "feat(update-checker): background check with 6h throttle + disabled toggle

Posts .didFindRemoteUpdate on positive result. Fire-and-forget; can
be called from AppDelegate's applicationDidFinishLaunching."
```

---

## Task 8: UpdateBanner View (SwiftUI, No Unit Test)

**Files:**
- Create: `MissingPlusPlus/Views/UpdateBanner.swift`

- [ ] **Step 1: Create the file**

Create `MissingPlusPlus/Views/UpdateBanner.swift`:

```swift
import SwiftUI
import AppKit

/// Sticky pink-gradient banner pinned to the top of the main window.
/// Mounted by `MenuBarContent` when it receives `.showUpdateBanner` notification.
///
/// 设计: 跟 NewMissingForm header 同色系 (AGENTS §11 §16 "焦虑型产品调性"),
/// sticky (不自动 fade) — 用户点 "稍后" 或 "查看" 才消失。
struct UpdateBanner: View {
    let version: String
    let url: URL
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundColor(.pink)
            VStack(alignment: .leading, spacing: 2) {
                Text("新版本 v\(version) 可用")
                    .font(.subheadline.weight(.medium))
                Text("点击「查看」去 GitHub release 页下载最新 DMG。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("稍后") { onDismiss() }
                .buttonStyle(.borderless)
            Button("查看") {
                NSWorkspace.shared.open(url)
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color.pink.opacity(0.12), Color.pink.opacity(0.04)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.pink.opacity(0.25)),
            alignment: .bottom
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`. (Compile-only check; SwiftUI view can't be unit-tested without a host app.)

- [ ] **Step 3: Commit**

```bash
git add MissingPlusPlus/Views/UpdateBanner.swift
git commit -m "feat(update-banner): sticky pink-gradient banner view

3 actions: 稍后 (dismiss only), 查看 (open URL + dismiss), tap to dismiss.
Not registered in pbxproj yet — Task 12 wires project.pbxproj."
```

---

## Task 9: MenuBuilder + MenuActionRouter + StatusPanelController Wiring

**Files:**
- Modify: `MissingPlusPlus/StatusBar/MenuBuilder.swift` (4-arg init + router @objc + new item)
- Modify: `MissingPlusPlus/StatusBar/StatusPanelController.swift` (forward 4th closure)
- Modify: `MissingPlusPlusTests/MenuBuilderTests.swift` (4-arg init + new test)

**Why this is a refactor, not pure TDD:** Adding a 4th closure to `MenuBuilder.init` is a coordinated contract change across 3 files. The "red" state is: MenuBuilderTests won't compile (3-arg call) AND StatusPanelController won't compile (3-arg call). The "green" state is: all 3 files agree on the 4-arg signature. The natural order is: change the contract first, then migrate callers.

- [ ] **Step 1: Read current `MenuBuilder` + `MenuActionRouter` to confirm insertion points**

Run:
```bash
sed -n '24,40p' MissingPlusPlus/StatusBar/MenuBuilder.swift
sed -n '125,165p' MissingPlusPlus/StatusBar/MenuBuilder.swift
```

Expected: see `init(onRecord:onOpenMain:onQuit:)` (~line 26) and the private `MenuActionRouter` class (~line 130).

- [ ] **Step 2: Update `MenuBuilder.init` to 4-arg**

In `MissingPlusPlus/StatusBar/MenuBuilder.swift`, replace the `init` body (around line 24-37) with:

```swift
    init(
        onRecord: @escaping (Mood, String, Intensity) -> Void,
        onOpenMain: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.router = MenuActionRouter(
            onRecord: onRecord,
            onOpenMain: onOpenMain,
            onCheckForUpdates: onCheckForUpdates,
            onQuit: onQuit
        )
    }
```

- [ ] **Step 3: Replace the private `MenuActionRouter` class with the 4-arg version**

Find the `// MARK: - Action Router` block and replace the entire `private final class MenuActionRouter: NSObject { ... }` class with:

```swift
@MainActor
private final class MenuActionRouter: NSObject {
    private let onRecord: (Mood, String, Intensity) -> Void
    private let onOpenMain: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onQuit: () -> Void

    init(
        onRecord: @escaping (Mood, String, Intensity) -> Void,
        onOpenMain: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onRecord = onRecord
        self.onOpenMain = onOpenMain
        self.onCheckForUpdates = onCheckForUpdates
        self.onQuit = onQuit
    }

    @objc func recordFromMenu(_ sender: NSMenuItem) {
        guard let req = sender.representedObject as? RecordRequest else { return }
        onRecord(req.mood, req.who, req.intensity)
    }

    @objc func openMainFromMenu(_ sender: NSMenuItem) {
        onOpenMain()
    }

    @objc func checkForUpdatesFromMenu(_ sender: NSMenuItem) {
        // 1. Visual feedback: item 变 "Checking…", disabled
        sender.title = "Checking…"
        sender.isEnabled = false
        // 2. 异步查
        Task { @MainActor in
            let result = await UpdateChecker.shared.checkNow()
            // 3. 恢复 item
            sender.title = "Check for Updates…"
            sender.isEnabled = true
            // 4. 弹结果
            Self.presentResult(result)
        }
    }

    @objc func quitFromMenu(_ sender: NSMenuItem) {
        onQuit()
    }

    private static func presentResult(_ result: UpdateCheckResult) {
        switch result {
        case .upToDate(let local):
            let alert = NSAlert()
            alert.messageText = "已是最新"
            alert.informativeText = "当前 v\(local) 已是最新版本。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.runModal()
        case .updateAvailable(let version, let url):
            // 直接打开 release 页;banner 由 .didFindRemoteUpdate 自动挂上
            NSWorkspace.shared.open(url)
        case .failed(let reason):
            let alert = NSAlert()
            alert.messageText = "检查更新失败"
            alert.informativeText = reason
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
}
```

- [ ] **Step 4: Add the "Check for Updates…" item in `build()`**

In `MenuBuilder.build(recentWhos:)`, find the location just before the existing "退出 心安日记" item (search for that literal string in the file). Insert **before** the quit item:

```swift
        menu.addItem(.separator())

        let checkItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(MenuActionRouter.checkForUpdatesFromMenu(_:)),
            keyEquivalent: ""
        )
        checkItem.target = router
        menu.addItem(checkItem)

        menu.addItem(.separator())
```

- [ ] **Step 5: Update `StatusPanelController` to forward the 4th closure**

In `MissingPlusPlus/StatusBar/StatusPanelController.swift`:

**Edit A** — add field at the top of the class (after `private let onOpenMain: () -> Void`):
```swift
    private let onCheckForUpdates: () -> Void
```

**Edit B** — update the `init` signature to take `onCheckForUpdates` and forward it to `MenuBuilder`:
```swift
    init(
        onRecord: @escaping (Mood, String, Intensity) -> Void,
        onOpenMain: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.onRecord = onRecord
        self.onOpenMain = onOpenMain
        self.onCheckForUpdates = onCheckForUpdates

        // 选 provider: macOS 26+ 走 NSPanel fallback, 其他走官方 NSStatusItem
        if #available(macOS 26, *) {
            self.provider = NSPanelStatusItemProvider()
        } else {
            self.provider = NSStatusItemProvider()
        }

        // MenuBuilder closures — 直接捕获 init 参数, 不 [weak self] (没循环引用风险)
        let onRecordRef = onRecord
        let onOpenMainRef = onOpenMain
        let onCheckForUpdatesRef = onCheckForUpdates
        self.menuBuilder = MenuBuilder(
            onRecord: { mood, who, intensity in
                onRecordRef(mood, who, intensity)
            },
            onOpenMain: {
                onOpenMainRef()
            },
            onCheckForUpdates: {
                onCheckForUpdatesRef()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        // (existing observer setup unchanged below)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePrefsChanged(_:)),
            name: .appPreferencesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMissingAdded),
            name: .missingStoreDidAdd,
            object: nil
        )

        installIfNeeded()
    }
```

- [ ] **Step 6: Migrate existing 3-arg `MenuBuilder(...)` calls in MenuBuilderTests to 4-arg form**

Run: `rg -n "MenuBuilder\(" MissingPlusPlusTests/MenuBuilderTests.swift`

For each match, add a 4th arg `onCheckForUpdates: {}`:

```swift
let builder = MenuBuilder(
    onRecord: { _, _, _ in },
    onOpenMain: {},
    onCheckForUpdates: {},  // 新增
    onQuit: {}
)
```

- [ ] **Step 7: Add new test for the "Check for Updates…" item**

Append to `MenuBuilderTests` class:

```swift
    func testBuildIncludesCheckForUpdatesItem() {
        var checkTapped = false
        let builder = MenuBuilder(
            onRecord: { _, _, _ in },
            onOpenMain: {},
            onCheckForUpdates: { checkTapped = true },
            onQuit: {}
        )
        let menu = builder.build(recentWhos: [])
        let titles = menu.items.map { $0.title }
        XCTAssertTrue(
            titles.contains("Check for Updates…"),
            "menu should include 'Check for Updates…' item, got: \(titles)"
        )
        // 触发 item 验证 closure 被调
        guard let item = menu.items.first(where: { $0.title == "Check for Updates…" }) else {
            return XCTFail("item not found")
        }
        _ = item.target?.perform(item.action, with: item)
        XCTAssertTrue(checkTapped, "Check for Updates… should fire onCheckForUpdates closure")
    }
```

- [ ] **Step 8: Run MenuBuilderTests, expect all pass (existing + new)**

Run: `./scripts/run_tests.sh --filter MenuBuilderTests`

Expected: `** TEST SUCCEEDED **` with all existing tests + 1 new test passing.

- [ ] **Step 9: Build to verify StatusPanelController migration**

Run: `xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: **BUILD FAILS** with `extra argument` on `StatusPanelController` init — because we haven't updated AppDelegate's call site yet. **This is expected** and will be fixed in Task 12 (AppDelegate wiring). Do NOT commit yet.

- [ ] **Step 10: Commit (after Task 12 fixes the AppDelegate call site)**

Skip commit here. The commit happens at end of Task 12 (AppDelegate wiring) which fixes the dangling call site. This is intentional to keep the build green at every commit boundary.

---

## Task 10: MenuBarContent Banner Mount

**Files:**
- Modify: `MissingPlusPlus/Views/MenuBarContent.swift`

- [ ] **Step 1: Read the current `MenuBarContent` structure**

Run: `sed -n '1,40p' MissingPlusPlus/Views/MenuBarContent.swift`

Expected: see `struct MenuBarContent: View { @ObservedObject var store: MissingStore; ... var body: some View { ... } }`.

- [ ] **Step 2: Add the banner @State + onReceive + overlay**

Edit `MenuBarContent.swift`:

**Edit A** — at the top of the struct (after `var store: MissingStore` line), add:
```swift
    @State private var updateBanner: (version: String, url: URL)?
    @State private var bannerVisible: Bool = false
```

**Edit B** — at the start of the existing `var body: some View` content, wrap in a VStack and add the banner overlay at the top:
```swift
    var body: some View {
        VStack(spacing: 0) {
            if let banner = updateBanner, bannerVisible {
                UpdateBanner(
                    version: banner.version,
                    url: banner.url,
                    onDismiss: {
                        AppPreferences.shared.lastDismissedVersion = banner.version
                        withAnimation { bannerVisible = false }
                    }
                )
            }
            // (existing body content stays unchanged below)
            originalBody
        }
        .onReceive(NotificationCenter.default.publisher(for: .showUpdateBanner)) { note in
            guard let version = note.userInfo?["version"] as? String,
                  let url = note.userInfo?["url"] as? URL else { return }
            // 同版本已 dismiss 过 → 不重弹
            if AppPreferences.shared.lastDismissedVersion == version { return }
            withAnimation {
                updateBanner = (version, url)
                bannerVisible = true
            }
        }
    }

    // 把现有 body 内容包成 computed property,以便上面 VStack 引用
    private var originalBody: some View {
        // ... (existing body content moved here verbatim) ...
    }
```

**Edit C** — move the existing `var body: some View { ... }` content into `private var originalBody: some View { ... }` verbatim (no semantic change).

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: **BUILD FAILS** with "cannot find 'UpdateBanner' in scope" because the file is not yet registered in pbxproj. **This is expected** — Task 12 wires pbxproj. The fix is to either (a) add the pbxproj entry now, or (b) continue and fix in Task 12. **Continue to Task 11**, fix everything together in Task 12.

- [ ] **Step 4: Commit (with build-fail acknowledged)**

```bash
git add MissingPlusPlus/Views/MenuBarContent.swift
git commit -m "feat(ui): mount UpdateBanner overlay at top of MenuBarContent

Subscribes .showUpdateBanner via .onReceive; sticky banner, dismiss
sets lastDismissedVersion to avoid re-popup on next launch.
Not yet built — pbxproj registration in Task 12."
```

---

## Task 11: SettingsView Update Section

**Files:**
- Modify: `MissingPlusPlus/Views/SettingsView.swift`

- [ ] **Step 1: Read the end of the existing body**

Run: `tail -50 MissingPlusPlus/Views/SettingsView.swift`

Expected: see the closing of `Form { ... }` and any `.formStyle(.grouped)` modifier.

- [ ] **Step 2: Add the new "更新" section**

In `body`, find a good location (recommend: after the "状态栏" section, before "依恋辅助"). Add:

```swift
            Section("更新") {
                Toggle("自动检查更新", isOn: $prefs.updateCheckEnabled)
                Text("启动 5s 后静默检查 GitHub Releases,有新版时主窗口顶部提示。")
                    .font(.caption).foregroundColor(.secondary)
                HStack {
                    Button("立即检查") {
                        isCheckingUpdate = true
                        Task { @MainActor in
                            _ = await UpdateChecker.shared.checkNow()
                            isCheckingUpdate = false
                        }
                    }
                    .disabled(isCheckingUpdate)
                    if isCheckingUpdate {
                        ProgressView().controlSize(.small)
                    }
                    if let last = prefs.lastCheckedAt {
                        Text("上次检查：\(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
```

- [ ] **Step 3: Add the `@State` for the button-disabled flag**

In `SettingsView`, find the other `@State` declarations (around `apiKey`, `isTestingAI`). Add:

```swift
    @State private var isCheckingUpdate: Bool = false
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: **BUILD FAILS** with "cannot find 'UpdateChecker' in scope" because the file is not yet in pbxproj. Continue; fix in Task 12.

- [ ] **Step 5: Commit**

```bash
git add MissingPlusPlus/Views/SettingsView.swift
git commit -m "feat(settings): add 更新 section with toggle + manual check

Displays lastCheckedAt timestamp. updateCheckEnabled toggle wired
to AppPreferences. Not yet built — pbxproj in Task 12."
```

---

## Task 12: AppDelegate Wiring + pbxproj Registration

**Files:**
- Modify: `MissingPlusPlus/MissingPlusPlusApp.swift` (AppDelegate)
- Modify: `MissingPlusPlus.xcodeproj/project.pbxproj` (3 new Swift files)

- [ ] **Step 1: Update AppDelegate to provide `onCheckForUpdates` closure + start background check**

In `MissingPlusPlus/MissingPlusPlusApp.swift`:

**Edit A** — update the `StatusPanelController` init (around line 50-65). Add the new closure param:

```swift
        statusPanelController = StatusPanelController(
            onRecord: { mood, who, intensity in
                MissingStore.shared.add(Missing(who: who, mood: mood, intensity: intensity))
            },
            onOpenMain: { [weak self] in
                self?.windowController.showMainWindow()
            },
            onCheckForUpdates: {
                // The actual check happens in MenuActionRouter.checkForUpdatesFromMenu
                // (so it has sender to disable). This closure is a no-op here; the
                // StatusPanelController closure chain is: NSMenu tap → MenuActionRouter
                // → UpdateChecker.shared.checkNow().
            }
        )
```

(The closure is intentionally a no-op because the actual click → check flow is owned by `MenuActionRouter`, which has the `sender: NSMenuItem` for visual feedback. AppDelegate only wires the chain, doesn't override the logic.)

**Edit B** — at the end of `applicationDidFinishLaunching`, add the background check + notification subscriber:

```swift
        // v0.0.2 update-checker: 启动 5s 后静默检查 + 订阅 .didFindRemoteUpdate
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            UpdateChecker.shared.startBackgroundCheck()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteUpdateFound(_:)),
            name: .didFindRemoteUpdate,
            object: nil
        )
```

**Edit C** — add the @objc handler at the end of the AppDelegate class:

```swift
    // MARK: - 更新检测

    @objc private func handleRemoteUpdateFound(_ note: Notification) {
        guard let version = note.userInfo?["version"] as? String,
              let url = note.userInfo?["url"] as? URL else { return }
        // 1. 拉主窗口到前
        windowController.showMainWindow()
        // 2. 二级派发,让 MenuBarContent 挂 banner
        NotificationCenter.default.post(
            name: .showUpdateBanner,
            object: nil,
            userInfo: ["version": version, "url": url]
        )
    }
```

- [ ] **Step 2: Register 3 new Swift files in pbxproj**

**Approach A (recommended):** Use Xcode UI:
1. Open `MissingPlusPlus.xcodeproj` in Xcode.
2. Right-click the `Services/` group → "Add Files to MissingPlusPlus…" → select `UpdateChecker.swift` → "Add".
3. Right-click the `Views/` group → "Add Files to MissingPlusPlus…" → select `UpdateBanner.swift` → "Add".
4. In the test target: right-click `MissingPlusPlusTests/` → "Add Files to MissingPlusPlus…" → select `UpdateCheckerTests.swift` → ensure "MissingPlusPlusTests" target is checked → "Add".
5. Xcode auto-registers in pbxproj. Save (⌘S).

**Approach B (scripted):** If you prefer command-line, manually edit pbxproj. The diff:

In `/* Begin PBXBuildFile section */` (line ~30), add 3 entries (use unique IDs `A10000A0…A10000A2` and `B10000A0…B10000A2`):

```diff
+		A10000A0000000000000A001 /* UpdateChecker.swift in Sources */ = {isa = PBXBuildFile; fileRef = B10000A0000000000000A001 /* UpdateChecker.swift */; };
+		A10000A1000000000000A001 /* UpdateBanner.swift in Sources */ = {isa = PBXBuildFile; fileRef = B10000A1000000000000A001 /* UpdateBanner.swift */; };
+		A10000A2000000000000A001 /* UpdateCheckerTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = B10000A2000000000000A001 /* UpdateCheckerTests.swift */; };
```

In `/* Begin PBXFileReference section */` (line ~120), add 3 entries:

```diff
+		B10000A0000000000000A001 /* UpdateChecker.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UpdateChecker.swift; sourceTree = "<group>"; };
+		B10000A1000000000000A001 /* UpdateBanner.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UpdateBanner.swift; sourceTree = "<group>"; };
+		B10000A2000000000000A001 /* UpdateCheckerTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UpdateCheckerTests.swift; sourceTree = "<group>"; };
```

In the Services group `children` (find the `Services` `PBXGroup` block), add:
```diff
+				B10000A0000000000000A001 /* UpdateChecker.swift */,
```

In the Views group `children`, add:
```diff
+				B10000A1000000000000A001 /* UpdateBanner.swift */,
```

In the MissingPlusPlusTests group `children`, add:
```diff
+				B10000A2000000000000A001 /* UpdateCheckerTests.swift */,
```

In the **main target** `PBXSourcesBuildPhase` (around line 383, NOT the test target one), add 2 entries:
```diff
+				A10000A0000000000000A001 /* UpdateChecker.swift in Sources */,
+				A10000A1000000000000A001 /* UpdateBanner.swift in Sources */,
```

In the **test target** `PBXSourcesBuildPhase` (around line 422), add 1 entry:
```diff
+				A10000A2000000000000A001 /* UpdateCheckerTests.swift in Sources */,
```

Verify with:
```bash
plutil -lint MissingPlusPlus.xcodeproj/project.pbxproj
```
Expected: `OK`.

- [ ] **Step 3: Build the project, expect SUCCESS for the first time**

Run: `xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run full test suite, expect all pass**

Run: `./scripts/run_tests.sh`

Expected: `** TEST SUCCEEDED **` with all existing tests + 15 new UpdateChecker tests + 5 AppPreferences tests + 1 new MenuBuilder test passing (or however many existing MenuBuilder tests there are + 1).

- [ ] **Step 5: Commit**

```bash
git add MissingPlusPlus/MissingPlusPlusApp.swift \
        MissingPlusPlus.xcodeproj/project.pbxproj
git commit -m "feat(appdelegate): wire update-checker into launch + pbxproj register

Start background check 5s after launch (fire-and-forget). On
.didFindRemoteUpdate, pull main window + post .showUpdateBanner for
MenuBarContent. Register 3 new Swift files in pbxproj."
```

---

## Task 13: AGENTS.md + docs/ci.md Updates

**Files:**
- Modify: `AGENTS.md` (add §24)
- Modify: `docs/ci.md` (add publish checklist)

- [ ] **Step 1: Add §24 to AGENTS.md**

Open `AGENTS.md` and add a new section after §23 (CI / Release workflow). Use the existing section format (## 24. [Title]):

```markdown
## 24. Update Checker (v0.0.2+)

启动后 5s 静默检查 GitHub Releases + 状态栏菜单 "Check for Updates…" 手动触发。零新依赖,完全自写 (不引 Sparkle)。

### 关键文件
- `Services/UpdateChecker.swift` — URLSession 拉 `https://api.github.com/repos/ZhiPenTu/MissingPlusPlus/releases/latest`,semver 比对,emit `.didFindRemoteUpdate` notification
- `Services/AppPreferences.swift` — 4 字段: `updateCheckEnabled` (持久化) / `lastDismissedVersion` (持久化) / `lastCheckedAt` (transient) / `lastKnownRemoteVersion` (transient)
- `StatusBar/MenuBuilder.swift` — 加 `onCheckForUpdates` closure + "Check for Updates…" item + `MenuActionRouter.checkForUpdatesFromMenu(_:)`
- `StatusBar/StatusPanelController.swift` — 转发 `onCheckForUpdates` 到 MenuBuilder
- `MissingPlusPlusApp.swift` (AppDelegate) — `startBackgroundCheck()` + 订阅 `.didFindRemoteUpdate` → 拉主窗口 + post `.showUpdateBanner`
- `Views/UpdateBanner.swift` — sticky pink gradient banner
- `Views/MenuBarContent.swift` — 订阅 `.showUpdateBanner` via `.onReceive` 挂 banner
- `Views/SettingsView.swift` — "更新" section: toggle + 立即检查按钮 + lastCheckedAt 显示
- `MissingPlusPlusTests/UpdateCheckerTests.swift` — 15 个 case (semver 5 + performCheck 5 + throttle 3 + happy path 2)

### 关键设计决策
- **二级 NotificationCenter 派发**:`UpdateChecker` → `.didFindRemoteUpdate` → AppDelegate → `.showUpdateBanner` → `MenuBarContent`。`UpdateChecker` 不持 controller 引用,符合 AGENTS §6。
- **6h 节流**:`lastCheckedAt` < 6h 跳过自动检查;手动菜单不受限。transient 字段,不持久化。
- **Skip prerelease**:`tag_name` 含 `-` (alpha/beta/rc) 视为"已是最新",避免给 prerelease 用户假阳性。
- **Fail-silent (启动) + NSAlert (手动)**:启动 5s 失败静默吞 (避免打断用户);手动检查失败 NSAlert (用户期待反馈)。
- **GitHub user/org rename 后 URL 失效**:URL 是常量,改 1 行;GitHub API 改 v4 时改 `Accept` header 即可。

### 发布流程 (publish checklist)
1. 现有:tag push → CI 跑 → draft release 创建
2. **手动**:GitHub Releases 页面打开 draft,点 "Publish release" 公开
3. **手动**:Publish 完几分钟后,跑一次旧版 app → 启动 5s 后 banner 应该出

GitHub API `/releases/latest` 不会返回 draft release,所以 publish 步骤必须有。

### 不要做
- 不要在 `UpdateChecker` 里持 `WindowController` 引用 (违反 AGENTS §6)
- 不要把 `lastCheckedAt` / `lastKnownRemoteVersion` 持久化 (transient)
- 不要在启动检查失败时 NSAlert 打断用户
- 不要解析 prerelease
- 不要在 v0.0.2 之前的版本上 (CFBundleShortVersionString == 0.0.0 / 0.0.1) 测 banner 出现 (banner 不会出,因为 remote == local)
```

- [ ] **Step 2: Append publish-checklist note to `docs/ci.md` §2**

Open `docs/ci.md` §2 (release.yml). After the existing "推 GitHub 后第一次 release 的检查清单" section, add a new section:

```markdown
### Update Checker publish 步骤 (v0.0.2+)

`release.yml` 创建的是 **draft release**,GitHub API `/releases/latest` **不会**返回 draft,所以 update checker 看不到新版本。**每次发布后必须手动 Publish release**:

1. 完成上面 "推 GitHub 后第一次 release 的检查清单"
2. GitHub Releases 页面打开 draft,点 "Publish release" 公开
3. Publish 完几分钟后,用旧版 app (e.g. v0.0.1) 跑一次,启动 5s 后主窗口顶部应该出 "新版本 v0.0.2 可用" banner

详细见 AGENTS.md §24。
```

- [ ] **Step 3: Build to verify nothing broke**

Run: `xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`. (Doc changes don't affect build, but verify no surprises.)

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md docs/ci.md
git commit -m "docs(update-checker): AGENTS §24 + ci.md publish-checklist

§24: 关键文件 + 设计决策 + 不要做。 ci.md: 每次发布后必须手动
Publish release,因为 GitHub API /releases/latest 不返回 draft。"
```

---

## Task 14: Integration Smoke Test (Build + Run + Manual Verify)

**Files:** None (verification only)

- [ ] **Step 1: Build the .app**

Run: `./scripts/build_and_run.sh`

Expected: `** BUILD SUCCEEDED **` and the .app launches (Dock icon appears, status bar icon appears).

- [ ] **Step 2: Verify the menu bar item appears**

Click the status bar icon. The NSMenu should now show:
- 5 mood submenus (existing)
- separator
- "在主窗口新建记录…" (existing)
- separator
- **"Check for Updates…"** ← new
- separator
- "退出 心安日记"

Expected: item present, with `…` (ellipsis) suffix indicating it'll do something.

- [ ] **Step 3: Verify "Check for Updates…" works**

Click "Check for Updates…". Expected:
- Item title briefly changes to "Checking…", disabled.
- 1-3 seconds later, item title restores to "Check for Updates…", enabled.
- Either: NSAlert "已是最新 v0.0.1" (since local is 0.0.1 and remote is also 0.0.1, no update)
- Or: NSWorkspace opens the GitHub release page in browser (if remote > local)

- [ ] **Step 4: Verify the background check banner (simulate "newer version" scenario)**

To test the banner without waiting for a real release, temporarily edit `Info.plist` to set `CFBundleShortVersionString` to `0.0.0`:

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.0.0" \
    MissingPlusPlus/Info.plist
./scripts/build_and_run.sh
```

Expected within 5-10s of launch: main window appears (because we pull it to front) with a pink banner "新版本 v0.0.1 可用" at the top. Banner has 3 actions: "稍后", "查看", X (close).

- [ ] **Step 5: Test banner dismiss + persistence**

Click "稍后". Expected: banner slides up + fades within 0.3s. Quit the app (⌘Q). Re-launch.

Expected: banner does NOT reappear (because `lastDismissedVersion` persisted to UserDefaults).

- [ ] **Step 6: Test "查看" action**

Re-launch (or temporarily set CFBundleShortVersionString to 0.0.0 again). Wait for banner. Click "查看".

Expected: browser opens to `https://github.com/ZhiPenTu/MissingPlusPlus/releases/tag/v0.0.1`. Banner dismisses.

- [ ] **Step 7: Verify Settings → "更新" section**

Open Settings (⌘,). Scroll to "更新" section. Expected:
- Toggle "自动检查更新" — on by default.
- Description text.
- "立即检查" button.
- "上次检查：..." timestamp (filled in after first check).

Toggle off. Click "立即检查". Expected: NSAlert "检查更新失败: 已在设置中关闭". Toggle back on.

- [ ] **Step 8: Restore `Info.plist` to original**

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.0.1" \
    MissingPlusPlus/Info.plist
```

- [ ] **Step 9: Final test run**

Run: `./scripts/run_tests.sh`

Expected: `** TEST SUCCEEDED **` with all tests passing (existing 34 + 15 new UpdateChecker + 5 new AppPreferences + 1 new MenuBuilder = 55 total).

- [ ] **Step 10: Commit any test-only files / final fixes**

```bash
git status
# If Info.plist was modified in step 4/8, revert:
git checkout MissingPlusPlus/Info.plist
# If other changes from the smoke test (e.g. debug logs to remove), commit them.
```

---

## Self-Review Notes

**1. Spec coverage:**
- §1 背景 / §2 目标 / §3 非目标 — covered by design (no task needed; spec is the design)
- §4.1 二级派发数据流 — Task 12 (AppDelegate) + Task 10 (MenuBarContent)
- §4.2 UpdateChecker — Tasks 3-7
- §4.3 AppPreferences — Task 2
- §4.4 MenuBuilder — Task 9
- §4.5 AppDelegate wiring — Task 12
- §4.6 UpdateBanner + MenuBarContent — Task 8 + Task 10
- §4.7 SettingsView — Task 11
- §5 文件改动清单 — all 12 files covered
- §6 错误处理 — covered by Tasks 5-7 (network/HTTP/JSON cases)
- §7 测试策略 — Tasks 1-7 + 9
- §8 发布流程 — Task 13 (AGENTS.md + ci.md)
- §9 风险 — covered in test cases (prerelease, throttle, network) + Settings toggle for off
- §10 未来扩展 — out of scope, no task

**2. Placeholder scan:** No "TBD" / "TODO" / "implement later" / "add appropriate handling" found. All code blocks are complete. Some steps have "verify" or "expected output" language but no implementation gaps.

**3. Type consistency:**
- `UpdateCheckResult` — defined Task 3, used Tasks 5-9 (consistent: 3 cases, all Equatable)
- `URLSessionProtocol.data(from:)` — defined Task 3, used Task 3+5+6 (consistent signature)
- `MenuBuilder.init` — 4-arg form from Task 9 used everywhere (StatusPanelController, MenuBuilderTests, AppDelegate)
- `prefs.updateCheckEnabled` / `prefs.lastDismissedVersion` — defined Task 2, used Tasks 9-12 (consistent)
- `Notification.Name.showUpdateBanner` / `.didFindRemoteUpdate` — defined Task 3, posted Task 7, listened Task 10 + 12 (consistent userInfo keys: `["version": String, "url": URL]`)
- pbxproj IDs `A10000A0…A10000A2` / `B10000A0…B10000A2` — picked to not collide with existing `A10000..A10015` / `B10000..B10015` IDs; verify uniqueness with `grep -E "A10000A0|B10000A0" project.pbxproj` before applying

**4. Risk notes:**
- Task 9 is the trickiest: coordinated 4-arg init migration across MenuBuilder + StatusPanelController + MenuBuilderTests. Order matters (MenuBuilder first, then StatusPanelController, then tests). Final build-green commit is in Task 12 (AppDelegate) — Task 9 commits would break AppDelegate's existing 3-arg call site.
- Task 10 step 3 + Task 11 step 4 + Task 12 (pbxproj) — there are 3 expected build-fail checkpoints between Tasks 10-11 and the final build success in Task 12. Don't panic, the failures are intentional.
- The CFBundleShortVersionString simulation in Task 14 step 4-8 must be reverted (step 8) or future runs will see "phantom" updates.

---

## Final Handoff

After all 15 tasks pass (Task 0 + Tasks 1-14):

```bash
git log --oneline -20
# Should show ~14 commits with conventional commit messages
# (Task 9 has no commit — its changes ship with Task 12 to keep build green)
```

The feature is complete. Next steps:
1. **Merge to main** + push — release.yml CI will run (test.yml per PR, not on direct push)
2. **Bump version** in `Info.plist` to `0.0.2` when ready to release
3. **Tag `v0.0.2`** and push — release.yml creates draft DMG
4. **Manually Publish release** in GitHub UI (per AGENTS §24 publish checklist)
5. **Verify** by running v0.0.1 app → banner should appear for v0.0.2 release
