import Foundation
import Security

public enum Provider: String, CaseIterable, Identifiable, Sendable {
    case anthropic
    case openai

    public struct Generation: Sendable {
        public let provider: Provider
        public let model: String
        public let prompt: String
        public let instructions: String
        public let output: String?
        public let latency: TimeInterval
        public let isError: Bool
    }

    @TaskLocal public static var generationObserver: (@Sendable (Generation) -> Void)? = nil

    private static let timeout: TimeInterval = 120

    public var id: Self { self }

    public var title: String {
        switch self {
        case .anthropic: "Claude"
        case .openai: "OpenAI"
        }
    }

    var model: String {
        switch self {
        case .anthropic: "claude-haiku-5-5"
        case .openai: "gpt-6-luna"
        }
    }

    func request(_ prompt: String, instructions: String, schema: String, key: String) -> URLRequest {
        let schema = (try? JSONSerialization.jsonObject(with: Data(schema.utf8))) ?? [:]
        var request: URLRequest
        let body: [String: Any]
        switch self {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": model,
                "max_tokens": 16000,
                "system": instructions,
                "messages": [["role": "user", "content": prompt]],
                "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            ]
        case .openai:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body = [
                "model": model,
                "instructions": instructions,
                "input": prompt,
                "reasoning": ["effort": "low"],
                "text": ["format": ["type": "json_schema", "name": "result", "schema": schema, "strict": true]],
            ]
        }
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    func structuredOutput(of response: Data) -> Data? {
        guard let envelope = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else { return nil }
        let parts: [[String: Any]]?
        switch self {
        case .anthropic:
            guard envelope["stop_reason"] as? String == "end_turn" else { return nil }
            parts = (envelope["content"] as? [[String: Any]])?.filter { $0["type"] as? String == "text" }
        case .openai:
            guard envelope["status"] as? String == "completed" else { return nil }
            parts = (envelope["output"] as? [[String: Any]])?
                .filter { $0["type"] as? String == "message" }
                .flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .filter { $0["type"] as? String == "output_text" }
        }
        guard let text = parts?.compactMap({ $0["text"] as? String }).joined(), !text.isEmpty else { return nil }
        return Data(text.utf8)
    }
}

public struct Credential: Equatable, Sendable {
    public let provider: Provider
    public let key: String

    public init(provider: Provider, key: String) {
        self.provider = provider
        self.key = key
    }

    func answer(_ prompt: String, instructions: String, schema: String) async -> Data? {
        let startedAt = Date()
        let reply = try? await URLSession.shared.data(for: provider.request(prompt, instructions: instructions, schema: schema, key: key))
        let output = reply.flatMap { body, response in
            (response as? HTTPURLResponse)?.statusCode == 200 ? provider.structuredOutput(of: body) : nil
        }
        Provider.generationObserver?(Provider.Generation(
            provider: provider,
            model: provider.model,
            prompt: prompt,
            instructions: instructions,
            output: output.map { String(decoding: $0, as: UTF8.self) },
            latency: Date().timeIntervalSince(startedAt),
            isError: output == nil
        ))
        return output
    }
}

public struct CredentialStore: Sendable {
    public var load: @Sendable () -> Credential?
    public var save: @Sendable (Credential?) -> Void

    public init(load: @escaping @Sendable () -> Credential?, save: @escaping @Sendable (Credential?) -> Void) {
        self.load = load
        self.save = save
    }

    public static func keychain(service: String) -> CredentialStore {
        CredentialStore {
            var found: CFTypeRef?
            let query = item(service).merging([kSecReturnAttributes: true, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]) { $1 }
            guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
                  let found = found as? [CFString: Any],
                  let provider = (found[kSecAttrAccount] as? String).flatMap(Provider.init),
                  let key = (found[kSecValueData] as? Data).map({ String(decoding: $0, as: UTF8.self) }) else { return nil }
            return Credential(provider: provider, key: key)
        } save: { credential in
            SecItemDelete(item(service) as CFDictionary)
            guard let credential else { return }
            let added = item(service).merging([
                kSecAttrAccount: credential.provider.rawValue,
                kSecValueData: Data(credential.key.utf8),
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            ]) { $1 }
            SecItemAdd(added as CFDictionary, nil)
        }
    }

    private static func item(_ service: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
    }
}
