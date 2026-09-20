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

This repository has no Makefile and no .env.example, unlike
docker-torrent-box-with-vpn and rsync-crypt, so it also has no
ALPINE_VERSION-shaped annotated pin and no custom regex manager to anchor
one against, and normalize() carries no .env.example branch at all. Its one
Dockerfile is .devcontainer/Dockerfile, whose base image Renovate pins by
digest; IMAGE_DIGEST below is what grades a bump to it, so ALLOWED_PATHS is
four surfaces.
"""

import hashlib
import re
import sys
from collections import Counter
from pathlib import Path

# The checkout this script runs from. coderabbit-gate.yml checks out the
# default branch, never the pull request's head, so a file read from here is
# the base side as it stands on main.
REPO_ROOT = Path(__file__).resolve().parents[1]

# The pin surfaces a dependency bot actually touches in this repository.
# Dependabot manages `.github/workflows/` (Action SHAs) and
# `.pre-commit-config.yaml` (the pre-commit-checklists `rev:` pin), see
# .github/dependabot.yml. Renovate manages `.tool-versions` (the asdf
# manager: pre-commit, github-cli) and `.devcontainer/Dockerfile` (the
# development container base image, pinned by digest), see
# .github/renovate.json5. Neither bot touches anything else in this
# repository: there is no requirements.txt, no Makefile, and no
# .env.example for either to have opinions about.
#
# `.devcontainer/Dockerfile` was missing here for as long as Renovate has
# been watching it, so every base image digest bump was refused as "not a
# dependency pin file" and had to be merged by hand past a required check.
ALLOWED_PATHS = (
    ".pre-commit-config.yaml",
    ".github/workflows/",
    ".devcontainer/Dockerfile",
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
#
# Anchored to a genuine `uses:` field at the start of the line, the same
# anchor BARE_ACTION_VERSION uses, rather than a bare `@<sha>` matched
# anywhere: a follow-up CodeRabbit finding pointed out the original,
# unanchored ACTION_SHA matched a 40 character hex run on ANY changed
# workflow line, `run:` step content included, so a `run:` command could
# change while its normalized form stayed equal, as long as the line
# still ended in something SHA-shaped. `prefix` now captures the full
# `uses: owner/repo@` text, not only `@`, and `_normalize_action_pin`
# reuses that whole prefix unchanged, so the dependency name stays
# literal to the left exactly as it already did.
ACTION_SHA = re.compile(
    r"(?P<prefix>^(?:[ \t]*-[ \t]+)?[ \t]*uses:[ \t]+[\w.-]+/[\w./-]+@)"
    r"[0-9a-fA-F]{40}(?![0-9a-fA-F])"
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


# The development container base image, pinned by digest in
# `.devcontainer/Dockerfile` as `ARG BASE_IMAGE=<image>@sha256:<64 hex>`.
#
# Only the digest becomes a placeholder; the image reference to the left of the `@`
# stays literal. A bump that also pointed the ARG at a different image or
# registry therefore reads as a structural change and is refused, the same
# way a swapped owner is for a `uses:` pin. The `$` anchor matters for the
# same reason it does on ARG_VALUE elsewhere in this organization's copies:
# without it, trailing text appended after the digest would normalize away.
IMAGE_DIGEST = re.compile(
    r"(?P<prefix>^ARG [A-Z0-9_]+=[\w./-]+(?::[\w.-]+)?@)sha256:[0-9a-f]{64}$"
)

FILE_HEADER = re.compile(r"^diff --git a/(?P<old>.+) b/(?P<new>.+)$")
# The blob ids a diff's preamble names for each side, and a hunk's starting
# line and length on each side (a length of one is written by omitting it).
INDEX_LINE = re.compile(
    r"^index (?P<old>[0-9a-f]{7,64})\.\.[0-9a-f]{7,64}(?: [0-7]{6})?$"
)
HUNK_HEADER = re.compile(
    r"^@@ -(?P<old_start>\d+)(?:,(?P<old_len>\d+))? "
    r"\+(?P<new_start>\d+)(?:,(?P<new_len>\d+))? @@"
)

# A YAML block scalar opener: `key: |`, `key: >`, or a bare sequence item
# whose own value is the scalar (`- |`, `- >-`), with the optional
# chomping (`-`/`+`) and explicit indentation (a digit) modifiers the spec
# allows, in either order (`|2-` and `|-2` are both valid), and an optional
# trailing comment. Everything indented more than a line matching this,
# until a line at or below its own indentation appears, is that block
# scalar's literal content, not further YAML structure: a `run: |` step
# body is the shape that matters here, since its content can coincidentally
# read exactly like a `uses:` field. A CodeRabbit review found and
# confirmed this: an indented `uses: owner/action@<sha> # v7` inside a
# run: | block matched ACTION_SHA and BARE_ACTION_VERSION alike, treating
# shell text as if it were a real GitHub Actions step, which a required
# check reading `Pin Only` then approves. A follow-up review found the
# first version of this pattern too narrow to catch every real opener: it
# missed `|2-` (digit before chomping) and a trailing `# comment`, either
# of which would have left a real block scalar unrecognized as one. A
# later review found it still missed a standalone sequence-item scalar
# header, `- |` with no `key:` in front at all, since the pattern required
# a colon before the scalar indicator; confirmed exploitable the same way,
# a `uses:` line nested under one read as ordinary YAML structure instead
# of a block scalar's literal content.
#
# YAML also allows node properties, an anchor (`&body`) and a tag (`!!str`,
# `!local`), between the colon or dash and the indicator, in either order:
# `run: &body |2-` and `run: !!str |-` open a block scalar just as `run: |`
# does. A CodeRabbit review found the pattern missed them, which let a
# `uses:` shaped line inside an anchored or tagged `run:` body read as a
# real step. Confirmed with PyYAML before the fix.
BLOCK_SCALAR_OPENER = re.compile(
    r"(?::|^[ \t]*-)(?:[ \t]+[&!]\S*)*\s*[|>](?:[+-][1-9]?|[1-9][+-]?)?"
    r"(?:[ \t]+#.*)?\s*$"
)
# The sequence markers leading a line, each a dash followed by whitespace,
# and the node properties (anchors, tags) that may lead a node after one.
SEQUENCE_MARKER = re.compile(r"-[ \t]+")
NODE_PROPERTIES = re.compile(r"(?:[&!]\S*(?:[ \t]+|$))*")
# A block scalar indicator alone on its line, optionally after node
# properties: the value of the key on an earlier line. `run: &body` or a
# bare `run:` followed by an indented `|` is as much a block scalar as
# `run: |` (confirmed with PyYAML), and its content may sit at the very
# column of that `|`. A CodeRabbit review found the scan missed it.
STANDALONE_INDICATOR = re.compile(
    r"^[ \t]*(?:[&!]\S*[ \t]+)*[|>](?:[+-][1-9]?|[1-9][+-]?)?"
    r"(?:[ \t]+#.*)?\s*$"
)


def _line_indent(line: str) -> int:
    return len(line) - len(line.lstrip(" \t"))


def _block_scalar_floor(line: str) -> int:
    """The indentation a block scalar opened on `line` has to exceed.

    For `key: |` that is the key's own column. After a sequence marker,
    `- name: |`, it is still the key's column rather than the dash's: YAML
    reads a line starting at that column as the key's sibling, not as
    scalar content (confirmed with PyYAML), so a step's `uses:` beside a
    `- name: |` is ordinary structure. Only when the sequence item itself
    is the scalar, `- |` or `- &body |`, is the dash the floor. Properties
    leading a compact mapping, `- &step name: |`, belong to the mapping,
    which starts where they do, so they are skipped before deciding.
    """
    column = _line_indent(line)
    rest = line[column:]
    while True:
        marker = SEQUENCE_MARKER.match(rest)
        if not marker:
            return column
        after = rest[marker.end() :]
        value = after[NODE_PROPERTIES.match(after).end() :]
        if not value or value[0] in "|>":
            return column
        column += marker.end()
        rest = after


def _standalone_floor() -> int:
    """The floor of a block scalar whose indicator stands alone on its line.

    None at all: every later line in the file counts as its content. Which
    node owns a lone indicator, and so where its content may start, depends
    on lines above it (a bare `- &body`, a property on a line of its own, an
    explicit indentation digit measured from that owner), and each attempt
    to derive it from them was found to under-mark some valid YAML, fuzzed
    against PyYAML. No workflow here uses a lone indicator, so treating the
    rest of the file as content costs nothing today and only ever refuses
    more: a pin below one waits for a person.
    """
    return -1


def _block_scalar_lines(lines: list[str]) -> list[bool]:
    """Mark every line of a whole YAML file as inside a block scalar or not.

    Walks the file top to bottom. After a line opening a block scalar,
    every following line that is blank or indented deeper than the opener
    is that scalar's literal content, until a non-blank line at or below
    the opener's own indentation closes it. Content is never read as an
    opener itself, which three lines of diff context never could
    guarantee: a `uses:` nested under an `if` inside a `run: |` block is
    content here, however deep. A line that merely looks like an opener
    marks what follows as content, which only ever refuses more; comment
    lines are the exception and are skipped (see below).
    """
    marks: list[bool] = []
    floor: int | None = None
    for line in lines:
        if floor is not None:
            if not line.strip() or _line_indent(line) > floor:
                marks.append(True)
                continue
            floor = None
        marks.append(False)
        # Outside a scalar, a line starting with `#` is a comment, never an
        # opener: reading `# note: |` as one would mark what follows as its
        # content, and a real opener among those lines would go unseen.
        # Fuzzing against PyYAML found exactly that.
        if line.lstrip().startswith("#"):
            continue
        if BLOCK_SCALAR_OPENER.search(line):
            floor = _block_scalar_floor(line)
        elif STANDALONE_INDICATOR.match(line):
            floor = _standalone_floor()
    return marks


def _git_blob_id(data: bytes) -> str:
    # git's own object id, recomputed to compare against the diff's `index`
    # line. It identifies a file version rather than guarding one: what
    # actually holds `_apply_hunks` honest is that every context and removed
    # line must match the base, which no hash collision can fake.
    header = b"blob %d\0" % len(data)
    return hashlib.sha1(header + data, usedforsecurity=False).hexdigest()


def _base_lines(path: str, blob: str) -> list[str] | None:
    """The file's base side read from the checkout, or None if it is not
    provably the same file the diff was taken against.

    coderabbit-gate.yml checks out the default branch, never the pull
    request's head, so this reads the file as it stands on main. That is
    the diff's own base only while main has not moved the file since the
    pull request branched, which is what comparing the git blob id against
    the diff's `index` line proves. If main has moved it, or the path
    leaves the checkout, the answer is None and every pin in the file is
    refused.
    """
    root = REPO_ROOT.resolve()
    target = (root / path).resolve()
    if not target.is_relative_to(root) or not target.is_file():
        return None
    data = target.read_bytes()
    if not _git_blob_id(data).startswith(blob):
        return None
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return None
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def _apply_hunks(
    base: list[str], hunks: list[tuple[re.Match[str], list[str]]]
) -> list[str] | None:
    """Rebuild the file's head side from its base and the diff's hunks.

    Every context and removed line has to match the base where the hunk
    header says it sits, every hunk has to land where its header says it
    does on the head side too, and each hunk body has to carry exactly the
    line counts its header declares on both sides. Any disagreement means
    the diff and the base are not describing the same file, or the diff
    was cut short, and the answer is None.
    """
    head: list[str] = []
    cursor = 0
    for header, body in hunks:
        old_len = int(header.group("old_len") or 1)
        new_len = int(header.group("new_len") or 1)
        start = int(header.group("old_start")) - (1 if old_len else 0)
        if start < cursor:
            return None
        head.extend(base[cursor:start])
        if len(head) != int(header.group("new_start")) - (1 if new_len else 0):
            return None
        position = start
        added = 0
        for line in body:
            tag, content = (line[:1], line[1:]) if line else (" ", "")
            if tag in (" ", "-"):
                if position >= len(base) or base[position] != content:
                    return None
                position += 1
                if tag == " ":
                    head.append(content)
                    added += 1
            elif tag == "+":
                head.append(content)
                added += 1
            elif tag != "\\":
                return None
        if position - start != old_len or added != new_len:
            return None
        cursor = position
    head.extend(base[cursor:])
    return head


def _whole_file_block_scalars(
    diff_lines: list[str],
) -> dict[str, tuple[list[bool], list[bool]]]:
    """Block scalar marks for each side of every workflow file whose base
    can be read whole and proven to be the diff's own.

    Keyed by path; each value holds the base side's marks and the head
    side's, indexed by line number minus one. A file missing from the
    result has every line treated as block scalar content, so any pin in it
    is refused (see `parse`). Only `.github/workflows/` is read, the one
    place `normalize` consults the answer.
    """
    files: dict[str, tuple[str | None, list[tuple[re.Match[str], list[str]]]]] = {}
    path = None
    for line in diff_lines:
        header = FILE_HEADER.match(line)
        if header:
            same = header.group("old") == header.group("new")
            path = header.group("new") if same else None
            if path is not None:
                files[path] = (None, [])
            continue
        if path is None:
            continue
        blob, hunks = files[path]
        hunk = HUNK_HEADER.match(line)
        if hunk:
            hunks.append((hunk, []))
        elif hunks:
            hunks[-1][1].append(line)
        else:
            index = INDEX_LINE.match(line)
            if index:
                files[path] = (index.group("old"), hunks)

    marks: dict[str, tuple[list[bool], list[bool]]] = {}
    for path, (blob, hunks) in files.items():
        if not path.startswith(".github/workflows/") or not blob or not hunks:
            continue
        if not blob.strip("0"):
            continue
        base = _base_lines(path, blob)
        if base is None:
            continue
        head = _apply_hunks(base, hunks)
        if head is None:
            continue
        marks[path] = (_block_scalar_lines(base), _block_scalar_lines(head))
    return marks


def normalize(line: str, path: str = "", in_block_scalar: bool = False) -> str:
    """Reduce a line to everything about it that a version bump may not change."""
    if path.endswith(".tool-versions"):
        return TOOL_VERSION_LINE.sub(r"\g<prefix><version>", line)
    # Scoped to .github/workflows/, because a block scalar (`run: |`) is a
    # YAML construct and cannot occur in a Dockerfile at all, while
    # a line whose file could not be read whole is treated as inside one.
    # Left unscoped, every `ARG` line at
    # indentation zero came back unnormalized and every base image digest
    # bump was refused even once the path and the grammar below were right.
    if in_block_scalar and path.startswith(".github/workflows/"):
        return line
    if path == ".devcontainer/Dockerfile":
        return IMAGE_DIGEST.sub(r"\g<prefix><digest>", line)
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
    # Whole-file marks where the base could be proven, and each side's
    # current line number (zero based) to look a line up in them by. With no
    # marks, every line counts as block scalar content: three lines of diff
    # context cannot prove a line sits outside a `run: |` body, and judging
    # from them was a documented gap (a `uses:` line under an `if` inside
    # one read as a step). A workflow diff whose base cannot be proven is
    # therefore refused, and waits for the dependency bot to rebase it onto
    # main, where it can be.
    diff_lines = diff.splitlines()
    whole_file = _whole_file_block_scalars(diff_lines)
    marks = None
    old_number = new_number = 0

    for line in diff_lines:
        header = FILE_HEADER.match(line)
        if header:
            old, new = header.group("old"), header.group("new")
            path = new
            in_hunk = False
            marks = whole_file.get(path) if old == new else None
            # Refused as a whole, not only by withholding pin normalization
            # from its lines: a workflow also carries pins no block scalar
            # check guards (a pip pin in a `run:` step, say), and none of
            # them is graded without a proven base.
            if marks is None and path.startswith(".github/workflows/"):
                structural.append(
                    f"{path}: its base on main could not be proven to be this "
                    "diff's, so nothing in it is graded as a pin until the "
                    "branch is rebased onto main"
                )
            changes.setdefault(path, (Counter(), Counter()))
            if old != new:
                structural.append(f"{old} renamed to {new}")
            continue

        if line.startswith("@@"):
            in_hunk = True
            hunk = HUNK_HEADER.match(line)
            if hunk:
                old_number = int(hunk.group("old_start")) - 1
                new_number = int(hunk.group("new_start")) - 1
            else:
                marks = None
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
            content = line[1:]
            in_scalar = marks[0][old_number] if marks else True
            changes[path][0][normalize(content, path, in_scalar)] += 1
            old_number += 1
        elif line.startswith("+"):
            content = line[1:]
            in_scalar = marks[1][new_number] if marks else True
            changes[path][1][normalize(content, path, in_scalar)] += 1
            new_number += 1
        elif line.startswith(" ") or line == "":
            # An unchanged context line: not compared itself, but it moves
            # both sides' line numbers along.
            old_number += 1
            new_number += 1

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
