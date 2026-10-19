import AVFoundation
import Testing
@testable import MartinKit

struct MicrophoneTests {
    @Test func framerEmitsFixedFramesAndKeepsRemainder() {
        var framer = Framer(size: 4)
        #expect(framer.push([1, 2, 3]) == [])
        #expect(framer.push([4, 5, 6, 7, 8, 9]) == [[1, 2, 3, 4], [5, 6, 7, 8]])
        #expect(framer.drain() == [9])
        #expect(framer.drain() == [])
    }

    @Test func levelMapsDecibels() {
        #expect(Microphone.level(of: Array(repeating: 0, count: 1600)) == 0)
        #expect(Microphone.level(of: Array(repeating: .max, count: 1600)) > 0.99)
        #expect(abs(Microphone.level(of: Array(repeating: 3277, count: 1600)) - 2.0 / 3) < 0.01)
    }

    @Test func dataIsLittleEndian() {
        #expect(Microphone.data([1, -2]) == Data([0x01, 0x00, 0xFE, 0xFF]))
    }

    @Test func resamplerKeepsStateAcrossBuffers() throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let resampler = try #require(Resampler(from: input))
        var phase = 0.0
        var samples: [Int16] = []
        for _ in 0..<20 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4800))
            buffer.frameLength = 4800
            for frame in 0..<4800 {
                let value = Float(0.5 * sin(phase))
                buffer.floatChannelData![0][frame] = value
                buffer.floatChannelData![1][frame] = value
                phase += 2 * .pi * 440 / 48000
            }
            let output = try #require(resampler.convert(buffer))
            samples += UnsafeBufferPointer(start: output.int16ChannelData![0], count: Int(output.frameLength))
        }
        #expect((31_500...32_000).contains(samples.count))
        let steady = samples.dropFirst(800).dropLast(800).map { Double($0) / 32768 }
        let rms = (steady.reduce(0) { $0 + $1 * $1 } / Double(steady.count)).squareRoot()
        #expect(abs(rms - 0.5 / 2.0.squareRoot()) < 0.02)
    }
}
