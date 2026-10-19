import Testing
@testable import MartinKit

@MainActor
struct RecorderTests {
    @Test func keytermsDedupeAndIncludeFirstNames() {
        let settings = Settings(name: "Ethan Chen", aliases: ["ethan chen", "EC"], keyterms: [" Martin ", "", "Deepgram"])
        #expect(Recorder.keyterms(settings: settings, attendees: ["Ada Lovelace", "Ethan Chen"]) == ["Ethan Chen", "EC", "Martin", "Deepgram", "Ada Lovelace", "Ada", "Ethan"])
    }

    @Test func keytermsAreCapped() {
        let settings = Settings(name: "Ethan", keyterms: (0..<100).map { "term\($0)" })
        #expect(Recorder.keyterms(settings: settings, attendees: []).count == 50)
    }
}
