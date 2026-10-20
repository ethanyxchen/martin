import AVFoundation
import CoreAudio

public final class SystemAudio: @unchecked Sendable {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private let queue = DispatchQueue(label: "dev.ethanchen.martin.system-audio")
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var running = false
    private var onAudio: @Sendable ([Int16]) -> Void = { _ in }
    private lazy var rebuild: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        guard let self, running else { return }
        teardown()
        try? run()
    }

    public init() {}

    public func start(onAudio: @escaping @Sendable ([Int16]) -> Void) throws {
        try queue.sync {
            guard !running else { return }
            self.onAudio = onAudio
            try run()
            running = true
            listen(kAudioHardwarePropertyDefaultOutputDevice, on: Self.system)
        }
    }

    public func stop() {
        queue.sync {
            guard running else { return }
            running = false
            stopListening(kAudioHardwarePropertyDefaultOutputDevice, on: Self.system)
            teardown()
        }
    }

    private func run() throws {
        do {
            let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
            description.isPrivate = true
            try check(AudioHardwareCreateProcessTap(description, &tap), "create the system audio tap")
            let device = try Self.property(kAudioHardwarePropertyDefaultOutputDevice, of: Self.system, initial: AudioObjectID(kAudioObjectUnknown))
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
            stream.mSampleRate = try Self.property(kAudioDevicePropertyNominalSampleRate, of: aggregate, initial: Float64(0))
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
            listen(kAudioDevicePropertyNominalSampleRate, on: aggregate)
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
        if aggregate != kAudioObjectUnknown {
            stopListening(kAudioDevicePropertyNominalSampleRate, on: aggregate)
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        proc = nil
        aggregate = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
    }

    private func listen(_ selector: AudioObjectPropertySelector, on object: AudioObjectID) {
        var address = Self.address(selector)
        AudioObjectAddPropertyListenerBlock(object, &address, queue, rebuild)
    }

    private func stopListening(_ selector: AudioObjectPropertySelector, on object: AudioObjectID) {
        var address = Self.address(selector)
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, rebuild)
    }

    private func check(_ status: OSStatus, _ action: String) throws {
        guard status != noErr else { return }
        throw Failure(errorDescription: "Could not \(action) (\(status)).")
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func property<T>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID, initial: T) throws -> T {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        guard status == noErr else { throw Failure(errorDescription: "Could not read audio property \(selector) (\(status)).") }
        return value
    }
}
