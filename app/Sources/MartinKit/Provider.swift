import Foundation
import Security

public enum Provider: String, CaseIterable, Identifiable, Sendable, Encodable {
    case anthropic
    case openai

    public var id: Self { self }

    public var title: String {
        switch self {
        case .anthropic: "Claude"
        case .openai: "OpenAI"
        }
    }

    var keyVariable: String {
        switch self {
        case .anthropic: "ANTHROPIC_API_KEY"
        case .openai: "OPENAI_API_KEY"
        }
    }
}

public struct Credential: Equatable, Sendable {
    public let provider: Provider
    public let key: String

    public init(provider: Provider, key: String) {
        self.provider = provider
        self.key = key
    }

    var environment: [String: String] {
        [provider.keyVariable: key]
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
