"""Run with: python3 -B -m unittest discover -s scripts/tests -v."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from validation_process import ValidationInterrupted, ValidationProcess, ValidationTimeout

spec = importlib.util.spec_from_file_location("fast_validation", SCRIPTS / "run-fast-validation.py")
fast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fast)

MOSAIC_SUITES = (
    "MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator",
    "MosaicMainnetAlphaPostManifestContributorTransportBridgeValidator",
)
RSA_SUITES = (
    "MosaicMainnetAlphaRuntimeSessionValidator", "MosaicMainnetAlphaAdmissionLedgerValidator",
    "MosaicMainnetAlphaConductorCoordinatorValidator", "MosaicMainnetAlphaContributorExecutorValidator",
    "MosaicMainnetAlphaLocalBCHSignatureBuilderValidator",
    "MosaicMainnetAlphaPostManifestAnonymousPublicationBridgeValidator",
    "MosaicMainnetAlphaPostManifestAnonymousBatchPublisherValidator",
    "MosaicMainnetAlphaPostManifestContributorTransportBridgeConformanceValidator",
    "MosaicMainnetAlphaReservationCoordinatorValidator", "MosaicMainnetAlphaContractValidator",
    "MosaicOpalV0AuthorizationValidator",
)
MATERIAL = "MosaicMainnetAlpha4MaterialValidator"
ALL_SUITES = (fast.CLIENT_SUITE,) + fast.BOUNDED_SUITES + MOSAIC_SUITES + RSA_SUITES + (MATERIAL,)


class ValidationLoopContract(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        shutil.copytree(SCRIPTS, self.root / "scripts", ignore=shutil.ignore_patterns("__pycache__"))
        fixtures = self.root / "Tests/OpalFusionTests"
        fixtures.mkdir(parents=True)
        for name in (*MOSAIC_SUITES, fast.BOUNDED_SUITES[-1],
                     "MosaicPrivateAlphaRuntimeRecoveryValidator",
                     "MosaicPrivateAlphaTransportBootstrapValidator", "RFC9500RSATestKeyFixture"):
            (fixtures / (name + ".swift")).write_text("// Guard fixture\n")
        binary = self.root / "bin"
        binary.mkdir()
        shutil.copyfile(SCRIPTS / "tests/swift_stub.py", binary / "swift")
        (binary / "swift").chmod(0o755)
        self.calls = self.root / "calls.jsonl"
        self.discovery = self.root / "discovery.json"
        self.discovery.write_text(json.dumps([f"OpalFusionTests.{s}/validate()" for s in ALL_SUITES]))
        self.env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"],
                        RUNNER_CALLS=str(self.calls), RUNNER_DISCOVERY=str(self.discovery),
                        OPALFUSION_EC_INTEROP="1", PYTHONDONTWRITEBYTECODE="1")

    def invoke(self, *arguments, scenario=""):
        self.calls.write_text("")
        result = subprocess.run(["zsh", str(self.root / "scripts/run-validation-loop.sh"), *arguments],
                                env=dict(self.env, RUNNER_SCENARIO=scenario), text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        return result, calls

    def test_default_and_explicit_fast_have_identical_dispatch(self):
        default, first = self.invoke()
        explicit, second = self.invoke("fast")
        self.assertEqual(default.returncode, 0, default.stdout)
        self.assertEqual(explicit.returncode, 0, explicit.stdout)
        self.assertEqual(first, second)
        self.assertEqual([call["phase"] for call in first], ["build", "discovery", "client", "bounded"])
        self.assertIn("--build-tests", first[0]["arguments"])
        for call in first[1:]:
            self.assertIn("--skip-build", call["arguments"])
            self.assertEqual(call["interop"], "")
        self.assertIn("60s", explicit.stdout)
        self.assertIn("fast selection only", explicit.stdout)

    def test_invalid_arguments_do_not_invoke_swift(self):
        for arguments in (("unknown",), ("fast", "extra")):
            result, calls = self.invoke(*arguments)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(calls, [])

    def test_missing_empty_and_duplicate_discovery_fail_before_tests(self):
        complete = json.loads(self.discovery.read_text())
        for listing in ([], complete[1:], complete + complete[:1]):
            self.discovery.write_text(json.dumps(listing))
            result, calls = self.invoke("fast")
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertEqual([call["phase"] for call in calls], ["build", "discovery"])

    def test_failure_stops_the_remaining_commands(self):
        for phase, code, count in (("build", 17, 1), ("discovery", 18, 2),
                                   ("client", 19, 3), ("bounded", 20, 4)):
            result, calls = self.invoke("fast", scenario="fail-" + phase)
            self.assertEqual(result.returncode, code, result.stdout)
            self.assertEqual(len(calls), count)
            self.assertNotIn("result: PASS", result.stdout)
            self.assertIn("Build elapsed:", result.stdout)
            self.assertIn("Post-build elapsed:", result.stdout)

    def test_material_guard_runs_before_build(self):
        fixture = self.root / "Tests/OpalFusionTests" / (MOSAIC_SUITES[0] + ".swift")
        fixture.write_text("ExecutionFixture.prepare()\n")
        result, calls = self.invoke("fast")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_empty_or_duplicate_selectors_are_rejected(self):
        for suites in ((), ("",), ("A", "A"), ("A|B",)):
            with self.assertRaises(ValueError):
                fast.suite_filter(suites)

    def test_fast_cannot_reach_serial_cryptographic_partition(self):
        with self.assertRaisesRegex(ValueError, "cryptographic serial lane"):
            fast.validate_discovery("OpalFusionTests.MosaicCrypto/validate()",
                                    ("MosaicCrypto",), "MosaicCrypto", MATERIAL)

    def test_discovery_is_inside_the_aggregate_deadline(self):
        options = type("Options", (), dict(swiftpm_flags=[], rsa_filter="|".join(RSA_SUITES),
                                           material_filter=MATERIAL, parallel_width=4,
                                           mosaic_fast_filter="|".join(MOSAIC_SUITES)))()
        errors = io.StringIO()
        with patch.dict(os.environ, dict(self.env, RUNNER_SCENARIO="slow-discovery"), clear=True), \
                patch.object(fast, "POST_BUILD_BUDGET_SECONDS", 0.8), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(errors):
            result = fast.run_fast(options)
        self.assertEqual(result, 124, errors.getvalue())
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual([call["phase"] for call in calls], ["build", "discovery"])

    def test_budget_is_shared_across_discovery_and_both_test_processes(self):
        options = type("Options", (), dict(swiftpm_flags=[], rsa_filter="|".join(RSA_SUITES),
                                           material_filter=MATERIAL, parallel_width=4,
                                           mosaic_fast_filter="|".join(MOSAIC_SUITES)))()
        errors = io.StringIO()
        with patch.dict(os.environ, dict(self.env, RUNNER_SCENARIO="slow-each"), clear=True), \
                patch.object(fast, "POST_BUILD_BUDGET_SECONDS", 4.0), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(errors):
            result = fast.run_fast(options)
        self.assertEqual(result, 124, errors.getvalue())
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual([call["phase"] for call in calls], ["build", "discovery", "client", "bounded"])

    def test_existing_mode_dispatch(self):
        def filtered(name, serial=False):
            return (["--no-parallel"] if serial else []) + ["--filter", name]

        width = ["--experimental-maximum-parallelization-width", "4"]
        rsa = "|".join(RSA_SUITES)
        expected = {
            "build": [("build", [])],
            "all": [("test", filtered(rsa, True)), ("test", filtered(MATERIAL, True)),
                    ("test", filtered(fast.CLIENT_SUITE, True)),
                    ("test", width + ["--skip", rsa + "|" + MATERIAL + "|" + fast.CLIENT_SUITE])],
            "codec": [("test", filtered(name)) for name in fast.BOUNDED_SUITES[:3]],
            "round": [("test", filtered("RoundEngineScriptedValidator"))],
            "runtime": [("test", filtered(name)) for name in
                        ("PrimaryRuntimeSessionValidator", "CovertRuntimeSessionValidator", "LiveRuntimeDriverValidator")],
            "workflow": [("test", filtered("ProductionWorkflowValidator"))],
            "client": [("test", filtered(fast.CLIENT_SUITE))],
            "mosaic": [("test", filtered(rsa, True)), ("test", filtered(MATERIAL, True)),
                       ("test", width + ["--filter", "Mosaic", "--skip", rsa + "|" + MATERIAL]),
                       ("test", filtered("FusionFacadeScaffoldValidator"))],
            "mosaic-fast": [("test", width + filtered("|".join(MOSAIC_SUITES)))],
            "mosaic-private-alpha-consumer-surface": [("test", filtered("MosaicPrivateAlphaRuntimeRecoveryValidator"))],
            "mosaic-private-alpha-spi": [("test", filtered(name, True)) for name in
                                         ("MosaicPrivateAlphaRuntimeSPIValidator", "MosaicPrivateAlphaTransportBootstrapValidator")],
            "mosaic-private-alpha-transport": [("test", filtered("MosaicPrivateAlphaTransportBootstrapValidator", True))],
            "mosaic-rehearsal": [("test", filtered("executeSixContributorConductor|executeThroughExactCommit", True))],
            "interop-parser": [("test", filtered("ElectronCashInteropValidator"))],
        }
        for mode, commands in expected.items():
            with self.subTest(mode=mode):
                result, calls = self.invoke(mode)
                self.assertEqual(result.returncode, 0, result.stdout)
                actual = []
                for call in calls:
                    args = call["arguments"]
                    end = args.index("--manifest-cache") + 2
                    actual.append((args[0], args[end:]))
                    if args[0] == "test":
                        self.assertEqual(call["interop"], "")
                self.assertEqual(actual, commands)
                if mode == "all":
                    self.assertIn("97 minutes", result.stdout)
                    self.assertNotIn("Post-build elapsed:", result.stdout)


class ValidationProcessContract(unittest.TestCase):
    def test_interrupt_during_launch_still_cleans_the_new_process(self):
        original = subprocess.Popen
        children = []

        def launch_and_interrupt(*arguments, **keywords):
            child = original(*arguments, **keywords)
            children.append(child)
            os.kill(os.getpid(), signal.SIGTERM)
            return child

        with ValidationProcess(dict(os.environ)) as process, patch.object(subprocess, "Popen", launch_and_interrupt):
            with self.assertRaises(ValidationInterrupted):
                process.run([sys.executable, "-c", "import time; time.sleep(300)"])
        self.assertEqual(len(children), 1)
        self.assertIsNotNone(children[0].poll())

    def test_timeout_cleans_descendants_and_preserves_unrelated_process(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "child.pid"
            child = "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(300)"
            command = [sys.executable, "-c", "import subprocess,time,pathlib; "
                       f"p=subprocess.Popen([{sys.executable!r},'-c',{child!r}]); "
                       f"pathlib.Path({str(marker)!r}).write_text(str(p.pid)); time.sleep(300)"]
            unrelated = subprocess.Popen([sys.executable, "-c", child], start_new_session=True)
            try:
                start = time.monotonic()
                with ValidationProcess(dict(os.environ)) as process:
                    with self.assertRaises(ValidationTimeout):
                        process.run(command, deadline=start + 0.4)
                self.assertLess(time.monotonic() - start, 5.9)
                self.assertIsNone(unrelated.poll())
                self.assertTrue(marker.exists())
                assert_process_stopped(self, int(marker.read_text()))
            finally:
                unrelated.kill()
                unrelated.wait()

    def test_interrupt_cleans_owned_group(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=signum), tempfile.TemporaryDirectory() as directory:
                marker = Path(directory) / "owned.pid"
                target = ("import os,pathlib,time; "
                          f"pathlib.Path({str(marker)!r}).write_text(str(os.getpid())); time.sleep(300)")
                harness = ("import os,sys; " + f"sys.path.insert(0,{str(SCRIPTS)!r}); "
                           "from validation_process import ValidationProcess,ValidationInterrupted\n"
                           "try:\n with ValidationProcess(dict(os.environ)) as p:\n"
                           f"  p.run([{sys.executable!r},'-c',{target!r}])\n"
                           "except ValidationInterrupted as e: sys.exit(128+e.signum)\n")
                parent = subprocess.Popen([sys.executable, "-B", "-c", harness], start_new_session=True)
                try:
                    end = time.monotonic() + 5
                    while not marker.exists() and time.monotonic() < end:
                        time.sleep(0.02)
                    self.assertTrue(marker.exists())
                    parent.send_signal(signum)
                    self.assertEqual(parent.wait(timeout=6), 128 + signum)
                    assert_process_stopped(self, int(marker.read_text()))
                finally:
                    if parent.poll() is None:
                        parent.terminate()
                        parent.wait(timeout=6)


def assert_process_stopped(test, pid):
    end = time.monotonic() + 1
    while time.monotonic() < end:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.02)
    test.fail(f"Owned process {pid} survived cleanup")


if __name__ == "__main__":
    unittest.main()
