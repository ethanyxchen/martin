import Foundation

public struct Bullet: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case action, decision, question }

    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public enum Note {
    public static func markdown(briefing: Briefing?, bullets: [Bullet], silence: String? = nil) -> String {
        var parts = (briefing.map(work) ?? []) + Bullet.Kind.allCases.compactMap { kind in
            let lines = bullets.filter { $0.kind == kind }.map { kind == .action ? "- [ ] \($0.text)" : "- \($0.text)" }
            return lines.isEmpty ? nil : section(kind.heading, lines)
        }
        if bullets.isEmpty, let silence { parts.append(silence) }
        return parts.joined(separator: "\n\n") + "\n"
    }

    static func work(_ briefing: Briefing) -> [String] {
        let since = briefing.since.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        let merged = briefing.merged, open = briefing.open
        guard !merged.isEmpty || !open.isEmpty else { return [section("Since \(since)", ["No pull requests merged or in progress."])] }
        return [
            merged.isEmpty ? nil : section("Merged since \(since)", merged.map(line)),
            open.isEmpty ? nil : section("In progress", open.map(line)),
        ].compactMap(\.self)
    }

    private static func line(_ pullRequest: PullRequest) -> String {
        "- \(pullRequest.title) [#\(pullRequest.number)](\(pullRequest.url.absoluteString))"
    }

    private static func section(_ heading: String, _ lines: [String]) -> String {
        (["## \(heading)"] + lines).joined(separator: "\n")
    }
}

private extension Bullet.Kind {
    var heading: String {
        switch self {
        case .action: "To do"
        case .decision: "Decisions"
        case .question: "Questions"
        }
    }
}
