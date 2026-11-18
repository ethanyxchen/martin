import AppKit
import AuthenticationServices
import MartinKit
import Supabase

struct CloudUser: Equatable, Sendable {
    let id: String
    let email: String?
}

struct Cloud: Sendable {
    var user: @Sendable () -> CloudUser?
    var signIn: @Sendable () async throws -> CloudUser
    var signOut: @Sendable () async throws -> Void
    var server: SyncServer

    static func supabase(in bundle: Bundle = .main) -> Cloud? {
        guard let url = (bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String).flatMap(URL.init(string:)),
              let key = bundle.object(forInfoDictionaryKey: "SupabaseKey") as? String else { return nil }
        let client = SupabaseClient(supabaseURL: url, supabaseKey: key, options: SupabaseClientOptions(
            auth: .init(
                storage: KeychainLocalStorage(service: (bundle.bundleIdentifier ?? "Martin") + ".account"),
                redirectToURL: URL(string: "\(WebSignIn.scheme)://auth"),
                emitLocalSessionAsInitialSession: true
            )
        ))
        let images = client.storage.from("images")
        let folder: @Sendable () async throws -> String = { try await client.auth.session.user.id.uuidString.lowercased() }
        let server = SyncServer { after in
            var changes: [SyncChange] = []
            while true {
                var query = client.from("records").select("kind, id, data, edited_at, updated_at")
                if let after { query = query.gt("updated_at", value: after) }
                let page: [Row] = try await query.order("updated_at").range(from: changes.count, to: changes.count + Row.page - 1).execute().value
                changes += try page.map { try $0.change }
                if page.count < Row.page { return changes }
            }
        } push: { records in
            try await client.from("records").upsert(records.map(Row.init), onConflict: "user_id,kind,id").execute()
        } upload: { path, data in
            try await images.upload("\(folder())/\(path)", data: data, options: FileOptions(upsert: true))
        } download: { path in
            try await images.download(path: "\(folder())/\(path)")
        } removeImages: { meeting in
            let prefix = "\(try await folder())/\(meeting)/images"
            let files = try await images.list(path: prefix)
            guard !files.isEmpty else { return }
            try await images.remove(paths: files.map { "\(prefix)/\($0.name)" })
        }
        return Cloud(
            user: { client.auth.currentUser.map(CloudUser.init) },
            signIn: { try await CloudUser(client.auth.signInWithOAuth(provider: .apple, launchFlow: WebSignIn.callback(from:)).user) },
            signOut: { try await client.auth.signOut(scope: .local) },
            server: server
        )
    }
}

@MainActor
private final class WebSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    nonisolated static let scheme = "martin"

    private var session: ASWebAuthenticationSession?

    static func callback(from url: URL) async throws -> URL {
        let signIn = WebSignIn()
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme), completionHandler: finish(continuation, keeping: signIn))
            session.presentationContextProvider = signIn
            signIn.session = session
            session.start()
        }
    }

    private nonisolated static func finish(_ continuation: CheckedContinuation<URL, any Error>, keeping signIn: WebSignIn) -> @Sendable (URL?, (any Error)?) -> Void {
        { url, error in
            Task { @MainActor in signIn.session = nil }
            if let url { continuation.resume(returning: url) } else { continuation.resume(throwing: error ?? ASWebAuthenticationSessionError(.canceledLogin)) }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? ASPresentationAnchor() }
    }
}

private extension CloudUser {
    init(_ user: User) {
        self.init(id: user.id.uuidString.lowercased(), email: user.email)
    }
}

private struct Row: Codable {
    static let page = 1000

    let kind: SyncRecord.Kind
    let id: String
    let data: AnyJSON?
    let editedAt: Date
    let updatedAt: Date?

    init(_ record: SyncRecord) throws {
        kind = record.key.kind
        id = record.key.id
        data = try record.data.map { try JSONDecoder().decode(AnyJSON.self, from: $0) }
        editedAt = record.editedAt
        updatedAt = nil
    }

    var change: SyncChange {
        get throws {
            let record = SyncRecord(key: .init(kind: kind, id: id), data: try data.map { try JSONEncoder().encode($0) }, editedAt: editedAt)
            return SyncChange(record: record, updatedAt: updatedAt ?? .distantPast)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(id, forKey: .id)
        try container.encode(data, forKey: .data)
        try container.encode(editedAt, forKey: .editedAt)
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case id
        case data
        case editedAt = "edited_at"
        case updatedAt = "updated_at"
    }
}
