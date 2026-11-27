#!/usr/bin/env bash
# Blind review of the current branch by the other vendor's agent, before it
# becomes a pull request (`make cross-review`). AGENTS.md, "Review before a
# pull request", has the flow this is one step of.
#
# The reviewer is the agent that did not write the change: Codex reviews
# what Claude wrote (the default), Claude reviews what Codex wrote
# (REVIEWER=claude). It runs blind and in place: it reads the diff and the
# code around it, but no agent instruction file (AGENTS.md, CLAUDE.md,
# rules) and no memory is loaded into it, and round 1 gets none of the
# author's reasoning. The files are still in the checkout and a reviewer
# could open them; blind means not loaded, not hidden.
#
# What the reviewer can read differs. Claude's file tools are kept to this
# checkout (--restricted). Codex's shell can read any file the user running
# this can, since its read only sandbox limits writes and the network, not
# reads. A diff that carries instructions could so steer Codex into reading
# private files into its answer. Run it as a user, or in a container, that
# holds nothing the reviewer should not see.
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
#   7  the reviewer failed (its own status is in the message)
#   anything else: a git command's own status
# Only a finished round counts toward the limit; a failed one leaves at most
# round-N-<reviewer>.md.partial. Deleting $REVIEW_DIR/<branch> starts over.
#
# Environment (all optional):
#   REVIEWER              codex (default) or claude
#   REVIEW_BASE           base to diff against (default origin/main, fetched
#                         first when it is a remote branch)
#   REVIEW_DIR            where rounds are saved (default .cross-review in the
#                         main checkout, gitignored, shared by its worktrees).
#                         Inside the checkout it has to be gitignored, or the
#                         next round finds the tree dirty
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
# A relative REVIEW_DIR means relative to where it was asked for, not to
# the top of the checkout this script moves to next.
review_root="${REVIEW_DIR:-}"
if [[ -n "${review_root}" && "${review_root}" != /* ]]; then
  review_root="${PWD}/${review_root}"
fi
cd "${top}"
if [[ -z "${review_root}" ]]; then
  # The main checkout, not this worktree: the record outlives the worktree.
  main="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
  review_root="${main:-${top}}/.cross-review"
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
case "${branch}" in
HEAD) die "detached HEAD: check out the branch to review" ;;
main | master) die "on ${branch}: review runs on a topic branch" ;;
esac

# Fail early, with the reason, rather than after the prompt is built.
# shellcheck disable=SC2086 # the command may carry a wrapper and its arguments
${reviewer_cmd} --version >/dev/null 2>&1 ||
  die "'${reviewer_cmd} --version' failed; set ${reviewer_var} to a command that runs here"

mcp_off=()
if [[ "${reviewer}" == codex ]]; then
  # An empty mcp_servers table is merged with the configured one, not put
  # in its place, so every configured server is switched off by name. A
  # name that cannot be written as a -c key path cannot be switched off.
  # shellcheck disable=SC2086 # the command may carry a wrapper
  mcp_list="$(${codex_cmd} mcp list --json 2>/dev/null)" ||
    die "'${codex_cmd} mcp list --json' failed, so its MCP servers cannot be switched off"
  mcp_names="$(printf '%s\n' "${mcp_list}" | sed -n 's/^    "name": "\(.*\)",$/\1/p')"
  [[ "$(printf '%s\n' "${mcp_list}" | grep -c '"transport"')" -eq "$(printf '%s' "${mcp_names}" | grep -c '')" ]] ||
    die "could not read the MCP server names from '${codex_cmd} mcp list --json'"
  for name in ${mcp_names}; do
    [[ "${name}" =~ ^[A-Za-z0-9_-]+$ ]] ||
      die "MCP server '${name}' cannot be switched off for the review; rename it"
    mcp_off+=(-c "mcp_servers.${name}.enabled=false")
  done
fi

# A stale remote base would put commits already merged into the review.
if [[ "${base}" == origin/* ]]; then
  git fetch --quiet origin "${base#origin/}" ||
    echo "cross-review: could not fetch ${base}, using the local copy" >&2
fi
git rev-parse --verify --quiet "${base}^{commit}" >/dev/null ||
  die "base '${base}' not found"

# A plain unified diff, whatever the user's git config says about color,
# external diff tools, textconv filters or path prefixes.
review_diff() {
  git diff --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ \
    "$@" "${base}...HEAD"
}

# Commits only, so the review sees exactly what the pull request will carry.
if [[ -n "$(git status --porcelain)" ]]; then
  die "uncommitted changes: commit (or set aside) everything first"
fi
if review_diff --quiet; then
  die "no changes between ${base} and ${branch}"
fi

dir="${review_root}/${branch}"
mkdir -p "${dir}"
# One run at a time per branch, or two would pick the same round number.
# mkdir is atomic; a run killed before its trap ran leaves the lock behind.
lock="${dir}/.lock"
mkdir "${lock}" 2>/dev/null ||
  die "another cross-review is running on ${branch} (if none is, remove ${lock})"
trap 'rmdir "${lock}" 2>/dev/null || true' EXIT
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
# Codex loads no AGENTS.md with project_doc_max_bytes=0, none of the
# developer_instructions a Codex config file (the user's, or a trusted
# project's .codex/config.toml) may carry, since an override on the command
# line wins over every file, no skill (the user's, or one a repository
# carries under .agents/skills) with skills.include_instructions off, no
# memory with memories off, and no MCP server with each one configured
# switched off. Claude Code skips every CLAUDE.md, AGENTS.md and rules file,
# project or user, through claudeMdExcludes, and its auto memory. Prompt and
# diff go on stdin: a single argument is capped at 128 KiB on Linux, and
# Claude Code's --tools takes every word after it, a positional prompt
# included.
claude_settings='{"claudeMdExcludes":["**/CLAUDE.md","**/CLAUDE.local.md","**/AGENTS.md","**/rules/**"],"autoMemoryEnabled":false,"disableClaudeAiConnectors":true}'

if [[ "${reviewer}" == codex ]]; then
  # project_doc_max_bytes covers the repository's AGENTS.md files. Codex's
  # own global one, in its home folder, is the user's to keep out.
  for global in "${CODEX_HOME:-${HOME}/.codex}"/AGENTS{,.override}.md; do
    if [[ -e "${global}" ]]; then
      echo "cross-review: ${global} exists and may still reach the reviewer; the review is not fully blind" >&2
    fi
  done
fi

if [[ "${round}" -gt "${max_rounds}" ]]; then
  of="past the limit of ${max_rounds} (REVIEW_FORCE=1)"
else
  of="of ${max_rounds}"
fi
echo "cross-review: round ${round} ${of}, ${reviewer} reviewing ${branch} against ${base}" >&2

rm -f "${out}.partial"
status=0
case "${reviewer}" in
codex)
  # `codex review --base` takes no prompt of its own, so this is exec.
  codex_args=(exec --sandbox read-only --skip-git-repo-check --ephemeral
    --cd "${top}" --output-last-message "${out}.partial"
    -c "model_reasoning_effort=\"${codex_effort}\""
    -c project_doc_max_bytes=0
    -c 'developer_instructions=""'
    -c skills.include_instructions=false
    -c 'web_search="disabled"'
    ${mcp_off[@]+"${mcp_off[@]}"})
  # No memory, and no tool that reaches the network or other programs:
  # web search and MCP servers (above), apps, plugins, the browser and
  # computer use. Its shell stays, to read the code. The read only sandbox
  # stops it writing and reaching the network, not reading: the shell can
  # read any file this user can (see the header). Hooks stay on: that is
  # where a command guard lives.
  for feature in memories external_agent_memory_import apps plugins \
    remote_plugin browser_use browser_use_external browser_use_full_cdp_access \
    computer_use image_generation skill_mcp_dependency_install \
    in_app_local_automation in_app_browser; do
    codex_args+=(--disable "${feature}")
  done
  if [[ -n "${CODEX_MODEL:-}" ]]; then
    codex_args+=(-c "model=\"${CODEX_MODEL}\"")
  fi
  # shellcheck disable=SC2086 # the command may carry a wrapper
  {
    printf '%s\n' "${prompt}"
    review_diff
  } |
    ${codex_cmd} "${codex_args[@]}" - >&2 || status=$?
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
    review_diff
  } |
    ${claude_cmd} -p --restricted --strict-mcp-config \
      --tools "Read,Grep,Glob" \
      --model "${claude_model}" --effort "${claude_effort}" \
      --settings "${claude_settings}" \
      --permission-mode dontAsk >"${out}.partial" || status=$?
  ;;
esac
if [[ "${status}" -ne 0 ]]; then
  echo "cross-review: ${reviewer} failed with status ${status}; round ${round} not counted" >&2
  exit 7
fi
if [[ ! -s "${out}.partial" ]]; then
  echo "cross-review: ${reviewer} exited 0 but wrote no answer; nothing saved for round ${round}" >&2
  rm -f "${out}.partial"
  exit 6
fi
mv "${out}.partial" "${out}"
cat "${out}"
echo

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
