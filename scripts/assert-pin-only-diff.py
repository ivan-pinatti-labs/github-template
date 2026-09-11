#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Ivan Pinatti
"""Refuse a unified diff that changes anything but a dependency pin.

Read a diff on stdin (`gh pr diff <n> | scripts/assert-pin-only-diff.py`) and
exit non-zero unless every changed file is one of the pin surfaces below and
every changed line differs from its counterpart in nothing but a version.

Ported from ivan-pinatti-labs/rsync-crypt's script of the same name, itself
ported from docker-torrent-box-with-vpn's script, which is the check that
stands between "renovate[bot] or dependabot[bot] opened a pull request" and
an unattended merge. It exists here for the same reason: approving a bot's
pull request on the strength of its author means the bot identity holds
write access to main, and a diff that is not actually pin-only is exactly
the shape a compromised or misconfigured bot would take. A path allowlist
alone would not be much of a fence, since `.github/workflows/` and
`.pre-commit-config.yaml` are executable surfaces on their own; the line
comparison below is what makes it one.

The comparison normalizes both sides and requires them to match line for
line per file, duplicates counted. A line whose structure changed has no
counterpart and the diff is refused, which covers
`uses: actions/checkout@v7` becoming `uses: evil/checkout@v7` as much as it
covers an added `curl | sh`. Anything this refuses is not broken, it just
waits for a person: the approval is skipped and the pull request sits there,
which is the direction to fail in.

What it deliberately does not catch: a bump to a version that exists but is
malicious. `pre-commit 4.5.1` becoming `pre-commit 4.6.2` is the change this
file exists to permit, and no amount of diff reading can tell a good release
from a backdoored one. Renovate's minimumReleaseAge window in
.github/renovate.json5 is the actual defence against that; see
docs/MERGE_PIPELINE.md.

This repository has no Makefile, no Dockerfile, and no .env.example, unlike
docker-torrent-box-with-vpn and rsync-crypt, so it also has no
ALPINE_VERSION-shaped annotated pin and no custom regex manager to anchor
one against. ALLOWED_PATHS below is three surfaces, not rsync-crypt's four,
and normalize() carries no .env.example branch at all.
"""

import re
import sys
from collections import Counter

# The pin surfaces a dependency bot actually touches in this repository.
# Dependabot manages `.github/workflows/` (Action SHAs) and
# `.pre-commit-config.yaml` (the pre-commit-checklists `rev:` pin), see
# .github/dependabot.yml. Renovate manages `.tool-versions` (the asdf
# manager: pre-commit, github-cli), see .github/renovate.json5. Neither bot
# touches anything else in this repository: there is no requirements.txt, no
# Makefile, and no .env.example for either to have opinions about.
ALLOWED_PATHS = (
    ".tool-versions",
    ".pre-commit-config.yaml",
    ".github/workflows/",
)

# A released version, always starting with a digit (an optional single
# leading `v` aside): `2.2.2`, `v2.2.2`, `4.6.2`. Anchors both `rev:` in
# `.pre-commit-config.yaml` and every value in `.tool-versions`, and is
# deliberately narrower than "any tag-shaped token": a floating ref like
# `main` or `latest` is made entirely of characters this would otherwise
# accept, and normalizing it the same as a real release would let a
# compromised bot trade an immutable pin for something that can move under
# it after the diff is already merged, with nothing left in the diff to
# catch it.
RELEASE = r"v?[0-9][0-9A-Za-z.+_-]*"

# `.tool-versions` writes `<tool> <version>`, one per line, with nothing to
# anchor on but the space. That cannot go in the prefix set below, because a
# lookbehind of variable width is not allowed and "the word after a space"
# would match most of a workflow file. It is matched whole-line instead, and
# only for that file, which is why normalize() takes the path. The value
# after the space has to be a real release, not merely non-blank:
# `pre-commit main` would otherwise normalize identically to
# `pre-commit 4.5.1`.
TOOL_VERSION_LINE = re.compile(
    r"^(?P<prefix>[A-Za-z0-9_.-]+[ \t]+)" + RELEASE + r"[ \t]*$"
)

# A pre-commit hook `rev:`. The prefix is captured and put back, so that a
# pin changing shape rather than value still reads as a difference.
#
# GitHub Actions pins are handled separately below rather than through this
# same released-version grammar: this repository pins every action to a
# full commit SHA rather than a tag (see any `uses:` line in
# .github/workflows/), so the immutable shape to require there is a SHA,
# not a release number.
REV_PIN = re.compile(r"(?P<prefix>\brev:[ \t]+)" + RELEASE)

# A GitHub Actions pin, always a full 40 character commit SHA in this
# repository (Dependabot updates it that way), optionally followed by a
# trailing release comment (`# v7`, `# v7.0.1`), which Dependabot rewrites
# on the same bump whenever the tag it resolves the SHA from changes. Both
# have to normalize together: an earlier version of this script normalized
# only the SHA and left the comment as ordinary text, so an ordinary bump
# that also moved `# v7` to `# v7.0.1` read as a structural change and
# `Pin Only` refused it. The comment is folded into the same placeholder
# only when it is actually a release token; anything else after the SHA is
# left alone, so a change to unrelated trailing text is still caught as
# structural. The negative lookahead after the hex run stops a 40 character
# prefix of a longer hex run from matching and silently swallowing the
# character that would have made the shapes differ.
#
# Case-insensitive (`[0-9a-fA-F]`, not `[0-9a-f]`): GitHub resolves a
# `uses:` SHA the same way regardless of case, so an uppercase or
# mixed-case SHA is just as real a pin as a lowercase one, and matching
# only lowercase left a gap a CodeRabbit review of BARE_ACTION_VERSION
# below found: an uppercase SHA on a first-time pin's new side fell
# through ACTION_SHA entirely and was accepted by BARE_ACTION_VERSION's
# generic RELEASE grammar instead, which does not check that a
# first-time pin's target is SHA-shaped at all.
ACTION_SHA = re.compile(
    r"(?P<prefix>@)[0-9a-fA-F]{40}(?![0-9a-fA-F])"
    r"(?P<comment>[ \t]+#[ \t]*" + RELEASE + r")?"
)


def _normalize_action_pin(match: re.Match[str]) -> str:
    """Collapse a `@<sha>` pin and its optional trailing release comment."""
    normalized = f"{match.group('prefix')}<version>"
    if match.group("comment"):
        normalized += " # <version>"
    return normalized


# A first-time `pinDigests` bump changes `uses: actions/checkout@v7` to
# `uses: actions/checkout@<sha> # v7` in one step: there is no prior SHA to
# compare against, and the trailing release comment appears for the first
# time alongside it. ACTION_SHA above normalizes the pinned side to
# `@<version> # <version>` whenever a comment trails the SHA, which every
# first-time pin does in practice (proven on docker-torrent-box-with-vpn's
# own PR #178: Renovate never adds a bare SHA with no comment on this update
# type). This pattern gives the unpinned side the identical placeholder, so
# the two sides of a first-time pin compare equal the same way an ordinary
# SHA-to-SHA bump does. A first-time pin whose comment is missing still
# reads as structural and gets refused, which is the correct, fail-closed
# outcome for a shape that never happens on a clean bump.
#
# Scoped to a `uses:` field and an owner/repo coordinate immediately before
# the `@`, not bare `@RELEASE` anywhere on the line: a CodeRabbit review of
# docker-torrent-box-with-vpn's own version of this pattern found that an
# unscoped version would let a `run:` step's own `tool@v7` normalize the
# same way, so that line could grow an unrelated-looking SHA and comment
# and still read as pin-only.
#
# `uses:` alone is not narrow enough either: a follow-up CodeRabbit finding
# on this exact pattern, on rsync-crypt's and pre-commit-checklists' own
# copies of it, showed `\buses:` is a word-boundary check, not a position
# check, so it matches the substring "uses:" anywhere a line contains it,
# including inside a `run:` step's own text
# (`run: uses: actions/checkout@v7` normalized the same way a real `uses:`
# line did). Anchored to the start of the line instead, with only an
# optional YAML list marker (`- `) and indentation in front of `uses:`,
# which is the only place a real `uses:` field can sit.
#
# Applying ACTION_SHA first, ahead of this one, is what keeps the two from
# double matching an already-pinned line with no comment: RELEASE's
# character class is wide enough to also accept a 40 character hex run, but
# ACTION_SHA has already replaced that run with `<version>` by the time
# this pattern runs, and `<version>` does not start with a digit or a bare
# `v`.
#
# The version is its own capture group, `bare_version`, rather than folded
# unnamed into the match, because a third CodeRabbit-class finding (found
# by extending their own test on rsync-crypt's and pre-commit-checklists'
# copies of this pattern, not reported directly here) showed RELEASE alone
# is still too permissive: `_normalize_bare_action_version` below refuses a
# 40 character match outright, real hex or not, because 40 characters is
# the shape ACTION_SHA exists to own exclusively. Without that check, a
# non-hex 40 character token, `0` followed by 39 `z`s for instance, never
# matches ACTION_SHA (not hex) and was accepted here instead, since
# nothing about this pattern's own grammar checked that the "version"
# replacing a first-time pin's bare tag was ever a real SHA at all, only
# that it was RELEASE-shaped. A real first-time pin's target is always
# exactly a 40 character SHA, ACTION_SHA's exclusive domain, so anything
# that length reaching this pattern instead is already suspect, and
# refusing it outright costs nothing: a length that long never occurs in a
# genuine bare release tag either.
BARE_ACTION_VERSION = re.compile(
    r"(?P<action_prefix>^(?:[ \t]*-[ \t]+)?[ \t]*uses:[ \t]+[\w.-]+/[\w./-]+)@"
    r"(?P<bare_version>" + RELEASE + r")$"
)


def _normalize_bare_action_version(match: re.Match[str]) -> str:
    if len(match.group("bare_version")) == 40:
        return match.group(0)
    return f"{match.group('action_prefix')}@<version> # <version>"


FILE_HEADER = re.compile(r"^diff --git a/(?P<old>.+) b/(?P<new>.+)$")


def normalize(line: str, path: str = "") -> str:
    """Reduce a line to everything about it that a version bump may not change."""
    if path.endswith(".tool-versions"):
        return TOOL_VERSION_LINE.sub(r"\g<prefix><version>", line)
    line = ACTION_SHA.sub(_normalize_action_pin, line)
    line = BARE_ACTION_VERSION.sub(_normalize_bare_action_version, line)
    line = REV_PIN.sub(r"\g<prefix><version>", line)
    return line


def parse(diff: str) -> tuple[dict[str, tuple[Counter, Counter]], list[str]]:
    """Group removed and added lines by file, and collect structural changes."""
    changes: dict[str, tuple[Counter, Counter]] = {}
    structural: list[str] = []
    path = None
    in_hunk = False

    for line in diff.splitlines():
        header = FILE_HEADER.match(line)
        if header:
            old, new = header.group("old"), header.group("new")
            path = new
            in_hunk = False
            changes.setdefault(path, (Counter(), Counter()))
            if old != new:
                structural.append(f"{old} renamed to {new}")
            continue

        if line.startswith("@@"):
            in_hunk = True
            continue

        # Everything between a file header and its first hunk is preamble:
        # the index line, the ---/+++ pair, and any mode line. Recognizing
        # those only here is what stops a content line impersonating one.
        # Inside a hunk, `+++foo` is an added line reading `++foo`, and
        # skipping it as a file header would drop it from the comparison,
        # which fails open.
        if not in_hunk:
            if line.startswith(
                ("new file ", "deleted file ", "old mode ", "new mode ")
            ):
                structural.append(f"{path}: {line.strip()}")
            continue

        if path is None:
            continue

        if line.startswith("-"):
            changes[path][0][normalize(line[1:], path)] += 1
        elif line.startswith("+"):
            changes[path][1][normalize(line[1:], path)] += 1

    return changes, structural


def main() -> int:
    diff = sys.stdin.read()
    if not diff.strip():
        print("REFUSED: the diff is empty, so there is nothing to approve.")
        return 1

    changes, problems = parse(diff)

    # Output that parsed into nothing is not a clean bill of health.
    # Truncated output, a binary diff, or anything that arrives without a
    # `diff --git` header would otherwise leave the change set empty and
    # read as "no problems found", approving a diff nobody managed to read.
    if not changes:
        print("REFUSED: no file headers in the diff, so nothing could be checked.")
        return 1

    for path in changes:
        if not path.startswith(ALLOWED_PATHS):
            problems.append(f"{path}: not a dependency pin file")

    for path, (removed, added) in changes.items():
        if not removed and not added:
            problems.append(
                f"{path}: no readable changed lines, so nothing was checked"
            )

    for path, (removed, added) in changes.items():
        # Counter subtraction drops non-positive counts, so each direction
        # has to be asked separately to see both halves of a mismatch.
        for line in removed - added:
            problems.append(f"{path}: removed a line that was not re-added: -{line}")
        for line in added - removed:
            problems.append(
                f"{path}: added a line that was not a version bump: +{line}"
            )

    if problems:
        print("REFUSED: this diff changes more than dependency pins.")
        for problem in problems:
            print(f"  {problem}")
        print(
            "\nNothing is broken. The automated approval is skipped and the pull "
            "request waits for a person, which is what should happen when a "
            "dependency bot reaches outside its lane."
        )
        return 1

    files = ", ".join(sorted(changes)) or "nothing"
    print(f"Pin-only diff confirmed: {files}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
