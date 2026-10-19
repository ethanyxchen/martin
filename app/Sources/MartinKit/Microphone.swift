import AVFoundation

public final class Microphone: @unchecked Sendable {
    public struct Failure: LocalizedError {
        public let errorDescription: String?

        static let denied = Failure(errorDescription: "Allow Martin to use the microphone in System Settings › Privacy & Security.")
        static let noInput = Failure(errorDescription: "No microphone is available.")
    }

    static let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    static let frameLength = 1600

    private let queue = DispatchQueue(label: "dev.ethanchen.martin.microphone")
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var resampler: Resampler?
    private var framer = Framer(size: frameLength)
    private var interruptedAt: Date?
    private var observer: NSObjectProtocol?
    private var onLevel: @Sendable (Float) -> Void = { _ in }
    private var onAudio: @Sendable (Data) -> Void = { _ in }

    public init() {}

    public static func authorize() async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw Failure.denied }
    }

    public func start(writingTo file: URL, onLevel: @escaping @Sendable (Float) -> Void, onAudio: @escaping @Sendable (Data) -> Void) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw Failure.denied }
        try queue.sync {
            guard self.file == nil else { return }
            self.file = try AVAudioFile(
                forWriting: file,
                settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000],
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
            self.onLevel = onLevel
            self.onAudio = onAudio
            do {
                try run()
            } catch {
                self.file = nil
                throw error
            }
            observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
                guard let self else { return }
                queue.async { self.reconfigure() }
            }
        }
    }

    public func stop() {
        queue.sync {
            guard file != nil else { return }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            let rest = framer.drain()
            if !rest.isEmpty { onAudio(Self.data(rest)) }
            file?.close()
            file = nil
            resampler = nil
        }
    }

    private func run() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, let resampler = Resampler(from: format) else { throw Failure.noInput }
        self.resampler = resampler
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            nonisolated(unsafe) let buffer = buffer
            queue.async { self.process(buffer) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    private func reconfigure() {
        guard file != nil else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        resampler = nil
        interruptedAt = interruptedAt ?? .now
        do {
            try run()
        } catch {
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.reconfigure() }
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let file, let resampler, buffer.format == resampler.input, let converted = resampler.convert(buffer) else { return }
        if let interruptedAt {
            self.interruptedAt = nil
            pad(seconds: Date.now.timeIntervalSince(interruptedAt), file: file)
        }
        try? file.write(from: converted)
        emit(UnsafeBufferPointer(start: converted.int16ChannelData![0], count: Int(converted.frameLength)))
    }

    private func pad(seconds: TimeInterval, file: AVAudioFile) {
        let count = AVAudioFrameCount(seconds * Self.format.sampleRate)
        guard count > 0, let silence = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: count) else { return }
        silence.frameLength = count
        try? file.write(from: silence)
        emit(repeatElement(0, count: Int(count)))
    }

    private func emit(_ samples: some Sequence<Int16>) {
        for frame in framer.push(samples) {
            onLevel(Self.level(of: frame))
            onAudio(Self.data(frame))
        }
    }

    static func level(of samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let power = samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)
        let decibels = 10 * log10(max(power, 1e-12) / (32768.0 * 32768.0))
        return Float(min(max((decibels + 60) / 60, 0), 1))
    }

    static func data(_ samples: [Int16]) -> Data {
        samples.map(\.littleEndian).withUnsafeBytes { Data($0) }
    }
}

struct Framer {
    let size: Int
    private var pending: [Int16] = []

    init(size: Int) {
        self.size = size
    }

    mutating func push(_ samples: some Sequence<Int16>) -> [[Int16]] {
        pending.append(contentsOf: samples)
        let count = pending.count / size * size
        let frames = stride(from: 0, to: count, by: size).map { Array(pending[$0..<$0 + size]) }
        pending.removeFirst(count)
        return frames
    }

    mutating func drain() -> [Int16] {
        defer { pending = [] }
        return pending
    }
}

final class Resampler {
    let input: AVAudioFormat
    private let converter: AVAudioConverter

    init?(from input: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: input, to: Microphone.format) else { return nil }
        converter.downmix = true
        self.input = input
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let ratio = Microphone.format.sampleRate / input.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: Microphone.format, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outcome in
            guard !supplied else {
                outcome.pointee = .noDataNow
                return nil
            }
            supplied = true
            outcome.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : output
    }
}
