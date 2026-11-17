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
            event.properties = scrubbingHome(event.properties)
            return event
        }
        config.logs.serviceName = "martin"
        config.logs.setBeforeSend { record in
            record.body = scrubbingHome(record.body)
            record.attributes = scrubbingHome(record.attributes)
            return record
        }
        return config
    }

    static func share(_ sharing: Bool) {
        guard sharing else { return PostHogSDK.shared.optOut() }
        if let config = config() { PostHogSDK.shared.setup(config) }
        PostHogSDK.shared.optIn()
    }

    static func scrubbingHome<Value>(_ value: Value, home: String = NSHomeDirectory()) -> Value {
        scrubbing(value, home: home) as? Value ?? value
    }

    private static func scrubbing(_ value: Any, home: String) -> Any {
        switch value {
        case let string as String: string.replacingOccurrences(of: home, with: "~")
        case let dictionary as [String: Any]: dictionary.mapValues { scrubbing($0, home: home) }
        case let array as [Any]: array.map { scrubbing($0, home: home) }
        default: value
        }
    }
}
