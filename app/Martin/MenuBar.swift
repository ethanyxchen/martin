import AppKit
import MartinKit
import SwiftUI

struct MenuBar: View {
    let app: AppState

    var body: some View {
        switch app.recorder.phase {
        case .idle:
            Button("Start Recording") { Task { await app.toggleRecording() } }
        case .recording(_, let since):
            Button { Task { await app.toggleRecording() } } label: {
                Text("Stop Recording")
                Text(Duration.seconds(Date.now.timeIntervalSince(since)).formatted(.time(pattern: .minuteSecond)))
            }
        case .analyzing(let meeting):
            Button("Writing Notes…") { app.open(meeting) }
        }

        if !app.meetings.isEmpty {
            Section("Recent") {
                ForEach(app.meetings.prefix(8)) { meeting in
                    Button { app.open(meeting) } label: {
                        Text(meeting.displayTitle)
                        Text(meeting.startedAt.formatted(.relative(presentation: .named)))
                    }
                }
            }
        }

        Divider()
        Button("Settings…") { app.openSettings() }
            .keyboardShortcut(",")
        Button("Quit Martin") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension NSImage {
    static func menuBarIcon(awake: Bool) -> NSImage {
        let heights: [CGFloat] = [4, 8, 11, 6]
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { bounds in
            let bars = NSBezierPath()
            for (index, height) in heights.enumerated() {
                let x = 5 + CGFloat(index) * 3.4
                bars.append(NSBezierPath(roundedRect: NSRect(x: x - 1, y: bounds.midY - height / 2, width: 2, height: height), xRadius: 1, yRadius: 1))
            }
            NSColor.black.setFill()
            guard awake else {
                bars.fill()
                return true
            }
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 7, yRadius: 7).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            bars.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
