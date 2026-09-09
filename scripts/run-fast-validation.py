#!/usr/bin/env python3
"""Build, discover, and run the fixed fast regression selection."""

import argparse
import os
import re
import subprocess
import sys
import time

from validation_process import ValidationInterrupted, ValidationProcess, ValidationTimeout


POST_BUILD_BUDGET_SECONDS = 60
CLIENT_SUITE = "ClientSessionValidator"
BOUNDED_SUITES = (
    "CashFusionPrimaryMessageCodecValidator",
    "CashFusionCovertMessageCodecValidator",
    "CashFusionOfficialProtobufFixtureValidator",
    "RoundEngineScriptedValidator",
    "ProductionWorkflowValidator",
    "PrimaryRuntimeSessionValidator",
    "CovertRuntimeSessionValidator",
    "FusionFacadeScaffoldValidator",
    "MosaicHostContractValidator",
    "OpalDiagnosticsFusionValidator",
    "MosaicMainnetAlphaReservationCoordinatorDependencyValidator",
)


def suite_filter(suites):
    if not suites or any(not re.fullmatch(r"[A-Za-z_]\w*", suite) for suite in suites):
        raise ValueError("Fast selection contains an empty or invalid suite")
    if len(suites) != len(set(suites)):
        raise ValueError("Fast selection contains duplicate suites")
    return r"^OpalFusionTests\." + "(" + "|".join(suites) + ")/"


def validate_discovery(output, suites, rsa_filter, material_filter):
    identifiers = [line.strip() for line in output.splitlines()
                   if line.startswith("OpalFusionTests.")]
    if not identifiers or len(identifiers) != len(set(identifiers)):
        raise ValueError("Discovery is empty or contains duplicate test identifiers")
    if any(not re.fullmatch(r"OpalFusionTests\.[^/]+/.+", item) for item in identifiers):
        raise ValueError("Discovery contains an unsupported test identifier")
    selected = re.compile(suite_filter(suites))
    serial = [re.compile(pattern) for pattern in
              (rsa_filter, material_filter, CLIENT_SUITE)]
    matches = [item for item in identifiers if selected.search(item)]
    for suite in suites:
        count = sum(item.startswith(f"OpalFusionTests.{suite}/") for item in matches)
        if not count:
            raise ValueError(f"Configured fast suite is missing or empty: {suite}")
        print(f"  {suite}: {count} tests", flush=True)
    # `all` runs these three serial partitions, then their exact complement.
    # Check against the wrapper's actual filters, including collision detection.
    for item in identifiers:
        partitions = sum(bool(pattern.search(item)) for pattern in serial)
        if partitions > 1:
            raise ValueError(f"Comprehensive partitions overlap: {item}")
        if selected.search(item):
            expected_client = item.startswith(f"OpalFusionTests.{CLIENT_SUITE}/")
            if bool(serial[0].search(item) or serial[1].search(item)):
                raise ValueError(f"Fast selection reaches a cryptographic serial lane: {item}")
            if bool(serial[2].search(item)) != expected_client:
                raise ValueError(f"Fast client partition differs from comprehensive selection: {item}")
    print(f"Fast scope: {len(matches)} tests in {len(suites)} complete suites; "
          f"comprehensive discovery: {len(identifiers)} tests.", flush=True)


def run_fast(options):
    flags = options.swiftpm_flags
    if flags and flags[0] == "--":
        flags = flags[1:]
    bounded = BOUNDED_SUITES + tuple(options.mosaic_fast_filter.split("|"))
    suites = (CLIENT_SUITE,) + bounded
    client_filter = suite_filter((CLIENT_SUITE,))
    bounded_filter = suite_filter(bounded)
    suite_filter(suites)
    if not options.rsa_filter or not options.material_filter or options.parallel_width != 4:
        raise ValueError("Fast validation requires the existing comprehensive filters and width four")
    environment = dict(os.environ, OPALFUSION_EC_INTEROP="")
    build_started = time.monotonic()
    post_started = None
    stage = "build"
    result = "FAIL"
    print("Fast local regression validation: 60 seconds after build; live coordinator proof disabled.",
          flush=True)
    try:
        with ValidationProcess(environment) as process:
            try:
                process.run(["swift", "build", *flags, "--build-tests"])
            finally:
                print(f"Build elapsed: {time.monotonic() - build_started:.3f}s", flush=True)
            post_started = time.monotonic()
            deadline = post_started + POST_BUILD_BUDGET_SECONDS
            stage = "discovery"
            listing = process.run(["swift", "test", *flags, "list", "--skip-build"],
                                  deadline=deadline, capture=True)
            validate_discovery(listing, suites, options.rsa_filter, options.material_filter)
            for stage, arguments in (
                ("serialized client tests", ["--no-parallel", "--filter", client_filter]),
                ("bounded regression tests", ["--experimental-maximum-parallelization-width",
                                              str(options.parallel_width), "--filter", bounded_filter]),
            ):
                print(f"Running {stage} (build skipped).", flush=True)
                process.run(["swift", "test", *flags, "--skip-build", *arguments], deadline=deadline)
            result = "PASS (fast selection only)"
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
        print(f"Post-build elapsed: {elapsed}; budget: 60s; result: {result}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rsa-filter", required=True)
    parser.add_argument("--material-filter", required=True)
    parser.add_argument("--mosaic-fast-filter", required=True)
    parser.add_argument("--parallel-width", type=int, required=True)
    parser.add_argument("swiftpm_flags", nargs=argparse.REMAINDER)
    try:
        return run_fast(parser.parse_args())
    except ValueError as error:
        print(f"Invalid fast selection: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
