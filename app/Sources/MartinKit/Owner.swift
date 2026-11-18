import Foundation

public struct Owner: Encodable, Equatable, Sendable {
    let name: String
    let emails: [String]
    let login: String

    public init(name: String?, email: String?, account: String?) {
        let account = (account ?? "").split(separator: " ").map(String.init)
        self.name = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        login = account.first ?? ""
        let noreply = account.count == 2 ? "\(account[1])+\(login)@users.noreply.github.com" : nil
        emails = [email?.trimmingCharacters(in: .whitespacesAndNewlines), noreply].compactMap { $0?.lowercased() }.filter { !$0.isEmpty }
    }

    public static func current(in folder: URL?) async -> Owner {
        let scope = folder.map { ["-C", $0.path(percentEncoded: false)] } ?? []
        async let name = Command.run("git", scope + ["config", "user.name"], timeout: 10).success
        async let email = Command.run("git", scope + ["config", "user.email"], timeout: 10).success
        async let account = Command.run("gh", ["api", "user", "--jq", #".login + " " + (.id | tostring)"#], timeout: 30).success
        return await Owner(name: name, email: email, account: account?.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
