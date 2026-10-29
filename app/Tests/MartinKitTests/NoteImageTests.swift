import Foundation
import Testing
@testable import MartinKit

struct NoteImageTests {
    @Test func aLineHoldingOnlyAnImageParsesWithItsWidth() {
        #expect(NoteImage(line: "![](images/a.png)") == NoteImage(path: "images/a.png"))
        #expect(NoteImage(line: "![chart](images/a.png \"width=320\")  ") == NoteImage(alt: "chart", path: "images/a.png", width: 320))
        #expect(NoteImage(line: "see ![](images/a.png)") == nil)
        #expect(NoteImage(line: "![](images/a.png) after") == nil)
        #expect(NoteImage(line: "[link](images/a.png)") == nil)
    }

    @Test func anImageWritesBackAsMarkdownWithItsWidth() {
        let image = NoteImage(alt: "x", path: "images/a.png")
        #expect(image.markdown == "![x](images/a.png)")
        #expect(image.resized(to: 300).markdown == "![x](images/a.png \"width=300\")")
        #expect(NoteImage(line: image.resized(to: 300).markdown)?.width == 300)
    }

    @Test func aNotePreviewSkipsImages() {
        #expect(Markdown.preview(of: "![](images/a.png)\nhello") == "hello")
        #expect(Markdown.preview(of: "![](images/a.png)") == nil)
    }

    @Test func imagesAreStoredInTheMeetingFolderAndLookedUpOnlyThere() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let images = NoteImages(meetingFolder: folder)
        let path = try images.add(Data([1, 2, 3]), fileExtension: "PNG")
        #expect(path.hasPrefix("images/") && path.hasSuffix(".png"))
        #expect(try Data(contentsOf: #require(images.url(for: path))) == Data([1, 2, 3]))
        #expect(try images.add(Data(), fileExtension: "exe").hasSuffix(".png"))
        #expect(images.url(for: "../meeting.json") == nil)
        #expect(images.url(for: "images/../../x.png") == nil)
        #expect(images.url(for: "/etc/passwd") == nil)
        #expect(images.url(for: "note.md") == nil)
    }
}
