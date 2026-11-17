import Foundation
import PostHog

enum Telemetry {
    static func config(in bundle: Bundle = .main) -> PostHogConfig? {
        guard let token = bundle.object(forInfoDictionaryKey: "PostHogProjectToken") as? String,
              let host = bundle.object(forInfoDictionaryKey: "PostHogHost") as? String else { return nil }
        let config = PostHogConfig(projectToken: token, host: host)
        config.disableGeoIp = true
        config.errorTrackingConfig.autoCapture = true
        config.setBeforeSend { event in
            event.properties = home.scrubbing(event.properties)
            return event
        }
        config.logs.serviceName = "martin"
        config.logs.setBeforeSend { record in
            record.body = home.scrubbing(record.body)
            record.attributes = home.scrubbing(record.attributes)
            return record
        }
        return config
    }

    static func share(_ sharing: Bool) {
        guard sharing else { return PostHogSDK.shared.optOut() }
        if let config = config() { PostHogSDK.shared.setup(config) }
        PostHogSDK.shared.optIn()
    }

    private static let home = HomePath(NSHomeDirectory())
}

struct HomePath: Sendable {
    private let forms: [String]
    private let pattern: String

    init(_ home: String) {
        forms = [home, home.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? home]
        pattern = "(?:" + forms.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")(?![\\p{L}\\p{N}])"
    }

    func scrubbing(_ string: String) -> String {
        guard forms.contains(where: { string.range(of: $0, options: .caseInsensitive) != nil }) else { return string }
        return string.replacingOccurrences(of: pattern, with: "~", options: [.regularExpression, .caseInsensitive])
    }

    func scrubbing(_ properties: [String: Any]) -> [String: Any] {
        properties.mapValues(scrubbing(any:))
    }

    private func scrubbing(any value: Any) -> Any {
        switch value {
        case let string as String: scrubbing(string)
        case let dictionary as [String: Any]: scrubbing(dictionary)
        case let array as [Any]: array.map(scrubbing(any:))
        default: value
        }
    }
}
