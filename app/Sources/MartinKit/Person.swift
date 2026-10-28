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
        guard let name = name?.filter({ !"{}<>\n".contains($0) }), !name.isEmpty else { return "@{\(email)}" }
        return "@{\(name) <\(email)>}"
    }

    func matches(_ query: String) -> Bool {
        !displayName.wordMatches(of: query).isEmpty || !email.wordMatches(of: query).isEmpty
    }
}

public extension String {
    func wordMatches(of query: String) -> [Range<String.Index>] {
        let starts = indices.filter { $0 == startIndex || self[index(before: $0)] == " " }
        return starts.compactMap { start in
            guard let end = index(start, offsetBy: query.count, limitedBy: endIndex), self[start..<end].lowercased() == query.lowercased() else { return nil }
            return start..<end
        }
    }
}

public extension [Person] {
    func suggestions(for query: String) -> [Person] {
        var seen: Set<String> = []
        return filter { seen.insert($0.email).inserted && $0.matches(query) }
    }
}
