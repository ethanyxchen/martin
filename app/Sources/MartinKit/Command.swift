import Darwin
import Foundation

enum Command {
    static let grace: TimeInterval = 1

    static func run(_ tool: String, _ arguments: [String], input: String? = nil, timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { continuation in
            Run(arguments: ["/usr/bin/env", tool] + arguments, input: input, timeout: timeout) { continuation.resume(returning: $0) }.start()
        }
    }

    fileprivate static var environment: [String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [environment["PATH"], "/opt/homebrew/bin", "/usr/local/bin", URL.homeDirectory.appending(path: ".local/bin").path(percentEncoded: false)]
            .compactMap(\.self).joined(separator: ":")
        return environment.map { "\($0.key)=\($0.value)" }
    }
}

private final class Run: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Command.run")
    private let arguments: [String]
    private let input: String?
    private let timeout: TimeInterval
    private let done: (String?) -> Void
    private var group: pid_t = 0
    private var output = Data()
    private var status: Int32?
    private var drained = false
    private var exited = false
    private var timedOut = false
    private var finished = false
    private var reader: DispatchIO?
    private var writer: DispatchIO?
    private var exit: DispatchSourceProcess?
    private var deadline: DispatchSourceTimer?

    init(arguments: [String], input: String?, timeout: TimeInterval, done: @escaping (String?) -> Void) {
        self.arguments = arguments
        self.input = input
        self.timeout = timeout
        self.done = done
    }

    func start() {
        queue.async { self.launch() }
    }

    private func launch() {
        var stdout: [Int32] = [-1, -1], stdin: [Int32] = [-1, -1]
        let piped = pipe(&stdout) == 0 && (input == nil || pipe(&stdin) == 0)
        (stdout + stdin).filter { $0 >= 0 }.forEach { _ = fcntl($0, F_SETFD, FD_CLOEXEC) }
        guard piped, let pid = spawn(stdin: stdin[0], stdout: stdout[1]) else {
            (piped ? [stdout[0], stdin[1]] : stdout + stdin).filter { $0 >= 0 }.forEach { close($0) }
            return finish(nil)
        }
        group = pid
        read(from: stdout[0])
        if let input { write(input, to: stdin[1]) }
        watchExit()
        startDeadline()
    }

    private func spawn(stdin: Int32, stdout: Int32) -> pid_t? {
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
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        let argv = arguments.map { strdup($0) } + [nil]
        let envp = Command.environment.map { strdup($0) } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid = pid_t()
        let spawned = posix_spawn(&pid, arguments[0], &actions, &attributes, argv, envp) == 0
        [stdin, stdout].filter { $0 >= 0 }.forEach { close($0) }
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
            status = -1
            return finish(nil)
        }
        guard result == 0, info.si_pid == group else { return }
        exited = true
        exit?.cancel()
        if drained { reap() }
        settle()
    }

    private func reap() {
        guard status == nil else { return }
        var status: Int32 = 0
        self.status = retrying { waitpid(group, &status, 0) } == group ? status : -1
    }

    private func retrying(_ call: () -> Int32) -> Int32 {
        var result: Int32
        repeat { result = call() } while result == -1 && errno == EINTR
        return result
    }

    private func startDeadline() {
        let deadline = DispatchSource.makeTimerSource(queue: queue)
        deadline.schedule(deadline: .now() + timeout)
        deadline.setEventHandler { [self] in
            noticeExit()
            guard !finished else { return }
            timedOut = !exited
            killpg(group, SIGKILL)
            queue.asyncAfter(deadline: .now() + Command.grace) { [self] in
                guard exited else { return finish(nil) }
                drained = true
                reap()
                settle()
            }
        }
        deadline.resume()
        self.deadline = deadline
    }

    private func settle() {
        guard let status, drained else { return }
        let succeeded = !timedOut && status & 0x7f == 0 && (status >> 8) & 0xff == 0
        finish(succeeded ? String(decoding: output, as: UTF8.self) : nil)
    }

    private func finish(_ result: String?) {
        guard !finished else { return }
        finished = true
        deadline?.cancel()
        exit?.cancel()
        reader?.close(flags: .stop)
        writer?.close(flags: .stop)
        if group > 0, status == nil {
            let group = group
            DispatchQueue.global().async {
                var status: Int32 = 0
                waitpid(group, &status, 0)
            }
        }
        done(result)
    }
}
