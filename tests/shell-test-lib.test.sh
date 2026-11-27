#!/usr/bin/env bash
#
# Tests for tests/shell-test-lib.sh itself: that check, refute, assert and
# finish report a failure, and fail the run, rather than passing it
# silently. Each case is a small test file of its own, run as its own
# process, whose output and status this file checks.
# shellcheck source=tests/shell-test-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/shell-test-lib.sh"

cases="${__scratch}/cases"
mkdir -p "${cases}"
# The script under test in every case: says hello and exits 2.
printf '#!/usr/bin/env bash\necho hello\nexit 2\n' >"${cases}/subject.sh"

# case NAME BODY: a test file that sources the harness and runs BODY.
case_file() {
  printf 'source %q\n%s\nfinish\n' "${__repo}/tests/shell-test-lib.sh" "${2}" >"${cases}/${1}.sh"
}

case_file pass "run ${cases}/subject.sh
check \"says hello\" 2 out hello
refute \"says nothing else\" out goodbye
assert \"true holds\" true"
run "${cases}/pass.sh"
check "a passing file passes" 0 out "ok says hello"
check "every passing kind reports ok" 0 out "ok true holds"
refute "and nothing failed" err "failed"

case_file status "run ${cases}/subject.sh
check \"wrong status\" 0 out hello"
run "${cases}/status.sh"
check "a wrong status fails the file" 1 err "FAIL wrong status: exit 2, wanted 0"
check "and finish counts it" 1 err "1 failed"

case_file text "run ${cases}/subject.sh
check \"missing text\" 2 out goodbye"
run "${cases}/text.sh"
check "missing text fails the file" 1 err "FAIL missing text: 'goodbye' not in out"

case_file refute "run ${cases}/subject.sh
refute \"found text\" out hello"
run "${cases}/refute.sh"
check "text that should be absent fails the file" 1 err "FAIL found text: 'hello' found in out"

case_file assert "assert \"false holds\" false"
run "${cases}/assert.sh"
check "a failing assert fails the file" 1 err "FAIL false holds"

case_file several "assert one false
assert two false
assert three true"
run "${cases}/several.sh"
check "finish counts every failure" 1 err "2 failed"

finish
