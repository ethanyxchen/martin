import AppKit
import MartinKit
import SwiftUI

struct MenuBar: View {
    let app: AppState

    var body: some View {
        Button("New Meeting") { Task { app.start(await CalendarLookup.currentEvent()) } }

        Button("Upcoming Meetings…") { app.openUpcoming() }

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
        Button("Quit Martin") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension NSImage {
    static let menuBarIcon: NSImage = {
        let heights: [CGFloat] = [4, 8, 11, 6]
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { bounds in
            let bars = NSBezierPath()
            for (index, height) in heights.enumerated() {
                let x = 5 + CGFloat(index) * 3.4
                bars.append(NSBezierPath(roundedRect: NSRect(x: x - 1, y: bounds.midY - height / 2, width: 2, height: height), xRadius: 1, yRadius: 1))
            }
            NSColor.black.setFill()
            bars.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
