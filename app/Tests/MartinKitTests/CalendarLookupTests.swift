import Foundation
import Testing
@testable import MartinKit

struct CalendarLookupTests {
    @Test func emailNameIsLocalPart() {
        #expect(CalendarLookup.emailName(URL(string: "mailto:ada.lovelace@example.com")!) == "ada.lovelace")
        #expect(CalendarLookup.emailName(URL(string: "https://example.com/ada")!) == nil)
    }
}
