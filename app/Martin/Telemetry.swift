import Foundation
import MartinKit
import PostHog

enum Telemetry {
    static func config(in bundle: Bundle = .main, sharing: Bool) -> PostHogConfig? {
        guard let token = bundle.object(forInfoDictionaryKey: "PostHogProjectToken") as? String,
              let host = bundle.object(forInfoDictionaryKey: "PostHogHost") as? String else { return nil }
        let config = PostHogConfig(projectToken: token, host: host)
        config.errorTrackingConfig.autoCapture = true
        config.logs.serviceName = "martin"
        config.optOut = !sharing
        return config
    }

    static func share(_ sharing: Bool) {
        sharing ? PostHogSDK.shared.optIn() : PostHogSDK.shared.optOut()
    }

    static func generation(_ generation: Assistant.Generation, trace: String, session: String) -> [String: Any] {
        [
            "$ai_trace_id": trace,
            "$ai_session_id": session,
            "$ai_span_name": "repository_match",
            "$ai_model": generation.model,
            "$ai_provider": generation.provider,
            "$ai_latency": generation.latency,
            "$ai_is_error": generation.isError,
        ]
    }
}
