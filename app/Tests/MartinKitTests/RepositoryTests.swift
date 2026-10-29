import Foundation
import Testing
@testable import MartinKit

final class RepositoryTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func clone(_ name: String, origin: String?, branch: String = "main") throws -> URL {
        let folder = root.appending(path: name, directoryHint: .isDirectory)
        let git = folder.appending(path: ".git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        let remote = origin.map { "[remote \"upstream\"]\n\turl = git@github.com:someone/else.git\n[remote \"origin\"]\n\turl = \($0)\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n" } ?? ""
        try "[core]\n\tbare = false\n\(remote)[branch \"main\"]\n\tremote = origin\n".write(to: git.appending(path: "config"), atomically: true, encoding: .utf8)
        try "ref: refs/heads/\(branch)\n".write(to: git.appending(path: "HEAD"), atomically: true, encoding: .utf8)
        return folder
    }

    func repository(_ slug: String, in folder: String) -> Repository {
        try! clone(folder, origin: "git@github.com:\(slug).git")
        return Repository(at: root.appending(path: folder, directoryHint: .isDirectory))!
    }

    @Test func theSlugComesFromTheOriginRemoteInAnyGitHubURLForm() {
        #expect(Repository.slug(of: "git@github.com:ethanyxchen/martin.git") == "ethanyxchen/martin")
        #expect(Repository.slug(of: "https://github.com/GoodnotesGlobal/ma-turbo-overload") == "GoodnotesGlobal/ma-turbo-overload")
        #expect(Repository.slug(of: "ssh://git@github.com/ethanyxchen/martin.app.git") == "ethanyxchen/martin.app")
        #expect(Repository.slug(of: "https://gitlab.com/ethanyxchen/martin.git") == nil)
    }

    @Test func aCloneIsReadWithItsSlugAndCheckedOutBranch() throws {
        let folder = try clone("martin", origin: "git@github.com:ethanyxchen/martin.git", branch: "ethanc/repos")
        let repository = try #require(Repository(at: folder))
        #expect(repository.slug == "ethanyxchen/martin")
        #expect(repository.name == "martin")
        #expect(repository.branch == "ethanc/repos")
        #expect(repository.web == URL(string: "https://github.com/ethanyxchen/martin"))
        #expect(repository.summary == nil)
        try "# Martin\n\n[![Build](https://x/badge.svg)](https://x)\n<img src=\"icon.png\">\nalt=\"chat\"></a>\n\n  A menu bar notepad.  \n```sh\nopen Martin.app\n```\n| a | b |\nTake notes.".write(to: folder.appending(path: "README.md"), atomically: true, encoding: .utf8)
        #expect(repository.summary == "# Martin A menu bar notepad. Take notes.")
    }

    @Test func aFolderWithoutAGitHubOriginIsNotARepository() throws {
        #expect(Repository(at: try clone("local", origin: nil)) == nil)
        #expect(Repository(at: try clone("gitlab", origin: "https://gitlab.com/a/b.git")) == nil)
        #expect(Repository(at: root.appending(path: "missing", directoryHint: .isDirectory)) == nil)
    }

    @Test func aWorktreeReadsItsOwnBranchAndTheMainCheckoutsRemote() throws {
        let main = try clone("martin", origin: "git@github.com:ethanyxchen/martin.git")
        let admin = main.appending(path: ".git/worktrees/feature", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: admin, withIntermediateDirectories: true)
        try "../..\n".write(to: admin.appending(path: "commondir"), atomically: true, encoding: .utf8)
        try "ref: refs/heads/feature\n".write(to: admin.appending(path: "HEAD"), atomically: true, encoding: .utf8)
        let worktree = root.appending(path: "martin-feature", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: \(admin.path)\n".write(to: worktree.appending(path: ".git"), atomically: true, encoding: .utf8)
        let repository = try #require(Repository(at: worktree))
        #expect(repository.slug == "ethanyxchen/martin")
        #expect(repository.branch == "feature")
        #expect(Repository.clones(in: [root]).map(\.folder.lastPathComponent) == ["martin"])
    }

    @Test func clonesAreFoundOneLevelInsideEachRoot() throws {
        try clone("martin", origin: "git@github.com:ethanyxchen/martin.git")
        try clone("local", origin: nil)
        try FileManager.default.createDirectory(at: root.appending(path: "notes"), withIntermediateDirectories: true)
        #expect(Repository.clones(in: [root, root.appending(path: "absent")]).map(\.slug) == ["ethanyxchen/martin"])
    }

    private func work(in gitDirectory: URL, at seconds: TimeInterval) throws {
        let log = gitDirectory.appending(path: "logs/HEAD")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "checkout\n".write(to: log, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: seconds)], ofItemAtPath: log.path(percentEncoded: false))
    }

    @Test func aCloneWasLastWorkedOnWhenItOrAnyOfItsWorktreesLastMoved() throws {
        let folder = try clone("martin", origin: "git@github.com:ethanyxchen/martin.git")
        #expect(Repository(at: folder)?.lastWorkedOn == nil)
        try work(in: folder.appending(path: ".git"), at: 1_000)
        #expect(Repository(at: folder)?.lastWorkedOn == Date(timeIntervalSince1970: 1_000))
        try work(in: folder.appending(path: ".git/worktrees/feature"), at: 2_000)
        try work(in: folder.appending(path: ".git/worktrees/fix"), at: 1_500)
        #expect(Repository(at: folder)?.lastWorkedOn == Date(timeIntervalSince1970: 2_000))
    }

    @Test func theMostRecentlyWorkedOnRanksFirstAndEachRepositoryAppearsOnce() throws {
        let martin = repository("ethanyxchen/martin", in: "martin")
        let copy = repository("ethanyxchen/martin", in: "a-martin-copy")
        try work(in: root.appending(path: "ma-rocket-tortoise/.git"), at: 3_000)
        try work(in: root.appending(path: "ma-turbo-overload/.git"), at: 1_000)
        let tortoise = repository("Goodnotes-CN/ma-rocket-tortoise", in: "ma-rocket-tortoise")
        let overload = repository("GoodnotesGlobal/ma-turbo-overload", in: "ma-turbo-overload")
        let atlas = repository("acme/atlas", in: "atlas")
        let activity = ["goodnotesglobal/ma-turbo-overload": Date(timeIntervalSince1970: 4_000), "ethanyxchen/martin": Date(timeIntervalSince1970: 2_000)]
        let ranked = [atlas, copy, martin, tortoise, overload].ranked(by: activity)
        #expect(ranked.map(\.folder.lastPathComponent) == ["ma-turbo-overload", "ma-rocket-tortoise", "martin", "atlas"])
        #expect(ranked.map(\.lastWorkedOn) == [4_000, 3_000, 2_000].map(Date.init(timeIntervalSince1970:)) + [nil])
    }

    @Test func gitHubActivityIsTheLatestEventOnEachRepository() {
        let events = ["GoodnotesGlobal/ma-turbo-overload 2026-10-29T09:00:00Z", "ethanyxchen/martin 2026-10-28T10:00:00Z", "GoodnotesGlobal/MA-turbo-overload 2026-10-01T09:00:00Z", "garbled"]
        #expect(GitHub.activity(in: events) == [
            "goodnotesglobal/ma-turbo-overload": Date(timeIntervalSince1970: 1_793_264_400),
            "ethanyxchen/martin": Date(timeIntervalSince1970: 1_793_181_600),
        ])
    }
}
