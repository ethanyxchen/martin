import AppKit
import MartinKit
import SwiftUI

@main
struct MartinApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBar(app: delegate.app)
        } label: {
            Image(nsImage: .menuBarIcon)
        }
        .commands {
            TextEditingCommands()
            CommandMenu("Format") {
                ForEach(NoteTextView.formats, id: \.title) { format in
                    Button(format.title) { NSApp.sendAction(format.action, to: nil, from: nil) }
                        .keyboardShortcut(KeyEquivalent(format.key), modifiers: format.shift ? [.command, .shift] : .command)
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppState()

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        app.reopen()
        return true
    }
}

@MainActor
@Observable
final class AppState {
    private static let page = NSSize(width: 520, height: 640)
    let library = MeetingLibrary()
    private(set) var meetings: [Meeting] = []
    @ObservationIgnored private var windows: [String: NSWindow] = [:]

    init() {
        reload()
    }

    func meeting(_ id: Meeting.ID) -> Meeting? {
        meetings.first { $0.id == id }
    }

    func reload() {
        meetings = (try? library.meetings()) ?? []
    }

    func start(_ event: CalendarEvent?) {
        do {
            let existing = try event.flatMap { try library.meeting(for: $0.occurrence) }
            let meeting = try existing ?? library.create(occurrence: event?.occurrence, title: event?.title, attendees: event?.attendees ?? [])
            reload()
            open(meeting)
        } catch {
            explain(error)
        }
    }

    func rename(_ meeting: Meeting, to title: String) {
        var renamed = meeting
        renamed.title = title.isEmpty ? nil : title
        guard renamed != meeting else { return }
        try? library.save(renamed)
        reload()
        windows[meeting.id]?.title = renamed.displayTitle
    }

    func open(_ meeting: Meeting) {
        show(windows[meeting.id] ?? present(NoteView(app: self, meeting: meeting), id: meeting.id, title: meeting.displayTitle, size: Self.page))
    }

    func reopen() {
        if windows.isEmpty { openUpcoming() }
    }

    func openUpcoming() {
        show(windows["upcoming"] ?? present(UpcomingView(app: self), id: "upcoming", title: "Upcoming Meetings", size: Self.page))
    }

    private func show(_ window: NSWindow) {
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate()
    }

    private func present(_ view: some View, id: String, title: String, size: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = Theme.paper.ns
        window.contentMinSize = NSSize(width: 420, height: 420)
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(size)
        window.center()
        windows[id] = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windows[id] = nil }
        }
        return window
    }

    private func explain(_ error: Error) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Martin can't start the meeting"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

extension Meeting {
    var displayTitle: String { title ?? "Meeting" }
}
