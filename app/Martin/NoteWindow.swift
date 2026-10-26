import MartinKit
import SwiftUI

struct NoteView: View {
    let app: AppState
    let meeting: Meeting
    @State private var note: String
    @State private var title: String
    @FocusState private var editingTitle: Bool

    init(app: AppState, meeting: Meeting) {
        self.app = app
        self.meeting = meeting
        _note = State(initialValue: app.library.note(of: meeting) ?? "")
        _title = State(initialValue: meeting.title ?? "")
    }

    private var library: MeetingLibrary { app.library }
    private var current: Meeting { app.meeting(meeting.id) ?? meeting }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            MarkdownEditor(text: $note, people: app.people(for: current))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.paper)
        .ignoresSafeArea(edges: .top)
        .onChange(of: editingTitle) {
            if !editingTitle { app.rename(current, to: title) }
        }
        .task(id: note) {
            try? await Task.sleep(for: .milliseconds(600))
            save()
        }
        .onDisappear(perform: save)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in save() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Meeting", text: $title)
                .textFieldStyle(.plain)
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
                .focused($editingTitle)
                .onSubmit { editingTitle = false }
            Text(details)
                .font(Theme.meta)
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .column()
        .padding(.top, 46)
        .padding(.bottom, 22)
        .movesWindow()
    }

    private var details: String {
        let day = current.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let time = current.startedAt.formatted(date: .omitted, time: .shortened)
        return ([day, time] + people).joined(separator: "  ·  ")
    }

    private var people: [String] {
        let attendees = current.attendees.map(\.displayName)
        guard attendees.count > 3 else { return attendees.isEmpty ? [] : [attendees.formatted(.list(type: .and))] }
        return [attendees.prefix(2).joined(separator: ", ") + " and \(attendees.count - 2) others"]
    }

    private func save() {
        guard !((library.note(of: meeting) ?? "") as NSString).isEqual(to: note) else { return }
        try? library.saveNote(note, for: meeting)
    }
}
