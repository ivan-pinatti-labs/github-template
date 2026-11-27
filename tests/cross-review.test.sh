#!/usr/bin/env bash
#
# Tests for scripts/cross-review.sh. git is real, in a scratch repository
# with a bare origin; codex and claude are stubs. The stubs save what they
# were given on stdin to $STUB_STDIN, and answer with $STUB_ANSWER (codex
# into its --output-last-message file, claude on stdout), or exit with
# $STUB_EXIT.
# shellcheck source=tests/shell-test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/shell-test-lib.sh"

script=scripts/cross-review.sh
# The script's own settings, as the caller may have them exported: each
# case below sets what it needs.
unset REVIEWER REVIEW_BASE REVIEW_DIR REVIEW_MAX_ROUNDS REVIEW_FORCE \
  CODEX CODEX_MODEL CODEX_EFFORT CLAUDE CLAUDE_REVIEW_MODEL CLAUDE_REVIEW_EFFORT
export STUB_STDIN="${__scratch}/stdin"

# The bodies expand when the stubs run, not here.
# shellcheck disable=SC2016
stub codex '
[ "$1" = --version ] && exit 0
if [ "$1" = mcp ]; then printf "%s" "${STUB_MCP:-[]}"; exit "${STUB_MCP_EXIT:-0}"; fi
cat >"${STUB_STDIN}"
[ -n "${STUB_EXIT:-}" ] && exit "${STUB_EXIT}"
out= prev=
for a in "$@"; do [ "${prev}" = --output-last-message ] && out="${a}"; prev="${a}"; done
[ -n "${out}" ] && printf "%s" "${STUB_ANSWER:-}" >"${out}"
exit 0'
# shellcheck disable=SC2016
stub claude '
[ "$1" = --version ] && exit 0
cat >"${STUB_STDIN}"
[ -n "${STUB_EXIT:-}" ] && exit "${STUB_EXIT}"
printf "%s" "${STUB_ANSWER:-}"'

# A git of its own: no user or system configuration, hooks or signing.
export HOME="${__scratch}/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset XDG_CONFIG_HOME CODEX_HOME
mkdir -p "${HOME}"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
git init --quiet --bare --initial-branch=main "${__scratch}/origin.git"
git clone --quiet "${__scratch}/origin.git" "${__scratch}/work" 2>/dev/null
work="${__scratch}/work"
cd "${work}"
git switch --quiet -c main
echo one >file.txt
git add file.txt
git commit --quiet -m "feat: first"
git push --quiet origin main
records="${work}/.cross-review/feat/topic"
printf '.cross-review/\n' >>.git/info/exclude
# Whatever the user's config says, the reviewer gets a plain diff: no
# color, no prefixes dropped, and no textconv filter hiding the change.
git config color.ui always
git config diff.noprefix true
git config diff.same.textconv "echo same #"
printf 'file.txt diff=same\n' >>.git/info/attributes

run "${script}"
check "refuses main" 1 err "cross-review: on main: review runs on a topic branch"
git switch --quiet --detach
run "${script}"
check "refuses a detached HEAD" 1 err "cross-review: detached HEAD"
git switch --quiet -c feat/topic main
run "${script}"
check "refuses an empty diff" 1 err "cross-review: no changes between origin/main and feat/topic"
echo two >>file.txt
run "${script}"
check "refuses uncommitted changes" 1 err "cross-review: uncommitted changes"
git commit --quiet -am "feat: second"

# What `codex mcp list --json` prints, trimmed to what the script reads.
mcp_entry() {
  printf '  {\n    "name": "%s",\n    "enabled": true,\n    "transport": {\n      "type": "stdio"\n    }\n  }' "${1}"
}
mcp_two="$(printf '[\n%s,\n%s\n]' "$(mcp_entry probe)" "$(mcp_entry other-one)")"
STUB_MCP="$(printf '[\n%s\n]' "$(mcp_entry dotted.name)")" run "${script}"
check "an MCP server it cannot switch off stops it" 1 err "MCP server 'dotted.name' cannot be switched off for the review; rename it"
STUB_MCP_EXIT=1 run "${script}"
check "so does a failing MCP listing" 1 err "'codex mcp list --json' failed, so its MCP servers cannot be switched off"
STUB_MCP='[{"name": "a", "transport": {}}]' run "${script}"
check "and one it cannot read" 1 err "could not read the MCP server names"

REVIEWER=gemini run "${script}"
check "only codex or claude" 1 err "REVIEWER must be codex or claude, not 'gemini'"
REVIEW_MAX_ROUNDS=0 run "${script}"
check "a positive round limit" 1 err "REVIEW_MAX_ROUNDS must be a positive integer, not '0'"
CODEX=no-such-codex run "${script}"
check "a reviewer CLI that runs" 1 err "'no-such-codex --version' failed; set CODEX to a command that runs here"
REVIEW_BASE=nowhere run "${script}"
check "a base that exists" 1 err "base 'nowhere' not found"
assert "no round recorded by a refusal" test ! -e "${records}"

STUB_ANSWER=$'All good.\n\n**VERDICT: CLEAN**\n' run "${script}"
check "round 1 clean, through Markdown" 0 err "cross-review: round 1 clean, saved to ${records}/round-1-codex.md"
check "the answer is printed" 0 out "All good."
check "and saved" 0 "${records}/round-1-codex.md" "All good."
check "codex runs read only" 0 calls "codex exec --sandbox read-only --skip-git-repo-check --ephemeral"
check "with no AGENTS.md loaded" 0 calls "-c project_doc_max_bytes=0"
check "and no configured instructions" 0 calls '-c developer_instructions=""'
refute "no MCP server to switch off" calls "mcp_servers."
check "no tool bearing feature" 0 calls "--disable apps --disable plugins"
check "at the default effort" 0 calls 'model_reasoning_effort="medium"'
refute "and the Codex config's model" calls "model=\""
check "the diff reaches it on stdin" 0 "${STUB_STDIN}" "+two"
assert "the lock is released" test ! -e "${records}/.lock"
check "as a plain unified diff" 0 "${STUB_STDIN}" "+++ b/file.txt"
refute "with no color" "${STUB_STDIN}" $'\e['
check "web search off" 0 calls 'web_search="disabled"'
check "memories off" 0 calls "--disable memories --disable external_agent_memory_import"
refute "no warning without a global AGENTS.md" err "may still reach the reviewer"
check "after the prompt" 0 "${STUB_STDIN}" "Be adversarial"
refute "nothing declined yet" "${STUB_STDIN}" "declined them"

mkdir "${records}/.lock"
run "${script}"
check "one run at a time per branch" 1 err "cross-review: another cross-review is running on feat/topic (if none is, remove ${records}/.lock)"
rmdir "${records}/.lock"
CODEX_MODEL=m1 CODEX_EFFORT=high STUB_MCP="${mcp_two}" STUB_ANSWER=$'1. file.txt:2 is wrong\nVERDICT: FINDINGS' run "${script}"
check "round 2 findings" 3 err "cross-review: round 2 has findings, saved to ${records}/round-2-codex.md"
check "the model is passed" 3 calls 'model="m1"'
check "every configured MCP server is switched off" 3 calls \
  "-c mcp_servers.probe.enabled=false -c mcp_servers.other-one.enabled=false"
check "and the effort" 3 calls 'model_reasoning_effort="high"'

printf '%s\n' "- file.txt:2, declined: two is intended." >"${records}/declined.md"
STUB_ANSWER=$'VERDICT: CLEAN\nBut one more thing.' run "${script}"
check "only the last line is the verdict" 4 err "cross-review: no verdict line in round 3; read ${records}/round-3-codex.md"
check "declined findings are fed back" 4 "${STUB_STDIN}" "two is intended."

run "${script}"
check "the round limit stops it" 5 err "cross-review: 3 rounds done on feat/topic (REVIEW_MAX_ROUNDS=3)."
REVIEW_MAX_ROUNDS=4 STUB_EXIT=3 run "${script}"
check "a failing reviewer has a status of its own" 7 err "cross-review: codex failed with status 3; round 4 not counted"
assert "and its round is not counted" test ! -e "${records}/round-4-codex.md"
REVIEW_FORCE=1 STUB_ANSWER= run "${script}"
check "forcing past the limit says so" 6 err "round 4 past the limit of 3 (REVIEW_FORCE=1)"
check "an empty answer has its own status" 6 err "cross-review: codex exited 0 but wrote no answer; nothing saved for round 4"
assert "and is not counted" test ! -e "${records}/round-4-codex.md"
assert "its stale partial is gone" test ! -e "${records}/round-4-codex.md.partial"

mkdir -p "${HOME}/.codex"
touch "${HOME}/.codex/AGENTS.md"
rm -rf "${work}/.cross-review"
STUB_ANSWER="VERDICT: CLEAN" run "${script}"
check "a global Codex AGENTS.md is warned about" 0 err "cross-review: ${HOME}/.codex/AGENTS.md exists and may still reach the reviewer"
rm -rf "${HOME}/.codex" "${work}/.cross-review"
REVIEWER=claude CLAUDE_REVIEW_MODEL=sonnet STUB_ANSWER=$'Fine.\nVERDICT: CLEAN' run "${script}"
check "claude reviews too" 0 err "saved to ${records}/round-1-claude.md"
check "restricted, three read only tools" 0 calls "claude -p --restricted --strict-mcp-config --tools Read,Grep,Glob --model sonnet --effort medium"
check "with no instruction files" 0 calls '"claudeMdExcludes":["**/CLAUDE.md","**/CLAUDE.local.md","**/AGENTS.md","**/rules/**"]'
check "no auto memory, no connectors" 0 calls '"autoMemoryEnabled":false,"disableClaudeAiConnectors":true'
check "without asking" 0 calls "--permission-mode dontAsk"
check "the diff on stdin" 0 "${STUB_STDIN}" "+two"
REVIEWER=claude STUB_ANSWER= run "${script}"
check "an empty claude answer too" 6 err "cross-review: claude exited 0 but wrote no answer; nothing saved for round 2"
REVIEWER=claude STUB_EXIT=1 run "${script}"
check "a failing claude too" 7 err "cross-review: claude failed with status 1; round 2 not counted"
assert "leaving only its partial" test -e "${records}/round-2-claude.md.partial"

rm -rf "${work}/.cross-review"
git worktree add --quiet -b feat/side "${work}/.claude/worktrees/side" feat/topic
printf '.claude/\n' >>.git/info/exclude
cd "${work}/.claude/worktrees/side"
STUB_ANSWER="VERDICT: CLEAN" run "${script}"
check "a worktree's rounds go to the main checkout" 0 err "saved to ${work}/.cross-review/feat/side/round-1-codex.md"
REVIEW_DIR="${__scratch}/elsewhere" STUB_ANSWER="VERDICT: CLEAN" run "${script}"
check "unless REVIEW_DIR says otherwise" 0 err "saved to ${__scratch}/elsewhere/feat/side/round-1-codex.md"
caller="${work}/.claude/worktrees/side/sub"
mkdir -p "${caller}"
(cd "${caller}" && REVIEW_DIR=rel STUB_ANSWER="VERDICT: CLEAN" run "${script}" && cp "${__scratch}/err" "${__scratch}/err.rel")
check "a relative REVIEW_DIR is the caller's" 0 "${__scratch}/err.rel" "saved to ${caller}/rel/feat/side/round-1-codex.md"

mkdir -p "${__scratch}/nowhere"
cd "${__scratch}/nowhere"
GIT_CEILING_DIRECTORIES="${__scratch}" run "${__repo}/${script}"
check "outside a repository" 1 err "cross-review: not inside a git repository"

finish
