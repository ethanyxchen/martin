import Foundation
import Testing
@testable import MartinKit

struct DeepgramTests {
    func message(type: String = "Results", isFinal: Bool = true, transcript: String = "ship it on Friday") -> Data {
        Data(#"{"type":"\#(type)","is_final":\#(isFinal),"speech_final":true,"start":12.5,"duration":2.25,"channel":{"alternatives":[{"transcript":"\#(transcript)","confidence":0.98}]}}"#.utf8)
    }

    @Test func finalResultBecomesSegment() {
        #expect(DeepgramStream.segment(from: message()) == Segment(at: 12.5, duration: 2.25, text: "ship it on Friday"))
    }

    @Test func interimResultIsSkipped() {
        #expect(DeepgramStream.segment(from: message(isFinal: false)) == nil)
    }

    @Test func emptyTranscriptIsSkipped() {
        #expect(DeepgramStream.segment(from: message(transcript: " ")) == nil)
    }

    @Test func otherMessageTypesAreSkipped() {
        #expect(DeepgramStream.segment(from: Data(#"{"type":"Metadata","request_id":"abc","duration":3.0}"#.utf8)) == nil)
        #expect(DeepgramStream.segment(from: message(type: "UtteranceEnd")) == nil)
    }

    @Test func urlRepeatsEncodedKeyterms() {
        let url = DeepgramStream.url(keyterms: ["Ethan Chen", "C++", "a&b=c"]).absoluteString
        #expect(url == "wss://api.deepgram.com/v1/listen?model=nova-3&encoding=linear16&sample_rate=16000&channels=1&smart_format=true&interim_results=false&mip_opt_out=true&keyterm=Ethan%20Chen&keyterm=C%2B%2B&keyterm=a%26b%3Dc")
    }

    @Test func urlCapsKeytermsByBudget() {
        let terms = (0..<200).map { "term\($0)-" + String(repeating: "x", count: 10) }
        let query = URLComponents(url: DeepgramStream.url(keyterms: terms), resolvingAgainstBaseURL: false)!.queryItems!
        let kept = query.filter { $0.name == "keyterm" }.compactMap(\.value)
        #expect(kept == Array(terms.prefix(kept.count)))
        #expect(kept.joined().count <= DeepgramStream.keytermBudget)
        #expect(kept.count > 50)
    }

    @Test func fatalCloses() {
        #expect(DeepgramStream.failure(closeCode: 0, status: 401) != nil)
        #expect(DeepgramStream.failure(closeCode: 1008, status: 101) != nil)
        #expect(DeepgramStream.failure(closeCode: 1011, status: 101) == nil)
        #expect(DeepgramStream.failure(closeCode: 1006, status: nil) == nil)
        #expect(DeepgramStream.failure(closeCode: 0, status: 429) == nil)
    }
}
