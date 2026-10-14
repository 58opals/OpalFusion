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

MOSAIC_SUITES = fast.MOSAIC_FAST_SUITES
RSA_SUITES = fast.MOSAIC_RSA_SUITES
MATERIAL = fast.MOSAIC_MATERIAL_SUITE
CASH_SUITES = (fast.CLIENT_SUITE,) + fast.BOUNDED_SUITES + ("LiveRuntimeDriverValidator", "ElectronCashInteropValidator", "CashFusionAdditionalValidator")
MOSAIC_ALL_SUITES = MOSAIC_SUITES + RSA_SUITES + (MATERIAL, "FusionFacadeScaffoldValidator", "MosaicPrivateAlphaRuntimeRecoveryValidator", "MosaicPrivateAlphaRuntimeSPIValidator", "MosaicPrivateAlphaTransportBootstrapValidator", "MosaicRehearsalValidator")


class ValidationLoopContract(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        shutil.copytree(SCRIPTS, self.root / "scripts", ignore=shutil.ignore_patterns("__pycache__"))
        self.mosaic_sources = self.root / "Tests/Mosaic/Tests/MosaicEngineTests"
        self.mosaic_sources.mkdir(parents=True)
        for name in (*MOSAIC_SUITES, "MosaicMainnetAlphaReservationCoordinatorDependencyValidator",
                     "MosaicPrivateAlphaRuntimeRecoveryValidator",
                     "MosaicPrivateAlphaTransportBootstrapValidator", "RFC9500RSATestKeyFixture"):
            (self.mosaic_sources / (name + ".swift")).write_text("// Guard fixture\n")
        binary = self.root / "bin"
        binary.mkdir()
        shutil.copyfile(SCRIPTS / "tests/swift_stub.py", binary / "swift")
        (binary / "swift").chmod(0o755)
        self.calls = self.root / "calls.jsonl"
        self.discovery = self.root / "discovery.json"
        listing = {
            "CashFusionEngineTests": [f"CashFusionEngineTests.{s}/validate()" for s in CASH_SUITES],
            "MosaicEngineTests": [f"MosaicEngineTests.{s}/validate()" for s in MOSAIC_ALL_SUITES],
        }
        listing["MosaicEngineTests"].remove("MosaicEngineTests.MosaicRehearsalValidator/validate()")
        listing["MosaicEngineTests"] += ["MosaicEngineTests.MosaicRehearsalValidator/executeSixContributorConductor()", "MosaicEngineTests.MosaicRehearsalValidator/executeThroughExactCommit()"]
        self.discovery.write_text(json.dumps(listing))
        self.env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"],
                        RUNNER_CALLS=str(self.calls), RUNNER_DISCOVERY=str(self.discovery),
                        OPALFUSION_EC_INTEROP="1", PYTHONDONTWRITEBYTECODE="1")
        for key in tuple(self.env):
            if key.startswith("OPALFUSION_SPM_"):
                del self.env[key]

    def invoke(self, *arguments, scenario="", overrides=None):
        self.calls.write_text("")
        result = subprocess.run(["zsh", str(self.root / "scripts/run-validation-loop.sh"), *arguments],
                                env=dict(self.env, RUNNER_SCENARIO=scenario, **(overrides or {})), text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        return result, calls

    def direct(self, *, mode="fast", scenario="", build_budget=300, post_budget=60):
        self.calls.write_text("")
        options = type("Options", (), dict(repo_root=self.root, mode=mode, focus=None))()
        output = io.StringIO()
        with patch.dict(os.environ, dict(self.env, RUNNER_SCENARIO=scenario), clear=True), \
                patch.object(fast, "BUILD_BUDGET_SECONDS", build_budget), \
                patch.object(fast, "POST_BUILD_BUDGET_SECONDS", post_budget), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            result = fast.run_lane(options)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        return result, calls, output.getvalue()

    def test_default_fast_and_complete_alias_have_identical_dispatch(self):
        default, first = self.invoke()
        explicit, second = self.invoke("fast")
        complete, third = self.invoke("cashfusion-all")
        for result in (default, explicit, complete):
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("budget: 60s", result.stdout)
            self.assertIn("PASS (complete harness)", result.stdout)
        self.assertEqual(first, second)
        self.assertEqual(first, third)
        self.assertEqual([call["phase"] for call in first], ["build", "discovery", "client", "bounded"])
        self.assertIn("--build-tests", first[0]["arguments"])
        for call in first:
            self.assertEqual(call["interop"], "")
            package = call["arguments"][call["arguments"].index("--package-path") + 1]
            self.assertEqual(package, str(self.root / "Tests/CashFusion"))
        for call in first[1:]:
            self.assertIn("--skip-build", call["arguments"])
        # Full default must also execute the suites outside the old fixed fast
        # selection; the parallel phase is an exact complement, not a filter.
        self.assertNotIn("--filter", first[-1]["arguments"])
        self.assertEqual(first[-1]["arguments"][-1], fast.suite_filter((fast.CLIENT_SUITE,)))

    def test_cashfusion_does_not_read_or_build_mosaic(self):
        shutil.rmtree(self.root / "Tests/Mosaic")
        result, calls = self.invoke("fast")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(calls)
        self.assertTrue(all("Mosaic" not in json.dumps(call) for call in calls))

    def test_invalid_arguments_do_not_invoke_swift(self):
        for arguments in (("unknown",), ("fast", "extra"), ("cashfusion-focused",),
                          ("cashfusion-focused", ""), ("cashfusion-focused", "[")):
            result, calls = self.invoke(*arguments)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(calls, [])

    def test_missing_empty_duplicate_and_foreign_discovery_fail_before_tests(self):
        complete = json.loads(self.discovery.read_text())
        for listing in ([], complete["CashFusionEngineTests"][1:],
                        complete["CashFusionEngineTests"] + complete["CashFusionEngineTests"][:1],
                        complete["CashFusionEngineTests"] + ["MosaicEngineTests.Foreign/validate()"]):
            self.discovery.write_text(json.dumps(dict(complete, CashFusionEngineTests=listing)))
            result, calls = self.invoke("fast")
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertEqual([call["phase"] for call in calls], ["build", "discovery"])

    def test_failure_stops_the_remaining_commands_without_retry(self):
        for phase, code, count in (("build", 17, 1), ("discovery", 18, 2),
                                   ("client", 19, 3), ("bounded", 20, 4)):
            result, calls = self.invoke("fast", scenario="fail-" + phase)
            self.assertEqual(result.returncode, code, result.stdout)
            self.assertEqual(len(calls), count)
            self.assertNotIn("result: PASS", result.stdout)
            self.assertIn("Build elapsed:", result.stdout)
            self.assertIn("Post-build elapsed:", result.stdout)

    def test_mosaic_guards_run_before_build_and_cover_explicit_engine_imports(self):
        fixtures = (
            (MOSAIC_SUITES[0], "ExecutionFixture.prepare()", "mosaic-fast"),
            ("MosaicMainnetAlphaReservationCoordinatorDependencyValidator", "LocalContributionMaterial.build()", "mosaic-all"),
            ("MosaicPrivateAlphaRuntimeRecoveryValidator", "@_spi(MosaicPrivateAlpha) @testable import MosaicEngine", "mosaic-private-alpha-consumer-surface"),
            ("RFC9500RSATestKeyFixture", "RSABSSA.SigningKey\n  .generate()", "mosaic-private-alpha-transport"),
        )
        for name, content, mode in fixtures:
            with self.subTest(mode=mode):
                fixture = self.mosaic_sources / (name + ".swift")
                fixture.write_text(content)
                result, calls = self.invoke(mode)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(calls, [])
                fixture.write_text("// Guard fixture\n")

    def test_empty_or_duplicate_suite_selectors_are_rejected(self):
        for suites in ((), ("",), ("A", "A"), ("A|B",)):
            with self.assertRaises(ValueError):
                fast.suite_filter(suites)

    def test_build_timeout_precedes_discovery_and_has_its_own_deadline(self):
        result, calls, output = self.direct(scenario="slow-build", build_budget=0.2, post_budget=0.1)
        self.assertEqual(result, 124, output)
        self.assertEqual([call["phase"] for call in calls], ["build"])
        self.assertIn("FAIL during build", output)
        self.assertIn("Post-build elapsed: not started", output)

    def test_build_time_does_not_consume_the_post_build_deadline(self):
        result, calls, output = self.direct(scenario="slow-build", build_budget=2, post_budget=0.8)
        self.assertEqual(result, 0, output)
        self.assertEqual([call["phase"] for call in calls], ["build", "discovery", "client", "bounded"])

    def test_discovery_is_inside_the_aggregate_deadline(self):
        result, calls, output = self.direct(scenario="slow-discovery", post_budget=0.2)
        self.assertEqual(result, 124, output)
        self.assertIn("FAIL during discovery", output)
        self.assertEqual([call["phase"] for call in calls], ["build", "discovery"])

    def test_budget_is_shared_across_discovery_and_both_test_processes(self):
        # Advance a controlled clock through process startup and completion.
        # This proves the aggregate budget without scheduling-dependent sleeps.
        now = [0.0]
        deadlines = []
        commands = []
        listing = "\n".join(json.loads(self.discovery.read_text())["CashFusionEngineTests"])

        class ProcessClock:
            def __init__(self, environment):
                pass

            def __enter__(self):
                return self

            def __exit__(self, *_):
                pass

            def run(self, command, *, deadline=None, capture=False):
                commands.append(command)
                deadlines.append(deadline)
                now[0] += 100 if command[1] == "build" else 0.3
                if now[0] > deadline:
                    raise ValidationTimeout("validation deadline exhausted")
                return listing if capture else None

        options = type("Options", (), dict(repo_root=self.root, mode="fast", focus=None))()
        output = io.StringIO()
        with patch.object(fast, "ValidationProcess", ProcessClock), \
                patch.object(fast.time, "monotonic", side_effect=lambda: now[0]), \
                patch.object(fast, "POST_BUILD_BUDGET_SECONDS", 0.8), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            result = fast.run_lane(options)
        self.assertEqual(result, 124, output.getvalue())
        self.assertEqual(len(commands), 4)
        self.assertEqual(deadlines[0], 300)
        self.assertEqual(deadlines[1:], [100.8] * 3)
        self.assertIn("remaining CashFusion tests", output.getvalue())

    def test_overridden_paths_are_root_relative_before_nested_package_dispatch(self):
        overrides = {"OPALFUSION_SPM_SCRATCH_PATH": "warm/build",
                     "OPALFUSION_SPM_CACHE_PATH": "warm/cache",
                     "OPALFUSION_SPM_CONFIG_PATH": "warm/config",
                     "OPALFUSION_SPM_SECURITY_PATH": "warm/security",
                     "OPALFUSION_SPM_MODULE_CACHE_PATH": "warm/module"}
        result, calls = self.invoke("fast", overrides=overrides)
        self.assertEqual(result.returncode, 0, result.stdout)
        for call in calls:
            args = call["arguments"]
            for flag, name in (("--scratch-path", "build"), ("--cache-path", "cache"),
                               ("--config-path", "config"), ("--security-path", "security")):
                self.assertEqual(args[args.index(flag) + 1], str(self.root / "warm" / name))
            self.assertEqual(call["module_cache"], str(self.root / "warm/module"))

    def test_named_modes_select_their_package_and_keep_skip_build_and_live_exclusion(self):
        modes = {
            "build": ("CashFusion", 1),
            "codec": ("CashFusion", 3), "round": ("CashFusion", 3),
            "runtime": ("CashFusion", 3), "workflow": ("CashFusion", 3),
            "client": ("CashFusion", 3), "interop-parser": ("CashFusion", 3),
            "mosaic": ("Mosaic", 5), "mosaic-all": ("Mosaic", 5),
            "mosaic-fast": ("Mosaic", 3),
            "mosaic-private-alpha-consumer-surface": ("Mosaic", 3),
            "mosaic-private-alpha-spi": ("Mosaic", 4),
            "mosaic-private-alpha-transport": ("Mosaic", 3),
            "mosaic-rehearsal": ("Mosaic", 3),
        }
        for mode, (package, count) in modes.items():
            with self.subTest(mode=mode):
                result, calls = self.invoke(mode)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(len(calls), count)
                for call in calls:
                    args = call["arguments"]
                    self.assertEqual(Path(args[args.index("--package-path") + 1]).name, package)
                    self.assertEqual(call["interop"], "")
                    if args[0] == "test":
                        self.assertIn("--skip-build", args)
                if mode == "mosaic-fast":
                    self.assertIn("budget: 15s", result.stdout)
                elif package == "Mosaic":
                    self.assertIn("budget: 7200s", result.stdout)

    def test_combined_all_keeps_complete_disjoint_engine_partitions(self):
        result, calls = self.invoke("all")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(len(calls), 9)
        self.assertEqual([Path(call["arguments"][call["arguments"].index("--package-path") + 1]).name
                          for call in calls], ["CashFusion"] * 4 + ["Mosaic"] * 5)
        self.assertIn("budget: 60s", result.stdout)
        self.assertIn("budget: 7200s", result.stdout)
        for mode in ("cashfusion-all", "mosaic-all"):
            module, _, suites, selection, phases = fast.selection_plan(mode)
            listing = "\n".join(json.loads(self.discovery.read_text())[module])
            identifiers, selected = fast.validate_discovery(listing, module, suites, selection)
            self.assertEqual(identifiers, selected)
            fast.validate_partitions(identifiers, selected, phases)

    def test_focused_filter_requires_matches_and_preserves_serial_execution(self):
        result, calls = self.invoke("cashfusion-focused", "RoundEngineScriptedValidator")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(len(calls), 3)
        self.assertIn("--no-parallel", calls[-1]["arguments"])
        self.assertIn("budget: 60s", result.stdout)
        result, calls = self.invoke("cashfusion-focused", "DoesNotExist")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 2)


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

    def test_timeout_probe_permission_failure_still_kills_descendants_and_preserves_unrelated_process(self):
        original_killpg = os.killpg
        probes = []
        delivered = []

        def permission_denied_probe(pid, signum):
            if signum == 0:
                probes.append(pid)
                raise PermissionError("Existence probe denied")
            delivered.append((pid, signum))
            return original_killpg(pid, signum)

        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "child.pid"
            child = "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(300)"
            command = [sys.executable, "-c", "import subprocess,time,pathlib; "
                       f"p=subprocess.Popen([{sys.executable!r},'-c',{child!r}]); "
                       f"pathlib.Path({str(marker)!r}).write_text(str(p.pid)); time.sleep(300)"]
            unrelated = subprocess.Popen([sys.executable, "-c", child], start_new_session=True)
            try:
                start = time.monotonic()
                with ValidationProcess(dict(os.environ)) as process, patch.object(os, "killpg", permission_denied_probe):
                    with self.assertRaises(ValidationTimeout):
                        process.run(command, deadline=start + 0.4)
                self.assertLess(time.monotonic() - start, 5.9)
                self.assertTrue(probes)
                self.assertEqual([s for _, s in delivered], [signal.SIGTERM, signal.SIGKILL])
                self.assertEqual(len({pid for pid, _ in delivered}), 1)
                self.assertIsNone(unrelated.poll())
                self.assertTrue(marker.exists())
                assert_process_stopped(self, int(marker.read_text()))
            finally:
                unrelated.kill()
                unrelated.wait()
                if marker.exists():
                    try:
                        os.kill(int(marker.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_real_signal_permission_failure_is_not_accepted_as_cleanup(self):
        child = type("Child", (), dict(pid=987654321, stdout=None))()
        process = ValidationProcess(dict(os.environ))
        process.active = child
        with patch.object(os, "killpg", side_effect=PermissionError("Signal delivery denied")):
            with self.assertRaises(PermissionError):
                process.cleanup()
        self.assertIs(process.active, child)

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
