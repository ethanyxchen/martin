import AppKit
import MartinKit
import Testing
@testable import Martin

@MainActor
struct NoteTextViewTests {
    @Test(arguments: ["", "# Standup\n- shipped icons"])
    func openingANoteFocusesItsEditorWithTheCaretAtTheEnd(note: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), styleMask: .titled, backing: .buffered, defer: true)
        let textView = NoteTextView.make()
        textView.load(note)
        window.contentView = textView
        #expect(window.firstResponder === textView)
        #expect(textView.selectedRange() == NSRange(location: (note as NSString).length, length: 0))
    }

    @Test func theCursorBecomesAPointingHandOverACheckbox() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), styleMask: .titled, backing: .buffered, defer: false)
        let textView = NoteTextView.make()
        textView.frame = window.contentRect(forFrameRect: window.frame)
        textView.load("- [ ] milk")
        window.contentView = textView
        func point(over location: Int) -> NSPoint {
            let rect = window.convertFromScreen(textView.firstRect(forCharacterRange: NSRange(location: location, length: 1), actualRange: nil))
            return textView.convert(NSPoint(x: rect.midX, y: rect.midY), from: nil)
        }
        #expect(textView.cursor(at: point(over: 3)) == .pointingHand)
        #expect(textView.cursor(at: point(over: 7)) == nil)
        textView.isEditable = false
        #expect(textView.cursor(at: point(over: 3)) == nil)
    }
}

@MainActor
struct NoteImageEditingTests {
    private func folder() throws -> (NoteImages, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return (NoteImages(meetingFolder: url), url)
    }

    private func png(width: Int = 400, height: Int = 200) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func editor(_ note: String, images: NoteImages) -> NoteTextView {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 640), styleMask: .titled, backing: .buffered, defer: true)
        let textView = NoteTextView.make()
        textView.frame = NSRect(x: 0, y: 0, width: 640, height: 640)
        textView.images = images
        textView.load(note)
        window.contentView = textView
        return textView
    }

    @Test func anImageLineShowsTheImageInsteadOfItsMarkdown() throws {
        let (images, url) = try folder()
        defer { try? FileManager.default.removeItem(at: url) }
        let path = try images.add(png(), fileExtension: "png")
        let textView = editor("![](\(path) \"width=200\")", images: images)
        #expect(textView.intrinsicContentSize.height >= 100 + 12)
        let missing = editor("![](images/gone.png)", images: images)
        #expect(missing.intrinsicContentSize.height < 100)
        #expect(missing.skippingImages(NSRange(location: 3, length: 0)) == NSRange(location: 3, length: 0))
    }

    @Test func aCaretLandingOnAnImageSelectsTheWholeImage() throws {
        let (images, url) = try folder()
        defer { try? FileManager.default.removeItem(at: url) }
        let line = "![](\(try images.add(png(), fileExtension: "png")))"
        let textView = editor("a\n\(line)\nb", images: images)
        let contents = NSRange(location: 2, length: (line as NSString).length)
        #expect(textView.skippingImages(NSRange(location: 5, length: 0)) == contents)
        #expect(textView.skippingImages(NSRange(location: 2, length: 0)) == contents)
        #expect(textView.skippingImages(NSRange(location: 0, length: 1)) == NSRange(location: 0, length: 1))
        #expect(textView.skippingImages(NSRange(location: NSMaxRange(contents) + 1, length: 0)) == NSRange(location: NSMaxRange(contents) + 1, length: 0))
    }

    @Test func aSelectedImageIsOutlinedInsteadOfHighlightedLikeText() throws {
        let (images, url) = try folder()
        defer { try? FileManager.default.removeItem(at: url) }
        let line = "![](\(try images.add(png(), fileExtension: "png")))"
        let textView = editor("a\n\(line)", images: images)
        let ordinary = textView.selectedTextAttributes[.backgroundColor] as? NSColor
        textView.setSelectedRange(NSRange(location: 2, length: (line as NSString).length))
        #expect(textView.selectedTextAttributes[.backgroundColor] as? NSColor == .clear)
        textView.setSelectedRange(NSRange(location: 0, length: 1))
        #expect(textView.selectedTextAttributes[.backgroundColor] as? NSColor == ordinary)
    }

    @Test func movingUpOrLeftFromAnImageAtTheTopOpensALineAboveIt() throws {
        let (images, url) = try folder()
        defer { try? FileManager.default.removeItem(at: url) }
        let line = "![](\(try images.add(png(), fileExtension: "png")))"
        for selector in [#selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveLeft(_:))] {
            let textView = editor(line, images: images)
            textView.setSelectedRange(NSRange(location: 0, length: (line as NSString).length))
            #expect(textView.moveOffImage(for: selector))
            #expect(textView.string == "\n" + line)
            #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
            textView.insertText("Title", replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(textView.string == "Title\n" + line)
        }
    }

    @Test func deletingASelectedImageRemovesItsWholeLine() throws {
        let (images, url) = try folder()
        defer { try? FileManager.default.removeItem(at: url) }
        let line = "![](\(try images.add(png(), fileExtension: "png")))"
        let textView = editor("a\n\(line)\nb", images: images)
        textView.setSelectedRange(NSRange(location: 2, length: (line as NSString).length))
        textView.deleteBackward(nil)
        #expect(textView.string == "a\nb")
    }

    @Test func typingWithAnImageSelectedKeepsTheImageAndTypesBelowIt() throws {
        let (images, url) = try folder()
        defer { try? FileManager.default.removeItem(at: url) }
        let line = "![](\(try images.add(png(), fileExtension: "png")))"
        let textView = editor(line, images: images)
        textView.setSelectedRange(NSRange(location: 0, length: (line as NSString).length))
        textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(textView.string == line + "\nx")
    }

    @Test func resizingAnImageStoresItsWidthInTheMarkdown() throws {
        let (images, url) = try folder()
        defer { try? FileManager.default.removeItem(at: url) }
        let path = try images.add(png(), fileExtension: "png")
        let textView = editor("![](\(path))", images: images)
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))
        textView.resizeSelectedImage(to: 120)
        #expect(textView.string == "![](\(path) \"width=120\")")
        #expect(textView.selectedImage?.image.width == 120)
        textView.resizeSelectedImage(to: nil)
        #expect(textView.string == "![](\(path))")
    }

    @Test func insertingImagesPutsEachOnItsOwnLineBetweenTheSurroundingText() throws {
        let (images, url) = try folder()
        defer { try? FileManager.default.removeItem(at: url) }
        let textView = editor("one\ntwo", images: images)
        textView.insertImages([ImageItem(data: png(), fileExtension: "png")], at: 4)
        let lines = textView.string.components(separatedBy: "\n")
        #expect(lines.count == 3 && lines[0] == "one" && lines[2] == "two")
        let image = try #require(NoteImage(line: lines[1]))
        #expect(images.url(for: image.path).map { FileManager.default.fileExists(atPath: $0.path) } == true)
        textView.insertImages([ImageItem(data: png(), fileExtension: "png")], at: (textView.string as NSString).length)
        let after = textView.string.components(separatedBy: "\n")
        #expect(after.count == 5 && after[2] == "two" && NoteImage(line: after[3]) != nil && after[4] == "")
    }

    @Test func aDroppedImageLandsOnTheNearestLineBreak() throws {
        let (images, url) = try folder()
        defer { try? FileManager.default.removeItem(at: url) }
        let textView = editor("one\ntwo\nthree", images: images)
        let top = textView.dropTarget(at: NSPoint(x: 100, y: 0))
        let middle = textView.dropTarget(at: NSPoint(x: 100, y: textView.textContainerOrigin.y + 24 + 20))
        let bottom = textView.dropTarget(at: NSPoint(x: 100, y: 600))
        #expect(top.location == 0)
        #expect(middle.location == 8)
        #expect(bottom.location == 13)
        #expect(middle.y > top.y)
    }
}
