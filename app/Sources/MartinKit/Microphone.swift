import Foundation

public final class Microphone: @unchecked Sendable {
    public init() {}

    public func start(writingTo file: URL, onLevel: @escaping @Sendable (Float) -> Void, onAudio: @escaping @Sendable (Data) -> Void) throws {}

    public func stop() {}
}
