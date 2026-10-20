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
    public var onNoteReady: ((Meeting) -> Void)?

    public let library: MeetingLibrary
    private var microphone: Microphone?
    private var stream: DeepgramStream?
    private var systemAudio: SystemAudio?

    public init(library: MeetingLibrary = MeetingLibrary()) {
        self.library = library
    }

    public func start() async throws {
        guard phase == .idle else { return }
        guard let apiKey = Secrets.get(Secrets.deepgram) else { throw Analyzer.Failure(errorDescription: "Add a Deepgram API key in Settings.") }
        try await Microphone.authorize()
        let settings = Settings.load()
        let event = await CalendarLookup.currentEvent()
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
        try? systemAudio.start(onAudio: { microphone.mix($0) })
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
        phase = .recording(meeting, since: .now)
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
        await analyze(meeting)
    }

    public func analyze(_ meeting: Meeting) async {
        phase = .analyzing(meeting)
        defer { phase = .idle }
        do {
            let note = try await Analyzer.note(for: meeting, transcript: library.transcript(of: meeting), settings: Settings.load())
            try library.saveNote(note, for: meeting)
        } catch {
            try? library.saveAnalysisError(error.localizedDescription, for: meeting)
        }
        onNoteReady?(meeting)
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
