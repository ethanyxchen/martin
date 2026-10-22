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
    public static func markdown(bullets: [Bullet], silence: String? = nil) -> String {
        var parts = Bullet.Kind.allCases.compactMap { kind in
            let lines = bullets.filter { $0.kind == kind }.map { kind == .action ? "- [ ] \($0.text)" : "- \($0.text)" }
            return lines.isEmpty ? nil : section(kind.heading, lines)
        }
        if bullets.isEmpty, let silence { parts.append(silence) }
        return parts.joined(separator: "\n\n") + "\n"
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
