#!/usr/bin/env python3
"""Run independently built CashFusion or Mosaic validation with fixed deadlines."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import time

from validation_process import ValidationInterrupted, ValidationProcess, ValidationTimeout


BUILD_BUDGET_SECONDS = 300
POST_BUILD_BUDGET_SECONDS = 60
MOSAIC_FAST_BUDGET_SECONDS = 15
MOSAIC_ALL_BUDGET_SECONDS = 7200
CLIENT_SUITE = "ClientSessionValidator"
BOUNDED_SUITES = (
    "CashFusionPrimaryMessageCodecValidator",
    "CashFusionCovertMessageCodecValidator",
    "CashFusionOfficialProtobufFixtureValidator",
    "RoundEngineScriptedValidator",
    "ProductionWorkflowValidator",
    "PrimaryRuntimeSessionValidator",
    "CovertRuntimeSessionValidator",
    "OpalDiagnosticsFusionValidator",
)
MOSAIC_FAST_SUITES = (
    "MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator",
    "MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator",
)
MOSAIC_RSA_SUITES = (
    "MosaicMainnetAlphaRuntimeSessionValidator",
    "MosaicMainnetAlphaAdmissionLedgerValidator",
    "MosaicMainnetAlphaConductorCoordinatorValidator",
    "MosaicMainnetAlphaContributorExecutorValidator",
    "MosaicMainnetAlphaLocalBCHSignatureBuilderValidator",
    "MosaicMainnetAlphaPostManifestAnonymousPublicationBridgeValidator",
    "MosaicMainnetAlphaPostManifestAnonymousBatchPublisherValidator",
    "MosaicMainnetAlphaPostManifestContributorTransportBridgeConformanceValidator",
    "MosaicMainnetAlphaReservationCoordinatorValidator",
    "MosaicMainnetAlphaContractValidator",
    "MosaicOpalV0AuthorizationValidator",
)
MOSAIC_MATERIAL_SUITE = "MosaicMainnetAlpha4MaterialValidator"
CASHFUSION_MODES = {
    "fast", "build", "cashfusion-all", "cashfusion-focused", "codec", "round",
    "runtime", "workflow", "client", "interop-parser",
}
MOSAIC_MODES = {
    "mosaic", "mosaic-all", "mosaic-fast", "mosaic-private-alpha-consumer-surface",
    "mosaic-private-alpha-spi", "mosaic-private-alpha-transport", "mosaic-rehearsal",
}


def suite_filter(suites, module="CashFusionEngineTests"):
    if not suites or any(not re.fullmatch(r"[A-Za-z_]\w*", suite) for suite in suites):
        raise ValueError("Selection contains an empty or invalid suite")
    if len(suites) != len(set(suites)):
        raise ValueError("Selection contains duplicate suites")
    return "^" + re.escape(module) + r"\.(" + "|".join(suites) + ")/"


def validate_discovery(output, module, suites=(), selection=None):
    identifiers = []
    for line in output.splitlines():
        item = line.strip()
        # SwiftPM may print informational lines, but every test identifier must
        # belong to this independent harness. Never silently accept another one.
        match = re.fullmatch(r"([A-Za-z_]\w*)\.([^/\s]+)/(.+)", item)
        if match:
            if match[1] != module:
                raise ValueError(f"Discovery contains a foreign-module test: {item}")
            identifiers.append(item)
        elif item.startswith(module + "."):
            raise ValueError(f"Discovery contains an unsupported test identifier: {item}")
    if not identifiers or len(identifiers) != len(set(identifiers)):
        raise ValueError("Discovery is empty or contains duplicate test identifiers")
    selected = re.compile(selection) if selection else None
    matches = [item for item in identifiers if selected is None or selected.search(item)]
    if not matches:
        raise ValueError("Configured selection is missing or empty")
    for suite in suites:
        count = sum(item.startswith(f"{module}.{suite}/") for item in matches)
        if not count:
            raise ValueError(f"Configured suite is missing or empty: {suite}")
        print(f"  {suite}: {count} tests", flush=True)
    print(f"Selected scope: {len(matches)} tests; harness discovery: {len(identifiers)} tests.",
          flush=True)
    return identifiers, matches


def swiftpm_flags(repo_root, engine):
    # Resolve overrides at the repository root before SwiftPM changes to a
    # nested package. This also keeps the two default build graphs independent.
    lane_root = repo_root / ".build" / "validation" / engine

    def path(variable, default):
        value = Path(os.environ.get(variable, str(default)))
        return str((value if value.is_absolute() else repo_root / value).resolve())

    scratch = path("OPALFUSION_SPM_SCRATCH_PATH", lane_root / "build")
    module_cache = path("OPALFUSION_SPM_MODULE_CACHE_PATH", lane_root / "module-cache")
    Path(module_cache).mkdir(parents=True, exist_ok=True)
    flags = [
        "--package-path", str(repo_root / "Tests" / ("CashFusion" if engine == "cashfusion" else "Mosaic")),
        "--scratch-path", scratch,
        "--cache-path", path("OPALFUSION_SPM_CACHE_PATH", scratch),
        "--config-path", path("OPALFUSION_SPM_CONFIG_PATH", lane_root / "config"),
        "--security-path", path("OPALFUSION_SPM_SECURITY_PATH", lane_root / "security"),
        "--manifest-cache", "local",
    ]
    return flags, module_cache


def selection_plan(mode, focus=None):
    """Return module, budget, required suites, filter, and complete process partitions."""
    cash = mode in CASHFUSION_MODES
    module = "CashFusionEngineTests" if cash else "MosaicEngineTests"
    width = ["--experimental-maximum-parallelization-width", "4"]
    budget = POST_BUILD_BUDGET_SECONDS if cash else MOSAIC_ALL_BUDGET_SECONDS
    suites = ()
    selection = None
    phases = []
    if mode == "build":
        return module, None, suites, selection, phases
    if mode in ("fast", "cashfusion-all"):
        suites = (CLIENT_SUITE,) + BOUNDED_SUITES
        client = suite_filter((CLIENT_SUITE,), module)
        phases = [
            ("serialized client tests", ["--no-parallel", "--filter", client]),
            ("remaining CashFusion tests", width + ["--skip", client]),
        ]
    elif mode in ("mosaic", "mosaic-all"):
        suites = MOSAIC_RSA_SUITES + (MOSAIC_MATERIAL_SUITE,)
        rsa = suite_filter(MOSAIC_RSA_SUITES, module)
        material = suite_filter((MOSAIC_MATERIAL_SUITE,), module)
        phases = [
            ("serialized Mosaic authorization tests", ["--no-parallel", "--filter", rsa]),
            ("serialized Mosaic material tests", ["--no-parallel", "--filter", material]),
            ("remaining Mosaic and facade tests", width + ["--skip", rsa + "|" + material]),
        ]
    elif mode == "mosaic-private-alpha-spi":
        suites = ("MosaicPrivateAlphaRuntimeSPIValidator", "MosaicPrivateAlphaTransportBootstrapValidator")
        selection = suite_filter(suites, module)
        phases = [(suite, ["--no-parallel", "--filter", suite_filter((suite,), module)]) for suite in suites]
    elif mode == "cashfusion-focused":
        if not focus:
            raise ValueError("cashfusion-focused requires one nonempty test filter")
        re.compile(focus)
        selection = focus
        # A focused selection may include client cases. Preserve their existing
        # serialized execution without introducing another partition policy.
        phases = [("selected CashFusion tests", ["--no-parallel", "--filter", focus])]
    elif mode == "mosaic-rehearsal":
        selection = "executeSixContributorConductor|executeThroughExactCommit"
        phases = [("serialized Mosaic rehearsal", ["--no-parallel", "--filter", selection])]
    else:
        named = {
            "codec": BOUNDED_SUITES[:3],
            "round": ("RoundEngineScriptedValidator",),
            "runtime": ("PrimaryRuntimeSessionValidator", "CovertRuntimeSessionValidator", "LiveRuntimeDriverValidator"),
            "workflow": ("ProductionWorkflowValidator",),
            "client": (CLIENT_SUITE,),
            "interop-parser": ("ElectronCashInteropValidator",),
            "mosaic-fast": MOSAIC_FAST_SUITES,
            "mosaic-private-alpha-consumer-surface": ("MosaicPrivateAlphaRuntimeRecoveryValidator",),
            "mosaic-private-alpha-transport": ("MosaicPrivateAlphaTransportBootstrapValidator",),
        }
        suites = named[mode]
        selection = suite_filter(suites, module)
        serial = mode in ("client", "mosaic-private-alpha-consumer-surface", "mosaic-private-alpha-transport")
        phases = [("selected tests", (["--no-parallel"] if serial else width) + ["--filter", selection])]
        if mode == "mosaic-fast":
            budget = MOSAIC_FAST_BUDGET_SECONDS
    return module, budget, suites, selection, phases


def validate_partitions(identifiers, selected, phases):
    for item in identifiers:
        owners = 0
        for _, arguments in phases:
            include = arguments[arguments.index("--filter") + 1] if "--filter" in arguments else None
            exclude = arguments[arguments.index("--skip") + 1] if "--skip" in arguments else None
            owners += bool((include is None or re.search(include, item)) and
                           (exclude is None or not re.search(exclude, item)))
        if owners != (1 if item in selected else 0):
            raise ValueError(f"Process partitions do not assign each selected test exactly once: {item}")


def run_lane(options):
    mode = options.mode
    module, budget, suites, selection, phases = selection_plan(mode, options.focus)
    engine = "cashfusion" if module == "CashFusionEngineTests" else "mosaic"
    flags, module_cache = swiftpm_flags(Path(options.repo_root).resolve(), engine)
    environment = dict(os.environ, OPALFUSION_EC_INTEROP="", CLANG_MODULE_CACHE_PATH=module_cache)
    build_started = time.monotonic()
    post_started = None
    stage = "build"
    result = "FAIL"
    print(f"{mode} local validation: build budget {BUILD_BUDGET_SECONDS}s; "
          f"post-build budget {budget if budget is not None else 'not applicable'}s; "
          "live coordinator proof disabled.", flush=True)
    if engine == "mosaic" and mode != "mosaic-fast":
        print("Explicit deferred Mosaic lane; historical combined Debug runtime: approximately 97 minutes.", flush=True)
    try:
        with ValidationProcess(environment) as process:
            try:
                process.run(["swift", "build", *flags, "--build-tests"],
                            deadline=build_started + BUILD_BUDGET_SECONDS)
            finally:
                print(f"Build elapsed: {time.monotonic() - build_started:.3f}s", flush=True)
            if mode == "build":
                result = "PASS (CashFusion harness build only)"
                return 0
            post_started = time.monotonic()
            deadline = post_started + budget
            stage = "discovery"
            listing = process.run(["swift", "test", *flags, "list", "--skip-build"],
                                  deadline=deadline, capture=True)
            identifiers, selected = validate_discovery(listing, module, suites, selection)
            validate_partitions(identifiers, selected, phases)
            for stage, arguments in phases:
                # Every discovered selected case is assigned exactly once.
                include = arguments[arguments.index("--filter") + 1] if "--filter" in arguments else None
                exclude = arguments[arguments.index("--skip") + 1] if "--skip" in arguments else None
                if not any((include is None or re.search(include, item)) and
                           (exclude is None or not re.search(exclude, item)) for item in selected):
                    continue
                print(f"Running {stage} (build skipped).", flush=True)
                process.run(["swift", "test", *flags, "--skip-build", *arguments], deadline=deadline)
            result = "PASS (complete harness)" if mode in ("fast", "cashfusion-all", "mosaic", "mosaic-all") else "PASS (selected scope only)"
            return 0
    except ValidationTimeout as error:
        print(f"FAIL during {stage}: {error}; no retry or budget extension.", file=sys.stderr)
        return 124
    except ValidationInterrupted as error:
        print(f"FAIL during {stage}: {error}.", file=sys.stderr)
        return 128 + error.signum
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"FAIL during {stage}: {error}", file=sys.stderr)
        return max(1, min(125, error.returncode)) if isinstance(error, subprocess.CalledProcessError) else 1
    finally:
        elapsed = "not started" if post_started is None else f"{time.monotonic() - post_started:.3f}s"
        print(f"Post-build elapsed: {elapsed}; budget: {budget if budget is not None else 'not applicable'}s; result: {result}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--mode", choices=sorted(CASHFUSION_MODES | MOSAIC_MODES | {"all"}), default="fast")
    parser.add_argument("--focus")
    options = parser.parse_args()
    try:
        if options.focus is not None and options.mode != "cashfusion-focused":
            raise ValueError("A test filter is accepted only by cashfusion-focused")
        modes = ("cashfusion-all", "mosaic-all") if options.mode == "all" else (options.mode,)
        for mode in modes:
            options.mode = mode
            result = run_lane(options)
            if result:
                return result
        return 0
    except (ValueError, re.error) as error:
        print(f"Invalid validation selection: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
