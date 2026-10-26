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

    @Test func mentionLinksTheNameToTheEmail() {
        #expect(Person(email: "kim.k@goodnotes.com").mention == "[@kim.k](mailto:kim.k@goodnotes.com)")
        #expect(Person(email: "a@x.com", name: "Ada [Labs]").mention == "[@Ada Labs](mailto:a@x.com)")
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
