"""Historical parser proof checks use revision-owned paths and require evidence."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
REPO_ROOT = SCRIPTS.parent
PROOF_REVISIONS = (
    "117949b08f354f5a58b78075dbf14b2ec4e4f88f",
    "79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46",
)
HISTORICAL_PATHS = (
    "Sources/OpalFusion/Mosaic/OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapConsensusEnvelope.swift",
    "Sources/OpalFusion/Mosaic/OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapEnvelope.swift",
    "Sources/OpalFusion/Mosaic/OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapPublicationRestoration.swift",
    "Tests/OpalFusionTests/MosaicPrivateAlphaTransportBootstrapValidator.swift",
)


class ParserHistoricalProofContract(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        (self.root / "scripts").mkdir()
        shutil.copyfile(SCRIPTS / "check-mosaic-g4-parser-root-registry.sh",
                        self.root / "scripts/check-mosaic-g4-parser-root-registry.sh")
        docs = self.root / "docs"
        docs.mkdir()
        for name in ("mosaic-g4-parser-implementation-files-2026-08-23.txt",
                     "mosaic-g4-parser-root-map-2026-08-23.txt",
                     "mosaic-g4-parser-composite-root-map-2026-08-23.txt"):
            shutil.copyfile(REPO_ROOT / "docs" / name, docs / name)
        registry = (docs / "mosaic-g4-parser-implementation-files-2026-08-23.txt").read_text().splitlines()
        for name in registry:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("CanonicalDecoder.decode\n")
        # Pure textual fixtures exercise the current registry scans. No Swift
        # build, protocol fixture, or repository-history mutation is involved.
        current_paths = [name.replace("Sources/OpalFusion/", "Sources/MosaicEngine/")
                         for name in HISTORICAL_PATHS[:3]]
        for name in current_paths:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            if not path.exists():
                path.write_text("")
        roots = (docs / "mosaic-g4-parser-composite-root-map-2026-08-23.txt").read_text().splitlines()
        with (self.root / current_paths[0]).open("a") as output:
            for row in roots:
                output.write("public static func " + row.split(" :: ")[0] + "() {}\n")
        binary = self.root / "bin"
        binary.mkdir()
        git = binary / "git"
        git.write_text("#!" + sys.executable + "\n" + r"""
import json
import os
from pathlib import Path
import sys
args = sys.argv[1:]
with Path(os.environ["PROOF_CALLS"]).open("a") as output:
    output.write(json.dumps(args) + "\n")
if "cat-file" in args:
    sys.exit(128 if args[-1] == os.environ.get("MISSING_PROOF_OBJECT") else 0)
if "diff" in args:
    paths = args[args.index("--") + 1:]
    # A missing pathspec produces an empty successful comparison in Git. The
    # double reproduces that failure mode unless the old paths are requested.
    historical = all(path.startswith(("Sources/OpalFusion/", "Tests/OpalFusionTests/")) for path in paths)
    sys.exit(1 if historical and os.environ.get("CHANGED_PROOF_FILE") else 0)
sys.exit(2)
""")
        git.chmod(0o755)
        self.calls = self.root / "calls.jsonl"
        self.env = dict(os.environ, PATH=str(binary) + os.pathsep + os.defpath,
                        PROOF_CALLS=str(self.calls))

    def invoke(self, **overrides):
        self.calls.write_text("")
        result = subprocess.run(["sh", str(self.root / "scripts/check-mosaic-g4-parser-root-registry.sh")],
                                env=dict(self.env, **overrides), text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        return result, calls

    def test_missing_historical_evidence_cannot_advertise_parity(self):
        for revision in PROOF_REVISIONS:
            for path in HISTORICAL_PATHS:
                with self.subTest(revision=revision, path=path):
                    result, calls = self.invoke(MISSING_PROOF_OBJECT=revision + ":" + path)
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertNotIn("passing G2 parity retained", result.stdout)
                    self.assertFalse(any("diff" in call for call in calls))

    def test_changed_historical_sources_cannot_pass_a_vacuous_pathspec(self):
        result, calls = self.invoke(CHANGED_PROOF_FILE="1")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("passing G2 parity retained", result.stdout)
        diffs = [call for call in calls if "diff" in call]
        self.assertEqual(len(diffs), 1)
        self.assertEqual(diffs[0][diffs[0].index("--") + 1:], list(HISTORICAL_PATHS))

    def test_each_required_file_exists_in_both_proof_revisions_before_comparison(self):
        result, calls = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout)
        proofs = [call[-1] for call in calls if "cat-file" in call]
        self.assertEqual(proofs, [revision + ":" + path for revision in PROOF_REVISIONS for path in HISTORICAL_PATHS])
        self.assertEqual(len(calls), 9)
        self.assertIn("passing G2 parity retained", result.stdout)

    def test_jsondecoder_scan_preserves_registered_file_membership(self):
        registry = self.root / "docs/mosaic-g4-parser-implementation-files-2026-08-23.txt"
        path = self.root / registry.read_text().splitlines()[0]
        path.write_text(path.read_text().replace("CanonicalDecoder.decode", "JSONDecoder().decode"))
        result, _ = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_decoder_and_composite_drift_fail_before_historical_checks(self):
        source = self.root / "Sources/MosaicEngine/Mosaic/Unexpected.swift"
        for content in ("CanonicalDecoder.decode\n", "JSONDecoder().decode\n"):
            with self.subTest(content=content):
                source.write_text(content)
                result, calls = self.invoke()
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(calls, [])
        source.unlink()
        composite = self.root / HISTORICAL_PATHS[0].replace("Sources/OpalFusion/", "Sources/MosaicEngine/")
        with composite.open("a") as stream:
            stream.write("public static func openTransportBootstrapUnexpected() {}\n")
        result, calls = self.invoke()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
