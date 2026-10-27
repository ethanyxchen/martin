import AppKit
import MartinKit
import SwiftUI

struct MenuBar: View {
    let app: AppState

    var body: some View {
        Button("Take Notes") { Task { app.start(await CalendarLookup.currentEvent(hiding: app.hiddenCalendars)) } }

        Button("Upcoming Meetings…") { app.openHome(on: .upcoming) }

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
        SettingsButton(app: app)
        Button("Quit \(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Martin")") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct SettingsButton: View {
    let app: AppState

    var body: some View {
        Button("Settings…") { app.openHome(on: .settings) }
            .keyboardShortcut(",")
    }
}

extension NSImage {
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { bounds in
            func window(_ frame: NSRect, degrees: CGFloat, inset: CGFloat = 0) -> NSBezierPath {
                let path = NSBezierPath(roundedRect: frame.insetBy(dx: inset, dy: inset), xRadius: 2 - inset, yRadius: 2 - inset)
                var tilt = AffineTransform(translationByX: frame.midX, byY: frame.midY)
                tilt.rotate(byDegrees: degrees)
                tilt.translate(x: -frame.midX, y: -frame.midY)
                path.transform(using: tilt)
                return path
            }
            let earlier = window(NSRect(x: 1.75, y: 2.25, width: 11, height: 8.5), degrees: -10)
            let focused = NSRect(x: 6.75, y: 5.75, width: 11.5, height: 8.5)
            let gap = NSBezierPath(rect: bounds)
            gap.append(window(focused, degrees: 4, inset: -1.5))
            gap.windingRule = .evenOdd
            NSGraphicsContext.saveGraphicsState()
            gap.addClip()
            NSColor.black.withAlphaComponent(0.5).setStroke()
            earlier.lineWidth = 1.5
            earlier.stroke()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.setFill()
            window(focused, degrees: 4).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
