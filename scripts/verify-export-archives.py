#!/usr/bin/env python3
"""Validate exported backups without requiring an external fixture index."""
import argparse
import importlib.util
import json
import pathlib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("exports", type=pathlib.Path)
    parser.add_argument("--report", type=pathlib.Path)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("validator", pathlib.Path(__file__).with_name("validate-playlist-fixtures.py"))
    validator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validator)
    archives = sorted(args.exports.rglob("*.jwlibrary"))
    if not archives:
        raise SystemExit("No exported .jwlibrary archives found")
    results = []
    for path in archives:
        try:
            snapshot = validator.inspect_archive(path)
            results.append(dict(path=str(path), passed=not snapshot["errors"], errors=snapshot["errors"], databaseSha256=snapshot["databaseSha256"]))
        except (AssertionError, KeyError, ValueError, OSError, validator.sqlite3.Error, validator.zipfile.BadZipFile) as error:
            results.append(dict(path=str(path), passed=False, errors=[str(error)]))
    report = dict(allPassed=all(result["passed"] for result in results), archiveCount=len(results), results=results)
    text = json.dumps(report, indent=2) + "\n"
    if args.report:
        args.report.write_text(text)
    print(text, end="")
    return 0 if report["allPassed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
