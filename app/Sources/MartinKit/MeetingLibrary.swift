import Foundation

public struct MeetingLibrary: Sendable {
    public let root: URL

    public static let applicationSupport = URL.applicationSupportDirectory.appending(path: "Martin", directoryHint: .isDirectory)

    public init(root: URL = applicationSupport.appending(path: "meetings", directoryHint: .isDirectory)) {
        self.root = root
    }

    public func meetings() throws -> [Meeting] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .compactMap { try? Self.decoder.decode(Meeting.self, from: Data(contentsOf: $0.appending(path: "meeting.json"))) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    public func create(startedAt: Date = .now, title: String? = nil, attendees: [String] = [], calendarNotes: String? = nil) throws -> Meeting {
        let startedAt = Date(timeIntervalSince1970: startedAt.timeIntervalSince1970.rounded(.down))
        let meeting = Meeting(id: Self.folderName.string(from: startedAt), startedAt: startedAt, title: title, attendees: attendees, calendarNotes: calendarNotes)
        try FileManager.default.createDirectory(at: folder(of: meeting), withIntermediateDirectories: true)
        try save(meeting)
        return meeting
    }

    public func save(_ meeting: Meeting) throws {
        try Self.encoder.encode(meeting).write(to: folder(of: meeting).appending(path: "meeting.json"), options: .atomic)
    }

    public func folder(of meeting: Meeting) -> URL {
        root.appending(path: meeting.id, directoryHint: .isDirectory)
    }

    public func audioURL(of meeting: Meeting) -> URL {
        folder(of: meeting).appending(path: "audio.aac")
    }

    public func append(_ segment: Segment, to meeting: Meeting) throws {
        let url = folder(of: meeting).appending(path: "transcript.jsonl")
        var line = try Self.encoder.encode(segment)
        line.append(0x0A)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try line.write(to: url)
            return
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    public func transcript(of meeting: Meeting) throws -> [Segment] {
        let url = folder(of: meeting).appending(path: "transcript.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map { try Self.decoder.decode(Segment.self, from: Data($0.utf8)) }
    }

    public func note(of meeting: Meeting) -> String? {
        try? String(contentsOf: noteURL(of: meeting), encoding: .utf8)
    }

    public func saveNote(_ note: String, for meeting: Meeting) throws {
        try note.write(to: noteURL(of: meeting), atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: errorURL(of: meeting))
    }

    public func analysisError(of meeting: Meeting) -> String? {
        try? String(contentsOf: errorURL(of: meeting), encoding: .utf8)
    }

    public func saveAnalysisError(_ message: String, for meeting: Meeting) throws {
        try message.write(to: errorURL(of: meeting), atomically: true, encoding: .utf8)
    }

    private func noteURL(of meeting: Meeting) -> URL {
        folder(of: meeting).appending(path: "note.md")
    }

    private func errorURL(of meeting: Meeting) -> URL {
        folder(of: meeting).appending(path: "error.txt")
    }

    private static let folderName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
