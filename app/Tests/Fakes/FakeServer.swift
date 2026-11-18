import Foundation
import MartinKit
import os

public final class FakeServer: Sendable {
    public init() {}

    private struct Store {
        var rows: [String: [SyncRecord.Key: SyncChange]] = [:]
        public var images: [String: Data] = [:]
        public var pushed: [SyncRecord] = []
        var pushes = 0
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private let store = OSAllocatedUnfairLock(initialState: Store())

    public var images: [String: Data] { store.withLock(\.images) }
    public var pushed: [SyncRecord] { store.withLock(\.pushed) }
    public var pushes: Int { store.withLock(\.pushes) }

    public func syncServer(for user: String) -> SyncServer {
        SyncServer { after in
            self.store.withLock { store in store.rows[user, default: [:]].values.filter { after == nil || $0.updatedAt > after! } }
        } push: { records in
            self.store.withLock { store in
                store.pushes += 1
                for record in records where store.rows[user]?[record.key].map({ record.editedAt >= $0.record.editedAt }) ?? true {
                    store.clock += 1
                    store.rows[user, default: [:]][record.key] = SyncChange(record: record, updatedAt: store.clock)
                    store.pushed.append(record)
                }
            }
        } upload: { path, data in
            self.store.withLock { $0.images[path] = data }
        } download: { path in
            try self.store.withLock { store in
                guard let data = store.images[path] else { throw CocoaError(.fileNoSuchFile) }
                return data
            }
        } removeImages: { meeting in
            self.store.withLock { $0.images = $0.images.filter { !$0.key.hasPrefix(meeting + "/") } }
        }
    }
}
