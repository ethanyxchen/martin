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
            CommandGroup(replacing: .appSettings) {
                SettingsButton(app: delegate.app)
            }
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
    private static let windowSize = NSSize(width: 520, height: 640)
    private static let hiddenCalendarsKey = "hiddenCalendars"
    private static let pageKey = "page"
    private static let hiddenPagesKey = "hiddenPages"
    let library: MeetingLibrary
    private let defaults: UserDefaults
    private(set) var meetings: [Meeting] = []
    private(set) var previews: [Meeting.ID: String] = [:]
    var page: HomePage {
        didSet { defaults.set(page.rawValue, forKey: Self.pageKey) }
    }
    var hiddenPages: Set<HomePage> {
        didSet { defaults.set(hiddenPages.map(\.rawValue).sorted(), forKey: Self.hiddenPagesKey) }
    }
    var hiddenCalendars: Set<EventCalendar.ID> {
        didSet { defaults.set(hiddenCalendars.sorted(), forKey: Self.hiddenCalendarsKey) }
    }
    @ObservationIgnored private var windows: [String: NSWindow] = [:]

    init(library: MeetingLibrary = MeetingLibrary(), defaults: UserDefaults = .standard) {
        self.library = library
        self.defaults = defaults
        page = defaults.string(forKey: Self.pageKey).flatMap(HomePage.init) ?? .upcoming
        hiddenPages = Set((defaults.stringArray(forKey: Self.hiddenPagesKey) ?? []).compactMap(HomePage.init))
        hiddenCalendars = Set(defaults.stringArray(forKey: Self.hiddenCalendarsKey) ?? [])
        reload()
    }

    func meeting(_ id: Meeting.ID) -> Meeting? {
        meetings.first { $0.id == id }
    }

    var pages: [HomePage] {
        HomePage.shown(hiding: hiddenPages, on: page)
    }

    var people: [Person] {
        meetings.flatMap(\.attendees)
    }

    func reload() {
        meetings = (try? library.meetings()) ?? []
        previews = meetings.reduce(into: [:]) { previews, meeting in
            previews[meeting.id] = library.note(of: meeting).flatMap(Markdown.preview(of:))
        }
    }

    func start(_ event: CalendarEvent?) {
        do {
            let meeting = try event.map(library.meeting(for:)) ?? library.create()
            reload()
            open(meeting)
        } catch {
            explain(error)
        }
    }

    func save(_ note: String, for meeting: Meeting) {
        try? library.saveNote(note, for: meeting)
        previews[meeting.id] = Markdown.preview(of: note)
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
        show(windows[meeting.id] ?? present(NoteView(app: self, meeting: meeting), id: meeting.id, title: meeting.displayTitle, size: Self.windowSize))
    }

    func reopen() {
        if windows.isEmpty { openHome(on: page) }
    }

    func openHome(on page: HomePage) {
        self.page = page
        show(windows["home"] ?? present(HomeView(app: self), id: "home", title: "Martin", size: Self.windowSize))
    }

    func widenHome(by width: CGFloat, over duration: TimeInterval) {
        guard let window = windows["home"], !window.styleMask.contains(.fullScreen) else { return }
        var frame = window.frame
        frame.size.width += width
        if let visible = window.screen?.visibleFrame {
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = .drawer
            window.animator().setFrame(frame, display: true)
        }
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
        if let front = NSApp.orderedWindows.first(where: windows.values.contains) {
            window.cascadeTopLeft(from: front.cascadeTopLeft(from: .zero))
        } else {
            window.center()
        }
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
