#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

assert_contains() {
	local haystack="$1"
	local needle="$2"
	local label="$3"
	[[ "${haystack}" == *"${needle}"* ]] || fail "${label}: missing '${needle}'"
}

assert_file_contains() {
	local path="$1"
	local pattern="$2"
	local label="$3"
	grep -Eq -- "${pattern}" "${path}" || fail "${label}: ${path} does not match ${pattern}"
}

make_fake_godot() {
	local target="$1"
	local mode="$2"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'set -eu' \
		'if [[ "${1:-}" == "--version" ]]; then printf "4.6.1.stable.test\\n"; exit 0; fi' \
		'log_file=""' \
		'while (( $# > 0 )); do' \
		'  if [[ "$1" == "--log-file" ]]; then log_file="$2"; shift 2; continue; fi' \
		'  shift' \
		'done' \
		'case "'"${mode}"'" in' \
		'  pass) printf "PASS: all assertions succeeded\\n" | tee "${log_file}" ;;' \
		'  exit_failure) printf "synthetic test failure\\n" | tee "${log_file}"; exit 7 ;;' \
		'  log_failure) printf "SCRIPT ERROR: synthetic parse failure\\n" | tee "${log_file}" ;;' \
		'  engine_log_failure) printf "SCRIPT ERROR: engine-log-only parse failure\\n" >"${log_file}" ;;' \
		'  leak_failure) printf "WARNING: ObjectDB instances leaked at exit\\n" | tee "${log_file}" ;;' \
		'  hang) sleep 5; printf "PASS: too late\\n" | tee "${log_file}" ;;' \
		'esac' >"${target}"
	chmod +x "${target}"
}

cd "${PROJECT_ROOT}"

[[ -x tools/run_tests.sh ]] || fail "tools/run_tests.sh must exist and be executable"
[[ -x tools/validate_project.sh ]] || fail "tools/validate_project.sh must exist and be executable"
[[ -f .github/workflows/validate.yml ]] || fail ".github/workflows/validate.yml must exist"

bash -n tools/run_tests.sh
bash -n tools/validate_project.sh

readonly TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/planewalker-ci-contract.XXXXXX")"
trap 'rm -rf -- "${TEMP_DIR}"' EXIT

find tests -type f \( -name '*_test.tscn' -o -name '*_smoke.tscn' \) -print \
	| LC_ALL=C sort >"${TEMP_DIR}/expected-scenes.txt"
tools/run_tests.sh --list >"${TEMP_DIR}/listed-scenes.txt"
scene_count="$(wc -l <"${TEMP_DIR}/expected-scenes.txt" | tr -d ' ')"
[[ ${scene_count} -gt 0 ]] || fail "test discovery must find at least one scene"
diff -u "${TEMP_DIR}/expected-scenes.txt" "${TEMP_DIR}/listed-scenes.txt" \
	|| fail "--list must return every test scene in stable order"

set +e
tools/run_tests.sh --filter definitely-not-a-real-test >/dev/null 2>&1
filter_status=$?
set -e
[[ ${filter_status} -ne 0 ]] || fail "an empty test filter must fail"

make_fake_godot "${TEMP_DIR}/godot-pass" pass
pass_output="$(GODOT_BIN="${TEMP_DIR}/godot-pass" TEST_LOG_DIR="${TEMP_DIR}/pass-logs" tools/run_tests.sh --filter seed_service_test)"
assert_contains "${pass_output}" "Scene tests: 1 passed, 0 failed" "successful scene summary"
assert_contains "${pass_output}" "Code coverage: not collected" "honest coverage summary"

make_fake_godot "${TEMP_DIR}/godot-exit-failure" exit_failure
set +e
GODOT_BIN="${TEMP_DIR}/godot-exit-failure" TEST_LOG_DIR="${TEMP_DIR}/exit-failure-logs" tools/run_tests.sh --filter seed_service_test >/dev/null 2>&1
exit_failure_status=$?
set -e
[[ ${exit_failure_status} -ne 0 ]] || fail "a non-zero Godot exit must fail the suite"

make_fake_godot "${TEMP_DIR}/godot-log-failure" log_failure
set +e
GODOT_BIN="${TEMP_DIR}/godot-log-failure" TEST_LOG_DIR="${TEMP_DIR}/log-failure-logs" tools/run_tests.sh --filter seed_service_test >/dev/null 2>&1
log_failure_status=$?
set -e
[[ ${log_failure_status} -ne 0 ]] || fail "a script error in Godot logs must fail even with exit code zero"

make_fake_godot "${TEMP_DIR}/godot-engine-log-failure" engine_log_failure
set +e
GODOT_BIN="${TEMP_DIR}/godot-engine-log-failure" TEST_LOG_DIR="${TEMP_DIR}/engine-log-failure-logs" tools/run_tests.sh --filter seed_service_test >/dev/null 2>&1
engine_log_failure_status=$?
set -e
[[ ${engine_log_failure_status} -ne 0 ]] || fail "an engine-log-only script error must fail the suite"

make_fake_godot "${TEMP_DIR}/godot-leak-failure" leak_failure
set +e
GODOT_BIN="${TEMP_DIR}/godot-leak-failure" TEST_LOG_DIR="${TEMP_DIR}/leak-failure-logs" tools/run_tests.sh --filter seed_service_test >/dev/null 2>&1
leak_failure_status=$?
set -e
[[ ${leak_failure_status} -ne 0 ]] || fail "an unexpected ObjectDB leak must fail the suite"

known_leak_output="$(GODOT_BIN="${TEMP_DIR}/godot-leak-failure" TEST_LOG_DIR="${TEMP_DIR}/known-leak-logs" tools/run_tests.sh --filter reward_system_smoke)"
assert_contains "${known_leak_output}" "Known leak warnings: 1" "explicit known-leak summary"

make_fake_godot "${TEMP_DIR}/godot-hang" hang
set +e
GODOT_BIN="${TEMP_DIR}/godot-hang" TEST_LOG_DIR="${TEMP_DIR}/hang-logs" tools/run_tests.sh --filter seed_service_test --timeout 1 >/dev/null 2>&1
timeout_status=$?
set -e
[[ ${timeout_status} -ne 0 ]] || fail "a scene exceeding its timeout must fail the suite"

assert_file_contains .github/workflows/validate.yml '^permissions:$' "workflow permissions block"
assert_file_contains .github/workflows/validate.yml 'contents: read' "workflow read-only repository access"
assert_file_contains .github/workflows/validate.yml 'godot-ci:4\.6\.1' "workflow Godot version pin"
assert_file_contains .github/workflows/validate.yml 'python3 --version' "workflow Python availability check"
assert_file_contains .github/workflows/validate.yml '\./tools/validate_project\.sh' "workflow validation entrypoint"
assert_file_contains tools/validate_project.sh 'python3 -m unittest tests\.contract\.localization\.test_validate_localization' "localization unit contract entrypoint"
assert_file_contains tools/validate_project.sh 'python3 tools/validate_localization\.py' "localization validator entrypoint"
assert_file_contains tools/validate_project.sh '"\$\{import_stdout_log\}" "\$\{import_engine_log\}"' "import scans stdout and engine logs"

printf 'PASS: test and CI contract is satisfied (%d discovered scenes)\n' "${scene_count}"
