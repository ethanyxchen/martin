import Foundation

public struct NoteImage: Equatable, Sendable {
    public let alt: String
    public let path: String
    public let width: Int?

    public init(alt: String = "", path: String, width: Int? = nil) {
        self.alt = alt
        self.path = path
        self.width = width
    }

    public init?(line: String) {
        let text = line as NSString
        guard let match = Self.pattern.firstMatch(in: line, options: .anchored, range: NSRange(location: 0, length: text.length)) else { return nil }
        let width = match.range(at: 3).location == NSNotFound ? nil : Int(text.substring(with: match.range(at: 3)))
        self.init(alt: text.substring(with: match.range(at: 1)), path: text.substring(with: match.range(at: 2)), width: width)
    }

    public var markdown: String {
        "![\(alt)](\(path)\(width.map { " \"width=\($0)\"" } ?? ""))"
    }

    public func resized(to width: Int?) -> NoteImage {
        NoteImage(alt: alt, path: path, width: width)
    }

    private static let pattern = try! NSRegularExpression(pattern: #" {0,3}!\[([^\[\]\n]*)\]\(([^)\s]+)(?:[ \t]+"width=(\d{1,5})")?\)[ \t]*$"#)
}

public struct NoteImages: Equatable, Sendable {
    public static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "heic", "webp"]

    public let meetingFolder: URL

    public init(meetingFolder: URL) {
        self.meetingFolder = meetingFolder
    }

    private var folder: URL { meetingFolder.appending(path: "images", directoryHint: .isDirectory) }

    public func add(_ data: Data, fileExtension: String) throws -> String {
        let fileExtension = fileExtension.lowercased()
        let name = UUID().uuidString.lowercased() + "." + (Self.extensions.contains(fileExtension) ? fileExtension : "png")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appending(path: name), options: .atomic)
        return "images/" + name
    }

    public func url(for path: String) -> URL? {
        let url = meetingFolder.appending(path: path).standardizedFileURL
        let inside = url.deletingLastPathComponent().path == folder.standardizedFileURL.path
        return inside && !path.hasPrefix("/") ? url : nil
    }
}
