import Darwin
import Foundation

func write(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }
func store(_ text: String, _ path: String) throws { try text.write(toFile: path, atomically: true, encoding: .utf8) }
let env = ProcessInfo.processInfo.environment
let arguments = Array(CommandLine.arguments.dropFirst())
let tool = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent

if arguments.first == "closed-descriptor" {
    let descriptor = Int32(arguments[1])!
    exit(fcntl(descriptor, F_GETFD) == -1 && errno == EBADF ? 0 : 42)
}

if arguments.first == "owned-process" {
    let marker = arguments[1]
    if arguments.contains("--descendant") {
        // No spawn attributes means this descendant stays in the owner's
        // existing process group, unlike the runner's isolated root child.
        let strings = [CommandLine.arguments[0], "owned-process", marker, "--ignore-term"].map { strdup($0) }
        let variables = env.map { strdup($0.key + "=" + $0.value) }
        var argv = strings + [nil]
        var envp = variables + [nil]
        var child: pid_t = 0
        let result = posix_spawn(&child, CommandLine.arguments[0], nil, nil, &argv, &envp)
        for pointer in strings + variables { free(pointer) }
        guard result == 0 else { exit(result) }
        if arguments.contains("--exit-parent") { exit(0) }
    } else { try store(String(getpid()), marker) }
    if arguments.contains("--ignore-term") { signal(SIGTERM, SIG_IGN) }
    while true { sleep(300) }
}

if tool == "git" {
    let data = try JSONSerialization.data(withJSONObject: arguments)
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: env["PROOF_CALLS"]!))
    try handle.seekToEnd(); try handle.write(contentsOf: data + Data([10])); try handle.close()
    if arguments.contains("cat-file") { exit(arguments.last == env["MISSING_PROOF_OBJECT"] ? 128 : 0) }
    if let index = arguments.firstIndex(of: "--"), arguments.contains("diff") {
        let historical = arguments.dropFirst(index + 1).allSatisfy { $0.hasPrefix("Sources/OpalFusion/") || $0.hasPrefix("Tests/OpalFusionTests/") }
        exit(historical && env["CHANGED_PROOF_FILE"] != nil ? 1 : 0)
    }
    exit(2)
}

let phase: String
if tool == "xcrun" && arguments == ["--find", "swift"] { phase = "toolchain" }
else if tool == "xcrun" { phase = "platform" }
else if arguments.contains("--show-bin-path") { phase = "products" }
else if arguments.first == "build" { phase = "build" }
else if arguments.contains("list") || arguments.contains("--list-tests") { phase = "discovery" }
else if arguments.contains("--no-parallel") { phase = "client" }
else { phase = "bounded" }
let call: [String: Any] = ["arguments": arguments, "phase": phase,
                           "interop": env["OPALFUSION_EC_INTEROP"] ?? NSNull(),
                           "module_cache": env["CLANG_MODULE_CACHE_PATH"] ?? NSNull()]
let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: env["RUNNER_CALLS"]!))
try handle.seekToEnd(); try handle.write(contentsOf: JSONSerialization.data(withJSONObject: call) + Data([10])); try handle.close()
let scenario = env["RUNNER_SCENARIO"] ?? ""
let root = URL(fileURLWithPath: env["RUNNER_DISCOVERY"]!).deletingLastPathComponent()
if (scenario == "standard-streams-build" && phase == "build") || (scenario == "standard-streams-discovery" && phase == "discovery") {
    let expected = Array("inherited standard input\n".utf8)
    var input = [UInt8](repeating: 0, count: expected.count + 1)
    let count = input.withUnsafeMutableBytes { Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count) }
    var failures: Int32 = count == expected.count && Array(input.prefix(max(0, count))) == expected ? 0 : 1
    let diagnostic = Array("inherited stderr from \(phase)\n".utf8)
    if diagnostic.withUnsafeBytes({ Darwin.write(STDERR_FILENO, $0.baseAddress, $0.count) }) != diagnostic.count { failures |= 2 }
    if phase == "build" {
        let output = Array("inherited stdout from build\n".utf8)
        if output.withUnsafeBytes({ Darwin.write(STDOUT_FILENO, $0.baseAddress, $0.count) }) != output.count { failures |= 4 }
    }
    if failures != 0 { exit(40 + failures) }
}
if ["products", "toolchain", "platform"].contains(phase) {
    write(root.appendingPathComponent(["products": "products", "toolchain": "toolchain/usr/bin/swift", "platform": "Platform"][phase]!).path)
    exit(0)
}
if scenario == "fail-" + phase { exit(["build": 17, "discovery": 18, "client": 19, "bounded": 20][phase] ?? 1) }
if scenario == "signal-" + phase { kill(getpid(), SIGTERM); sleep(1); exit(99) }
if scenario == "signal-parent" {
    try store(String(getpid()), env["OWNED_MARKER"]!)
    kill(getppid(), SIGTERM)
    while true { sleep(300) }
}
if scenario == "owned-build" {
    try store(String(getpid()), env["OWNED_MARKER"]!)
    while true { sleep(300) }
}
if scenario == "slow-" + phase { usleep(1_000_000) }
if scenario == "slow-each" && phase != "build" { usleep(300_000) }
if phase == "discovery" {
    let listing = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("discovery.json"))) as! [String: [String]]
    let module: String
    if let index = arguments.firstIndex(of: "--package-path") {
        module = URL(fileURLWithPath: arguments[index + 1]).lastPathComponent == "CashFusion" ? "CashFusionEngineTests" : "MosaicEngineTests"
    } else {
        module = URL(fileURLWithPath: arguments[arguments.firstIndex(of: "--test-bundle-path")! + 1]).lastPathComponent
    }
    write(listing[module]!.joined(separator: "\n"))
}
if let index = arguments.firstIndex(of: "--xunit-output"), scenario != "missing-execution-proof" {
    let body = scenario == "empty-execution" ? "" : "<testcase name=\"validate\" classname=\"Fixture\"/>"
    try store("<testsuites><testsuite>\(body)</testsuite></testsuites>", arguments[index + 1])
}
