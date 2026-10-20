import CoreAudio
import Foundation

enum AudioHardware {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    static func property<T>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID, initial: T) throws -> T {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        guard status == noErr else { throw Failure(errorDescription: "Could not read audio property \(selector) (\(status)).") }
        return value
    }

    static func listen(_ selector: AudioObjectPropertySelector, on object: AudioObjectID, queue: DispatchQueue, _ block: @escaping AudioObjectPropertyListenerBlock) {
        var address = address(selector)
        AudioObjectAddPropertyListenerBlock(object, &address, queue, block)
    }

    static func stopListening(_ selector: AudioObjectPropertySelector, on object: AudioObjectID, queue: DispatchQueue, _ block: @escaping AudioObjectPropertyListenerBlock) {
        var address = address(selector)
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
    }
}

final class Restart: @unchecked Sendable {
    static let settle: TimeInterval = 0.3
    static let retry: TimeInterval = 1

    private let queue: DispatchQueue
    private let attempt: () -> Bool
    private var scheduled = false

    init(queue: DispatchQueue, attempt: @escaping () -> Bool) {
        self.queue = queue
        self.attempt = attempt
    }

    func schedule(after delay: TimeInterval = settle) {
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            scheduled = false
            if !attempt() { schedule(after: Self.retry) }
        }
    }
}
