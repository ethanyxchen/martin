import Foundation

public struct PullRequest: Codable, Hashable, Sendable {
    public enum State: String, Codable, Sendable { case open, merged, closed }

    public let repo: String
    public let number: Int
    public let title: String
    public let url: URL
    public let state: State
    public let mergedAt: Date?
    public let updatedAt: Date
}

public struct Briefing: Hashable, Sendable {
    static let recentDays = 14

    public let since: Date
    public let until: Date
    public let pullRequests: [PullRequest]

    public var merged: [PullRequest] {
        pullRequests.filter { $0.mergedAt.map { (since..<until).contains($0) } ?? false }
    }

    public var open: [PullRequest] {
        pullRequests.filter { $0.state == .open && $0.updatedAt >= since }
    }

    static func earliest(since: Date, until: Date) -> Date {
        min(since, Calendar.current.date(byAdding: .day, value: -recentDays, to: until)!)
    }
}
