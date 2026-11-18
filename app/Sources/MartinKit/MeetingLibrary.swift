import Foundation

public struct MeetingLibrary: Sendable {
    public let root: URL

    public static let dataDirectory = (Bundle.main.object(forInfoDictionaryKey: "MartinDataDirectory") as? String)
        .map { URL(filePath: $0, directoryHint: .isDirectory) }
        ?? URL.applicationSupportDirectory.appending(path: "Martin", directoryHint: .isDirectory)

    public init(root: URL = dataDirectory) {
        self.root = root
    }

    var meetingsFolder: URL { root.appending(path: "meetings", directoryHint: .isDirectory) }
    var projectsFile: URL { root.appending(path: "projects.json") }
    private var lookupsFile: URL { root.appending(path: "lookups.json") }
    private var overviewsFile: URL { root.appending(path: "overviews.json") }

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
        meeting = try restored(meeting)
        try save(meeting)
        return meeting
    }

    public func restore(_ meeting: Meeting) throws {
        try save(restored(meeting))
    }

    private func restored(_ meeting: Meeting) throws -> Meeting {
        var restored = meeting
        restored.archivedAt = nil
        if try projects().contains(where: { $0.id == meeting.project && $0.archivedAt != nil }) { restored.project = nil }
        return restored
    }

    func meeting(for occurrence: Occurrence) throws -> Meeting? {
        try meetings().first { $0.occurrence == occurrence }
    }

    public func create(startedAt: Date = .now, occurrence: Occurrence? = nil, title: String? = nil, project: Project.ID? = nil) throws -> Meeting {
        let startedAt = Date(timeIntervalSince1970: startedAt.timeIntervalSince1970.rounded(.down))
        let meeting = Meeting(id: unusedID(at: startedAt), startedAt: startedAt, occurrence: occurrence, title: title, project: project)
        try FileManager.default.createDirectory(at: folder(of: meeting), withIntermediateDirectories: true)
        try save(meeting)
        return meeting
    }

    private func unusedID(at startedAt: Date) -> Meeting.ID {
        let stamp = Self.folderName.string(from: startedAt)
        var id = stamp
        var copy = 1
        while FileManager.default.fileExists(atPath: meetingsFolder.appending(path: id).path) {
            copy += 1
            id = "\(stamp)-\(copy)"
        }
        return id
    }

    public func save(_ meeting: Meeting) throws {
        try Self.encoder.encode(meeting).write(to: folder(of: meeting).appending(path: "meeting.json"), options: .atomic)
    }

    public func delete(_ meeting: Meeting) throws {
        try FileManager.default.removeItem(at: folder(of: meeting))
    }

    public func folder(of meeting: Meeting) -> URL {
        meetingFolder(meeting.id)
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
        try forget(project: project.id)
    }

    func forget(project: Project.ID) throws {
        try save(projects().filter { $0.id != project })
        try save(nil as RepositoryLookup?, for: project, in: lookupsFile)
        try save(nil as OverviewRecord?, for: project, in: overviewsFile)
    }

    public func lookups() -> [Project.ID: RepositoryLookup] {
        records(in: lookupsFile)
    }

    public func save(_ lookup: RepositoryLookup, for project: Project.ID) throws {
        try save(lookup, for: project, in: lookupsFile)
    }

    public func overviews() -> [Project.ID: OverviewRecord] {
        records(in: overviewsFile)
    }

    public func save(_ overview: OverviewRecord, for project: Project.ID) throws {
        try save(overview, for: project, in: overviewsFile)
    }

    private func records<Record: Decodable>(in file: URL) -> [Project.ID: Record] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? Self.decoder.decode([Project.ID: Record].self, from: data)) ?? [:]
    }

    private func save<Record: Codable>(_ record: Record?, for project: Project.ID, in file: URL) throws {
        var records: [Project.ID: Record] = records(in: file)
        guard records[project] != nil || record != nil else { return }
        records[project] = record
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.encoder.encode(records).write(to: file, options: .atomic)
    }

    private func project(following occurrence: Occurrence) throws -> Project.ID? {
        guard let series = occurrence.recurringSeries else { return nil }
        return try projects().first { $0.archivedAt == nil && $0.series.contains(series) }?.id
    }

    func save(_ projects: [Project]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.encoder.encode(projects).write(to: projectsFile, options: .atomic)
    }

    public func note(of meeting: Meeting) -> String? {
        try? String(contentsOf: noteFile(of: meeting), encoding: .utf8)
    }

    public func saveNote(_ note: String, for meeting: Meeting) throws {
        try note.write(to: noteFile(of: meeting), atomically: true, encoding: .utf8)
    }

    public func noteFile(of meeting: Meeting) -> URL {
        folder(of: meeting).appending(path: "note.md")
    }

    private static let folderName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
