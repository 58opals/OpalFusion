import Darwin
import Foundation
import Synchronization

private let interruptedSignal = Atomic<Int32>(0)

struct ValidationInterrupted: Error, CustomStringConvertible {
    let signal: Int32
    var description: String { "interrupted by signal \(signal)" }
}
struct ValidationTimeout: Error, CustomStringConvertible {
    var description: String { "validation deadline exhausted" }
}
struct CommandFailure: Error, CustomStringConvertible {
    let status: Int32
    let command: [String]
    var description: String { "Command \(command) returned non-zero exit status \(status)." }
}
struct ProcessFailure: Error, CustomStringConvertible {
    let operation: String
    let code: Int32
    var description: String { "\(operation): \(String(cString: strerror(code)))" }
}

final class SignalScope {
    private var handlers: [(Int32, sig_t?)] = []
    init() {
        interruptedSignal.store(0, ordering: .relaxed)
        for number in [SIGINT, SIGTERM, SIGHUP] {
            let previous = Darwin.signal(number) { number in
                interruptedSignal.store(number, ordering: .relaxed)
            }
            handlers.append((number, previous))
        }
    }
    deinit { for (number, handler) in handlers { Darwin.signal(number, handler) } }
}

protocol ValidationExecuting: AnyObject {
    var environment: [String: String] { get set }
    func run(_ command: [String], deadline: Double?, capture: Bool) throws -> String
}

final class ValidationProcess: ValidationExecuting {
    var environment: [String: String]
    private(set) var active: pid_t?
    // The signal operation is kept at the system boundary so cleanup errors
    // remain distinguishable from an absent group. In particular, EPERM must
    // never be interpreted as successful termination.
    let signalGroup: (pid_t, Int32) -> Int32
    init(environment: [String: String], signalGroup: @escaping (pid_t, Int32) -> Int32 = { Darwin.kill(-$0, $1) }) {
        self.environment = environment
        self.signalGroup = signalGroup
    }

    func run(_ command: [String], deadline: Double? = nil, capture: Bool = false) throws -> String {
        if let deadline, monotonicTime() >= deadline { throw ValidationTimeout() }
        guard let executable = command.first, !executable.isEmpty else { throw ValidationFailure("Empty validation command") }
        let path = try executablePath(executable)
        var attributes: posix_spawnattr_t?
        var actions: posix_spawn_file_actions_t?
        try checked(posix_spawnattr_init(&attributes), "posix_spawnattr_init")
        defer { posix_spawnattr_destroy(&attributes) }
        try checked(posix_spawn_file_actions_init(&actions), "posix_spawn_file_actions_init")
        defer { posix_spawn_file_actions_destroy(&actions) }
        try checked(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)), "posix_spawnattr_setflags")
        try checked(posix_spawnattr_setpgroup(&attributes, 0), "posix_spawnattr_setpgroup")
        var empty = sigset_t()
        sigemptyset(&empty)
        try checked(posix_spawnattr_setsigmask(&attributes, &empty), "posix_spawnattr_setsigmask")
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for number in [SIGINT, SIGTERM, SIGHUP] { sigaddset(&defaults, number) }
        try checked(posix_spawnattr_setsigdefault(&attributes, &defaults), "posix_spawnattr_setsigdefault")

        // Close unrelated parent descriptors by default, while preserving the
        // same open standard streams as the original subprocess owner. The
        // captured stdout pipe below supplies its own explicit dup action.
        for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] where descriptor != STDOUT_FILENO || !capture {
            if fcntl(descriptor, F_GETFD) >= 0 {
                try checked(posix_spawn_file_actions_addinherit_np(&actions, descriptor), "posix_spawn_file_actions_addinherit_np")
            } else if errno != EBADF {
                throw ProcessFailure(operation: "fcntl(F_GETFD)", code: errno)
            }
        }

        var descriptors: [Int32] = [-1, -1]
        defer {
            if descriptors[0] >= 0 { close(descriptors[0]) }
            if descriptors[1] >= 0 { close(descriptors[1]) }
        }
        if capture {
            guard pipe(&descriptors) == 0 else { throw ProcessFailure(operation: "pipe", code: errno) }
            try checked(posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO), "posix_spawn_file_actions_adddup2")
            try checked(posix_spawn_file_actions_addclose(&actions, descriptors[0]), "posix_spawn_file_actions_addclose")
            try checked(posix_spawn_file_actions_addclose(&actions, descriptors[1]), "posix_spawn_file_actions_addclose")
            _ = fcntl(descriptors[0], F_SETFL, O_NONBLOCK)
        }
        let strings = command.map { strdup($0) }
        let variables = environment.sorted { $0.key < $1.key }.map { strdup($0.key + "=" + $0.value) }
        defer { for pointer in strings + variables { free(pointer) } }
        var argv = strings + [nil]
        var envp = variables + [nil]
        var pid: pid_t = 0
        try checked(posix_spawn(&pid, path, &actions, &attributes, &argv, &envp), "posix_spawn")
        active = pid
        if descriptors[1] >= 0 { close(descriptors[1]); descriptors[1] = -1 }
        var captured = Data()
        var outputClosed = !capture
        var terminalStatus: Int32?
        do {
            while true {
                let number = interruptedSignal.load(ordering: .relaxed)
                if number != 0 { throw ValidationInterrupted(signal: number) }
                if let deadline, monotonicTime() >= deadline { throw ValidationTimeout() }
                if capture && !outputClosed { outputClosed = try drain(descriptors[0], into: &captured) }
                if terminalStatus == nil {
                    var status: Int32 = 0
                    let waited = waitpid(pid, &status, WNOHANG)
                    if waited == pid { terminalStatus = status }
                    else if waited == -1 && errno != EINTR { throw ProcessFailure(operation: "waitpid", code: errno) }
                }
                // Captured output belongs to the complete pipe lifetime. A
                // descendant may keep stdout open after the direct child has
                // exited; keep the same deadline and owned group in that case.
                if let status = terminalStatus, outputClosed {
                    let code = exitCode(status)
                    guard code == 0 else { throw CommandFailure(status: code, command: command) }
                    if let deadline, monotonicTime() > deadline { throw ValidationTimeout() }
                    active = nil
                    guard let output = String(data: captured, encoding: .utf8) else { throw ValidationFailure("Validation command output is not UTF-8") }
                    return output
                }
                usleep(10_000)
            }
        } catch {
            try cleanup()
            throw error
        }
    }

    func cleanup() throws {
        guard let pid = active else { return }
        let handlers = [SIGINT, SIGTERM, SIGHUP].map { ($0, Darwin.signal($0, SIG_IGN)) }
        defer { for (number, previous) in handlers { Darwin.signal(number, previous) } }
        let end = monotonicTime() + 5
        if signalGroup(pid, SIGTERM) == -1 {
            let code = errno
            guard code == ESRCH else { throw ProcessFailure(operation: "killpg(SIGTERM)", code: code) }
            try reap(pid, deadline: end)
            active = nil
            return
        }
        var reaped = false
        var groupGone = false
        while monotonicTime() < end - 0.2 {
            if !reaped {
                var status: Int32 = 0
                let result = waitpid(pid, &status, WNOHANG)
                if result == pid || (result == -1 && errno == ECHILD) { reaped = true }
                else if result == -1 && errno != EINTR { throw ProcessFailure(operation: "waitpid", code: errno) }
            }
            if signalGroup(pid, 0) == -1 {
                let code = errno
                if code == ESRCH { groupGone = true; break }
                // A denied existence probe does not establish that the group
                // is gone. Finish the grace period, then deliver SIGKILL.
                if code != EPERM { throw ProcessFailure(operation: "killpg(probe)", code: code) }
            }
            usleep(50_000)
        }
        if !groupGone, signalGroup(pid, SIGKILL) == -1, errno != ESRCH {
            throw ProcessFailure(operation: "killpg(SIGKILL)", code: errno)
        }
        if !reaped { try reap(pid, deadline: end) }
        active = nil
    }

    private func executablePath(_ executable: String) throws -> String {
        if executable.contains("/") {
            guard FileManager.default.isExecutableFile(atPath: executable) else { throw ProcessFailure(operation: executable, code: ENOENT) }
            return executable
        }
        for directory in (environment["PATH"] ?? "/usr/bin:/bin").components(separatedBy: ":") {
            let path = URL(fileURLWithPath: directory.isEmpty ? "." : directory).appendingPathComponent(executable).path
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        throw ProcessFailure(operation: executable, code: ENOENT)
    }

    private func checked(_ result: Int32, _ operation: String) throws {
        if result != 0 { throw ProcessFailure(operation: operation, code: result) }
    }
    private func drain(_ descriptor: Int32, into data: inout Data) throws -> Bool {
        var bytes = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = bytes.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 { data.append(contentsOf: bytes.prefix(count)); continue }
            if count == 0 { return true }
            if errno == EAGAIN || errno == EWOULDBLOCK { return false }
            if errno != EINTR { throw ProcessFailure(operation: "read", code: errno) }
        }
    }
    private func reap(_ pid: pid_t, deadline: Double) throws {
        while monotonicTime() < deadline {
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid || (result == -1 && errno == ECHILD) { return }
            if result == -1 && errno != EINTR { throw ProcessFailure(operation: "waitpid", code: errno) }
            usleep(10_000)
        }
        throw ValidationFailure("Owned validation process did not stop within the cleanup deadline")
    }
}

func monotonicTime() -> Double { ProcessInfo.processInfo.systemUptime }
func exitCode(_ status: Int32) -> Int32 {
    let signal = status & 0x7f
    return signal == 0 ? (status >> 8) & 0xff : -signal
}
