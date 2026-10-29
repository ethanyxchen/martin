import Foundation

public enum Conductor {
    public struct Note: Sendable {
        public let id: String
        public let title: String
        public let date: Date
        public let changedAt: Date
        public let text: String

        public init(id: String, title: String, date: Date, changedAt: Date, text: String) {
            self.id = id
            self.title = title
            self.date = date
            self.changedAt = changedAt
            self.text = text
        }
    }

    public struct Sources: Sendable {
        public var notes: [Note]
        public var activity: @Sendable (Date?) async -> String?

        public init(notes: [Note], activity: @escaping @Sendable (Date?) async -> String?) {
            self.notes = notes
            self.activity = activity
        }
    }

    public typealias Ask = @Sendable (String) async -> Data?

    public static let turns = 8
    static let noteLimit = 4000
    static let activityLimit = 4000
    static let titleLimit = 80
    static let captionLimit = 160
    static let limits = (now: 3, next: 6, shelved: 6)

    static let instructions = """
        You keep a short, friendly overview of one project for the person who owns it. Each turn you choose one action:
        - read_note: read the note whose id you give in "note".
        - read_activity: read the project's GitHub activity since it was last read.
        - revise: put your current best overview in "overview" so you can look at it again next turn. Use it to make the overview shorter and simpler.
        - submit: put the final overview in "overview". Submit as soon as it is good; do not read what you do not need.
        The overview has three sections, most important first:
        - now: what they are working on right now, at most \(limits.now) tasks, most recently updated first.
        - next: what they will work on next.
        - shelved: ideas they have set aside.
        A task is a title and a caption. The title names the overall task in a few words. The caption is one short sentence on where it stands. \
        Never mention pull request numbers, commit hashes or file names. Set "updated" to the YYYY-MM-DD date of the latest note or activity about that task, or null when unknown. \
        Start from the previous overview, keep what still holds, and change only what the new material changes. Leave out anything you cannot support from the material.
        """

    static let schema = {
        let task = #"{"type":"object","properties":{"title":{"type":"string"},"caption":{"type":"string"},"updated":{"type":["string","null"]}},"required":["title","caption","updated"],"additionalProperties":false}"#
        let tasks = #"{"type":"array","items":\#(task)}"#
        let overview = #"{"type":["object","null"],"properties":{"now":\#(tasks),"next":\#(tasks),"shelved":\#(tasks)},"required":["now","next","shelved"],"additionalProperties":false}"#
        return #"{"type":"object","properties":{"thinking":{"type":"string"},"action":{"type":"string","enum":["read_note","read_activity","revise","submit"]},"note":{"type":["string","null"]},"overview":\#(overview)},"required":["thinking","action","note","overview"],"additionalProperties":false}"#
    }()

    public static func ask(using assistant: Assistant) -> Ask {
        { await assistant.answer($0, instructions: instructions, schema: schema, effort: .deep) }
    }

    public static func run(_ project: Project, previous: Overview?, sources: Sources, now: Date = .now, turns: Int = turns, ask: Ask) async -> Overview? {
        var gathered: [String] = []
        var read: Set<String> = []
        var activityRead = false
        var draft: Overview?
        for turn in 1...max(turns, 1) {
            let last = turn == max(turns, 1)
            let prompt = prompt(for: project, previous: previous, sources: sources, gathered: gathered, draft: draft, now: now, turnsLeft: max(turns, 1) - turn, last: last)
            guard let step = await ask(prompt).flatMap(Step.init(from:)) else { return nil }
            let proposed = step.overview.map { $0.overview(readAt: now) }
            switch step.action {
            case "submit":
                if let proposed { return proposed }
                gathered.append("Submit needs an overview, and none was given.")
            case "revise":
                draft = proposed ?? draft
            case "read_note":
                gathered.append(observe(note: step.note, in: sources.notes, read: &read))
            case "read_activity":
                gathered.append(activityRead ? "The activity was already read." : await activity(sources, since: previous?.readAt))
                activityRead = true
            default:
                gathered.append("Unknown action. Choose read_note, read_activity, revise or submit.")
            }
            if last { return proposed ?? draft }
        }
        return nil
    }

    private static func observe(note id: String?, in notes: [Note], read: inout Set<String>) -> String {
        guard let note = notes.first(where: { $0.id == id }) else { return "There is no note with id \(id ?? "nil")." }
        guard read.insert(note.id).inserted else { return "Note \(note.id) was already read." }
        return "Note \(note.id), “\(note.title)”:\n\(note.text.prefix(noteLimit))"
    }

    private static func activity(_ sources: Sources, since date: Date?) async -> String {
        guard let activity = await sources.activity(date) else { return "This project has no GitHub activity to read." }
        return "GitHub activity\(date.map { " since \($0.day)" } ?? ""):\n\(activity.prefix(activityLimit))"
    }

    static func prompt(for project: Project, previous: Overview?, sources: Sources, gathered: [String], draft: Overview?, now: Date, turnsLeft: Int, last: Bool) -> String {
        let notes = sources.notes.map { note in
            let fresh = previous.map { note.changedAt > $0.readAt } ?? true
            return "- \(note.id) · \(note.title) · meeting \(note.date.day) · edited \(note.changedAt.day)\(fresh ? " · new since last read" : "")"
        }
        return [
            "Project: \(project.name)",
            "Today: \(now.day)",
            "Last read: \(previous?.readAt.day ?? "never")",
            "Previous overview:\n\(previous.map(describe) ?? "None yet.")",
            "Notes:\n\(notes.isEmpty ? "No notes." : notes.joined(separator: "\n"))",
            "Read so far:\n\(gathered.isEmpty ? "Nothing yet." : gathered.joined(separator: "\n\n"))",
            "Your current draft:\n\(draft.map(describe) ?? "None.")",
            last ? "This is your last turn: submit now." : "Turns left after this one: \(turnsLeft).",
        ].joined(separator: "\n\n")
    }

    static func describe(_ overview: Overview) -> String {
        [("now", overview.now), ("next", overview.next), ("shelved", overview.shelved)].map { name, tasks in
            "\(name):" + (tasks.isEmpty ? " none" : "\n" + tasks.map { "- \($0.title) · \($0.updatedAt?.day ?? "unknown date") · \($0.caption)" }.joined(separator: "\n"))
        }.joined(separator: "\n")
    }

    struct Step {
        struct Draft: Decodable {
            struct Item: Decodable {
                let title: String
                let caption: String
                let updated: String?
            }

            let now: [Item]
            let next: [Item]
            let shelved: [Item]

            func overview(readAt: Date) -> Overview {
                func tasks(_ items: [Item], limit: Int) -> [Overview.Task] {
                    items.compactMap { item in
                        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return nil }
                        let updated = item.updated.flatMap { try? Date($0, strategy: .iso8601.year().month().day()) }
                        return Overview.Task(title: String(title.prefix(titleLimit)), caption: String(item.caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(captionLimit)), updatedAt: updated.flatMap { $0 <= readAt ? $0 : nil })
                    }
                    .prefix(limit).map { $0 }
                }
                return Overview(now: tasks(now, limit: limits.now), next: tasks(next, limit: limits.next), shelved: tasks(shelved, limit: limits.shelved), readAt: readAt)
            }
        }

        let action: String
        let note: String?
        let overview: Draft?

        init?(from data: Data) {
            struct Answer: Decodable {
                let action: String
                let note: String?
                let overview: Draft?
            }
            guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return nil }
            action = answer.action
            note = answer.note
            overview = answer.overview
        }
    }
}

private extension Date {
    var day: String { formatted(.iso8601.year().month().day()) }
}
