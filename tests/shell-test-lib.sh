# shellcheck shell=bash
#
# Shared by the tests/*.test.sh files, which source it (the same harness as
# devcontainer-airlock's). Each test runs the script under test as its own
# bash process, with the external commands it should not really call
# replaced by stubs on PATH, in a scratch directory removed afterwards.

set -o errexit
set -o pipefail
set -o nounset

# Run from a git hook (the pre-commit hook runs these tests), GIT_DIR,
# GIT_INDEX_FILE and the like point at the repository being committed to.
# The tests' own git must never see them.
while read -r __var; do
  unset "${__var}"
done < <(git rev-parse --local-env-vars)

__repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
__scratch="$(mktemp -d)"
trap 'rm -rf "${__scratch}"' EXIT
__failures=0
__status=0
mkdir "${__scratch}/bin"
# The stubs log their calls here, one line each.
export STUB_LOG="${__scratch}/calls"
: >"${STUB_LOG}"
export PATH="${__scratch}/bin:${PATH}"

# stub NAME [BODY]: a command on PATH that logs `NAME args` and then runs
# BODY (default: nothing, exit 0).
stub() {
  local name="${1}" body="${2:-}"
  # shellcheck disable=SC2016 # expanded when the stub runs
  printf '#!/bin/bash\necho "%s $*" >>"${STUB_LOG}"\n%s\n' "${name}" "${body}" \
    >"${__scratch}/bin/${name}"
  chmod +x "${__scratch}/bin/${name}"
}

# run SCRIPT [ARGS...]: runs it, recording its exit status, standard output
# and standard error for check. SCRIPT is relative to the repository root,
# or absolute.
run() {
  local script="${1}"
  shift
  [[ "${script}" == /* ]] || script="${__repo}/${script}"
  : >"${STUB_LOG}"
  __status=0
  bash "${script}" "$@" >"${__scratch}/out" 2>"${__scratch}/err" </dev/null || __status=$?
}

# check NAME STATUS STREAM TEXT: the last run exited STATUS and TEXT is in
# STREAM (out, err or calls), or in the file at that absolute path.
check() {
  local name="${1}" want_status="${2}" stream="${3}" want_text="${4}"
  local file="${__scratch}/${stream}"
  [[ "${stream}" == /* ]] && file="${stream}"
  if [[ "${__status}" -ne "${want_status}" ]]; then
    echo "FAIL ${name}: exit ${__status}, wanted ${want_status}" >&2
    sed 's/^/  | /' "${__scratch}/err" >&2
    __failures=$((__failures + 1))
  elif ! grep --quiet --fixed-strings -- "${want_text}" "${file}" 2>/dev/null; then
    echo "FAIL ${name}: '${want_text}' not in ${stream}" >&2
    __failures=$((__failures + 1))
  else
    echo "ok ${name}"
  fi
}

# refute NAME FILE TEXT: TEXT is not in FILE (a stream name or a path).
refute() {
  local file="${__scratch}/${2}"
  [[ "${2}" == /* ]] && file="${2}"
  if grep --quiet --fixed-strings -- "${3}" "${file}" 2>/dev/null; then
    echo "FAIL ${1}: '${3}' found in ${2}" >&2
    __failures=$((__failures + 1))
  else
    echo "ok ${1}"
  fi
}

# assert NAME COMMAND [ARGS...]: COMMAND succeeds.
assert() {
  local name="${1}"
  shift
  if "$@"; then
    echo "ok ${name}"
  else
    echo "FAIL ${name}" >&2
    __failures=$((__failures + 1))
  fi
}

finish() {
  if [[ "${__failures}" -gt 0 ]]; then
    echo "${__failures} failed" >&2
    exit 1
  fi
}
