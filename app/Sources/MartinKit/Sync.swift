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
    nonisolated(nonsending) public func run() async throws -> Set<SyncRecord.Key> {
        var state = loadState()
        try notice(library.syncData(), in: &state)
        try save(state)
        var applied: Set<SyncRecord.Key> = []
        for change in try await server.pull(state.cursor.map { $0 - Self.overlap }).sorted(by: { $0.updatedAt < $1.updatedAt }) {
            state.cursor = max(state.cursor ?? .distantPast, change.updatedAt)
            let remote = change.record
            let theirs = try remote.data.map { try library.canonical(remote.key.kind, $0) }
            let mine = try library.syncData(for: remote.key)
            let editedHere = mine.map(Self.hash) != state.synced[remote.key.name]
            if mine != theirs, editedHere, editedAt(remote.key, mine, state) > remote.editedAt { continue }
            if mine != theirs {
                try library.apply(SyncRecord(key: remote.key, data: theirs, editedAt: remote.editedAt))
                applied.insert(remote.key)
                if remote.key.kind == .meeting, theirs != nil { state.missing.insert(remote.key.id) }
            }
            state.synced[remote.key.name] = theirs.map(Self.hash)
            state.changedAt[remote.key.name] = nil
        }
        let local = try library.syncData()
        notice(local, in: &state)
        let outgoing = changed(local, state).map { SyncRecord(key: $0, data: local[$0], editedAt: editedAt($0, local[$0], state)) }
        for record in outgoing where record.key.kind == .meeting && record.data != nil {
            try await uploadImages(of: record.key.id, into: &state)
        }
        if !outgoing.isEmpty { try await server.push(outgoing) }
        for record in outgoing {
            state.synced[record.key.name] = record.data.map(Self.hash)
            state.changedAt[record.key.name] = nil
            guard record.key.kind == .meeting, record.data == nil else { continue }
            try await server.removeImages(record.key.id)
            state.images = state.images.filter { !$0.hasPrefix(record.key.id + "/") }
        }
        for meeting in state.missing {
            let complete = local[SyncRecord.Key(kind: .meeting, id: meeting)] == nil ? true : try await downloadImages(of: meeting, into: &state)
            if complete { state.missing.remove(meeting) }
        }
        try save(state)
        return applied
    }

    public func forget() throws {
        guard FileManager.default.fileExists(atPath: stateFile.path) else { return }
        try FileManager.default.removeItem(at: stateFile)
    }

    private func changed(_ local: [SyncRecord.Key: Data], _ state: State) -> [SyncRecord.Key] {
        Set(local.keys).union(state.synced.keys.compactMap(SyncRecord.Key.init(name:)))
            .filter { local[$0].map(Self.hash) != state.synced[$0.name] }
    }

    private func notice(_ local: [SyncRecord.Key: Data], in state: inout State) {
        let now = Date.now
        for key in changed(local, state) where state.changedAt[key.name] == nil {
            state.changedAt[key.name] = now
        }
    }

    private func editedAt(_ key: SyncRecord.Key, _ data: Data?, _ state: State) -> Date {
        if key.kind == .meeting, data != nil, let modified = library.modified(meeting: key.id) { return modified }
        return state.changedAt[key.name] ?? .now
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

    private func downloadImages(of meeting: Meeting.ID, into state: inout State) async throws -> Bool {
        let folder = library.meetingFolder(meeting)
        let images = NoteImages(meetingFolder: folder)
        let note = (try? String(contentsOf: folder.appending(path: "note.md"), encoding: .utf8)) ?? ""
        var complete = true
        for path in Set(note.components(separatedBy: .newlines).compactMap { NoteImage(line: $0)?.path }) {
            guard let file = images.url(for: path), !FileManager.default.fileExists(atPath: file.path) else { continue }
            let remote = "\(meeting)/\(path)"
            guard let data = try? await server.download(remote) else {
                complete = false
                continue
            }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            state.images.insert(remote)
        }
        return complete
    }

    private struct State: Codable {
        var user: String
        var cursor: Date?
        var synced: [String: String] = [:]
        var changedAt: [String: Date] = [:]
        var images: Set<String> = []
        var missing: Set<Meeting.ID> = []
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
    func syncData() throws -> [SyncRecord.Key: Data] {
        var records: [SyncRecord.Key: Data] = [:]
        for meeting in try meetings() {
            records[SyncRecord.Key(kind: .meeting, id: meeting.id)] = try syncData(of: meeting)
        }
        for project in try projects() {
            records[SyncRecord.Key(kind: .project, id: project.id)] = try Self.encoder.encode(project.synced)
        }
        return records
    }

    func syncData(for key: SyncRecord.Key) throws -> Data? {
        switch key.kind {
        case .meeting:
            let file = meetingFolder(key.id).appending(path: "meeting.json")
            guard let meeting = try? Self.decoder.decode(Meeting.self, from: Data(contentsOf: file)) else { return nil }
            return try syncData(of: meeting)
        case .project:
            return try projects().first { $0.id == key.id }.map { try Self.encoder.encode($0.synced) }
        }
    }

    private func syncData(of meeting: Meeting) throws -> Data {
        try Self.encoder.encode(SyncedMeeting(meeting: meeting, note: note(of: meeting) ?? ""))
    }

    func modified(meeting id: Meeting.ID) -> Date? {
        ["meeting.json", "note.md"].compactMap { try? meetingFolder(id).appending(path: $0).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
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
}

private extension Project {
    var synced: Project {
        var synced = self
        synced.repository = nil
        return synced
    }
}
