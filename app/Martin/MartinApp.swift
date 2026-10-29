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
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: delegate.updater)
            }
            CommandGroup(replacing: .appSettings) {
                SettingsButton(app: delegate.app)
            }
            CommandGroup(replacing: .newItem) {
                QuickNoteButton(app: delegate.app)
            }
            CommandMenu("Note") {
                NoteActions(app: delegate.app, meeting: delegate.app.focusedNote, placement: .menu)
            }
            CommandMenu("Project") {
                ProjectActions(app: delegate.app, project: delegate.app.focusedProject, placement: .menu)
                Divider()
                Toggle("Show Secret Projects", isOn: Bindable(delegate.app).showsSecrets)
                    .keyboardShortcut(SecretsToggle.shortcut)
            }
            CommandGroup(before: .windowList) {
                ForEach(HomePage.shown(hiding: delegate.app.hiddenPages), id: \.self) { page in
                    Button(page.title) { delegate.app.openHome(on: page) }
                        .keyboardShortcut(delegate.app.shortcut(of: page).map { KeyboardShortcut(KeyEquivalent(Character(String($0)))) })
                }
                Divider()
                Button("Archive") { delegate.app.openArchive() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
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
    let updater = Updater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.reopen()
        Task { await app.suggestRepositories() }
    }

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
    private static let assistantKey = "assistant"
    let library: MeetingLibrary
    private let defaults: UserDefaults
    private let finder: RepositoryFinder
    private(set) var meetings: [Meeting] = []
    private(set) var allProjects: [Project] = []
    private(set) var previews: [Meeting.ID: String] = [:]
    private(set) var clones: [Repository] = []
    private(set) var suggestions: [Project.ID: RepositorySuggestion] = [:]
    @ObservationIgnored private var scouting: Task<[Repository], Never>?
    @ObservationIgnored private var lookupRound = 0
    var page: HomePage {
        didSet { defaults.set(page.rawValue, forKey: Self.pageKey) }
    }
    var hiddenPages: Set<HomePage> {
        didSet { defaults.set(hiddenPages.map(\.rawValue).sorted(), forKey: Self.hiddenPagesKey) }
    }
    var assistant: Assistant? {
        didSet {
            defaults.set(assistant?.rawValue, forKey: Self.assistantKey)
            suggestions = [:]
            lookupRound += 1
        }
    }
    var selectedShelf: Shelf.ID?
    var showsSecrets = false
    var hiddenCalendars: Set<EventCalendar.ID> {
        didSet { defaults.set(hiddenCalendars.sorted(), forKey: Self.hiddenCalendarsKey) }
    }
    private var keyWindow: String?
    @ObservationIgnored private var windows: [String: NSWindow] = [:]

    init(library: MeetingLibrary = MeetingLibrary(), defaults: UserDefaults = .standard, finder: RepositoryFinder = RepositoryFinder()) {
        self.library = library
        self.defaults = defaults
        self.finder = finder
        page = defaults.string(forKey: Self.pageKey).flatMap(HomePage.init) ?? .upcoming
        hiddenPages = Set((defaults.stringArray(forKey: Self.hiddenPagesKey) ?? []).compactMap(HomePage.init))
        assistant = defaults.string(forKey: Self.assistantKey).flatMap(Assistant.init)
        hiddenCalendars = Set(defaults.stringArray(forKey: Self.hiddenCalendarsKey) ?? [])
        reload()
        observeWindows()
    }

    func meeting(_ id: Meeting.ID) -> Meeting? {
        meetings.first { $0.id == id }
    }

    var focusedNote: Meeting? {
        keyWindow.flatMap(meeting)
    }

    var focusedProject: Project? {
        guard keyWindow == "home", page == .projects, case .project(let id) = selectedShelf else { return nil }
        return projects.first { $0.id == id }
    }

    var notes: [Meeting] {
        revealed.filter { $0.archivedAt == nil }
    }

    var pinned: [Meeting] {
        revealed.filter(\.isPinned).sorted { $0.pinnedAt! > $1.pinnedAt! }
    }

    var unpinned: [Meeting] {
        notes.filter { !$0.isPinned }
    }

    var shelves: [Shelf] {
        notes.shelved(in: projects.filter { showsSecrets || !$0.isSecret })
    }

    private var revealed: [Meeting] {
        guard !showsSecrets else { return meetings }
        let secrets = Set(allProjects.filter(\.isSecret).map(\.id))
        return meetings.filter { $0.project.map(secrets.contains) != true }
    }

    var archive: [Meeting] {
        meetings.filter { $0.archivedAt != nil }
    }

    var pages: [HomePage] {
        HomePage.shown(hiding: hiddenPages, on: page)
    }

    func shortcut(of page: HomePage) -> Int? {
        HomePage.shown(hiding: hiddenPages).firstIndex(of: page).map { $0 + 1 }
    }

    var people: [Person] {
        meetings.flatMap(\.attendees)
    }

    var projects: [Project] {
        allProjects.filter { $0.archivedAt == nil }
    }

    var archivedProjects: [Project] {
        allProjects.filter { $0.archivedAt != nil }
    }

    func notes(in project: Project) -> [Meeting] {
        meetings.filter { $0.project == project.id }
    }

    func project(of meeting: Meeting) -> Project? {
        projects.first { $0.id == meeting.project }
    }

    func projectName(of meeting: Meeting) -> String {
        allProjects.first { $0.id == meeting.project }?.name ?? Shelf.unassigned
    }

    func reload() {
        meetings = (try? library.meetings()) ?? []
        allProjects = (try? library.projects()) ?? []
        previews = meetings.reduce(into: [:]) { previews, meeting in
            previews[meeting.id] = library.note(of: meeting).flatMap(Markdown.preview(of:))
        }
    }

    func start(_ event: CalendarEvent) {
        begin { try library.meeting(for: event) }
    }

    func quickNote(in project: Project.ID? = nil) {
        begin { try library.create(project: project) }
    }

    private func begin(_ make: () throws -> Meeting) {
        do {
            let meeting = try make()
            reload()
            open(meeting)
        } catch {
            explain(error)
        }
    }

    func file(_ meeting: Meeting, in project: Project.ID?) {
        try? library.file(self.meeting(meeting.id) ?? meeting, in: project)
        reload()
    }

    func file(_ meeting: Meeting, inNewProjectNamed name: String) {
        guard let project = try? library.createProject(named: name) else { return }
        file(meeting, in: project.id)
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

    func pin(_ meeting: Meeting, _ pinned: Bool) {
        var changed = self.meeting(meeting.id) ?? meeting
        changed.pinnedAt = pinned ? .now : nil
        try? library.save(changed)
        reload()
    }

    func archive(_ meeting: Meeting) {
        windows[meeting.id]?.close()
        var archived = self.meeting(meeting.id) ?? meeting
        archived.archivedAt = .now
        try? library.save(archived)
        reload()
    }

    func restore(_ meeting: Meeting) {
        try? library.restore(self.meeting(meeting.id) ?? meeting)
        reload()
    }

    func delete(_ meeting: Meeting) {
        windows[meeting.id]?.close()
        try? library.delete(meeting)
        reload()
    }

    func confirmDeletion(of meeting: Meeting) {
        guard confirm("Delete “\(meeting.displayTitle)”?", "This note will be deleted immediately. You can’t undo this action.") else { return }
        delete(meeting)
    }

    func rename(_ project: Project, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var renamed = allProjects.first(where: { $0.id == project.id }), !name.isEmpty, renamed.name != name else { return }
        renamed.name = name
        try? library.save(renamed)
        reload()
    }

    func link(_ project: Project, to repository: RepositoryLink?) {
        guard var linked = allProjects.first(where: { $0.id == project.id }), linked.repository != repository else { return }
        linked.repository = repository
        try? library.save(linked)
        if let folder = repository?.folder {
            try? library.save(RepositoryLookup(folder: folder), for: project.id)
            suggestions[project.id] = .found(Repository(at: folder))
        }
        reload()
    }

    func chooseRepository(for project: Project) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Link"
        panel.message = "Choose the repository folder for \(project.name)."
        panel.directoryURL = project.repository?.folder ?? Repository.roots.first
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        guard Repository(at: folder) != nil else {
            return inform("“\(folder.lastPathComponent)” isn’t a GitHub repository", "Choose a folder cloned from GitHub.")
        }
        link(project, to: .folder(folder))
    }

    func scoutRepositories() async {
        let folders = allProjects.compactMap { $0.repository?.folder?.deletingLastPathComponent() }
        let scouting = Task { [finder] in await finder.nearby(folders) }
        self.scouting = scouting
        clones = await scouting.value
    }

    func addRepository(to project: Project) {
        guard case .found(let repository?) = suggestions[project.id] else { return link(project, to: .unset) }
        link(project, to: .folder(repository.folder))
    }

    func suggestRepositories() async {
        for project in projects where !project.isSecret {
            await suggestRepository(for: project)
        }
    }

    func suggestRepository(for project: Project) async {
        guard project.repository?.folder == nil, suggestions[project.id] == nil else { return }
        if let saved = (try? library.lookups())?[project.id] {
            return found(saved.folder.flatMap(Repository.init(at:)), for: project)
        }
        guard let assistant else { return }
        suggestions[project.id] = .thinking
        let round = lookupRound
        if scouting == nil { await scoutRepositories() }
        let candidates = await scouting?.value ?? []
        let notes = notes(in: project).prefix(Agent.noteLimit).map { "# \($0.displayTitle)\n\(library.note(of: $0) ?? "")" }
        let matches = await finder.match(project, notes, candidates, assistant)
        let repository = await Task.detached { Agent.pick(for: project, matches: matches ?? [], among: candidates) }.value
        guard round == lookupRound, allProjects.contains(where: { $0.id == project.id }) else { return }
        if matches != nil { try? library.save(RepositoryLookup(folder: repository?.folder), for: project.id) }
        found(repository, for: project)
    }

    private func found(_ repository: Repository?, for project: Project) {
        suggestions[project.id] = .found(repository)
        if let repository, let waiting = allProjects.first(where: { $0.id == project.id && $0.repository == .unset }) {
            link(waiting, to: .folder(repository.folder))
        }
    }

    func openAssistantSetup() {
        show(windows["assistant"] ?? present(AssistantSetup(app: self), id: "assistant", title: "Choose an Assistant", size: AssistantSetup.size))
    }

    func use(_ assistant: Assistant) {
        self.assistant = assistant
        closeAssistantSetup()
        Task { await suggestRepositories() }
    }

    func closeAssistantSetup() {
        windows["assistant"]?.close()
    }

    func keepSecret(_ project: Project, _ secret: Bool) {
        guard var changed = allProjects.first(where: { $0.id == project.id }) else { return }
        changed.secretAt = secret ? .now : nil
        if secret, !showsSecrets { notes(in: project).forEach { windows[$0.id]?.close() } }
        try? library.save(changed)
        reload()
    }

    func archive(_ project: Project) {
        notes(in: project).forEach { windows[$0.id]?.close() }
        try? library.archive(project)
        reload()
    }

    func restore(_ project: Project) {
        try? library.restore(project)
        reload()
    }

    func delete(_ project: Project) {
        notes(in: project).forEach { windows[$0.id]?.close() }
        suggestions[project.id] = nil
        try? library.delete(project)
        reload()
    }

    func confirmDeletion(of project: Project) {
        let count = notes(in: project).count
        let doomed = switch count {
        case 0: "This project"
        case 1: "This project and its note"
        default: "This project and all \(count) of its notes"
        }
        guard confirm("Delete “\(project.name)”?", "\(doomed) will be deleted immediately, including any in the Archive. You can’t undo this action.") else { return }
        delete(project)
    }

    private func confirm(_ message: String, _ detail: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
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

    func openArchive() {
        show(windows["archive"] ?? present(ArchiveView(app: self), id: "archive", title: "Archive", size: Self.windowSize))
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

    func present(_ view: some View, id: String, title: String, size: NSSize) -> NSWindow {
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
        return window
    }

    private func observeWindows() {
        observe(NSWindow.willCloseNotification) { app, id in
            app.windows[id] = nil
            app.resign(id)
        }
        observe(NSWindow.didBecomeKeyNotification) { app, id in app.keyWindow = id }
        observe(NSWindow.didResignKeyNotification) { app, id in app.resign(id) }
    }

    private func observe(_ name: Notification.Name, _ handle: @escaping @MainActor (AppState, String) -> Void) {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            guard let window = (notification.object as? NSWindow).map(ObjectIdentifier.init) else { return }
            MainActor.assumeIsolated {
                guard let self, let id = self.windows.first(where: { ObjectIdentifier($0.value) == window })?.key else { return }
                handle(self, id)
            }
        }
    }

    private func resign(_ id: String) {
        if keyWindow == id { keyWindow = nil }
    }

    private func explain(_ error: Error) {
        inform("Martin can't start the note", error.localizedDescription)
    }

    private func inform(_ message: String, _ detail: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}

extension Meeting {
    var displayTitle: String { title ?? untitled }
    var untitled: String { occurrence == nil ? "Quick note" : "Meeting" }
}

struct RepositoryFinder: Sendable {
    var nearby: @Sendable ([URL]) async -> [Repository] = Repository.nearby
    var match: @Sendable (Project, [String], [Repository], Assistant) async -> Set<String>? = Agent.match
}

enum RepositorySuggestion: Equatable {
    case thinking
    case found(Repository?)
}
