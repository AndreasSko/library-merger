#!/usr/bin/env python3
"""Regressions for the contract oracle, independent of the merger itself."""
import importlib.util
import pathlib
import unittest
import tempfile
import subprocess
import sys
import shutil
import sqlite3
import zipfile

spec = importlib.util.spec_from_file_location("harness", pathlib.Path(__file__).with_name("execute-playlist-fixture-scenarios.py"))
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)

export_spec = importlib.util.spec_from_file_location("exports", pathlib.Path(__file__).with_name("verify-playlist-exports.py"))
exports = importlib.util.module_from_spec(export_spec)
export_spec.loader.exec_module(exports)


def snapshot(settings):
    return {"playlists": [{"name": "Portable", "items": [{"position": n, "item": {"Label": "Repeated video", "StartTrimOffsetTicks": trim}, "independentMedia": [], "locations": [], "markers": []} for n, trim in enumerate(settings)]}], "mediaPayloads": []}


class ContractOracleTests(unittest.TestCase):
    def test_order_uses_occurrence_settings_when_labels_are_identical(self):
        ancestor, inserted = snapshot([0, 10]), snapshot([0, 20, 10])
        expected = {"order": ["video-1", "video-new", "video-2"]}
        self.assertEqual(harness.ordered_tokens(inserted, [ancestor, inserted], expected), expected["order"])
        self.assertEqual(harness.ordered_tokens(inserted, [inserted, ancestor], expected), expected["order"])
        self.assertNotEqual(harness.ordered_tokens(snapshot([0, 10, 20]), [ancestor, inserted], expected), expected["order"])

    def test_multiset_detects_loss_of_identical_occurrences(self):
        expected = harness.expected_additive_multiset([snapshot([0, 0]), snapshot([0, 0, 0])])
        self.assertNotEqual(harness.occurrence_multiset(snapshot([0, 0])), expected)
        self.assertEqual(harness.occurrence_multiset(snapshot([0, 0, 0])), expected)

    def test_unknown_invariants_cannot_silently_pass(self):
        self.assertEqual(harness.invariant_failures(snapshot([0]), [], ["future-unimplemented-invariant"]), ["unsupported declared invariant: future-unimplemented-invariant"])
        self.assertTrue(harness.invariant_failures(snapshot([0]), [], ["two-playlists"]))

    def test_wrong_conflict_dimension_cannot_satisfy_label_contract(self):
        import json
        def conflict(left, right):
            return {"Key": "playlist-occurrence-0", "Left": json.dumps({"model": left}),
                    "Right": json.dumps({"model": right})}
        left = {"type": "PlaylistItem", "label": "A", "endAction": 0}
        action = conflict(left, dict(left, endAction=3))
        label = conflict(left, dict(left, label="Changed A"))
        self.assertEqual(harness.conflict_dimension_failures([label], ["label"]), [])
        self.assertTrue(harness.conflict_dimension_failures([action], ["label"]))
        self.assertTrue(harness.conflict_dimension_failures([label], ["label", "action"]))
        self.assertTrue(harness.conflict_dimension_failures([label, label], ["label"]))
        duration_left = {"type": "PlaylistItemIndependentMediaMap", "durationTicks": 10}
        duration = conflict(duration_left, dict(duration_left, durationTicks=20))
        duration["Key"] = "map-0"
        self.assertEqual(harness.conflict_dimension_failures([label, duration], ["label", "duration"]), [])

    def test_unsupported_error_matches_declared_table_and_probe_is_bounded(self):
        from unittest.mock import patch
        expected = {"errorSubstring": "table PlaylistItemMarkerBibleVerseMap"}
        self.assertTrue(harness.expected_error_failures({"status": "error", "error": "table PlaylistItemMarker"}, expected))
        self.assertEqual(harness.expected_error_failures({"status": "error", "error": "unsupported table PlaylistItemMarkerBibleVerseMap"}, expected), [])
        with patch.object(harness.subprocess, "run", side_effect=subprocess.TimeoutExpired("probe", 60)) as process:
            result = harness.invoke(pathlib.Path("probe"), pathlib.Path("left"), pathlib.Path("right"), "detect")
        self.assertEqual(result["returnCode"], 124)
        self.assertEqual(process.call_args.kwargs["timeout"], 60)
        self.assertTrue(pathlib.Path(process.call_args.args[0][0]).is_absolute())


class MandatoryExportInventoryTests(unittest.TestCase):
    def test_single_valid_export_does_not_masquerade_as_complete_suite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            fixture = pathlib.Path(__file__).resolve().parents[1] / "LibraryMergerTests/Fixtures/front.jwlibrary"
            shutil.copyfile(fixture, root / "front.jwlibrary")
            result = subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name("verify-playlist-exports.py")), str(root)], text=True, capture_output=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Export inventory mismatch", result.stderr)
            self.assertIn("repeated-aba-abaa", result.stderr)

    def test_every_mandatory_export_and_optional_original_is_accounted_for(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for name in exports.MANDATORY_EXPORTS:
                (root / (name + ".jwlibrary")).touch()
            self.assertEqual(len(exports.validate_export_inventory(root)), len(exports.MANDATORY_EXPORTS))
            with self.assertRaisesRegex(AssertionError, "scenario-1-insert-front"):
                exports.validate_export_inventory(root, require_originals=True)
            for name in exports.ORIGINAL_EXPORTS:
                (root / (name + ".jwlibrary")).touch()
            self.assertEqual(len(exports.validate_export_inventory(root, require_originals=True)), len(exports.MANDATORY_EXPORTS | exports.ORIGINAL_EXPORTS))
            with self.assertRaisesRegex(AssertionError, "unexpected"):
                exports.validate_export_inventory(root)
            (root / "typo-thumbnail.jwlibrary").touch()
            with self.assertRaisesRegex(AssertionError, "typo-thumbnail"):
                exports.validate_export_inventory(root, require_originals=True)
            (root / "typo-thumbnail.jwlibrary").unlink()
            (root / "thumbnail-auto.jwlibrary").unlink()
            with self.assertRaisesRegex(AssertionError, "thumbnail-auto"):
                exports.validate_export_inventory(root, require_originals=True)


class DeterministicFixtureGeneratorTests(unittest.TestCase):
    def test_trigger_managed_timestamp_is_fixed_before_hashing(self):
        script = pathlib.Path(__file__).with_name("build-playlist-test-fixtures.py")
        spec = importlib.util.spec_from_file_location("builder", script)
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        # Hosted CI checks out the pinned source inside the iOS workspace.
        if (builder.ROOT / "go-source").is_dir():
            builder.GO = builder.ROOT / "go-source"
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            builder.OUT = root
            builder.build("first", [("Portable", ["A", "A"])], 'UPDATE PlaylistItem SET EndAction=0', mixed_hashes=True)
            builder.build("second", [("Portable", ["A", "A"])], 'UPDATE PlaylistItem SET EndAction=0', mixed_hashes=True)
            self.assertEqual((root / "first.jwlibrary").read_bytes(), (root / "second.jwlibrary").read_bytes())
            with zipfile.ZipFile(root / "first.jwlibrary") as archive:
                database = root / "verify.db"
                database.write_bytes(archive.read("userData.db"))
            with sqlite3.connect(database) as connection:
                self.assertEqual(connection.execute("SELECT LastModified FROM LastModified").fetchone()[0], "2020-01-01T00:00:00Z")
                self.assertEqual(connection.execute("SELECT COUNT(*) FROM PlaylistItem").fetchone()[0], 2)
                self.assertEqual(connection.execute("SELECT COUNT(DISTINCT IndependentMediaId) FROM PlaylistItemIndependentMediaMap").fetchone()[0], 2)


class SourceFingerprintTests(unittest.TestCase):
    def test_ignored_diagnostic_is_excluded_but_package_source_and_tracked_mutation_fail(self):
        script = pathlib.Path(__file__).with_name("verify-gomobile-provenance.py")
        spec = importlib.util.spec_from_file_location("provenance", script)
        verifier = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(verifier)
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / "source"
            source.mkdir()
            def git(*args):
                return subprocess.run(["git", "-C", str(source), *args], check=True, capture_output=True, timeout=30)
            git("init", "--quiet")
            (source / "model/data").mkdir(parents=True)
            for name, data in {"go.mod": "module fictional.invalid/test\n", "go.sum": "",
                               "model/data/userData.db": "fictional schema", "main.go": "package main\n",
                               ".gitignore": "/outputs/\n*.local.go\n/vendor/\n"}.items():
                (source / name).write_text(data)
            git("add", ".")
            git("-c", "user.name=Fixture Test", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "Fictional source snapshot")
            clean = pathlib.Path(directory) / "clean"
            subprocess.run(["git", "clone", "--quiet", "--local", str(source), str(clean)], check=True, capture_output=True, timeout=30)
            fingerprint = verifier.source_fingerprint(clean)
            diagnostic = source / "outputs/playlist-review/mobile.go"
            diagnostic.parent.mkdir(parents=True)
            diagnostic.write_text("//go:build ignore\n\npackage main\n")
            self.assertEqual(verifier.source_fingerprint(source), fingerprint)
            verifier.verify_source_clean(source)
            extra = source / "injected.local.go"
            extra.write_text("package main\n")
            with self.assertRaisesRegex(SystemExit, "ignored package source"):
                verifier.verify_source_clean(source)
            extra.unlink()
            vendor = source / "vendor/dependency/injected.go"
            vendor.parent.mkdir(parents=True)
            vendor.write_text("package dependency\n")
            with self.assertRaisesRegex(SystemExit, "ignored package source"):
                verifier.verify_source_clean(source)
            shutil.rmtree(source / "vendor")
            (source / "main.go").write_text("package main\nfunc changed() {}\n")
            self.assertNotEqual(verifier.source_fingerprint(source), fingerprint)
            with self.assertRaisesRegex(SystemExit, "tracked source modifications"):
                verifier.verify_source_clean(source)


if __name__ == "__main__":
    unittest.main()
