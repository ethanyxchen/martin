import MartinKit
import SwiftUI

struct NoteView: View {
    let app: AppState
    let meeting: Meeting
    @State private var note: String?
    @State private var title: String
    @State private var showsTranscript = false
    @FocusState private var editingTitle: Bool

    init(app: AppState, meeting: Meeting) {
        self.app = app
        self.meeting = meeting
        _note = State(initialValue: app.recorder.library.note(of: meeting))
        _title = State(initialValue: meeting.title ?? "")
    }

    private enum Activity { case recording, writing }

    private var library: MeetingLibrary { app.recorder.library }
    private var current: Meeting { app.meeting(meeting.id) ?? meeting }

    private var activity: Activity? {
        switch app.recorder.phase {
        case .recording(let live, _) where live.id == meeting.id: .recording
        case .analyzing(let live) where live.id == meeting.id: .writing
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.paper)
        .ignoresSafeArea(edges: .top)
        .onChange(of: activity) {
            if activity == nil { note = library.note(of: meeting) }
        }
        .onChange(of: editingTitle) {
            if !editingTitle { app.rename(current, to: title) }
        }
        .task(id: note) {
            try? await Task.sleep(for: .milliseconds(600))
            save()
        }
        .onDisappear(perform: save)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("Meeting", text: $title)
                    .textFieldStyle(.plain)
                    .font(Theme.title)
                    .foregroundStyle(Theme.ink)
                    .focused($editingTitle)
                    .onSubmit { editingTitle = false }
                Button(showsTranscript ? "Notes" : "Transcript") { showsTranscript.toggle() }
                    .buttonStyle(.plain)
                    .font(Theme.meta)
                    .foregroundStyle(Theme.tertiary)
            }
            Text(details)
                .font(Theme.meta)
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.leading, Theme.column)
        .padding(.trailing, Theme.margin)
        .padding(.top, 46)
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private var content: some View {
        if showsTranscript {
            TranscriptView(segments: (try? library.transcript(of: meeting)) ?? [])
        } else if let activity {
            HStack(spacing: 10) {
                Waveform(level: 0, breathing: true)
                    .foregroundStyle(Theme.tertiary)
                Text(activity == .recording ? "Recording…" : "Writing notes…")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.leading, Theme.column)
        } else if let text = Binding($note) {
            MarkdownEditor(text: text)
        } else {
            Unwritten(error: library.analysisError(of: meeting)) {
                Task { await app.recorder.analyze(current) }
            }
        }
    }

    private var details: String {
        let day = current.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let start = current.startedAt.formatted(date: .omitted, time: .shortened)
        let time = current.endedAt.map { "\(start) – \($0.formatted(date: .omitted, time: .shortened))" } ?? start
        return ([day, time] + people).joined(separator: "  ·  ")
    }

    private var people: [String] {
        let attendees = current.attendees
        guard attendees.count > 3 else { return attendees.isEmpty ? [] : [attendees.formatted(.list(type: .and))] }
        return [attendees.prefix(2).joined(separator: ", ") + " and \(attendees.count - 2) others"]
    }

    private func save() {
        guard let note, note != library.note(of: meeting) else { return }
        try? library.saveNote(note, for: meeting)
    }
}

private struct Unwritten: View {
    let error: String?
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error == nil ? "No notes yet" : "Couldn’t write notes")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text(error ?? "Martin hasn’t written notes for this meeting.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .lineLimit(10)
            Button(error == nil ? "Write Notes" : "Try Again", action: retry)
                .padding(.top, 8)
        }
        .padding(.leading, Theme.column)
        .padding(.trailing, Theme.margin)
    }
}

private struct TranscriptView: View {
    let segments: [Segment]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if segments.isEmpty {
                    Text("Nothing was transcribed.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
                ForEach(segments, id: \.self) { segment in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(segment.text)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Duration.seconds(segment.at).formatted(.time(pattern: segment.at >= 3600 ? .hourMinuteSecond : .minuteSecond)))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }
            .textSelection(.enabled)
            .padding(.leading, Theme.column)
            .padding(.trailing, Theme.margin)
            .padding(.bottom, 28)
        }
    }
}
