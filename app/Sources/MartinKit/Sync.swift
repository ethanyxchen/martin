import CryptoKit
import Foundation

public struct SyncRecord: Hashable, Sendable {
    public struct Key: Hashable, Sendable {
        public let kind: Kind
        public let id: String

        public init(kind: Kind, id: String) {
            self.kind = kind
            self.id = id
        }

        var name: String { "\(kind.rawValue)/\(id)" }
    }

    public enum Kind: String, Codable, Sendable {
        case meeting
        case project
    }

    public let key: Key
    public let data: Data?
    public let editedAt: Date

    public init(key: Key, data: Data?, editedAt: Date) {
        self.key = key
        self.data = data
        self.editedAt = editedAt
    }
}

public struct SyncChange: Hashable, Sendable {
    public let record: SyncRecord
    public let updatedAt: Date

    public init(record: SyncRecord, updatedAt: Date) {
        self.record = record
        self.updatedAt = updatedAt
    }
}

public struct SyncServer: Sendable {
    public var pull: @Sendable (_ after: Date?) async throws -> [SyncChange]
    public var push: @Sendable ([SyncRecord]) async throws -> Void
    public var upload: @Sendable (_ path: String, Data) async throws -> Void
    public var download: @Sendable (_ path: String) async throws -> Data
    public var removeImages: @Sendable (Meeting.ID) async throws -> Void

    public init(
        pull: @escaping @Sendable (Date?) async throws -> [SyncChange],
        push: @escaping @Sendable ([SyncRecord]) async throws -> Void,
        upload: @escaping @Sendable (String, Data) async throws -> Void,
        download: @escaping @Sendable (String) async throws -> Data,
        removeImages: @escaping @Sendable (Meeting.ID) async throws -> Void
    ) {
        self.pull = pull
        self.push = push
        self.upload = upload
        self.download = download
        self.removeImages = removeImages
    }
}

public struct Sync: Sendable {
    static let overlap: TimeInterval = 60

    public let library: MeetingLibrary
    public let server: SyncServer
    public let user: String

    public init(library: MeetingLibrary, server: SyncServer, user: String) {
        self.library = library
        self.server = server
        self.user = user
    }

    private var stateFile: URL { library.root.appending(path: "sync.json") }

    @discardableResult
    public func run() async throws -> Set<SyncRecord.Key> {
        let now = Date.now
        var state = loadState()
        var local = try library.syncRecords()
        var applied: Set<SyncRecord.Key> = []
        for change in try await server.pull(state.cursor.map { $0 - Self.overlap }).sorted(by: { $0.updatedAt < $1.updatedAt }) {
            state.cursor = max(state.cursor ?? .distantPast, change.updatedAt)
            let remote = change.record
            let theirs = try remote.data.map { try library.canonical(remote.key.kind, $0) }
            let mine = local[remote.key]
            guard mine?.data != theirs else {
                state.synced[remote.key.name] = theirs.map(Self.hash)
                continue
            }
            let editedHere = mine?.data.map(Self.hash) != state.synced[remote.key.name]
            if editedHere, (mine?.editedAt ?? now) > remote.editedAt { continue }
            try library.apply(SyncRecord(key: remote.key, data: theirs, editedAt: remote.editedAt))
            local[remote.key] = theirs.map { SyncRecord(key: remote.key, data: $0, editedAt: remote.editedAt) }
            state.synced[remote.key.name] = theirs.map(Self.hash)
            applied.insert(remote.key)
        }
        let keys = Set(local.keys).union(state.synced.keys.compactMap(SyncRecord.Key.init(name:)))
        let outgoing = keys.filter { local[$0]?.data.map(Self.hash) != state.synced[$0.name] }
            .map { local[$0] ?? SyncRecord(key: $0, data: nil, editedAt: now) }
        for record in outgoing where record.key.kind == .meeting && record.data != nil {
            try await uploadImages(of: record.key.id, into: &state)
        }
        if !outgoing.isEmpty { try await server.push(outgoing) }
        for record in outgoing {
            state.synced[record.key.name] = record.data.map(Self.hash)
            guard record.key.kind == .meeting, record.data == nil else { continue }
            try await server.removeImages(record.key.id)
            state.images = state.images.filter { !$0.hasPrefix(record.key.id + "/") }
        }
        for key in applied where key.kind == .meeting && local[key] != nil {
            try await downloadImages(of: key.id, into: &state)
        }
        try save(state)
        return applied
    }

    public func forget() throws {
        guard FileManager.default.fileExists(atPath: stateFile.path) else { return }
        try FileManager.default.removeItem(at: stateFile)
    }

    private func uploadImages(of meeting: Meeting.ID, into state: inout State) async throws {
        let folder = library.meetingFolder(meeting).appending(path: "images", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let path = "\(meeting)/images/\(file.lastPathComponent)"
            guard !state.images.contains(path) else { continue }
            try await server.upload(path, Data(contentsOf: file))
            state.images.insert(path)
        }
    }

    private func downloadImages(of meeting: Meeting.ID, into state: inout State) async throws {
        let folder = library.meetingFolder(meeting)
        let images = NoteImages(meetingFolder: folder)
        let note = (try? String(contentsOf: folder.appending(path: "note.md"), encoding: .utf8)) ?? ""
        for path in Set(note.components(separatedBy: .newlines).compactMap { NoteImage(line: $0)?.path }) {
            guard let file = images.url(for: path), !FileManager.default.fileExists(atPath: file.path) else { continue }
            let remote = "\(meeting)/\(path)"
            guard let data = try? await server.download(remote) else { continue }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            state.images.insert(remote)
        }
    }

    private struct State: Codable {
        var user: String
        var cursor: Date?
        var synced: [String: String] = [:]
        var images: Set<String> = []
    }

    private func loadState() -> State {
        let saved = (try? Data(contentsOf: stateFile)).flatMap { try? MeetingLibrary.decoder.decode(State.self, from: $0) }
        return saved?.user == user ? saved! : State(user: user)
    }

    private func save(_ state: State) throws {
        try FileManager.default.createDirectory(at: library.root, withIntermediateDirectories: true)
        try MeetingLibrary.encoder.encode(state).write(to: stateFile, options: .atomic)
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension SyncRecord.Key {
    init?(name: String) {
        let parts = name.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = SyncRecord.Kind(rawValue: parts[0]) else { return nil }
        self.init(kind: kind, id: parts[1])
    }
}

private struct SyncedMeeting: Codable {
    let meeting: Meeting
    let note: String
}

extension MeetingLibrary {
    func syncRecords() throws -> [SyncRecord.Key: SyncRecord] {
        var records: [SyncRecord.Key: SyncRecord] = [:]
        for meeting in try meetings() {
            let key = SyncRecord.Key(kind: .meeting, id: meeting.id)
            let editedAt = [folder(of: meeting).appending(path: "meeting.json"), noteFile(of: meeting)].compactMap(Self.modified).max() ?? .distantPast
            records[key] = try SyncRecord(key: key, data: Self.encoder.encode(SyncedMeeting(meeting: meeting, note: note(of: meeting) ?? "")), editedAt: editedAt)
        }
        let editedAt = Self.modified(projectsFile) ?? .distantPast
        for project in try projects() {
            let key = SyncRecord.Key(kind: .project, id: project.id)
            records[key] = try SyncRecord(key: key, data: Self.encoder.encode(project.synced), editedAt: editedAt)
        }
        return records
    }

    func canonical(_ kind: SyncRecord.Kind, _ data: Data) throws -> Data {
        switch kind {
        case .meeting: try Self.encoder.encode(Self.decoder.decode(SyncedMeeting.self, from: data))
        case .project: try Self.encoder.encode(Self.decoder.decode(Project.self, from: data).synced)
        }
    }

    func apply(_ record: SyncRecord) throws {
        switch (record.key.kind, record.data) {
        case (.meeting, let data?):
            let synced = try Self.decoder.decode(SyncedMeeting.self, from: data)
            try FileManager.default.createDirectory(at: folder(of: synced.meeting), withIntermediateDirectories: true)
            try save(synced.meeting)
            try saveNote(synced.note, for: synced.meeting)
        case (.meeting, nil):
            let folder = meetingFolder(record.key.id)
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        case (.project, let data?):
            var project = try Self.decoder.decode(Project.self, from: data)
            let known = try projects()
            project.repository = known.first { $0.id == project.id }?.repository
            try save(known.contains { $0.id == project.id } ? known.map { $0.id == project.id ? project : $0 } : known + [project])
        case (.project, nil):
            try forget(project: record.key.id)
        }
    }

    func meetingFolder(_ id: Meeting.ID) -> URL {
        meetingsFolder.appending(path: id, directoryHint: .isDirectory)
    }

    private static func modified(_ file: URL) -> Date? {
        try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

private extension Project {
    var synced: Project {
        var synced = self
        synced.repository = nil
        return synced
    }
}
