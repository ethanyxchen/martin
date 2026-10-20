import AppKit
import MartinKit
import SwiftUI

@main
struct MartinApp: App {
    @State private var app = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBar(app: app)
        } label: {
            Image(nsImage: .menuBarIcon(awake: app.recorder.phase != .idle))
        }
    }
}

@MainActor
@Observable
final class AppState {
    private static let page = NSSize(width: 520, height: 640)
    let recorder = Recorder()
    private(set) var meetings: [Meeting] = []
    @ObservationIgnored private var windows: [String: NSWindow] = [:]
    @ObservationIgnored private var pill: RecordingPill?

    init() {
        pill = RecordingPill(recorder: recorder)
        reload()
        recorder.onNoteReady = { [weak self] meeting in
            self?.reload()
            self?.open(meeting, activating: false)
        }
    }

    func meeting(_ id: Meeting.ID) -> Meeting? {
        meetings.first { $0.id == id }
    }

    func reload() {
        meetings = (try? recorder.library.meetings()) ?? []
    }

    func toggleRecording() async {
        switch recorder.phase {
        case .idle:
            await record(await CalendarLookup.currentEvent())
        case .recording:
            await recorder.stop()
        case .analyzing:
            return
        }
        reload()
    }

    func record(_ event: CalendarEvent?) async {
        do {
            try await recorder.start(event)
            reload()
            if case .recording(let meeting, _) = recorder.phase { open(meeting, activating: false) }
        } catch {
            explain(error)
        }
    }

    func rename(_ meeting: Meeting, to title: String) {
        var renamed = meeting
        renamed.title = title.isEmpty ? nil : title
        guard renamed != meeting else { return }
        try? recorder.library.save(renamed)
        reload()
        windows[meeting.id]?.title = renamed.displayTitle
    }

    func open(_ meeting: Meeting, activating: Bool = true) {
        let window = windows[meeting.id] ?? present(NoteView(app: self, meeting: meeting), id: meeting.id, title: meeting.displayTitle, size: Self.page)
        if activating {
            show(window)
        } else {
            window.orderFrontRegardless()
        }
    }

    func openUpcoming() {
        show(windows["upcoming"] ?? present(UpcomingView(app: self), id: "upcoming", title: "Upcoming Meetings", size: Self.page))
    }

    func openSettings() {
        show(windows["settings"] ?? present(SettingsView(), id: "settings", title: "Settings", size: NSSize(width: 560, height: 680)))
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
        alert.messageText = "Martin can't start recording"
        alert.informativeText = error.localizedDescription
        let needsKey = Secrets.get(Secrets.deepgram) == nil
        if needsKey {
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
        }
        if alert.runModal() == .alertFirstButtonReturn, needsKey { openSettings() }
    }
}

extension Meeting {
    var displayTitle: String { title ?? "Meeting" }
}
