#!/usr/bin/env python3
"""Turns Markdown into release notes. See docs/releasing.md.

    release_notes.py paragraph < pr-body.md     the PR's first paragraph
    release_notes.py plain < release-body.md    text for TestFlight and
                                                the App Store
"""
import re
import sys

COMMENT = re.compile(r"<!--.*?-->", re.S)


def paragraph(body):
    """The first prose paragraph, on one line. Headings and images don't count."""
    for block in re.split(r"\n\s*\n", COMMENT.sub("", body)):
        lines = [line.strip() for line in block.strip().splitlines()]
        while lines and lines[0].startswith("#"):
            lines.pop(0)
        if lines and not lines[0].startswith(("![", "<")):
            return " ".join(lines)
    return ""


def plain(markdown):
    """Plain text, since neither TestFlight nor the App Store renders Markdown."""
    text = COMMENT.sub("", markdown).replace("\r\n", "\n")
    lines = []
    for line in text.split("\n"):
        line = re.sub(r"\s*\(#\d+\)", "", line)
        line = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", line)
        line = re.sub(r"(\*\*|__)(.+?)\1", r"\2", line)
        line = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"\1", line)
        line = re.sub(r"`([^`]*)`", r"\1", line)
        line = re.sub(r"^#+\s*", "", line)
        line = re.sub(r"^(\s*)[-*+]\s+", r"\1• ", line)
        lines.append(line.rstrip())
    return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()


if __name__ == "__main__":
    modes = {"paragraph": paragraph, "plain": plain}
    if len(sys.argv) != 2 or sys.argv[1] not in modes:
        sys.exit(__doc__)
    print(modes[sys.argv[1]](sys.stdin.read()))
