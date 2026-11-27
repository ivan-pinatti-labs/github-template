#!/usr/bin/env bash
# Blind review of the current branch by the other vendor's agent, before it
# becomes a pull request (`make cross-review`). AGENTS.md, "Review before a
# pull request", has the flow this is one step of.
#
# The reviewer is the agent that did not write the change: Codex reviews
# what Claude wrote (the default), Claude reviews what Codex wrote
# (REVIEWER=claude). It runs blind and in place: it reads the diff and the
# code around it, but no agent instruction file (AGENTS.md, CLAUDE.md,
# rules) and no auto memory is loaded into it, and round 1 gets none of the
# author's reasoning. The files are still in the checkout and a reviewer
# could open them; blind means not loaded, not hidden.
#
# It runs where the reviewer CLIs and their logins are: on a host, or in
# whatever environment holds them. It is not project code for a container
# with no network and no credentials, because the reviewer needs both.
#
# Each run is one round, saved under $REVIEW_DIR/<branch>/. The author fixes
# what holds up, records each finding it declines (with the reason) in
# $REVIEW_DIR/<branch>/declined.md, commits, and runs it again, until a
# round reports nothing new. Later rounds are shown declined.md, reasons
# included, so a finding already answered is not raised forever (and from
# round 2 the review is no longer fully blind).
#
# Exit status:
#   0  VERDICT: CLEAN
#   1  usage error, or a precondition failed (branch, tree, base, CLI)
#   3  VERDICT: FINDINGS
#   4  the answer has no verdict line
#   5  the round limit is reached: hand what is open to a person
#   6  the reviewer exited 0 but wrote no answer
#   anything else: the failing command's own status (a reviewer CLI, git)
# Only a finished round counts toward the limit. An interrupted one stays as
# round-N-<reviewer>.md.partial. Deleting $REVIEW_DIR/<branch> starts over.
#
# Environment (all optional):
#   REVIEWER              codex (default) or claude
#   REVIEW_BASE           base to diff against (default origin/main, fetched
#                         first when it is a remote branch)
#   REVIEW_DIR            where rounds are saved (default .cross-review in the
#                         main checkout, gitignored, shared by its worktrees)
#   REVIEW_MAX_ROUNDS     stop after this many rounds (default 3); every
#                         round counts, clean or not, as a token budget
#   REVIEW_FORCE=1        run past REVIEW_MAX_ROUNDS anyway
#   CODEX                 Codex command (default codex). It may carry a
#                         wrapper, e.g. CODEX="env VAR=value codex"
#   CODEX_MODEL           Codex model (default: what the Codex config sets)
#   CODEX_EFFORT          Codex reasoning effort (default medium)
#   CLAUDE                Claude Code command (default claude)
#   CLAUDE_REVIEW_MODEL   Claude model (default opus)
#   CLAUDE_REVIEW_EFFORT  Claude effort (default medium)
set -o errexit
set -o nounset
set -o pipefail

reviewer="${REVIEWER:-codex}"
base="${REVIEW_BASE:-origin/main}"
max_rounds="${REVIEW_MAX_ROUNDS:-3}"
codex_cmd="${CODEX:-codex}"
codex_effort="${CODEX_EFFORT:-medium}"
claude_cmd="${CLAUDE:-claude}"
claude_model="${CLAUDE_REVIEW_MODEL:-opus}"
claude_effort="${CLAUDE_REVIEW_EFFORT:-medium}"

die() {
  echo "cross-review: $*" >&2
  exit 1
}

case "${reviewer}" in
codex) reviewer_cmd="${codex_cmd}" reviewer_var=CODEX ;;
claude) reviewer_cmd="${claude_cmd}" reviewer_var=CLAUDE ;;
*) die "REVIEWER must be codex or claude, not '${reviewer}'" ;;
esac
[[ "${max_rounds}" =~ ^[1-9][0-9]*$ ]] ||
  die "REVIEW_MAX_ROUNDS must be a positive integer, not '${max_rounds}'"

top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "${top}"
# The main checkout, not this worktree: the record outlives the worktree.
common="$(git rev-parse --path-format=absolute --git-common-dir)"
review_root="${REVIEW_DIR:-$(dirname "${common}")/.cross-review}"

branch="$(git rev-parse --abbrev-ref HEAD)"
case "${branch}" in
HEAD) die "detached HEAD: check out the branch to review" ;;
main | master) die "on ${branch}: review runs on a topic branch" ;;
esac

# Fail early, with the reason, rather than after the prompt is built.
# shellcheck disable=SC2086 # the command may carry a wrapper and its arguments
${reviewer_cmd} --version >/dev/null 2>&1 ||
  die "'${reviewer_cmd} --version' failed; set ${reviewer_var} to a command that runs here"

# A stale remote base would put commits already merged into the review.
if [[ "${base}" == origin/* ]]; then
  git fetch --quiet origin "${base#origin/}" ||
    echo "cross-review: could not fetch ${base}, using the local copy" >&2
fi
git rev-parse --verify --quiet "${base}^{commit}" >/dev/null ||
  die "base '${base}' not found"

# Commits only, so the review sees exactly what the pull request will carry.
if [[ -n "$(git status --porcelain)" ]]; then
  die "uncommitted changes: commit (or set aside) everything first"
fi
if git diff --quiet "${base}...HEAD"; then
  die "no changes between ${base} and ${branch}"
fi

dir="${review_root}/${branch}"
mkdir -p "${dir}"
rounds_done="$(find "${dir}" -maxdepth 1 -name 'round-*.md' | wc -l)"
round=$((rounds_done + 1))
if [[ "${round}" -gt "${max_rounds}" && "${REVIEW_FORCE:-0}" != 1 ]]; then
  echo "cross-review: ${rounds_done} rounds done on ${branch} (REVIEW_MAX_ROUNDS=${max_rounds})." >&2
  echo "cross-review: hand what is open to a person, or rerun with REVIEW_FORCE=1." >&2
  exit 5
fi
out="${dir}/round-${round}-${reviewer}.md"

prompt="You are reviewing a change on branch ${branch}, written by a different AI
agent, before it is opened as a pull request. Be adversarial: your job is to
find what is wrong, not to approve it.

Review blind. The working directory is the branch, checked out at HEAD; the
diff against ${base} is at the end of this message. Judge the change only by
that diff and the code around it. Do not look for instructions written for
agents, or for the author's reasoning.

Report correctness bugs, regressions, security problems, things that would
break the build, the tests or CI, and comments or docs that claim something
the code does not do. Each finding names a file and line and gives a
concrete failure scenario. Most severe first. No style preferences, no
praise, no summary of what the change does."

if [[ -s "${dir}/declined.md" ]]; then
  prompt+="

The author already answered the findings below and declined them, with
reasons. Do not raise them again unless the reason given is wrong; if it is,
say why.

$(cat "${dir}/declined.md")"
fi

prompt+="

End your answer with exactly one final line, nothing after it:
VERDICT: CLEAN    if nothing should change
VERDICT: FINDINGS otherwise

The diff against ${base}:
"

# What keeps the reviewers blind is configuration, not a copy of the tree.
# Codex loads no AGENTS.md with project_doc_max_bytes=0, and no MCP server.
# Claude Code skips every CLAUDE.md, AGENTS.md and rules file, project or
# user, through claudeMdExcludes, and its auto memory. Prompt and diff go on
# stdin: a single argument is capped at 128 KiB on Linux, and Claude Code's
# --tools takes every word after it, a positional prompt included.
claude_settings='{"claudeMdExcludes":["**/CLAUDE.md","**/CLAUDE.local.md","**/AGENTS.md","**/rules/**"],"autoMemoryEnabled":false,"disableClaudeAiConnectors":true}'

echo "cross-review: round ${round} of ${max_rounds}, ${reviewer} reviewing ${branch} against ${base}" >&2

rm -f "${out}.partial"
case "${reviewer}" in
codex)
  # `codex review --base` takes no prompt of its own, so this is exec.
  codex_args=(exec --sandbox read-only --skip-git-repo-check --ephemeral
    --cd "${top}" --output-last-message "${out}.partial"
    -c "model_reasoning_effort=\"${codex_effort}\""
    -c project_doc_max_bytes=0
    -c 'mcp_servers={}')
  # Plugins and apps bring tools of their own, outside mcp_servers, and
  # the read only sandbox constrains the shell only, so every feature that
  # brings tools is off. Hooks stay on: that is where a command guard
  # lives.
  for feature in apps plugins remote_plugin browser_use browser_use_external \
    browser_use_full_cdp_access computer_use image_generation \
    skill_mcp_dependency_install in_app_local_automation in_app_browser; do
    codex_args+=(--disable "${feature}")
  done
  if [[ -n "${CODEX_MODEL:-}" ]]; then
    codex_args+=(-c "model=\"${CODEX_MODEL}\"")
  fi
  # shellcheck disable=SC2086 # the command may carry a wrapper
  {
    printf '%s\n' "${prompt}"
    git diff "${base}...HEAD"
  } |
    ${codex_cmd} "${codex_args[@]}" - >&2
  if [[ ! -s "${out}.partial" ]]; then
    echo "cross-review: ${reviewer} exited 0 but wrote no answer; nothing saved for round ${round}" >&2
    rm -f "${out}.partial"
    exit 6
  fi
  cat "${out}.partial"
  echo
  ;;
claude)
  # --restricted: no Bash or other tool that runs code, no web, file tools
  # kept to this checkout, and the user, project and local settings files
  # (and so their hooks) ignored. --tools leaves exactly the three read
  # only tools; --allowedTools would not restrict anything. With
  # --strict-mcp-config and no --mcp-config, and connectors off, no MCP
  # tool is left either.
  # shellcheck disable=SC2086 # the command may carry a wrapper
  {
    printf '%s\n' "${prompt}"
    git diff "${base}...HEAD"
  } |
    ${claude_cmd} -p --restricted --strict-mcp-config \
      --tools "Read,Grep,Glob" \
      --model "${claude_model}" --effort "${claude_effort}" \
      --settings "${claude_settings}" \
      --permission-mode dontAsk | tee "${out}.partial"
  if [[ ! -s "${out}.partial" ]]; then
    echo "cross-review: ${reviewer} exited 0 but wrote no answer; nothing saved for round ${round}" >&2
    rm -f "${out}.partial"
    exit 6
  fi
  ;;
esac
mv "${out}.partial" "${out}"

# Only the last non-empty line counts, so a verdict quoted earlier in the
# answer cannot pass for one. Models dress it up (**VERDICT: CLEAN**,
# indentation, code spans): that is stripped first.
verdict="$(sed -E 's/[*`_]//g; s/^[[:space:]]+//; s/[[:space:]]+$//' "${out}" |
  grep -v '^$' | tail -n 1 || true)"
case "${verdict}" in
"VERDICT: CLEAN")
  echo "cross-review: round ${round} clean, saved to ${out}" >&2
  exit 0
  ;;
"VERDICT: FINDINGS")
  echo "cross-review: round ${round} has findings, saved to ${out}" >&2
  echo "cross-review: fix or decline each (declined ones go in ${dir}/declined.md), commit, rerun." >&2
  exit 3
  ;;
*)
  echo "cross-review: no verdict line in round ${round}; read ${out}" >&2
  exit 4
  ;;
esac
