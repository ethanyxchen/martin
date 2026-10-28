import Foundation

public struct MeetingLibrary: Sendable {
    public let root: URL

    public static let dataDirectory = (Bundle.main.object(forInfoDictionaryKey: "MartinDataDirectory") as? String)
        .map { URL(filePath: $0, directoryHint: .isDirectory) }
        ?? URL.applicationSupportDirectory.appending(path: "Martin", directoryHint: .isDirectory)

    public init(root: URL = dataDirectory.appending(path: "meetings", directoryHint: .isDirectory)) {
        self.root = root
    }

    public func meetings() throws -> [Meeting] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .compactMap { try? Self.decoder.decode(Meeting.self, from: Data(contentsOf: $0.appending(path: "meeting.json"))) }
            .sorted { $0.date > $1.date }
    }

    public func meeting(for event: CalendarEvent) throws -> Meeting {
        var meeting = try meeting(for: event.occurrence) ?? create(occurrence: event.occurrence, title: event.title)
        guard meeting.scheduledAt != event.start || meeting.attendees != event.attendees || meeting.archivedAt != nil else { return meeting }
        meeting.scheduledAt = event.start
        meeting.attendees = event.attendees
        meeting.archivedAt = nil
        try save(meeting)
        return meeting
    }

    func meeting(for occurrence: Occurrence) throws -> Meeting? {
        try meetings().first { $0.occurrence == occurrence }
    }

    public func create(startedAt: Date = .now, occurrence: Occurrence? = nil, title: String? = nil) throws -> Meeting {
        let startedAt = Date(timeIntervalSince1970: startedAt.timeIntervalSince1970.rounded(.down))
        let meeting = Meeting(id: Self.folderName.string(from: startedAt), startedAt: startedAt, occurrence: occurrence, title: title)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder(of: meeting), withIntermediateDirectories: false)
        try save(meeting)
        return meeting
    }

    public func save(_ meeting: Meeting) throws {
        try Self.encoder.encode(meeting).write(to: folder(of: meeting).appending(path: "meeting.json"), options: .atomic)
    }

    public func delete(_ meeting: Meeting) throws {
        try FileManager.default.removeItem(at: folder(of: meeting))
    }

    public func folder(of meeting: Meeting) -> URL {
        root.appending(path: meeting.id, directoryHint: .isDirectory)
    }

    public func note(of meeting: Meeting) -> String? {
        try? String(contentsOf: noteURL(of: meeting), encoding: .utf8)
    }

    public func saveNote(_ note: String, for meeting: Meeting) throws {
        try note.write(to: noteURL(of: meeting), atomically: true, encoding: .utf8)
    }

    private func noteURL(of meeting: Meeting) -> URL {
        folder(of: meeting).appending(path: "note.md")
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
