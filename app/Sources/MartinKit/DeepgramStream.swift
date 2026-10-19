import Foundation

public final class DeepgramStream: @unchecked Sendable {
    public init(apiKey: String, keyterms: [String]) {}

    public func connect(onSegment: @escaping @Sendable (Segment) -> Void) {}

    public func send(_ audio: Data) {}

    public func finish() async {}

    public static func segment(from message: Data) -> Segment? { nil }
}
