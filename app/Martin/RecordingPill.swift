import AppKit
import MartinKit
import SwiftUI

@MainActor
final class RecordingPill {
    private let recorder: Recorder
    private let panel: NSPanel

    init(recorder: Recorder) {
        self.recorder = recorder
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.contentView = FirstClickHostingView(rootView: PillView(recorder: recorder))
        observe()
    }

    private func observe() {
        withObservationTracking {
            update(recorder.phase)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func update(_ phase: Recorder.Phase) {
        switch phase {
        case .idle where panel.isVisible:
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            } completionHandler: { [panel] in
                MainActor.assumeIsolated { panel.orderOut(nil) }
            }
        case .recording where !panel.isVisible:
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            guard let frame = screen?.visibleFrame else { return }
            let origin = NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 12)
            panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y - 8))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(origin)
            }
        default:
            return
        }
    }
}

private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PillView: View {
    let recorder: Recorder

    var body: some View {
        Pill(phase: recorder.phase, level: recorder.level) { await recorder.stop() }
    }
}

struct Pill: View {
    let phase: Recorder.Phase
    let level: Float
    let stop: () async -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch phase {
            case .recording(_, let since):
                Waveform(level: level, breathing: false)
                    .foregroundStyle(.white)
                Text(since, style: .timer)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
                    .transition(.opacity)
                StopButton { Task { await stop() } }
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            default:
                Waveform(level: 0, breathing: true)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Writing notes…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.trailing, 6)
                    .transition(.opacity)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(Capsule().fill(Color(red: 0.09, green: 0.086, blue: 0.08).opacity(0.94)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.24), radius: 14, y: 6)
        .animation(.spring(duration: 0.4, bounce: 0.18), value: phase)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }
}

private struct StopButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(.white.opacity(hovering ? 0.2 : 0.11))
                .frame(width: 24, height: 24)
                .overlay {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Theme.ember)
                        .frame(width: 9, height: 9)
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Stop recording")
    }
}

struct Waveform: View {
    let level: Float
    let breathing: Bool
    @State private var follower = Follower()

    private static let envelope: [Double] = [0.5, 0.75, 0.92, 1, 0.92, 0.75, 0.5]
    private static let rest: CGFloat = 3
    private static let peak: CGFloat = 18
    private static let pitch: CGFloat = 5

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate
                follower.advance(to: Self.loudness(level), at: time)
                for (index, weight) in Self.envelope.enumerated() {
                    let distance = abs(Double(index) - 3)
                    let value = breathing
                        ? 0.14 + 0.14 * sin(time * 3.2 - Double(index) * 0.7)
                        : follower.value(at: time - distance * 0.045) * weight
                    let height = Self.rest + (Self.peak - Self.rest) * CGFloat(value)
                    let x = CGFloat(index) * Self.pitch
                    let bar = CGRect(x: x, y: (size.height - height) / 2, width: Self.rest, height: height)
                    canvas.fill(Path(roundedRect: bar, cornerRadius: Self.rest / 2), with: .foreground)
                }
            }
        }
        .frame(width: Self.pitch * CGFloat(Self.envelope.count - 1) + Self.rest, height: Self.peak)
    }

    private static func loudness(_ level: Float) -> Double {
        pow(min(max((Double(level) - 0.3) / 0.55, 0), 1), 0.8)
    }
}

private final class Follower {
    private var samples: [(time: Double, value: Double)] = []

    func advance(to target: Double, at time: Double) {
        guard let last = samples.last else {
            samples.append((time, 0))
            return
        }
        guard time > last.time else { return }
        let elapsed = time - last.time
        let speed = target > last.value ? 0.07 : 0.2
        let value = last.value + (target - last.value) * (1 - exp(-elapsed / speed))
        samples.append((time, value))
        samples.removeAll { time - $0.time > 0.4 }
    }

    func value(at time: Double) -> Double {
        samples.first { $0.time >= time }?.value ?? samples.last?.value ?? 0
    }
}
