import Foundation

struct ValidationFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

let buildBudgetSeconds = 300.0
let postBuildBudgetSeconds = 60.0
let mosaicFastBudgetSeconds = 15.0
let mosaicAllBudgetSeconds = 7_200.0
let clientSuite = "ClientSessionValidator"
let boundedSuites = [
    "CashFusionPrimaryMessageCodecValidator", "CashFusionCovertMessageCodecValidator",
    "CashFusionOfficialProtobufFixtureValidator", "RoundEngineScriptedValidator",
    "ProductionWorkflowValidator", "PrimaryRuntimeSessionValidator",
    "CovertRuntimeSessionValidator", "OpalDiagnosticsFusionValidator"
]
let mosaicFastSuites = [
    "MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator",
    "MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator"
]
let mosaicRSASuites = [
    "MosaicMainnetAlphaRuntimeSessionValidator", "MosaicMainnetAlphaAdmissionLedgerValidator",
    "MosaicMainnetAlphaConductorCoordinatorValidator", "MosaicMainnetAlphaContributorExecutorValidator",
    "MosaicMainnetAlphaLocalBCHSignatureBuilderValidator",
    "MosaicMainnetAlphaPostManifestAnonymousPublicationBridgeValidator",
    "MosaicMainnetAlphaPostManifestAnonymousBatchPublisherValidator",
    "MosaicMainnetAlphaPostManifestContributorTransportBridgeConformanceValidator",
    "MosaicMainnetAlphaReservationCoordinatorValidator", "MosaicMainnetAlphaContractValidator",
    "MosaicOpalV0AuthorizationValidator"
]
let mosaicMaterialSuite = "MosaicMainnetAlpha4MaterialValidator"
let cashFusionModes: Set<String> = ["fast", "build", "cashfusion-all", "cashfusion-focused", "codec", "round", "runtime", "workflow", "client", "interop-parser"]
let mosaicModes: Set<String> = ["mosaic", "mosaic-all", "mosaic-fast", "mosaic-private-alpha-consumer-surface", "mosaic-private-alpha-spi", "mosaic-private-alpha-transport", "mosaic-rehearsal"]

func regularExpression(_ pattern: String) throws -> NSRegularExpression {
    do { return try NSRegularExpression(pattern: pattern) }
    catch { throw ValidationFailure("Invalid regular expression: \(pattern)") }
}

func matches(_ pattern: String, _ input: String) throws -> Bool {
    try regularExpression(pattern).firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) != nil
}

func suiteFilter(_ suites: [String], module: String = "CashFusionEngineTests") throws -> String {
    guard !suites.isEmpty, try suites.allSatisfy({ try matches(#"\A[A-Za-z_]\w*\z"#, $0) }) else {
        throw ValidationFailure("Selection contains an empty or invalid suite")
    }
    guard suites.count == Set(suites).count else { throw ValidationFailure("Selection contains duplicate suites") }
    return "^" + NSRegularExpression.escapedPattern(for: module) + #"\.("# + suites.joined(separator: "|") + ")/"
}

struct Phase {
    let name: String
    let arguments: [String]
    func owns(_ identifier: String) throws -> Bool {
        let include = arguments.firstIndex(of: "--filter").map { arguments[$0 + 1] }
        let exclude = arguments.firstIndex(of: "--skip").map { arguments[$0 + 1] }
        return try (include.map { try matches($0, identifier) } ?? true)
            && !(exclude.map { try matches($0, identifier) } ?? false)
    }
}

struct SelectionPlan {
    let module: String
    let budget: Double?
    let suites: [String]
    let selection: String?
    let phases: [Phase]
}

func selectionPlan(_ mode: String, focus: String? = nil) throws -> SelectionPlan {
    let cash = cashFusionModes.contains(mode)
    let module = cash ? "CashFusionEngineTests" : "MosaicEngineTests"
    let width = ["--experimental-maximum-parallelization-width", "4"]
    var budget = cash ? postBuildBudgetSeconds : mosaicAllBudgetSeconds
    var suites: [String] = []
    var selection: String?
    var phases: [Phase] = []
    switch mode {
    case "build": return SelectionPlan(module: module, budget: nil, suites: [], selection: nil, phases: [])
    case "fast", "cashfusion-all":
        suites = [clientSuite] + boundedSuites
        let filter = try suiteFilter([clientSuite], module: module)
        phases = [Phase(name: "serialized client tests", arguments: ["--no-parallel", "--filter", filter]),
                  Phase(name: "remaining CashFusion tests", arguments: width + ["--skip", filter])]
    case "mosaic", "mosaic-all":
        suites = mosaicRSASuites + [mosaicMaterialSuite]
        let rsa = try suiteFilter(mosaicRSASuites, module: module)
        let material = try suiteFilter([mosaicMaterialSuite], module: module)
        phases = [Phase(name: "serialized Mosaic authorization tests", arguments: ["--no-parallel", "--filter", rsa]),
                  Phase(name: "serialized Mosaic material tests", arguments: ["--no-parallel", "--filter", material]),
                  Phase(name: "remaining Mosaic and facade tests", arguments: width + ["--skip", rsa + "|" + material])]
    case "mosaic-private-alpha-spi":
        suites = ["MosaicPrivateAlphaRuntimeSPIValidator", "MosaicPrivateAlphaTransportBootstrapValidator"]
        selection = try suiteFilter(suites, module: module)
        phases = try suites.map { Phase(name: $0, arguments: ["--no-parallel", "--filter", try suiteFilter([$0], module: module)]) }
    case "cashfusion-focused":
        guard let focus, !focus.isEmpty else { throw ValidationFailure("cashfusion-focused requires one nonempty test filter") }
        _ = try regularExpression(focus)
        selection = focus
        phases = [Phase(name: "selected CashFusion tests", arguments: ["--no-parallel", "--filter", focus])]
    case "mosaic-rehearsal":
        selection = "executeSixContributorConductor|executeThroughExactCommit"
        phases = [Phase(name: "serialized Mosaic rehearsal", arguments: ["--no-parallel", "--filter", selection!])]
    default:
        let named = [
            "codec": Array(boundedSuites.prefix(3)), "round": ["RoundEngineScriptedValidator"],
            "runtime": ["PrimaryRuntimeSessionValidator", "CovertRuntimeSessionValidator", "LiveRuntimeDriverValidator"],
            "workflow": ["ProductionWorkflowValidator"], "client": [clientSuite], "interop-parser": ["ElectronCashInteropValidator"],
            "mosaic-fast": mosaicFastSuites,
            "mosaic-private-alpha-consumer-surface": ["MosaicPrivateAlphaRuntimeRecoveryValidator"],
            "mosaic-private-alpha-transport": ["MosaicPrivateAlphaTransportBootstrapValidator"]
        ]
        guard let names = named[mode] else { throw ValidationFailure("Unknown validation mode: \(mode)") }
        suites = names
        selection = try suiteFilter(suites, module: module)
        let serial = ["client", "mosaic-private-alpha-consumer-surface", "mosaic-private-alpha-transport"].contains(mode)
        phases = [Phase(name: "selected tests", arguments: (serial ? ["--no-parallel"] : width) + ["--filter", selection!])]
        if mode == "mosaic-fast" { budget = mosaicFastBudgetSeconds }
    }
    return SelectionPlan(module: module, budget: budget, suites: suites, selection: selection, phases: phases)
}

func validateDiscovery(_ output: String, module: String, suites: [String] = [], selection: String? = nil,
                       emit: (String) -> Void) throws -> (identifiers: [String], selected: [String]) {
    let identifierPattern = try regularExpression(#"\A([A-Za-z_]\w*)\.([^/\s]+)/(.+)\z"#)
    var identifiers: [String] = []
    for line in output.components(separatedBy: .newlines) {
        let item = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = identifierPattern.firstMatch(in: item, range: NSRange(item.startIndex..., in: item)),
           let range = Range(match.range(at: 1), in: item) {
            guard item[range] == module else { throw ValidationFailure("Discovery contains a foreign-module test: \(item)") }
            identifiers.append(item)
        } else if item.hasPrefix(module + ".") {
            throw ValidationFailure("Discovery contains an unsupported test identifier: \(item)")
        }
    }
    guard !identifiers.isEmpty, identifiers.count == Set(identifiers).count else {
        throw ValidationFailure("Discovery is empty or contains duplicate test identifiers")
    }
    let selected = try identifiers.filter { identifier in try selection.map { try matches($0, identifier) } ?? true }
    guard !selected.isEmpty else { throw ValidationFailure("Configured selection is missing or empty") }
    for suite in suites {
        let count = selected.filter { $0.hasPrefix("\(module).\(suite)/") }.count
        guard count > 0 else { throw ValidationFailure("Configured suite is missing or empty: \(suite)") }
        emit("  \(suite): \(count) tests")
    }
    emit("Selected scope: \(selected.count) tests; harness discovery: \(identifiers.count) tests.")
    return (identifiers, selected)
}

func validatePartitions(identifiers: [String], selected: [String], phases: [Phase]) throws {
    let selectedSet = Set(selected)
    for identifier in identifiers {
        let count = try phases.filter { try $0.owns(identifier) }.count
        guard count == (selectedSet.contains(identifier) ? 1 : 0) else {
            throw ValidationFailure("Process partitions do not assign each selected test exactly once: \(identifier)")
        }
    }
}

func validateSourceGuards(repoRoot: URL, mode: String) throws {
    let all = ["all", "mosaic", "mosaic-all"].contains(mode)
    let tests = repoRoot.appendingPathComponent("Tests/Mosaic/Tests/MosaicEngineTests")
    let material = #"requireAuthorizationEvaluators\(|authorizationEvaluator\(|bchSignatureAuthorizationEvaluator\(|AuthorizationEvaluator\.generate\(|ExecutionFixtures?\.prepare\("#
    var guards: [([String], String, String)] = []
    if all || mode == "mosaic-fast" {
        guards.append((mosaicFastSuites, material, "The Mosaic fast lane reached an RSA evaluator or real-material fixture."))
    }
    if all {
        guards.append((["MosaicMainnetAlphaReservationCoordinatorDependencyValidator"],
                       material + #"|LocalContributionMaterial\.build\(|makeLocalContributionMaterial\(|makeMaterializedPreparation\("#,
                       "The Mosaic reservation dependency lane reached evaluator or material construction."))
    }
    if all || mode == "mosaic-private-alpha-consumer-surface" {
        guards.append((["MosaicPrivateAlphaRuntimeRecoveryValidator"], #"@testable[\t\n\v\f\r ]+import[\t\n\v\f\r ]+(OpalFusion|OpalFusionCore|MosaicEngine)"#,
                       "The private-alpha consumer-surface lane must not use @testable import."))
    }
    if all || ["mosaic-private-alpha-spi", "mosaic-private-alpha-transport"].contains(mode) {
        guards.append((["MosaicPrivateAlphaTransportBootstrapValidator", "RFC9500RSATestKeyFixture"],
                       #"RSABSSA\.SigningKey[\t\n\v\f\r ]*\.generate\("#,
                       "The private-alpha transport lane must use its standard public test key fixture."))
    }
    for (names, pattern, message) in guards {
        for name in names {
            let path = tests.appendingPathComponent(name + ".swift")
            let content = try String(contentsOf: path, encoding: .utf8)
            if let match = try regularExpression(pattern).firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range, in: content) {
                let line = content[..<range.lowerBound].filter { $0 == "\n" }.count + 1
                let relative = String(path.path.dropFirst(repoRoot.path.count + 1))
                throw ValidationFailure("\(relative):\(line): \(message)")
            }
        }
    }
}
