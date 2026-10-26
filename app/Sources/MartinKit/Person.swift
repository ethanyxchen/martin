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

    func matches(_ query: String) -> Bool {
        let query = query.lowercased()
        return ([email, displayName] + displayName.split(separator: " ").map(String.init)).contains { $0.lowercased().hasPrefix(query) }
    }
}

public extension [Person] {
    func suggestions(for query: String) -> [Person] {
        var seen: Set<String> = []
        return filter { seen.insert($0.email).inserted && $0.matches(query) }
    }
}
