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
        Page(title: current.displayTitle) {
            header
        } content: {
            MarkdownEditor(text: $note, attendees: current.attendees, acquaintances: app.people)
                .frame(maxHeight: .infinity)
                .padding(.bottom, Theme.margin)
        }
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
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Meeting", text: $title)
                    .textFieldStyle(.plain)
                    .font(Theme.title)
                    .foregroundStyle(Theme.ink)
                    .focused($editingTitle)
                    .onSubmit { editingTitle = false }
                if let year {
                    Text(year)
                        .font(Theme.meta)
                        .foregroundStyle(Theme.secondary)
                }
            }
            DateLeaf(date: current.date)
        }
        .column()
    }

    private var year: String? {
        let start = current.date
        return Calendar.current.isDate(start, equalTo: .now, toGranularity: .year) ? nil : start.formatted(.dateTime.year())
    }

    private func save() {
        guard !((library.note(of: meeting) ?? "") as NSString).isEqual(to: note) else { return }
        try? library.saveNote(note, for: meeting)
    }
}

private struct DateLeaf: View {
    private static let unit: CGFloat = 46 / 20
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 3.75 * Self.unit, weight: .bold))
                .tracking(-0.0375 * Self.unit)
                .foregroundStyle(.white)
                .offset(y: 0.625 * Self.unit)
                .frame(maxWidth: .infinity, maxHeight: 6.25 * Self.unit)
                .background(LinearGradient(colors: [Color(red: 0.996, green: 0.373, blue: 0.341), Color(red: 0.922, green: 0.322, blue: 0.290)], startPoint: .top, endPoint: .bottom))
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 12.5 * Self.unit))
                .foregroundStyle(.black)
                .offset(y: 0.225 * Self.unit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LinearGradient(colors: [.white, Color(red: 0.949, green: 0.945, blue: 0.933)], startPoint: .top, endPoint: .bottom))
        }
        .frame(width: 20 * Self.unit, height: 20 * Self.unit)
        .clipShape(.rect(cornerRadius: 5.15625 * Self.unit, style: .continuous))
        .shadow(color: .black.opacity(0.13), radius: 0.546 * Self.unit, y: 0.437 * Self.unit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }
}
