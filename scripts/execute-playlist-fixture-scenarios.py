#!/usr/bin/env python3
"""Execute fixture-index merge contracts through probe-playlist-merge."""

import argparse
import importlib.util
import hashlib
import json
import pathlib
import subprocess
import tempfile
from collections import Counter


def load_validator(script_dir):
    spec = importlib.util.spec_from_file_location(
        "playlist_fixture_validator", script_dir / "validate-playlist-fixtures.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def invoke(probe, left, right, mode, output=None):
    command = [str(probe.resolve()), str(left), str(right), mode]
    if output:
        command.append(str(output))
    try:
        process = subprocess.run(command, text=True, capture_output=True, timeout=60)
    except subprocess.TimeoutExpired:
        return {"status": "error", "error": "probe timed out after 60 seconds", "returnCode": 124}
    try:
        value = json.loads(process.stdout)
    except json.JSONDecodeError:
        value = {"status": "error", "error": "invalid probe JSON: " + process.stdout}
    if value.get("status") not in {"success", "conflict", "error"}:
        value = {"status": "error", "error": "unknown probe status: " + repr(value)}
    if value.get("status") in {"success", "conflict"} and process.returncode != 0:
        value = {"status": "error", "error": f"probe reported success/conflict with exit code {process.returncode}"}
    value["returnCode"] = process.returncode
    if process.stderr:
        value["stderr"] = process.stderr
    return value


def labels(snapshot):
    return [[item["item"]["Label"] for item in playlist["items"]] for playlist in snapshot["playlists"]]


ALIASES = {
    "Wurde das Universum erschaffen?": "a",
    "Gibt es Gott?": "b",
    "Hat Gott einen Namen?": "c",
    "Kann man ein Freund Gottes werden?": "x",
    "quiet-meeting-room.jpg": "photo",
    "city-road.mp4": "video",
}


def alias(label):
    return ALIASES.get(label, label)


def is_subsequence(needles, values):
    iterator = iter(values)
    return all(any(value == needle for value in iterator) for needle in needles)


def settings(snapshot):
    return [
        json.dumps({"playlist": playlist["name"], "occurrence": occurrence}, sort_keys=True)
        for playlist in snapshot["playlists"]
        for occurrence in playlist["items"]
    ]


def occurrence_settings(snapshot):
    result = []
    for playlist in snapshot["playlists"]:
        for occurrence in playlist["items"]:
            value = dict(occurrence)
            value.pop("position", None)
            result.append(json.dumps(value, sort_keys=True))
    return result


def occurrence_multiset(snapshot):
    result = Counter()
    for playlist in snapshot["playlists"]:
        for occurrence in playlist["items"]:
            value = dict(occurrence)
            value.pop("position", None)
            result[(playlist["name"], json.dumps(value, sort_keys=True))] += 1
    return result


def expected_additive_multiset(input_snapshots):
    expected = Counter()
    for snapshot in input_snapshots:
        for key, count in occurrence_multiset(snapshot).items():
            expected[key] = max(expected[key], count)
    return expected


def occurrence_sequences(snapshot):
    result = {}
    for playlist in snapshot["playlists"]:
        sequence = []
        for occurrence in playlist["items"]:
            value = dict(occurrence)
            value.pop("position", None)
            sequence.append(json.dumps(value, sort_keys=True))
        result[playlist["name"]] = sequence
    return result


def ordered_tokens(snapshot, inputs, expected):
    """Resolve occurrence names from content/settings, never duplicate labels."""
    if not any(value.startswith("video-") for value in expected.get("order", [])):
        return [alias(value) for playlist in labels(snapshot) for value in playlist]
    baseline = min(inputs, key=lambda value: sum(len(p["items"]) for p in value["playlists"]))
    names = {}
    for number, value in enumerate(occurrence_settings(baseline), 1):
        names[value] = f"video-{number}"
    return [names.get(value, "video-new") for value in occurrence_settings(snapshot)]


SUPPORTED_INVARIANTS = {
    "two-playlists", "three-playlists", "no-cross-playlist-combination",
    "common-playlist-additive", "per-occurrence-settings", "self-merge-idempotent",
    "all-occurrence-settings-preserved", "input-order-independent",
    "relationships-by-content", "media-present", "content-hash-identity",
    "two-distinct-content-hashes", "both-payloads-retained",
    "path-collision-remapped", "no-overwrite", "shared-media", "repeat-merge-idempotent",
}


def invariant_failures(snapshot, inputs, declared):
    failures = [f"unsupported declared invariant: {value}" for value in declared if value not in SUPPORTED_INVARIANTS]
    counts = {"two-playlists": 2, "three-playlists": 3}
    for key, count in counts.items():
        if key in declared and len(snapshot["playlists"]) != count:
            failures.append(f"{key}: expected {count} playlists")
    # Every success is checked by the occurrence multiset, media-byte union,
    # reverse direction and remerge checks below. These establish the declared
    # content/settings/relationship/no-overwrite/idempotency contracts.
    if "two-distinct-content-hashes" in declared and len(snapshot["mediaPayloads"]) < 2:
        failures.append("two-distinct-content-hashes: fewer than two payload hashes")
    if "shared-media" in declared:
        media = Counter(m["contentSha256"] for p in snapshot["playlists"] for item in p["items"] for m in item["independentMedia"])
        if not any(count > 1 for count in media.values()):
            failures.append("shared-media: no payload is used by multiple occurrences")
    return failures


CONFLICT_FIELDS = {
    "PlaylistItem": {"label": ("label",), "action": ("endAction",),
                     "trim": ("startTrimOffsetTicks", "endTrimOffsetTicks"),
                     "accuracy": ("accuracy",), "thumbnail": ("thumbnailFilePath",)},
    "PlaylistItemIndependentMediaMap": {"custom-duration": ("durationTicks",)},
    "PlaylistItemLocationMap": {"location-base-duration": ("baseDurationTicks",),
                                "multimedia-type": ("majorMultimediaType",)},
}


def conflict_dimension_failures(conflicts, expected):
    """Check changed fields in each serialized conflict, retaining its Key."""
    dimensions = set()
    failures = []
    seen = set()
    for conflict in conflicts:
        key = conflict.get("Key")
        if not isinstance(key, str) or not key or key in seen:
            failures.append(f"missing or duplicate conflict Key: {key!r}")
        seen.add(key)
        try:
            left = json.loads(conflict["Left"])["model"]
            right = json.loads(conflict["Right"])["model"]
            kind = left["type"]
            if kind != right["type"] or kind not in CONFLICT_FIELDS:
                raise ValueError("unrecognized or mismatched playlist model types")
            changed = {dimension for dimension, fields in CONFLICT_FIELDS[kind].items()
                       if any(left.get(field) != right.get(field) for field in fields)}
            if not changed:
                failures.append(f"conflict {key!r} has no changed supported dimension")
            dimensions.update(changed)
        except (KeyError, TypeError, ValueError) as error:
            failures.append(f"invalid serialized conflict {key!r}: {error}")
    declared = set(expected)
    # The original combined fixture calls either map's duration change duration.
    actual = set(dimensions)
    if "duration" in declared:
        durations = actual & {"custom-duration", "location-base-duration"}
        if durations:
            actual -= durations
            actual.add("duration")
    if actual != declared:
        failures.append(f"conflict dimensions differ: expected {sorted(declared)}, got {sorted(actual)}")
    return failures


def expected_error_failures(got, expected):
    substring = expected.get("errorSubstring")
    if not isinstance(substring, str) or not substring:
        return ["error contract must declare a nonempty errorSubstring"]
    if got.get("status") != "error" or substring not in got.get("error", ""):
        return [f"expected error containing {substring!r}, got {got}"]
    return []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixtures", type=pathlib.Path)
    parser.add_argument("--probe", required=True, type=pathlib.Path)
    parser.add_argument("--report", type=pathlib.Path)
    args = parser.parse_args()
    args.probe = args.probe.resolve()
    root = args.fixtures.resolve()
    validator = load_validator(pathlib.Path(__file__).resolve().parent)
    index = json.loads((root / "fixture-index.json").read_text())
    results = []
    with tempfile.TemporaryDirectory(prefix="playlist-scenario-execution-") as tmp:
        tmp = pathlib.Path(tmp)
        directions = []
        for original in index["scenarios"]:
            directions.append(dict(original, direction="forward"))
            if len(original["inputs"]) == 2:
                directions.append(dict(original, inputs=list(reversed(original["inputs"])), direction="reverse"))
        forward_semantics = {}
        for scenario in directions:
            expected = scenario["expected"]
            inputs = [root / path for path in scenario["inputs"]]
            input_snapshots = [validator.inspect_archive(path) for path in inputs]
            failures = [error for snapshot in input_snapshots for error in snapshot["errors"]]
            failures.extend(f"unsupported declared invariant: {value}" for value in expected.get("invariants", []) if value not in SUPPORTED_INVARIANTS)
            left, right = (inputs[0], inputs[1]) if len(inputs) == 2 else (inputs[0], inputs[0])
            output = tmp / (scenario["id"] + "-" + scenario["direction"] + ".jwlibrary")
            got = invoke(args.probe, left, right, "detect", output)
            if got.get("status") in ("success", "conflict") and got["returnCode"] != 0:
                failures.append(f"probe status {got['status']} used exit code {got['returnCode']}")
            if got.get("status") == "error" and got["returnCode"] == 0:
                failures.append("probe error used successful exit code")
            status = expected["status"]
            if status == "success":
                if got["status"] != "success":
                    failures.append(f"expected success, got {got['status']}: {got.get('error', '')}")
                elif not output.exists():
                    failures.append("successful merge did not export an archive")
                else:
                    snapshot = validator.inspect_archive(output)
                    failures.extend(snapshot["errors"])
                    reference = expected.get("reference")
                    if reference:
                        reference_snapshot = validator.inspect_archive(root / reference)
                        failures.extend(reference_snapshot["errors"])
                        if validator.semantic(snapshot) != validator.semantic(reference_snapshot):
                            failures.append("merged semantic content differs from expected reference")
                    if len(inputs) == 1:
                        if validator.semantic(snapshot) != validator.semantic(input_snapshots[0]):
                            failures.append("self-merge changed semantic content")
                    elif not reference:
                        want_occurrences = expected_additive_multiset(input_snapshots)
                        got_occurrences = occurrence_multiset(snapshot)
                        if got_occurrences != want_occurrences:
                            failures.append(
                                f"additive occurrence multiset differs: expected {sum(want_occurrences.values())}, got {sum(got_occurrences.values())}"
                            )
                        output_sequences = occurrence_sequences(snapshot)
                        for source in input_snapshots:
                            for playlist, sequence in occurrence_sequences(source).items():
                                if not is_subsequence(sequence, output_sequences.get(playlist, [])):
                                    failures.append(f"input occurrence order absent from output playlist {playlist}")
                        want_media = sorted({value for source in input_snapshots for value in source["mediaPayloads"]})
                        if snapshot["mediaPayloads"] != want_media:
                            failures.append("merged media payload hashes differ from input union")
                    if "playlists" in expected:
                        actual = {p["name"]: [alias(i["item"]["Label"]) for i in p["items"]] for p in snapshot["playlists"]}
                        if actual != expected["playlists"]:
                            failures.append(f"playlist content differs: {actual}")
                    flattened = ordered_tokens(snapshot, input_snapshots, expected)
                    if "order" in expected and flattened != expected["order"]:
                        failures.append(f"order differs: {flattened}")
                    for partial in expected.get("partialOrders", []):
                        if not is_subsequence(partial, flattened):
                            failures.append(f"partial order absent: {partial} in {flattened}")
                    failures.extend(invariant_failures(snapshot, input_snapshots, expected.get("invariants", [])))
                    if scenario["direction"] == "forward":
                        forward_semantics[scenario["id"]] = validator.semantic(snapshot)
                    elif "input-order-independent" in expected.get("invariants", []) and validator.semantic(snapshot) != forward_semantics.get(scenario["id"]):
                        failures.append("reversed inputs changed semantic content")
                    if got["status"] == "success":
                        again = tmp / f"{scenario['id']}-{scenario['direction']}-again.jwlibrary"
                        repeat = invoke(args.probe, output, inputs[0], "detect", again)
                        if repeat["status"] != "success":
                            failures.append(f"repeat merge failed: {repeat}")
                        else:
                            again_snapshot = validator.inspect_archive(again)
                            failures.extend(again_snapshot["errors"])
                            if validator.semantic(snapshot) != validator.semantic(again_snapshot):
                                failures.append("repeat merge changed semantic content")
            elif status in ("unsupported", "rejection"):
                failures.extend(expected_error_failures(got, expected))
            elif status == "known-failure":
                if got["status"] == "success" and output.exists():
                    snapshot = validator.inspect_archive(output)
                    failures.extend(snapshot["errors"])
                    desired_occurrences = expected_additive_multiset(input_snapshots)
                    if occurrence_multiset(snapshot) != desired_occurrences:
                        failures.append("known failure changed but still loses or duplicates occurrences")
                    output_sequences = occurrence_sequences(snapshot)
                    for input_snapshot in input_snapshots:
                        for playlist, sequence in occurrence_sequences(input_snapshot).items():
                            if not is_subsequence(sequence, output_sequences.get(playlist, [])):
                                failures.append(f"known failure changed but violates input order in {playlist}")
                    desired_media = sorted({value for source in input_snapshots for value in source["mediaPayloads"]})
                    if snapshot["mediaPayloads"] != desired_media:
                        failures.append("known failure changed but does not retain the media-byte union")
                else:
                    failures.append("known semantic failure: desired successful insertion is not implemented")
            elif got["status"] != "conflict" or not got.get("conflicts"):
                failures.append(f"expected typed playlist conflict, got {got}")

            if status == "conflict" and got["status"] == "conflict":
                conflicts = got.get("conflicts", [])
                initial = got.get("initialConflicts", [])
                if not initial or any(conflict not in conflicts for conflict in initial):
                    failures.append("initial conflict phase is missing from the aggregate conflict ledger")
                failures.extend(conflict_dimension_failures(conflicts, expected.get("dimensions", [])))

            resolutions = {}
            if status in ("conflict", "known-failure") and got["status"] == "conflict":
                for side in ("left", "right"):
                    resolved_path = tmp / f"{scenario['id']}-{scenario['direction']}-{side}.jwlibrary"
                    resolved = invoke(args.probe, left, right, side, resolved_path)
                    if resolved["status"] != "success":
                        failures.append(f"{side} resolution failed: {resolved}")
                        continue
                    resolved_snapshot = validator.inspect_archive(resolved_path)
                    failures.extend(resolved_snapshot["errors"])
                    resolutions[side] = {
                        "settings": settings(resolved_snapshot),
                        "occurrenceSettings": occurrence_settings(resolved_snapshot),
                        "labels": labels(resolved_snapshot),
                    }
                if scenario["id"].startswith("settings-conflict"):
                    left_snapshot = validator.inspect_archive(tmp / f"{scenario['id']}-{scenario['direction']}-left.jwlibrary") if "left" in resolutions else None
                    right_snapshot = validator.inspect_archive(tmp / f"{scenario['id']}-{scenario['direction']}-right.jwlibrary") if "right" in resolutions else None
                    if left_snapshot is None or validator.semantic(left_snapshot) != validator.semantic(input_snapshots[0]):
                        failures.append("chooseLeft did not preserve all left setting fields")
                    if right_snapshot is None or validator.semantic(right_snapshot) != validator.semantic(input_snapshots[1]):
                        failures.append("chooseRight did not preserve all right setting fields")
                if scenario["id"] == "duplicate-occurrences":
                    desired = set(occurrence_settings(input_snapshots[0])) | set(occurrence_settings(input_snapshots[1]))
                    left_values = resolutions.get("left", {}).get("occurrenceSettings", [])
                    right_values = resolutions.get("right", {}).get("occurrenceSettings", [])
                    if len(left_values) != len(set(left_values)) or set(left_values) != desired:
                        failures.append("known semantic failure: chooseLeft duplicates settings and loses the inserted occurrence")
                    if len(right_values) != len(set(right_values)) or set(right_values) != desired:
                        failures.append("chooseRight did not preserve all intentional occurrences")
            results.append(
                {"id": scenario["id"], "direction": scenario["direction"], "expected": status, "probe": got, "resolutions": resolutions, "passed": not failures, "failures": failures}
            )
    report = {"provenance": {"fixtureIndexSha256": hashlib.sha256((root / "fixture-index.json").read_bytes()).hexdigest(), "probeSha256": hashlib.sha256(args.probe.read_bytes()).hexdigest(), "harnessSha256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(), "validatorSha256": hashlib.sha256((pathlib.Path(__file__).parent / "validate-playlist-fixtures.py").read_bytes()).hexdigest()}, "contractCount": len(index["scenarios"]), "allPassed": all(item["passed"] for item in results), "scenarioCount": len(results), "results": results}
    text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.report:
        args.report.write_text(text)
    print(text, end="")
    return 0 if report["allPassed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
