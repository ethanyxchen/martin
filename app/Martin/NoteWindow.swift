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
            MarkdownEditor(text: $note)
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
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Meeting", text: $title)
                    .textFieldStyle(.plain)
                    .font(Theme.title)
                    .foregroundStyle(Theme.ink)
                    .focused($editingTitle)
                    .onSubmit { editingTitle = false }
                Text(details)
                    .font(Theme.meta.monospacedDigit())
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            DateLeaf(date: current.startedAt)
        }
        .column()
        .padding(.top, 46)
        .padding(.bottom, 22)
        .movesWindow()
    }

    private var details: String {
        let start = current.startedAt
        let year = Calendar.current.isDate(start, equalTo: .now, toGranularity: .year) ? [] : [start.formatted(.dateTime.year())]
        return (year + [start.formatted(date: .omitted, time: .shortened)]).joined(separator: "  ·  ")
    }

    private func save() {
        guard !((library.note(of: meeting) ?? "") as NSString).isEqual(to: note) else { return }
        try? library.saveNote(note, for: meeting)
    }
}

private struct DateLeaf: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(Theme.ember)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 24, weight: .semibold, design: .serif).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .padding(.top, 3)
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.tertiary)
                .padding(.bottom, 6)
        }
        .frame(width: 48)
        .background(Theme.well)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.tertiary.opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }
}
