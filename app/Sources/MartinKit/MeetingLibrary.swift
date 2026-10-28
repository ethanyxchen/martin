import Foundation

public struct MeetingLibrary: Sendable {
    public let root: URL

    public static let dataDirectory = (Bundle.main.object(forInfoDictionaryKey: "MartinDataDirectory") as? String)
        .map { URL(filePath: $0, directoryHint: .isDirectory) }
        ?? URL.applicationSupportDirectory.appending(path: "Martin", directoryHint: .isDirectory)

    public init(root: URL = dataDirectory) {
        self.root = root
    }

    private var meetingsFolder: URL { root.appending(path: "meetings", directoryHint: .isDirectory) }
    private var projectsFile: URL { root.appending(path: "projects.json") }

    public func meetings() throws -> [Meeting] {
        guard FileManager.default.fileExists(atPath: meetingsFolder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: meetingsFolder, includingPropertiesForKeys: nil)
            .compactMap { try? Self.decoder.decode(Meeting.self, from: Data(contentsOf: $0.appending(path: "meeting.json"))) }
            .sorted { $0.date > $1.date }
    }

    public func meeting(for event: CalendarEvent) throws -> Meeting {
        var meeting = try meeting(for: event.occurrence) ?? create(occurrence: event.occurrence, title: event.title, project: project(following: event.occurrence))
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

    public func create(startedAt: Date = .now, occurrence: Occurrence? = nil, title: String? = nil, project: Project.ID? = nil) throws -> Meeting {
        let startedAt = Date(timeIntervalSince1970: startedAt.timeIntervalSince1970.rounded(.down))
        let meeting = Meeting(id: Self.folderName.string(from: startedAt), startedAt: startedAt, occurrence: occurrence, title: title, project: project)
        try FileManager.default.createDirectory(at: meetingsFolder, withIntermediateDirectories: true)
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
        meetingsFolder.appending(path: meeting.id, directoryHint: .isDirectory)
    }

    public func projects() throws -> [Project] {
        guard FileManager.default.fileExists(atPath: projectsFile.path) else { return [] }
        return try Self.decoder.decode([Project].self, from: Data(contentsOf: projectsFile))
    }

    public func createProject(named name: String) throws -> Project {
        let project = Project(name: name)
        try save(projects() + [project])
        return project
    }

    public func file(_ meeting: Meeting, in project: Project.ID?) throws {
        var filed = meeting
        filed.project = project
        try save(filed)
        if let series = meeting.occurrence?.recurringSeries {
            try save(projects().map {
                var followed = $0
                followed.series.removeAll { $0 == series }
                if followed.id == project { followed.series.append(series) }
                return followed
            })
        }
    }

    public func save(_ project: Project) throws {
        try save(projects().map { $0.id == project.id ? project : $0 })
    }

    public func archive(_ project: Project, at date: Date = .now) throws {
        let date = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        for var meeting in try meetings() where meeting.project == project.id && meeting.archivedAt == nil {
            meeting.archivedAt = date
            try save(meeting)
        }
        var archived = project
        archived.archivedAt = date
        try save(archived)
    }

    public func restore(_ project: Project) throws {
        for var meeting in try meetings() where meeting.project == project.id && meeting.archivedAt == project.archivedAt {
            meeting.archivedAt = nil
            try save(meeting)
        }
        var restored = project
        restored.archivedAt = nil
        try save(restored)
    }

    public func delete(_ project: Project) throws {
        for meeting in try meetings() where meeting.project == project.id {
            try delete(meeting)
        }
        try save(projects().filter { $0.id != project.id })
    }

    private func project(following occurrence: Occurrence) throws -> Project.ID? {
        guard let series = occurrence.recurringSeries else { return nil }
        return try projects().first { $0.archivedAt == nil && $0.series.contains(series) }?.id
    }

    private func save(_ projects: [Project]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.encoder.encode(projects).write(to: projectsFile, options: .atomic)
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
