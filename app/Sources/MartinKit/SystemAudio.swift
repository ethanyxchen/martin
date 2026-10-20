import AVFoundation
import CoreAudio

public final class SystemAudio: @unchecked Sendable {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private static let defaultOutput = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private let queue = DispatchQueue(label: "dev.ethanchen.martin.system-audio")
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var listener: AudioObjectPropertyListenerBlock?
    private var onAudio: @Sendable ([Int16]) -> Void = { _ in }

    public init() {}

    public func start(onAudio: @escaping @Sendable ([Int16]) -> Void) throws {
        try queue.sync {
            guard listener == nil else { return }
            self.onAudio = onAudio
            try run()
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.rebuild() }
            var address = Self.defaultOutput
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
            self.listener = listener
        }
    }

    public func stop() {
        queue.sync {
            guard let listener else { return }
            var address = Self.defaultOutput
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
            self.listener = nil
            teardown()
        }
    }

    private func rebuild() {
        guard listener != nil else { return }
        teardown()
        try? run()
    }

    private func run() throws {
        do {
            let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
            description.isPrivate = true
            try check(AudioHardwareCreateProcessTap(description, &tap), "create the system audio tap")
            let device = try Self.property(kAudioHardwarePropertyDefaultOutputDevice, of: AudioObjectID(kAudioObjectSystemObject), initial: AudioObjectID(kAudioObjectUnknown))
            let uid: CFString? = try Self.property(kAudioDevicePropertyDeviceUID, of: device, initial: nil)
            guard let output = uid else { throw Failure(errorDescription: "No audio output device is available.") }
            let configuration: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Martin",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: output,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
            ]
            try check(AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate), "create the system audio device")
            var stream = try Self.property(kAudioTapPropertyFormat, of: tap, initial: AudioStreamBasicDescription())
            guard let format = AVAudioFormat(streamDescription: &stream), let resampler = Resampler(from: format) else {
                throw Failure(errorDescription: "System audio has an unsupported format.")
            }
            let onAudio = onAudio
            try check(AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, input, _, _, _ in
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil), buffer.frameLength > 0,
                      let converted = resampler.convert(buffer) else { return }
                onAudio(Array(UnsafeBufferPointer(start: converted.int16ChannelData![0], count: Int(converted.frameLength))))
            }, "listen to system audio")
            try check(AudioDeviceStart(aggregate, proc), "start system audio")
        } catch {
            teardown()
            throw error
        }
    }

    private func teardown() {
        if let proc {
            AudioDeviceStop(aggregate, proc)
            AudioDeviceDestroyIOProcID(aggregate, proc)
        }
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        proc = nil
        aggregate = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
    }

    private func check(_ status: OSStatus, _ action: String) throws {
        guard status != noErr else { return }
        throw Failure(errorDescription: "Could not \(action) (\(status)).")
    }

    private static func property<T>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID, initial: T) throws -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        guard status == noErr else { throw Failure(errorDescription: "Could not read audio property \(selector) (\(status)).") }
        return value
    }
}
