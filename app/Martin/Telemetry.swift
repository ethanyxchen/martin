import Foundation
import PostHog

enum Telemetry {
    static func config(in bundle: Bundle = .main) -> PostHogConfig? {
        guard let token = bundle.object(forInfoDictionaryKey: "PostHogProjectToken") as? String,
              let host = bundle.object(forInfoDictionaryKey: "PostHogHost") as? String else { return nil }
        let config = PostHogConfig(projectToken: token, host: host)
        config.errorTrackingConfig.autoCapture = true
        config.logs.serviceName = "martin"
        return config
    }

    static func share(_ sharing: Bool) {
        guard sharing else { return PostHogSDK.shared.optOut() }
        if let config = config() { PostHogSDK.shared.setup(config) }
        PostHogSDK.shared.optIn()
    }
}
