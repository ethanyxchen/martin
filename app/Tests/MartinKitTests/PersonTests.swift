import Testing
@testable import MartinKit

struct PersonTests {
    @Test func personIsKeyedByLowercasedEmail() {
        #expect(Person(email: "Kim.K@GoodNotes.com", name: "Kim Kam") == Person(email: "kim.k@goodnotes.com", name: "Kim Kam"))
        #expect(Person(email: "kim.k@goodnotes.com", name: "Kim.K@goodnotes.com").name == nil)
        #expect(Person(email: "kim.k@goodnotes.com", name: "").name == nil)
    }

    @Test func displayNameFallsBackToTheEmailLocalPart() {
        #expect(Person(email: "kim.k@goodnotes.com").displayName == "kim.k")
        #expect(Person(email: "kim.k@goodnotes.com", name: "Kim Kam").displayName == "Kim Kam")
    }

    @Test func mentionNamesTheEmailWithoutLinkingIt() {
        #expect(Person(email: "inamiy@goodnotes.com").mention == "@{inamiy@goodnotes.com}")
        #expect(Person(email: "kim.k@goodnotes.com", name: "Kim Kam").mention == "@{Kim Kam <kim.k@goodnotes.com>}")
        #expect(Person(email: "a@x.com", name: "Ada <Labs>").mention == "@{Ada Labs <a@x.com>}")
        #expect(Person(email: "a@x.com", name: "{}").mention == "@{a@x.com}")
    }

    @Test func matchesAreTheQueryAtTheStartOfEachWord() {
        func matched(_ query: String, in text: String) -> [String] {
            text.wordMatches(of: query).map { String(text[$0]) }
        }
        #expect(matched("k", in: "Kim Kam") == ["K", "K"])
        #expect(matched("ka", in: "Kim Kam") == ["Ka"])
        #expect(matched("kim.k", in: "kim.k@goodnotes.com") == ["kim.k"])
        #expect(matched("goodnotes", in: "kim.k@goodnotes.com").isEmpty)
        #expect(matched("kimberly", in: "Kim").isEmpty)
    }

    @Test func suggestionsMatchNameWordsOrEmailOncePerPerson() {
        let kim = Person(email: "kim.k@goodnotes.com")
        let kevin = Person(email: "kevin@goodnotes.com", name: "Kevin Kam")
        let ada = Person(email: "ada@example.com", name: "Ada Lovelace")
        let people = [kim, ada, kevin, Person(email: "KIM.K@goodnotes.com", name: "Kim Kardashian")]
        #expect(people.suggestions(for: "") == [kim, ada, kevin])
        #expect(people.suggestions(for: "kim") == [kim])
        #expect(people.suggestions(for: "K") == [kim, kevin])
        #expect(people.suggestions(for: "kam") == [kevin])
        #expect(people.suggestions(for: "love") == [ada])
        #expect(people.suggestions(for: "zed").isEmpty)
    }
}
