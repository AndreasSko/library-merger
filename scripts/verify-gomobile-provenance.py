#!/usr/bin/env python3
"""Verify checked-in framework digests and its immutable Go source/tool pin."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess


def git_output(source, *arguments):
    return subprocess.check_output(["git", "-c", "core.fsmonitor=false", "-C", str(source), *arguments], timeout=30)


def tracked_source_paths(source):
    tracked = {path.decode() for path in git_output(source, "ls-files", "-z").split(b"\0") if path}
    required = {"go.mod", "go.sum", "model/data/userData.db"}
    if not required <= tracked:
        raise SystemExit("Go module files and schema asset must be tracked")
    return {name for name in tracked if name.endswith(".go")} | required


def source_fingerprint(source):
    fingerprint = hashlib.sha256()
    for name in sorted(tracked_source_paths(source)):
        fingerprint.update(name.encode() + b"\0" + (source / name).read_bytes() + b"\0")
    return fingerprint.hexdigest()


def verify_source_clean(source):
    if git_output(source, "diff", "HEAD", "--"):
        raise SystemExit("Go checkout has tracked source modifications")
    untracked = [path.decode() for path in git_output(source, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0") if path]
    if any(path.endswith(".go") for path in untracked):
        raise SystemExit("Go checkout contains untracked Go source")
    # Ignored diagnostics outside tracked packages cannot enter a clean module's
    # compiled source. Extra files inside a package can, despite Git ignoring
    # them; vendor can also replace pinned module dependencies during a build.
    package_dirs = {pathlib.PurePosixPath(name).parent for name in tracked_source_paths(source) if name.endswith(".go")}
    ignored = [path.decode() for path in git_output(source, "ls-files", "--others", "--ignored", "--exclude-standard", "-z").split(b"\0") if path]
    for name in ignored:
        path = pathlib.PurePosixPath(name)
        if name.endswith(".go") and (path.parent in package_dirs or path.parts[0] == "vendor"):
            raise SystemExit("Go checkout contains ignored package source: " + name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--go-source", type=pathlib.Path)
    parser.add_argument("--print-source", action="store_true")
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    provenance = json.loads((root / "Gomobile.source.json").read_text())
    commit = provenance["sourceCommit"]
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise SystemExit("sourceCommit must be an immutable full Git SHA")
    if args.print_source:
        print(commit)
        return
    if provenance["module"] != "github.com/AndreasSko/go-library-merger":
        raise SystemExit("Unexpected Go source module")
    files = provenance["files"]
    actual_files = {path.relative_to(root).as_posix() for path in (root / "Gomobile.xcframework").rglob("*") if path.is_file()}
    if set(files) != actual_files:
        raise SystemExit("Provenance must inventory every framework file exactly once")
    for name, digest in files.items():
        if not name.startswith("Gomobile.xcframework/") or ".." in pathlib.PurePosixPath(name).parts:
            raise SystemExit("Unsafe framework inventory path")
        if hashlib.sha256((root / name).read_bytes()).hexdigest() != digest:
            raise SystemExit("Framework hash differs from provenance: " + name)
    if args.go_source:
        actual = subprocess.check_output(["git", "-c", "core.fsmonitor=false", "-C", str(args.go_source), "rev-parse", "HEAD"], text=True).strip()
        if actual != commit:
            raise SystemExit("Go checkout differs from sourceCommit")
        verify_source_clean(args.go_source)
        if source_fingerprint(args.go_source) != provenance["sourceFingerprintSha256"]:
            raise SystemExit("Go source fingerprint differs from framework provenance")
        module = (args.go_source / "go.mod").read_text()
        if not re.search(r"golang.org/x/mobile\s+" + re.escape(provenance["gomobileVersion"]) + r"(?:\s|$)", module):
            raise SystemExit("Gomobile tool pin differs from Go source module")
    print(f"Verified {len(files)} framework files from {commit}")


if __name__ == "__main__":
    main()
