import Foundation
import SwiftUI

extension Notification.Name {
    static let missingStoreDidAdd = Notification.Name("MissingStoreDidAdd")
    static let missingStoreDidImport = Notification.Name("MissingStoreDidImport")
    /// Posted by `MissingStore` when a record is mutated in place
    /// (resolved stamped, reality check attached, triggers updated).
    /// `userInfo: ["missing": Missing]` carries the updated record.
    static let missingStoreDidUpdate = Notification.Name("MissingStoreDidUpdate")
    /// Posted by views (e.g. the popover overflow menu) when the user
    /// wants the settings window to open. `AppDelegate` listens for this
    /// and shows / raises the settings window.
    static let openSettings = Notification.Name("MissingPlusPlusOpenSettings")
}

@MainActor
final class MissingStore: ObservableObject {
    static let shared = MissingStore()

    @Published private(set) var items: [Missing] = []
    @Published private(set) var knownWhos: [String] = []

    /// The disk location is owned by `StorageService`. We don't hold our
    /// own `fileURL` anymore — every load/save goes through the service
    /// so the user can change the storage path from settings and the
    /// store transparently follows.
    private let storage: StorageService

    private init() {
        // The default-value `StorageService = .shared` shorthand doesn't
        // work here: default-value expressions are evaluated outside the
        // @MainActor context, so the `shared` access becomes a
        // Swift-6-mode error. Fetch the singleton inside the body instead.
        self.storage = StorageService.shared
        load()
    }

    // MARK: - Mutations

    func add(_ missing: Missing) {
        items.append(missing)
        rebuildKnownWhos()
        save()
        NotificationCenter.default.post(name: .missingStoreDidAdd, object: self, userInfo: ["missing": missing])
    }

    func delete(_ missing: Missing) {
        items.removeAll { $0.id == missing.id }
        rebuildKnownWhos()
        save()
    }

    /// Stamp `resolvedAt` on the given record (default: now). Idempotent — calling
    /// again resets the stamp. Posts `.missingStoreDidUpdate` so views (HistoryList /
    /// StatisticsView) re-render.
    func markResolved(_ missing: Missing, at date: Date = Date()) {
        guard let idx = items.firstIndex(where: { $0.id == missing.id }) else { return }
        items[idx].resolvedAt = date
        save()
        NotificationCenter.default.post(
            name: .missingStoreDidUpdate, object: self,
            userInfo: ["missing": items[idx]]
        )
    }

    /// Attach a reality check to the given record. Posts `.missingStoreDidUpdate`.
    func attachRealityCheck(_ missing: Missing, check: RealityCheck) {
        guard let idx = items.firstIndex(where: { $0.id == missing.id }) else { return }
        items[idx].realityCheck = check
        save()
        NotificationCenter.default.post(
            name: .missingStoreDidUpdate, object: self,
            userInfo: ["missing": items[idx]]
        )
    }

    /// Update trigger tags on the given record. Posts `.missingStoreDidUpdate`.
    func updateTriggers(_ missing: Missing, tags: [TriggerTag]) {
        guard let idx = items.firstIndex(where: { $0.id == missing.id }) else { return }
        items[idx].triggerTags = tags
        save()
        NotificationCenter.default.post(
            name: .missingStoreDidUpdate, object: self,
            userInfo: ["missing": items[idx]]
        )
    }

    /// Replace the in-memory list wholesale and persist. Used by import
    /// (after the user confirms a merge / replace).
    func replaceAll(with newItems: [Missing]) {
        items = newItems
        rebuildKnownWhos()
        save()
    }

    /// Merge items into the existing list, deduping by `id`. New items
    /// (those whose id is not already present) are appended in the order
    /// they appear in `incoming`. Returns the number of items that were
    /// actually added.
    @discardableResult
    func merge(_ incoming: [Missing]) -> Int {
        let existingIDs = Set(items.map(\.id))
        let new = incoming.filter { !existingIDs.contains($0.id) }
        guard !new.isEmpty else { return 0 }
        items.append(contentsOf: new)
        rebuildKnownWhos()
        save()
        NotificationCenter.default.post(
            name: .missingStoreDidImport,
            object: self,
            userInfo: ["count": new.count]
        )
        return new.count
    }

    /// Wipe everything. Persists the empty list to disk.
    func clearAll() {
        items = []
        knownWhos = []
        save()
    }

    var sortedItems: [Missing] {
        items.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Disk

    /// Re-read the on-disk file. Called by `StorageService` (and from the
    /// app delegate) when the storage URL has just been changed, so the
    /// store picks up whatever lives at the new location.
    func reloadFromDisk() {
        load()
    }

    private func rebuildKnownWhos() {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in items.reversed() {
            let key = item.who.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, seen.insert(key).inserted {
                ordered.append(key)
            }
        }
        knownWhos = ordered
    }

    private func load() {
        if let decoded = storage.readItems() {
            items = decoded
            rebuildKnownWhos()
        }
    }

    private func save() {
        storage.writeItems(items)
    }
}
