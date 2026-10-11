#!/usr/bin/env python3
"""Generate copyright-free, deterministic playlist contracts for mandatory CI."""
import argparse
import hashlib
import json
import pathlib
import random
import shutil
import sqlite3
import tempfile
import zipfile


def build(root, source, name, lists, change="", mixed_hashes=False):
    with tempfile.TemporaryDirectory() as tmp:
        database = pathlib.Path(tmp) / "userData.db"
        shutil.copyfile(source / "model/data/userData.db", database)
        connection = sqlite3.connect(database)
        payloads = {}
        item_id = 0
        for tag_id, (title, labels) in enumerate(lists, 1):
            connection.execute("INSERT INTO Tag VALUES (?,2,?)", (tag_id, title))
            for position, label in enumerate(labels):
                item_id += 1
                filename = label + ".bin"
                if filename not in payloads:
                    payloads[filename] = (len(payloads) + 1, ("fictional payload " + label).encode())
                    media_id, data = payloads[filename]
                    connection.execute("INSERT INTO IndependentMedia VALUES (?,?,?,?,?)", (media_id, filename, filename, "application/octet-stream", hashlib.sha256(data).hexdigest()))
                media_id, _ = payloads[filename]
                connection.execute("INSERT INTO PlaylistItem VALUES (?,?,2500000000,NULL,1,0,NULL)", (item_id, label))
                connection.execute("INSERT INTO TagMap VALUES (?,?,NULL,NULL,?,?)", (item_id, item_id, tag_id, position))
                connection.execute("INSERT INTO PlaylistItemIndependentMediaMap VALUES (?,?,5000000000)", (item_id, media_id))
        if mixed_hashes:
            data = payloads['A.bin'][1]
            filename = 'A-native.bin'
            media_id = len(payloads)+1
            payloads[filename] = (media_id, data)
            native = ''.join(format(byte, 'x') for byte in hashlib.sha256(data).digest())
            connection.execute("INSERT INTO IndependentMedia VALUES (?,?,?,?,?)", (media_id,'A.bin',filename,'application/octet-stream',native))
            connection.execute("UPDATE PlaylistItemIndependentMediaMap SET IndependentMediaId=? WHERE PlaylistItemId=2", (media_id,))
        if change:
            connection.executescript(change)
        connection.execute("UPDATE LastModified SET LastModified='2020-01-01T00:00:00Z'")
        connection.commit()
        assert connection.execute("pragma integrity_check").fetchone()[0] == "ok"
        assert not connection.execute("pragma foreign_key_check").fetchall()
        connection.close()
        # The writer-version field is informational; keep the template value
        # to avoid byte drift between local and hosted SQLite runtimes.
        blob = bytearray(database.read_bytes())
        blob[96:100] = (source / "model/data/userData.db").read_bytes()[96:100]
        database.write_bytes(blob)
        with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as check:
            assert check.execute("pragma integrity_check").fetchone()[0] == "ok"
            assert not check.execute("pragma foreign_key_check").fetchall()
        blob = bytes(blob)
        manifest = json.loads((source / "model/testdata/manifest_correct.json").read_text())
        manifest["userDataBackup"].update(hash=hashlib.sha256(blob).hexdigest(), schemaVersion=16)
        archive = root / (name + ".jwlibrary")
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_STORED) as output:
            def write(path, data):
                entry = zipfile.ZipInfo(path, date_time=(2020, 1, 1, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_STORED
                output.writestr(entry, data)
            write("userData.db", blob)
            write("manifest.json", json.dumps(manifest, sort_keys=True))
            for filename, (_, data) in sorted(payloads.items()):
                write(filename, data)
        return archive.name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--go-source", required=True, type=pathlib.Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    scenarios = []
    def pair(name, left, right, expected, change=""):
        inputs = [build(args.output, args.go_source, name + "-left", left), build(args.output, args.go_source, name + "-right", right, change)]
        scenarios.append(dict(id=name, inputs=inputs, expected=expected))
    for name, parent, child in [("front", "ABC", "XABC"), ("middle", "ABC", "ABXC"), ("tail", "ABC", "ABCX"), ("repeat-tail", "AB", "ABA"), ("repeat-front", "ABA", "AABA"), ("repeat-middle", "ABA", "ABBA")]:
        pair(name, [("Portable", list(parent))], [("Portable", list(child))], dict(status="success", order=list(child), reference=name + "-right.jwlibrary", invariants=["all-occurrence-settings-preserved", "input-order-independent", "repeat-merge-idempotent"]))
    generator = random.Random(20261011)
    for number in range(24):
        parent = [generator.choice("AB") for _ in range(generator.randint(1, 5))]
        child = parent[:]
        child.insert(generator.randrange(len(child) + 1), generator.choice("AB"))
        name = f"seeded-{number:02}"
        pair(name, [("Portable", parent)], [("Portable", child)], dict(status="success", reference=name + "-right.jwlibrary", invariants=["all-occurrence-settings-preserved", "input-order-independent"]))
    pair("separate", [("Left", ["A"])], [("Right", ["B"])], dict(status="success", invariants=["two-playlists", "no-cross-playlist-combination"]))
    pair("shared", [("Left", ["A"])], [("Right", ["A"])], dict(status="success", invariants=["two-playlists", "shared-media", "per-occurrence-settings"]))
    pair("settings-conflict-duration", [("Portable", ["A"])], [("Portable", ["A"])], dict(status="conflict", dimensions=["custom-duration"]), "UPDATE PlaylistItemIndependentMediaMap SET DurationTicks=6000000000")
    pair("settings-conflict-item", [("Portable", ["A"])], [("Portable", ["A"])], dict(status="conflict", dimensions=["label", "action", "trim"]), "UPDATE PlaylistItem SET Label='Changed', EndAction=3, StartTrimOffsetTicks=3000000000")
    mixed = build(args.output, args.go_source, "mixed-hashes", [("Portable", ["A", "A"])], mixed_hashes=True)
    scenarios.append(dict(id="mixed-hashes", inputs=[mixed], expected=dict(status="success", order=["A", "A"], invariants=["self-merge-idempotent", "per-occurrence-settings"])))
    marker = build(args.output, args.go_source, "markers", [("Portable", ["A"])], "INSERT INTO PlaylistItemMarker VALUES(1,1,'fictional',0,10,0); INSERT INTO PlaylistItemMarkerBibleVerseMap VALUES(1,1); INSERT INTO PlaylistItemMarkerParagraphMap VALUES(1,1,1,1)")
    scenarios.append(dict(id="markers", inputs=[marker], expected=dict(status="unsupported", errorSubstring="not supported yet for table PlaylistItemMarker")))
    empty = build(args.output, args.go_source, "empty-named", [("Empty", [])])
    scenarios.append(dict(id="empty-named", inputs=[empty], expected=dict(status="success", playlists={"Empty": []}, invariants=["self-merge-idempotent"])))
    index = dict(schemaVersion=2, seed=20261011, fixtures=[dict(path=p.name, sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(args.output.glob("*.jwlibrary"))], scenarios=scenarios)
    (args.output / "fixture-index.json").write_text(json.dumps(index, indent=2) + "\n")
    print(f"Generated {len(index['fixtures'])} synthetic archives / {len(scenarios)} contracts")


if __name__ == "__main__":
    main()
