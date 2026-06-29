import Foundation
import AppKit

/// Manages the on-disk location for `missings.json`.
///
/// Responsibilities:
///   * Resolve the active storage URL on launch (security-scoped bookmark
///     if the user previously picked a folder, otherwise the default
///     `~/Library/Application Support/MissingPlusPlus/missings.json`).
///   * Persist a security-scoped bookmark to UserDefaults when the user
///     picks a new folder, so the choice survives app restarts.
///   * Detect whether the current URL is on iCloud Drive (path lives under
///     `~/Library/Mobile Documents/...`) so the settings UI can show an
///     "iCloud" badge.
///   * Coordinate reads/writes through `NSFileCoordinator` so iCloud Drive
///     can upload the file cleanly.
///
/// `MissingStore` owns the in-memory list and calls into this service for
/// every disk operation; the service itself never touches the data model.
@MainActor
final class StorageService: ObservableObject {
    static let shared = StorageService()

    /// Where `missings.json` currently lives. Never nil — falls back to the
    /// default Application Support path on first launch.
    @Published private(set) var currentURL: URL

    /// True when the user has picked a folder that's *not* the default
    /// location. Drives the "Reset to default" button in settings.
    @Published private(set) var isCustom: Bool = false

    /// True when the current path lives under iCloud Drive
    /// (`~/Library/Mobile Documents/...`). The settings UI uses this to
    /// show a small iCloud badge.
    @Published private(set) var isOniCloud: Bool = false

    private let defaultURL: URL
    private let bookmarkKey = "MissingPlusPlus.StorageBookmark"
    private var activeSecurityScopedURL: URL?

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let dir = appSupport.appendingPathComponent("MissingPlusPlus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaultURL = dir.appendingPathComponent("missings.json")
        self.defaultURL = defaultURL
        self.currentURL = defaultURL

        // Resolve any persisted bookmark from a previous launch.
        if let resolved = resolvePersistedBookmark() {
            applyURL(resolved, isCustom: true)
        } else {
            // Even for the default URL, detect iCloud (extremely unlikely
            // but harmless) so the badge is honest.
            isOniCloud = defaultURL.path.contains("Mobile Documents")
        }
    }

    // MARK: - Public API used by MissingStore

    /// Read the current file via NSFileCoordinator. Returns nil if the
    /// file doesn't exist or can't be decoded.
    func readItems() -> [Missing]? {
        let url = currentURL
        var coordError: NSError?
        var result: [Missing]?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
            guard let data = try? Data(contentsOf: coordinatedURL) else { return }
            result = try? JSONDecoder().decode([Missing].self, from: data)
        }
        if let coordError {
            NSLog("[MissingPlusPlus] StorageService read coord error: \(coordError)")
        }
        return result
    }

    /// Write the current items atomically via NSFileCoordinator.
    func writeItems(_ items: [Missing]) {
        let url = currentURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(items) else { return }
        var coordError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordError
        ) { coordinatedURL in
            try? data.write(to: coordinatedURL, options: .atomic)
        }
        if let coordError {
            NSLog("[MissingPlusPlus] StorageService write coord error: \(coordError)")
        }
    }

    // MARK: - Settings mutations

    /// Switch the active storage URL to a user-picked folder.
    ///
    /// If the new URL has no `missings.json` and the current store has
    /// data, the existing data is *copied* into the new location so the
    /// user doesn't lose their records just by changing folders. If the
    /// new URL already has data, we leave it alone — the caller
    /// (settings UI) is expected to ask the user whether to merge or
    /// replace before getting here.
    func setStorageURL(_ newURL: URL, copyCurrentData currentItems: [Missing]) {
        if let old = activeSecurityScopedURL {
            old.stopAccessingSecurityScopedResource()
            activeSecurityScopedURL = nil
        }

        let candidate = newURL.appendingPathComponent("missings.json", isDirectory: false)
        if !FileManager.default.fileExists(atPath: candidate.path) {
            if !currentItems.isEmpty {
                try? FileManager.default.createDirectory(
                    at: newURL,
                    withIntermediateDirectories: true
                )
                if let data = try? JSONEncoder().encode(currentItems) {
                    try? data.write(to: candidate, options: .atomic)
                }
            } else {
                try? FileManager.default.createDirectory(
                    at: newURL,
                    withIntermediateDirectories: true
                )
            }
        }

        if let bookmark = try? newURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        }

        if newURL.startAccessingSecurityScopedResource() {
            activeSecurityScopedURL = newURL
        }

        applyURL(candidate, isCustom: true)
    }

    /// Reset to the default `~/Library/Application Support/...` location.
    /// Existing data at the default location is preserved.
    func resetToDefault(currentItems: [Missing]) {
        if let old = activeSecurityScopedURL {
            old.stopAccessingSecurityScopedResource()
            activeSecurityScopedURL = nil
        }
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        if !FileManager.default.fileExists(atPath: defaultURL.path),
           !currentItems.isEmpty,
           let data = try? JSONEncoder().encode(currentItems) {
            try? data.write(to: defaultURL, options: .atomic)
        }
        applyURL(defaultURL, isCustom: false)
    }

    // MARK: - Import / export helpers

    /// Export the given items to a user-chosen file URL.
    func exportItems(_ items: [Missing], to destination: URL) -> Bool {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: destination, options: .atomic)
            return true
        } catch {
            NSLog("[MissingPlusPlus] export failed: \(error)")
            return false
        }
    }

    /// Read items from a user-chosen file URL. Returns nil if the file
    /// can't be parsed as `[Missing]`.
    func importItems(from source: URL) -> [Missing]? {
        guard let data = try? Data(contentsOf: source) else { return nil }
        return try? JSONDecoder().decode([Missing].self, from: data)
    }

    /// Suggested filename for an export, e.g. `MissingPlusPlus-2026-06-25.json`.
    static func suggestedExportFilename(now: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "zh_CN")
        return "MissingPlusPlus-\(fmt.string(from: now)).json"
    }

    // MARK: - Internals

    private func applyURL(_ url: URL, isCustom: Bool) {
        currentURL = url
        self.isCustom = isCustom
        isOniCloud = url.path.contains("Mobile Documents")
    }

    private func resolvePersistedBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if url.startAccessingSecurityScopedResource() {
                activeSecurityScopedURL = url
                return url.appendingPathComponent("missings.json", isDirectory: false)
            } else {
                NSLog("[MissingPlusPlus] bookmark resolved but security scope denied")
                return nil
            }
        } catch {
            NSLog("[MissingPlusPlus] bookmark resolution failed: \(error)")
            return nil
        }
    }
}
