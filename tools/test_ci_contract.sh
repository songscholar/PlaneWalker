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

make_fake_import_godot() {
	local target="$1"
	local mode="$2"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'set -eu' \
		'if [[ "${1:-}" == "--version" ]]; then printf "4.6.1.stable.test\\n"; exit 0; fi' \
		'log_file=""' \
		'is_import=false' \
		'while (( $# > 0 )); do' \
		'  if [[ "$1" == "--log-file" ]]; then log_file="$2"; shift 2; continue; fi' \
		'  if [[ "$1" == "--import" ]]; then is_import=true; fi' \
		'  shift' \
		'done' \
		'if [[ "${is_import}" == false ]]; then printf "PASS: all assertions succeeded\\n" | tee "${log_file}"; exit 0; fi' \
		'state_file="'"${target}"'.state"' \
		'import_count=0' \
		'if [[ -f "${state_file}" ]]; then import_count="$(cat "${state_file}")"; fi' \
		'import_count=$((import_count + 1))' \
		'printf "%s\\n" "${import_count}" >"${state_file}"' \
		'write_expected_translations() {' \
		'  printf "%s\\n" \' \
		'    "ERROR: Cannot open file '\''res://data/localization/translations.en.translation'\''." \' \
		'    "ERROR: Failed loading resource: res://data/localization/translations.en.translation." \' \
		'    "ERROR: Cannot open file '\''res://data/localization/translations.zh_CN.translation'\''." \' \
		'    "ERROR: Failed loading resource: res://data/localization/translations.zh_CN.translation."' \
		'}' \
		'write_editor_warning() {' \
		'  printf "%s\\n" \' \
		'    "ERROR: Cannot save file '\''/Users/test/Library/Application Support/Godot/editor_settings-4.6.tres'\''." \' \
		'    "ERROR: Error saving editor settings to /Users/test/Library/Application Support/Godot/editor_settings-4.6.tres"' \
		'}' \
		'{' \
		'  case "'"${mode}"':${import_count}" in' \
		'    bootstrap_expected:1) write_expected_translations; write_editor_warning ;;' \
		'    bootstrap_expected:2) write_editor_warning ;;' \
		'    bootstrap_partial:1) printf "%s\\n" "ERROR: Failed loading resource: res://data/localization/translations.en.translation." ;;' \
		'    bootstrap_unexpected_resource:1) write_expected_translations; printf "%s\\n" "ERROR: Failed loading resource: res://scenes/missing_room.tscn." ;;' \
		'    clean_resource_error:1) write_expected_translations ;;' \
		'    clean_resource_error:2) printf "%s\\n" "ERROR: Failed loading resource: res://scenes/still_missing.tscn." ;;' \
		'    editor_warning_only:*) write_editor_warning ;;' \
		'    unrelated_error:1) printf "%s\\n" "ERROR: Synthetic unrelated engine failure." ;;' \
		'  esac' \
		'} >"${log_file}"' >"${target}"
	chmod +x "${target}"
}

run_fake_validation() {
	local mode="$1"
	local output_path="$2"
	local fake_godot="${TEMP_DIR}/godot-import-${mode}"
	make_fake_import_godot "${fake_godot}" "${mode}"
	SKIP_CI_CONTRACT=true \
		GODOT_BIN="${fake_godot}" \
		VALIDATION_LOG_DIR="${TEMP_DIR}/validation-${mode}" \
		TEST_LOG_DIR="${TEMP_DIR}/validation-${mode}/scene-tests" \
		tools/validate_project.sh >"${output_path}" 2>&1
	local status=$?
	return "${status}"
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
for event_contract in \
	tests/contract/events/run_lifecycle_publication_test.tscn \
	tests/contract/events/combat_event_publication_test.tscn \
	tests/contract/events/event_bus_source_contract_test.tscn; do
	grep -Fxq -- "${event_contract}" "${TEMP_DIR}/listed-scenes.txt" \
		|| fail "event contract must be included in scene discovery: ${event_contract}"
done

set +e
tools/run_tests.sh --filter definitely-not-a-real-test >/dev/null 2>&1
filter_status=$?
set -e
[[ ${filter_status} -ne 0 ]] || fail "an empty test filter must fail"

make_fake_godot "${TEMP_DIR}/godot-pass" pass
pass_output="$(GODOT_BIN="${TEMP_DIR}/godot-pass" TEST_LOG_DIR="${TEMP_DIR}/pass-logs" tools/run_tests.sh --filter seed_service_test)"
assert_contains "${pass_output}" "Scene tests: 1 passed, 0 failed" "successful scene summary"
assert_contains "${pass_output}" "Code coverage: not collected" "honest coverage summary"
[[ -f "${TEMP_DIR}/pass-logs/gdscript-coverage.json" ]] \
	|| fail "scene runner must retain a machine-readable GDScript coverage report"
python3 - "${TEMP_DIR}/pass-logs/gdscript-coverage.json" <<'PY'
import json
import sys

report = json.load(open(sys.argv[1], encoding="utf-8"))
if report.get("status") != "unavailable":
    raise SystemExit("stock runner coverage must fail closed as unavailable")
if report.get("metric") != "line" or report.get("language") != "GDScript":
    raise SystemExit("coverage report must describe GDScript line coverage")
collector = report.get("collector", {})
if collector.get("name") != "planewalker-gdscript-line-coverage":
    raise SystemExit("coverage report must identify the trusted collector")
if report.get("capabilities", {}).get("instrumented_line_hits") is not False:
    raise SystemExit("unavailable coverage must not claim instrumented line hits")
if report.get("capabilities", {}).get("scene_counts_are_coverage") is not False:
    raise SystemExit("scene counts must never be accepted as code coverage")
PY

printf '%s\n' '{"status":"collected","summary":{"covered_lines":1,"executable_lines":1}}' \
	>"${TEMP_DIR}/aggregate-only-coverage.json"
set +e
GDSCRIPT_COVERAGE_PROVIDER_REPORT="${TEMP_DIR}/aggregate-only-coverage.json" \
	GODOT_BIN="${TEMP_DIR}/godot-pass" \
	TEST_LOG_DIR="${TEMP_DIR}/invalid-coverage-logs" \
	tools/run_tests.sh --filter seed_service_test >/dev/null 2>&1
invalid_coverage_status=$?
set -e
[[ ${invalid_coverage_status} -ne 0 ]] \
	|| fail "invalid or aggregate-only coverage evidence must fail closed"

make_fake_godot "${TEMP_DIR}/godot-exit-failure" exit_failure
set +e
exit_failure_output="$(GODOT_BIN="${TEMP_DIR}/godot-exit-failure" TEST_LOG_DIR="${TEMP_DIR}/exit-failure-logs" tools/run_tests.sh --filter seed_service_test 2>&1)"
exit_failure_status=$?
set -e
[[ ${exit_failure_status} -ne 0 ]] || fail "a non-zero Godot exit must fail the suite"
assert_contains "${exit_failure_output}" "[  FAILED  ]" "non-zero exit diagnostic"
assert_contains "${exit_failure_output}" "Scene tests: 0 passed, 1 failed" "non-zero exit summary"

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
assert_file_contains tools/validate_project.sh 'python3 -m unittest tests\.contract\.documentation\.test_document_governance' "documentation unit contract entrypoint"
assert_file_contains tools/validate_project.sh 'python3 tools/document_governance\.py' "documentation validator entrypoint"
assert_file_contains tools/validate_project.sh 'tools/document_governance_baseline\.json' "documentation migration baseline"
assert_file_contains tools/validate_project.sh 'python3 -m unittest tests\.contract\.playtest\.test_playtest_data' "playtest data contract entrypoint"
assert_file_contains tools/validate_project.sh 'python3 -m unittest tests\.contract\.m1\.test_m1_gate' "M1 release gate contract entrypoint"
assert_file_contains tools/validate_project.sh 'python3 -m unittest tests\.contract\.coverage\.test_gdscript_coverage' "GDScript coverage contract entrypoint"
assert_file_contains tools/validate_project.sh 'validate_import_logs "\$\{phase\}" "\$\{stdout_log\}" "\$\{engine_log\}"' "each import scans stdout and engine logs"
assert_file_contains tools/validate_project.sh '"\$\{SCRIPT_DIR\}/run_tests\.sh"$' "validation runs the scene-test entrypoint without a partial wrapper"
if grep -Eq -- '--filter|--skip|--exclude' tools/validate_project.sh; then
	fail "validation entrypoint must not filter or exclude discovered scene tests"
fi

bootstrap_output="${TEMP_DIR}/bootstrap-expected.out"
if ! run_fake_validation bootstrap_expected "${bootstrap_output}"; then
	cat "${bootstrap_output}" >&2 || true
	fail "the exact pair of generated translation misses must bootstrap successfully"
fi
assert_contains "$(cat "${bootstrap_output}")" "generated translation resources were absent before bootstrap" "bootstrap translation classification"
assert_contains "$(cat "${bootstrap_output}")" "cannot persist global Godot editor settings" "editor settings environment warning"
assert_contains "$(cat "${bootstrap_output}")" "Discovered scene tests: ${scene_count}" "validation executes every discovered scene"
assert_contains "$(cat "${bootstrap_output}")" "Scene tests: ${scene_count} passed, 0 failed" "validation reports the complete discovered scene count"

set +e
run_fake_validation bootstrap_partial "${TEMP_DIR}/bootstrap-partial.out"
bootstrap_partial_status=$?
run_fake_validation bootstrap_unexpected_resource "${TEMP_DIR}/bootstrap-unexpected.out"
bootstrap_unexpected_status=$?
run_fake_validation clean_resource_error "${TEMP_DIR}/clean-resource-error.out"
clean_resource_error_status=$?
run_fake_validation unrelated_error "${TEMP_DIR}/unrelated-error.out"
unrelated_error_status=$?
set -e
[[ ${bootstrap_partial_status} -ne 0 ]] || fail "an incomplete generated-translation pair must fail"
[[ ${bootstrap_unexpected_status} -ne 0 ]] || fail "an unrelated bootstrap resource error must fail"
[[ ${clean_resource_error_status} -ne 0 ]] || fail "the clean second import must reject every resource error"
[[ ${unrelated_error_status} -ne 0 ]] || fail "an unclassified ERROR line must fail"

editor_warning_output="${TEMP_DIR}/editor-warning.out"
run_fake_validation editor_warning_only "${editor_warning_output}" \
	|| fail "editor settings write failures must remain an environment warning"
assert_contains "$(cat "${editor_warning_output}")" "cannot persist global Godot editor settings" "editor settings warning classification"

printf 'PASS: test and CI contract is satisfied (%d discovered scenes)\n' "${scene_count}"
