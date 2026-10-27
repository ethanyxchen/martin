import Foundation

public struct Person: Codable, Hashable, Sendable {
    public let email: String
    public let name: String?

    public init(email: String, name: String? = nil) {
        self.email = email.lowercased()
        self.name = name.flatMap { $0.isEmpty || $0.caseInsensitiveCompare(email) == .orderedSame ? nil : $0 }
    }

    public var displayName: String {
        name ?? String(email.prefix { $0 != "@" })
    }

    public var mention: String {
        "[@\(displayName.filter { $0 != "[" && $0 != "]" })](mailto:\(email))"
    }

    public static func matches(of query: String, in text: String) -> [Range<String.Index>] {
        let starts = text.indices.filter { $0 == text.startIndex || text[text.index(before: $0)] == " " }
        return starts.compactMap { start in
            guard let end = text.index(start, offsetBy: query.count, limitedBy: text.endIndex), text[start..<end].lowercased() == query.lowercased() else { return nil }
            return start..<end
        }
    }

    func matches(_ query: String) -> Bool {
        !Self.matches(of: query, in: displayName).isEmpty || !Self.matches(of: query, in: email).isEmpty
    }
}

public extension [Person] {
    func suggestions(for query: String) -> [Person] {
        var seen: Set<String> = []
        return filter { seen.insert($0.email).inserted && $0.matches(query) }
    }
}
