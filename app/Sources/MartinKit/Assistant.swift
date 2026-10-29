import Foundation

public enum Assistant: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    public enum Status: Sendable {
        case missing
        case signedOut
        case ready
    }

    public var id: Self { self }

    private static let probeTimeout: TimeInterval = 30
    private static let answerTimeout: TimeInterval = 120
    private static let deepTimeout: TimeInterval = 300

    public enum Effort: Sendable {
        case quick
        case deep
    }

    public var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    public var account: String {
        switch self {
        case .claude: "Claude"
        case .codex: "ChatGPT"
        }
    }

    private var tool: String { rawValue }

    public func status() async -> Status {
        guard await Command.run(tool, ["--version"], timeout: Self.probeTimeout) != nil else { return .missing }
        switch self {
        case .claude:
            struct Auth: Decodable { let loggedIn: Bool }
            let auth = await Command.run(tool, ["auth", "status"], timeout: Self.probeTimeout).flatMap { try? JSONDecoder().decode(Auth.self, from: Data($0.utf8)) }
            return auth?.loggedIn == true ? .ready : .signedOut
        case .codex:
            return await Command.run(tool, ["login", "status"], timeout: Self.probeTimeout) == nil ? .signedOut : .ready
        }
    }

    func answer(_ prompt: String, instructions: String, schema: String, effort: Effort = .quick) async -> Data? {
        switch self {
        case .claude:
            let arguments = ["-p"] + claudeModel(for: effort) + ["--tools", "", "--setting-sources", "", "--no-session-persistence",
                             "--system-prompt", instructions, "--output-format", "json", "--json-schema", schema]
            return await Command.run(tool, arguments, input: prompt, timeout: timeout(for: effort)).flatMap(structuredOutput(of:))
        case .codex:
            let scratch = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let schemaFile = scratch.appending(path: "schema.json")
            guard (try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)) != nil,
                  (try? schema.write(to: schemaFile, atomically: true, encoding: .utf8)) != nil else { return nil }
            let arguments = ["exec", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules", "--sandbox", "read-only",
                             "--color", "never", "--model", "gpt-6-luna", "--config", "model_reasoning_effort=\"\(effort == .deep ? "high" : "low")\"", "--cd", scratch.path(percentEncoded: false), "--output-schema", schemaFile.path(percentEncoded: false), "-"]
            return await Command.run(tool, arguments, input: "\(instructions)\n\n\(prompt)", timeout: timeout(for: effort)).flatMap(structuredOutput(of:))
        }
    }

    func claudeModel(for effort: Effort) -> [String] {
        effort == .deep ? ["--model", "opus", "--effort", "high"] : ["--model", "haiku"]
    }

    func timeout(for effort: Effort) -> TimeInterval {
        effort == .deep ? Self.deepTimeout : Self.answerTimeout
    }

    func structuredOutput(of output: String) -> Data? {
        switch self {
        case .claude:
            guard let envelope = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
                  envelope["is_error"] as? Bool == false,
                  let answer = envelope["structured_output"] as? [String: Any] else { return nil }
            return try? JSONSerialization.data(withJSONObject: answer)
        case .codex:
            return Data(output.utf8)
        }
    }
}
