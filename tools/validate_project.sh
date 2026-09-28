#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

fail() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 2
}

godot_command="${GODOT_BIN:-godot}"
if [[ "${godot_command}" == */* ]]; then
	[[ -x "${godot_command}" ]] || fail "Godot executable is not runnable: ${godot_command}"
	godot_bin="${godot_command}"
else
	command -v "${godot_command}" >/dev/null 2>&1 || fail "Godot executable not found: ${godot_command}"
	godot_bin="$(command -v "${godot_command}")"
fi
command -v python3 >/dev/null 2>&1 || fail "python3 is required for localization contracts"

if [[ -n "${VALIDATION_LOG_DIR:-}" ]]; then
	validation_log_dir="${VALIDATION_LOG_DIR}"
	mkdir -p "${validation_log_dir}"
else
	validation_log_dir="$(mktemp -d "${TMPDIR:-/tmp}/planewalker-validation.XXXXXX")"
fi
validation_log_dir="$(cd "${validation_log_dir}" && pwd)"

import_stdout_log="${validation_log_dir}/import.stdout.log"
import_engine_log="${validation_log_dir}/import.godot.log"

printf 'Validation logs: %s\n' "${validation_log_dir}"
printf '\n== Shell and CI contract ==\n'
"${SCRIPT_DIR}/test_ci_contract.sh"

printf '\n== Localization contracts ==\n'
cd "${PROJECT_ROOT}"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.localization.test_validate_localization
PYTHONDONTWRITEBYTECODE=1 python3 tools/validate_localization.py

printf '\n== Godot import ==\n'
set +e
"${godot_bin}" \
	--headless \
	--editor \
	--import \
	--path "${PROJECT_ROOT}" \
	--log-file "${import_engine_log}" >"${import_stdout_log}" 2>&1
import_status=$?
set -e

if (( import_status != 0 )); then
	tail -120 "${import_stdout_log}" >&2 || true
	fail "Godot import failed with exit ${import_status}"
fi

if grep -Eq \
	-e 'SCRIPT ERROR:' \
	-e 'Parse Error:' \
	-e 'Failed to load script' \
	-e 'Failed loading resource' \
	-e 'Cannot open file .*\.(gd|tscn|tres|json|csv)' \
	-e 'Cannot load resource' \
	-- "${import_stdout_log}" "${import_engine_log}"; then
	printf '%s\n' "--- stdout/stderr log ---" >&2
	tail -120 "${import_stdout_log}" >&2 || true
	printf '%s\n' "--- Godot engine log ---" >&2
	tail -120 "${import_engine_log}" >&2 || true
	fail "Godot import log contains a script or resource failure"
fi
if grep -Eq \
	-e 'ObjectDB instances leaked at exit' \
	-e 'RID allocations leaked at exit' \
	-- "${import_stdout_log}" "${import_engine_log}"; then
	printf '%s\n' "--- stdout/stderr log ---" >&2
	tail -120 "${import_stdout_log}" >&2 || true
	printf '%s\n' "--- Godot engine log ---" >&2
	tail -120 "${import_engine_log}" >&2 || true
	fail "Godot import log contains an engine object leak"
fi
printf 'PASS: Godot import completed without script/resource failures\n'

printf '\n== Godot scene tests ==\n'
TEST_LOG_DIR="${TEST_LOG_DIR:-${validation_log_dir}/scene-tests}" \
	GODOT_BIN="${godot_bin}" \
	"${SCRIPT_DIR}/run_tests.sh"

printf '\nPASS: project validation completed\n'
