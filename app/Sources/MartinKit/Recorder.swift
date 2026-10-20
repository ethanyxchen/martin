import Foundation
import Observation

@MainActor
@Observable
public final class Recorder {
    public enum Phase: Equatable {
        case idle
        case recording(Meeting, since: Date)
        case analyzing(Meeting)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var level: Float = 0
    public private(set) var lastLine: String?
    public private(set) var transcriptionError: String?
    public private(set) var briefing: Briefing?
    public private(set) var bullets: [Bullet] = []
    public private(set) var assistantError: String?
    public var onNoteReady: ((Meeting) -> Void)?

    public let library: MeetingLibrary
    private var microphone: Microphone?
    private var stream: DeepgramStream?
    private var systemAudio: SystemAudio?
    private var assistant: Task<Void, Never>?
    private var heard = 0

    public init(library: MeetingLibrary = MeetingLibrary()) {
        self.library = library
    }

    public func start(_ event: CalendarEvent?) async throws {
        guard phase == .idle else { return }
        guard let apiKey = Secrets.get(Secrets.deepgram) else { throw Analyzer.Failure(errorDescription: "Add a Deepgram API key in Settings.") }
        try await Microphone.authorize()
        let settings = Settings.load()
        let meeting = try library.create(title: event?.title, attendees: event?.attendees ?? [], calendarNotes: event?.notes)
        let stream = DeepgramStream(apiKey: apiKey, keyterms: Self.keyterms(settings: settings, attendees: meeting.attendees))
        let library = library
        let microphone = Microphone()
        try microphone.start(
            writingTo: library.audioURL(of: meeting),
            onLevel: { [weak self] level in Task { @MainActor in self?.level = level } },
            onAudio: { stream.send($0) }
        )
        let systemAudio = SystemAudio()
        do {
            try systemAudio.start(onAudio: { microphone.mix($0) })
        } catch {
            Log.audio.error("System audio unavailable, recording the microphone only: \(error.localizedDescription, privacy: .public)")
        }
        stream.connect(
            onSegment: { [weak self] segment in
                try? library.append(segment, to: meeting)
                Task { @MainActor in self?.lastLine = segment.text }
            },
            onError: { [weak self] message in Task { @MainActor in self?.transcriptionError = message } }
        )
        self.stream = stream
        self.microphone = microphone
        self.systemAudio = systemAudio
        lastLine = nil
        transcriptionError = nil
        forget()
        phase = .recording(meeting, since: .now)
        assistant = Task { await assist(in: meeting) }
    }

    public func stop() async {
        guard case .recording(var meeting, _) = phase else { return }
        systemAudio?.stop()
        microphone?.stop()
        await stream?.finish()
        systemAudio = nil
        microphone = nil
        stream = nil
        level = 0
        meeting.endedAt = .now
        try? library.save(meeting)
        phase = .analyzing(meeting)
        assistant?.cancel()
        await assistant?.value
        assistant = nil
        await write(meeting)
    }

    public func analyze(_ meeting: Meeting) async {
        forget()
        phase = .analyzing(meeting)
        await write(meeting)
    }

    private func assist(in meeting: Meeting) async {
        while !Task.isCancelled {
            do {
                try await catchUp(on: meeting)
                assistantError = nil
            } catch {
                assistantError = error.localizedDescription
                Log.assistant.error("Live pass failed: \(error.localizedDescription, privacy: .public)")
            }
            try? await Task.sleep(for: .seconds(15))
        }
    }

    private func write(_ meeting: Meeting) async {
        defer { phase = .idle }
        do {
            try await catchUp(on: meeting)
            Log.assistant.notice("Meeting \(meeting.id, privacy: .public) ended with \(self.heard) transcript lines and \(self.bullets.count) bullets")
            let silence = heard > 0 ? "Nothing in this meeting needed you." : "Nothing was transcribed."
            try library.saveNote(Note.markdown(briefing: briefing, bullets: bullets, silence: silence), for: meeting)
        } catch {
            Log.assistant.error("Writing the note failed: \(error.localizedDescription, privacy: .public)")
            try? library.saveAnalysisError(error.localizedDescription, for: meeting)
        }
        onNoteReady?(meeting)
    }

    private func catchUp(on meeting: Meeting) async throws {
        if briefing == nil { briefing = try await Self.briefing(for: meeting) }
        let transcript = try library.transcript(of: meeting)
        guard transcript.count > heard else { return }
        bullets += try await Analyzer.listen(meeting: meeting, work: briefing?.pullRequests ?? [], transcript: transcript, bullets: bullets, settings: Settings.load())
        heard = transcript.count
    }

    private func forget() {
        briefing = nil
        bullets = []
        assistantError = nil
        heard = 0
    }

    static func briefing(for meeting: Meeting) async throws -> Briefing {
        let until = meeting.startedAt
        let since = await CalendarLookup.previousStart(ofEventAt: until) ?? Calendar.current.date(byAdding: .day, value: -1, to: until)!
        return Briefing(since: since, until: until, pullRequests: try await Analyzer.work(since: Briefing.earliest(since: since, until: until)))
    }

    static func keyterms(settings: Settings, attendees: [String]) -> [String] {
        let names = attendees.flatMap { [$0, $0.split(separator: " ").first.map(String.init) ?? $0] }
        var seen = Set<String>()
        return ([settings.name] + settings.aliases + settings.keyterms + names)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(50)
            .map { $0 }
    }
}
