import Darwin
import Foundation

enum Command {
    static let grace: TimeInterval = 1
    static let census: TimeInterval = 0.1

    struct Outcome: Equatable, Sendable {
        enum Ending: Equatable, Sendable {
            case exited(Int32)
            case signalled(Int32)
            case stopped
            case unlaunched
        }

        let output: String
        let ending: Ending

        var success: String? {
            ending == .exited(0) ? output : nil
        }
    }

    static func run(_ tool: String, _ arguments: [String], input: String? = nil, environment: [String: String] = [:], timeout: TimeInterval) async -> Outcome {
        let environment = Self.environment.merging(environment) { $1 }
        guard let executable = executable(tool, searching: environment["PATH"] ?? "") else { return Outcome(output: "", ending: .unlaunched) }
        let run = Run(arguments: [executable] + arguments, input: input, environment: environment, timeout: timeout)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                run.start { continuation.resume(returning: $0) }
            }
        } onCancel: {
            run.stop()
        }
    }

    private static func executable(_ tool: String, searching path: String) -> String? {
        let candidates = tool.contains("/") ? [tool] : path.split(separator: ":").map { "\($0)/\(tool)" }
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    private static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [environment["PATH"], "/opt/homebrew/bin", "/usr/local/bin", URL.homeDirectory.appending(path: ".local/bin").path(percentEncoded: false)]
            .compactMap(\.self).joined(separator: ":")
        return environment
    }
}

private final class Run: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Command.run")
    private let arguments: [String]
    private let input: String?
    private let environment: [String: String]
    private let timeout: TimeInterval
    private var done: (@Sendable (Command.Outcome) -> Void)?
    private var group: pid_t = 0
    private var lineage: Lineage?
    private var tracker: Int32 = -1
    private var output = Data()
    private var ending: Command.Outcome.Ending?
    private var drained = false
    private var exited = false
    private var halted = false
    private var stopped = false
    private var finished = false
    private var reader: DispatchIO?
    private var writer: DispatchIO?
    private var exit: DispatchSourceProcess?
    private var deadline: DispatchSourceTimer?
    private var census: DispatchSourceTimer?

    init(arguments: [String], input: String?, environment: [String: String], timeout: TimeInterval) {
        self.arguments = arguments
        self.input = input
        self.environment = environment
        self.timeout = timeout
    }

    func start(_ done: @escaping @Sendable (Command.Outcome) -> Void) {
        queue.async {
            self.done = done
            self.halted ? self.finish(.stopped) : self.launch()
        }
    }

    func stop() {
        queue.async { self.halt() }
    }

    private func launch() {
        var stdout: [Int32] = [-1, -1], stdin: [Int32] = [-1, -1], tracking: [Int32] = [-1, -1]
        let piped = pipe(&stdout) == 0 && pipe(&tracking) == 0 && (input == nil || pipe(&stdin) == 0)
        (stdout + stdin + tracking).filter { $0 >= 0 }.forEach { _ = fcntl($0, F_SETFD, FD_CLOEXEC) }
        guard piped, let pid = spawn(stdin: stdin[0], stdout: stdout[1], tracking: tracking[1]) else {
            (piped ? [stdout[0], stdin[1], tracking[0]] : stdout + stdin + tracking).filter { $0 >= 0 }.forEach { close($0) }
            return finish(.unlaunched)
        }
        group = pid
        tracker = tracking[0]
        lineage = Lineage(leader: pid, pipes: [stdout[0], tracking[0]] + (stdin[1] >= 0 ? [stdin[1]] : []))
        startCensus()
        read(from: stdout[0])
        if let input { write(input, to: stdin[1]) }
        watchExit()
        startDeadline()
    }

    private func spawn(stdin: Int32, stdout: Int32, tracking: Int32) -> pid_t? {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        if stdin >= 0 {
            posix_spawn_file_actions_adddup2(&actions, stdin, STDIN_FILENO)
        } else {
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        }
        posix_spawn_file_actions_adddup2(&actions, stdout, STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, tracking, 3)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid = pid_t()
        let spawned = posix_spawn(&pid, arguments[0], &actions, &attributes, argv, envp) == 0
        [stdin, stdout, tracking].filter { $0 >= 0 }.forEach { close($0) }
        return spawned ? pid : nil
    }

    private func read(from descriptor: Int32) {
        let reader = DispatchIO(type: .stream, fileDescriptor: descriptor, queue: queue) { _ in close(descriptor) }
        reader.setLimit(lowWater: 1)
        reader.read(offset: 0, length: .max, queue: queue) { [self] done, data, _ in
            if let data { output.append(contentsOf: data) }
            if done {
                drained = true
                if exited { reap() }
                settle()
            }
        }
        self.reader = reader
    }

    private func write(_ input: String, to descriptor: Int32) {
        _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        let writer = DispatchIO(type: .stream, fileDescriptor: descriptor, queue: queue) { _ in close(descriptor) }
        let data = Data(input.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        writer.write(offset: 0, data: data, queue: queue) { done, _, _ in
            if done { writer.close() }
        }
        self.writer = writer
    }

    private func watchExit() {
        let exit = DispatchSource.makeProcessSource(identifier: group, eventMask: .exit, queue: queue)
        exit.setEventHandler { [self] in noticeExit() }
        exit.resume()
        self.exit = exit
        noticeExit()
    }

    private func noticeExit() {
        guard !exited else { return }
        var info = siginfo_t()
        let result = retrying { waitid(P_PID, id_t(group), &info, WEXITED | WNOHANG | WNOWAIT) }
        if result == -1, errno == ECHILD {
            ending = .stopped
            return finish(.stopped)
        }
        guard result == 0, info.si_pid == group else { return }
        exited = true
        exit?.cancel()
        if drained { reap() } else { sweep(escapedOnly: true) }
        settle()
    }

    private func startCensus() {
        let census = DispatchSource.makeTimerSource(queue: queue)
        census.schedule(deadline: .now(), repeating: Command.census)
        census.setEventHandler { [self] in
            lineage?.record()
            if exited, !drained { sweep(escapedOnly: true) }
        }
        census.resume()
        self.census = census
    }

    private func sweep(escapedOnly: Bool = false) {
        guard var lineage else { return }
        lineage.record(holders: true)
        self.lineage = lineage
        Lineage.kill(escapedOnly ? lineage.escaped() : Array(lineage.members))
        if !escapedOnly { killpg(group, SIGKILL) }
    }

    private func reap() {
        guard ending == nil else { return }
        sweep()
        var status: Int32 = 0
        guard retrying({ waitpid(group, &status, 0) }) == group else { return ending = .stopped }
        ending = status & 0x7f == 0 ? .exited((status >> 8) & 0xff) : .signalled(status & 0x7f)
    }

    private func retrying(_ call: () -> Int32) -> Int32 {
        var result: Int32
        repeat { result = call() } while result == -1 && errno == EINTR
        return result
    }

    private func startDeadline() {
        let deadline = DispatchSource.makeTimerSource(queue: queue)
        deadline.schedule(deadline: .now() + timeout)
        deadline.setEventHandler { [self] in halt() }
        deadline.resume()
        self.deadline = deadline
    }

    private func halt() {
        guard !finished, !halted else { return }
        halted = true
        guard group > 0 else { return }
        noticeExit()
        guard !finished else { return }
        stopped = !exited
        sweep()
        queue.asyncAfter(deadline: .now() + Command.grace) { [self] in
            guard exited else { return finish(.stopped) }
            drained = true
            reap()
            settle()
        }
    }

    private func settle() {
        guard let ending, drained else { return }
        finish(stopped ? .stopped : ending)
    }

    private func finish(_ ending: Command.Outcome.Ending) {
        guard !finished else { return }
        finished = true
        deadline?.cancel()
        census?.cancel()
        exit?.cancel()
        reader?.close(flags: .stop)
        writer?.close(flags: .stop)
        if tracker >= 0 { close(tracker) }
        if group > 0, self.ending == nil {
            sweep()
            let group = group
            DispatchQueue.global().async {
                var status: Int32 = 0
                waitpid(group, &status, 0)
            }
        }
        done?(Command.Outcome(output: String(decoding: output, as: UTF8.self), ending: ending))
    }
}
