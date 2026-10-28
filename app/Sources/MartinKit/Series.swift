import Foundation

public struct Series: Identifiable, Hashable, Sendable {
    public enum ID: Hashable, Sendable {
        case recurring(String)
        case other
    }

    public let id: ID
    public let meetings: [Meeting]
}

public extension [Meeting] {
    var series: [Series] {
        var order: [Series.ID] = []
        var groups: [Series.ID: [Meeting]] = [:]
        for meeting in self {
            let id: Series.ID = if let occurrence = meeting.occurrence, occurrence.start != nil { .recurring(occurrence.series) } else { .other }
            if groups[id] == nil { order.append(id) }
            groups[id, default: []].append(meeting)
        }
        return (order.filter { $0 != .other } + order.filter { $0 == .other }).map { Series(id: $0, meetings: groups[$0]!) }
    }
}
