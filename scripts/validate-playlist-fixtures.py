#!/usr/bin/env python3
"""Audit every playlist fixture archive and its semantic playlist content.

The semantic projection deliberately excludes SQLite identifiers and archive
paths. Repeated playlist entries remain separate ordered occurrences.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sqlite3
import subprocess
import tempfile
import zipfile


MARKER_TABLES = (
    "PlaylistItemMarker",
    "PlaylistItemMarkerBibleVerseMap",
    "PlaylistItemMarkerParagraphMap",
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _rows(db: sqlite3.Connection, query: str, values=()):
    return [dict(row) for row in db.execute(query, values)]


def inspect_archive(path: pathlib.Path) -> dict:
    errors: list[str] = []
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        duplicates = sorted({name for name in names if names.count(name) > 1})
        if duplicates:
            errors.append(f"duplicate zip entries: {duplicates}")
        for required in ("manifest.json", "userData.db"):
            if required not in names:
                raise AssertionError(f"{path}: missing {required}")
        blobs = {name: archive.read(name) for name in names}
        manifest = json.loads(blobs["manifest.json"])
        if manifest.get("version") != 1:
            errors.append(f"unsupported manifest version {manifest.get('version')}")
        if manifest["userDataBackup"].get("databaseName") != "userData.db":
            errors.append("unsupported backup databaseName")
        schema = manifest["userDataBackup"]["schemaVersion"]
        if schema != 16:
            errors.append(f"unsupported schemaVersion {schema}; expected 16")
        expected_hash = manifest["userDataBackup"]["hash"].lower()
        actual_hash = sha256(blobs["userData.db"])
        if expected_hash != actual_hash:
            errors.append(f"manifest database hash {expected_hash} != {actual_hash}")

        with tempfile.TemporaryDirectory(prefix="playlist-fixture-audit-") as tmp:
            db_path = pathlib.Path(tmp) / "userData.db"
            db_path.write_bytes(blobs["userData.db"])
            db = sqlite3.connect(db_path)
            db.row_factory = sqlite3.Row
            integrity = db.execute("pragma integrity_check").fetchone()[0]
            if integrity != "ok":
                errors.append(f"SQLite integrity_check: {integrity}")
            foreign_keys = _rows(db, "pragma foreign_key_check")
            if foreign_keys:
                errors.append(f"foreign key violations: {foreign_keys}")

            media: dict[int, dict] = {}
            for row in _rows(db, "select * from IndependentMedia order by IndependentMediaId"):
                media_id = row.pop("IndependentMediaId")
                archive_path = row.pop("FilePath")
                if archive_path not in blobs:
                    errors.append(f"missing media payload {archive_path}")
                    content_hash = None
                else:
                    content_hash = sha256(blobs[archive_path])
                    recorded = row["Hash"].lower()
                    unpadded = "".join(format(byte, "x") for byte in bytes.fromhex(content_hash))
                    if recorded not in (content_hash, unpadded):
                        errors.append(
                            f"IndependentMedia {media_id} hash {recorded} != {content_hash}"
                        )
                media[media_id] = {
                    "contentSha256": content_hash,
                    "mimeType": row["MimeType"],
                    "originalFilename": row["OriginalFilename"],
                }

            playlists = []
            mapped_item_ids: set[int] = set()
            playlist_rows = _rows(db, "select TagId,Name from Tag where Type=2 order by Name")
            for playlist in playlist_rows:
                tag_id = playlist["TagId"]
                mappings = _rows(
                    db,
                    "select Position,PlaylistItemId from TagMap "
                    "where TagId=? and PlaylistItemId is not null order by Position,TagMapId",
                    (tag_id,),
                )
                positions = [row["Position"] for row in mappings]
                if positions != list(range(len(mappings))):
                    errors.append(f"playlist {playlist['Name']!r} positions are {positions}")
                occurrences = []
                for mapping in mappings:
                    item_id = mapping["PlaylistItemId"]
                    mapped_item_ids.add(item_id)
                    item = _rows(db, "select * from PlaylistItem where PlaylistItemId=?", (item_id,))
                    if len(item) != 1:
                        errors.append(f"playlist item {item_id} has {len(item)} rows")
                        continue
                    item = item[0]
                    item.pop("PlaylistItemId")
                    thumbnail = item.pop("ThumbnailFilePath")
                    if thumbnail is not None and thumbnail not in blobs:
                        errors.append(f"missing thumbnail payload {thumbnail}")
                    item["thumbnailSha256"] = sha256(blobs[thumbnail]) if thumbnail in blobs else None

                    independent = []
                    for link in _rows(
                        db,
                        "select IndependentMediaId,DurationTicks from "
                        "PlaylistItemIndependentMediaMap where PlaylistItemId=? "
                        "order by IndependentMediaId",
                        (item_id,),
                    ):
                        linked = media.get(link["IndependentMediaId"])
                        if linked is None:
                            errors.append(f"playlist item {item_id} references absent media")
                            continue
                        independent.append({"durationTicks": link["DurationTicks"], **linked})
                    locations = _rows(
                        db,
                        "select l.*,m.MajorMultimediaType,m.BaseDurationTicks "
                        "from PlaylistItemLocationMap m join Location l using(LocationId) "
                        "where m.PlaylistItemId=? order by l.LocationId",
                        (item_id,),
                    )
                    for location in locations:
                        location.pop("LocationId")
                    if len(independent) + len(locations) != 1:
                        errors.append(
                            f"playlist item {item_id} has {len(independent)} media and "
                            f"{len(locations)} locations"
                        )

                    markers = []
                    for marker in _rows(
                        db,
                        "select * from PlaylistItemMarker where PlaylistItemId=? "
                        "order by StartTimeTicks,PlaylistItemMarkerId",
                        (item_id,),
                    ):
                        marker_id = marker.pop("PlaylistItemMarkerId")
                        marker.pop("PlaylistItemId")
                        marker["bibleVerses"] = [
                            row["VerseId"]
                            for row in _rows(
                                db,
                                "select VerseId from PlaylistItemMarkerBibleVerseMap "
                                "where PlaylistItemMarkerId=? order by VerseId",
                                (marker_id,),
                            )
                        ]
                        marker["paragraphs"] = _rows(
                            db,
                            "select MepsDocumentId,ParagraphIndex,MarkerIndexWithinParagraph "
                            "from PlaylistItemMarkerParagraphMap where PlaylistItemMarkerId=? "
                            "order by MepsDocumentId,ParagraphIndex,MarkerIndexWithinParagraph",
                            (marker_id,),
                        )
                        markers.append(marker)
                    occurrences.append(
                        {
                            "position": mapping["Position"],
                            "item": item,
                            "independentMedia": independent,
                            "locations": locations,
                            "markers": markers,
                        }
                    )
                playlists.append({"name": playlist["Name"], "items": occurrences})

            all_item_ids = {
                row["PlaylistItemId"] for row in _rows(db, "select PlaylistItemId from PlaylistItem")
            }
            orphan_items = sorted(all_item_ids - mapped_item_ids)
            if orphan_items:
                errors.append(f"playlist items without playlist membership: {orphan_items}")
            duplicate_memberships = _rows(
                db,
                "select PlaylistItemId,count(*) as Memberships from TagMap "
                "where PlaylistItemId is not null group by PlaylistItemId having count(*) != 1",
            )
            if duplicate_memberships:
                errors.append(f"playlist items with invalid membership cardinality: {duplicate_memberships}")

            marker_counts = {
                table: db.execute(f"select count(*) from {table}").fetchone()[0]
                for table in MARKER_TABLES
            }
            db.close()

    return {
        "path": str(path),
        "archiveSha256": sha256(path.read_bytes()),
        "databaseSha256": actual_hash,
        "schemaVersion": manifest["userDataBackup"]["schemaVersion"],
        "errors": errors,
        "playlists": playlists,
        "markerCounts": marker_counts,
        "mediaPayloads": sorted({
            value["contentSha256"] for value in media.values() if value["contentSha256"]
        }),
    }


def semantic(snapshot: dict) -> dict:
    """Return the ID/path-independent content used for comparisons."""
    return {
        "playlists": snapshot["playlists"],
        "markerCounts": snapshot["markerCounts"],
        "mediaPayloads": snapshot["mediaPayloads"],
    }


def validate_index(root: pathlib.Path, index: dict, snapshots: dict[str, dict]) -> list[str]:
    errors: list[str] = []
    indexed: set[str] = set()
    for fixture in index.get("fixtures", []):
        rel = fixture.get("path")
        if not rel:
            errors.append("fixture index entry is missing path")
            continue
        if rel in indexed:
            errors.append(f"duplicate fixture index path: {rel}")
        indexed.add(rel)
        if rel not in snapshots:
            errors.append(f"indexed archive is missing: {rel}")
            continue
        digest = fixture.get("sha256")
        if digest and digest.lower() != snapshots[rel]["archiveSha256"]:
            errors.append(f"fixture-index hash mismatch: {rel}")
    inventory = set(snapshots)
    missing = sorted(inventory - indexed)
    if missing:
        errors.append(f"archives absent from fixture index: {missing}")

    # A scenario may name an expected archive. Compare complete semantic state,
    # rather than labels or IDs, when a separately produced result is supplied.
    for scenario in index.get("scenarios", []):
        expected = scenario.get("expected", {})
        expected_path = expected.get("reference") or expected.get("archive") or scenario.get("expectedArchive")
        actual_path = scenario.get("actual") or scenario.get("mergedArchive")
        for input_path in scenario.get("inputs", []):
            if input_path not in snapshots:
                errors.append(f"{scenario.get('id')}: missing input archive {input_path}")
        for role, path in (("expected", expected_path), ("actual", actual_path)):
            if path and path not in snapshots:
                errors.append(f"{scenario.get('id')}: missing {role} archive {path}")
        if expected_path and actual_path and expected_path in snapshots and actual_path in snapshots:
            if semantic(snapshots[expected_path]) != semantic(snapshots[actual_path]):
                errors.append(f"{scenario.get('id')}: merged result differs from expected archive")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixtures", type=pathlib.Path, help="fixture collection root")
    parser.add_argument("--index", type=pathlib.Path, help="defaults to fixture-index.json")
    parser.add_argument("--report", type=pathlib.Path, help="write full JSON evidence")
    parser.add_argument(
        "--allow-unindexed", action="store_true", help="do not fail when an archive is unindexed"
    )
    args = parser.parse_args()
    root = args.fixtures.resolve()
    archives = sorted(root.rglob("*.jwlibrary"))
    if not archives:
        raise SystemExit(f"no .jwlibrary archives below {root}")
    snapshots = {}
    for archive in archives:
        rel = archive.relative_to(root).as_posix()
        snapshots[rel] = inspect_archive(archive)

    collection_errors = []
    index_path = args.index or root / "fixture-index.json"
    if index_path.exists():
        collection_errors = validate_index(root, json.loads(index_path.read_text()), snapshots)
        if args.allow_unindexed:
            collection_errors = [
                error for error in collection_errors if not error.startswith("archives absent from")
            ]
    else:
        collection_errors.append(f"missing fixture index: {index_path}")
    archive_failures = {
        rel: snapshot["errors"] for rel, snapshot in snapshots.items() if snapshot["errors"]
    }
    report = {
        "scope": "fixture archive structure and semantic inventory; merge execution is separate",
        "root": str(root),
        "archiveCount": len(snapshots),
        "allValid": not collection_errors and not archive_failures,
        "collectionErrors": collection_errors,
        "archiveFailures": archive_failures,
        "archives": snapshots,
    }
    output = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.report:
        args.report.write_text(output)
    print(output, end="")
    return 0 if report["allValid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
