#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly DEFAULT_TIMEOUT_SECONDS=90

filter=""
list_only=false
timeout_seconds="${TEST_TIMEOUT_SECONDS:-${DEFAULT_TIMEOUT_SECONDS}}"
current_pid=""

usage() {
	cat <<'EOF'
Usage: tools/run_tests.sh [--list] [--filter TEXT] [--timeout SECONDS]

Runs every Godot scene test serially in a headless process. Test logs are
written to TEST_LOG_DIR when set, or to a temporary directory otherwise.

Environment:
  GODOT_BIN             Godot executable or command name (default: godot)
  TEST_LOG_DIR          Directory for per-scene logs
  TEST_TIMEOUT_SECONDS  Per-scene timeout (default: 90)
EOF
}

fail() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 2
}

cleanup_process() {
	if [[ -n "${current_pid}" ]] && kill -0 "${current_pid}" 2>/dev/null; then
		kill "${current_pid}" 2>/dev/null || true
		wait "${current_pid}" 2>/dev/null || true
	fi
}

trap cleanup_process INT TERM EXIT

while (( $# > 0 )); do
	case "$1" in
		--list)
			list_only=true
			shift
			;;
		--filter)
			(( $# >= 2 )) || fail "--filter requires a value"
			filter="$2"
			shift 2
			;;
		--timeout)
			(( $# >= 2 )) || fail "--timeout requires a value"
			timeout_seconds="$2"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			fail "unknown argument: $1"
			;;
	esac
done

[[ "${timeout_seconds}" =~ ^[1-9][0-9]*$ ]] || fail "timeout must be a positive integer"

test_scenes=()
while IFS= read -r scene; do
	if [[ -z "${filter}" || "${scene}" == *"${filter}"* ]]; then
		test_scenes+=("${scene}")
	fi
done < <(
	cd "${PROJECT_ROOT}"
	find tests -type f \( -name '*_test.tscn' -o -name '*_smoke.tscn' \) -print | LC_ALL=C sort
)

(( ${#test_scenes[@]} > 0 )) || fail "no test scenes matched${filter:+ filter '${filter}'}"

if [[ "${list_only}" == true ]]; then
	printf '%s\n' "${test_scenes[@]}"
	exit 0
fi

godot_command="${GODOT_BIN:-godot}"
if [[ "${godot_command}" == */* ]]; then
	[[ -x "${godot_command}" ]] || fail "Godot executable is not runnable: ${godot_command}"
	godot_bin="${godot_command}"
else
	command -v "${godot_command}" >/dev/null 2>&1 || fail "Godot executable not found: ${godot_command}"
	godot_bin="$(command -v "${godot_command}")"
fi
command -v python3 >/dev/null 2>&1 || fail "python3 is required for coverage evidence"

if [[ -n "${TEST_LOG_DIR:-}" ]]; then
	log_dir="${TEST_LOG_DIR}"
	mkdir -p "${log_dir}"
else
	log_dir="$(mktemp -d "${TMPDIR:-/tmp}/planewalker-tests.XXXXXX")"
fi
log_dir="$(cd "${log_dir}" && pwd)"

run_with_timeout() {
	local stdout_log="$1"
	local engine_log="$2"
	local scene="$3"
	local user_data_dir="$4"
	local started_at=$SECONDS
	local scene_timeout_seconds="${timeout_seconds}"
	if [[ "${scene}" == "tests/smoke/p14_dungeon_loadout_matrix_smoke_test.tscn" ]] && (( scene_timeout_seconds < 600 )); then
		scene_timeout_seconds=600
	fi
	if [[ "${scene}" == "tests/integration/save/native_combat_checkpoint_test.tscn" || "${scene}" == "tests/integration/save/local_run_records_test.tscn" || "${scene}" == "tests/integration/save/native_content_migration_test.tscn" ]] && (( scene_timeout_seconds < 300 )); then
		scene_timeout_seconds=300
	fi

	PLANEWALKER_TEST_DATA_DIR="${user_data_dir}/files" \
	PLANEWALKER_COVERAGE_SCENE_ID="${scene//\//__}" \
	XDG_DATA_HOME="${user_data_dir}" \
	XDG_CACHE_HOME="${user_data_dir}/cache" \
		"${godot_bin}" \
		--headless \
		--path "${PROJECT_ROOT}" \
		--log-file "${engine_log}" \
		"res://${scene}" >"${stdout_log}" 2>&1 &
	current_pid=$!

	while kill -0 "${current_pid}" 2>/dev/null; do
		if (( SECONDS - started_at >= scene_timeout_seconds )); then
			kill "${current_pid}" 2>/dev/null || true
			wait "${current_pid}" 2>/dev/null || true
			current_pid=""
			return 124
		fi
		sleep 0.1
	done

	wait "${current_pid}"
	local status=$?
	current_pid=""
	return "${status}"
}

log_has_runtime_failure() {
	grep -Eq \
		-e 'SCRIPT ERROR:' \
		-e 'Error calling deferred method:' \
		-e 'Parse Error:' \
		-e 'Failed to load script' \
		-e 'Failed loading resource' \
		-e 'Cannot open file .*\.gd' \
		-e 'Cannot load resource' \
		-e 'Invalid (call|get|set)(\.| )' \
		-- "$@" 2>/dev/null
}

log_has_leak() {
	grep -Eq \
		-e 'ObjectDB instances leaked at exit' \
		-e 'RID allocations leaked at exit' \
		-- "$@" 2>/dev/null
}

printf 'Godot: %s\n' "$("${godot_bin}" --version | head -1)"
printf 'Discovered scene tests: %d\n' "${#test_scenes[@]}"
printf 'Logs: %s\n' "${log_dir}"

passed=0
failed=0
for scene in "${test_scenes[@]}"; do
	safe_name="${scene//\//__}"
	safe_name="${safe_name%.tscn}"
	stdout_log="${log_dir}/${safe_name}.stdout.log"
	engine_log="${log_dir}/${safe_name}.godot.log"
	user_data_dir="${log_dir}/user-data/${safe_name}"
	mkdir -p "${user_data_dir}/cache"

	printf '[ RUN      ] %s\n' "${scene}"
	set +e
	run_with_timeout "${stdout_log}" "${engine_log}" "${scene}" "${user_data_dir}"
	status=$?
	set -e

	runtime_failure=false
	if log_has_runtime_failure "${stdout_log}" "${engine_log}"; then
		runtime_failure=true
	fi
	if log_has_leak "${stdout_log}" "${engine_log}"; then
		runtime_failure=true
		printf '[  WARNING ] %s (engine object leak)\n' "${scene}" >&2
	fi

	if (( status == 0 )) && [[ "${runtime_failure}" == false ]]; then
		((passed += 1))
		printf '[       OK ] %s\n' "${scene}"
		continue
	fi

	((failed += 1))
	if (( status == 124 )); then
		printf '[  TIMEOUT ] %s (%ss)\n' "${scene}" "${timeout_seconds}" >&2
	elif (( status != 0 )); then
		printf '[  FAILED  ] %s (exit %d)\n' "${scene}" "${status}" >&2
	else
		printf '[  FAILED  ] %s (runtime error in log)\n' "${scene}" >&2
	fi
	printf '%s\n' "--- stdout/stderr log ---" >&2
	tail -80 "${stdout_log}" >&2 || true
	printf '%s\n' "--- Godot engine log ---" >&2
	tail -80 "${engine_log}" >&2 || true
done

printf '\nScene tests: %d passed, %d failed, %d total\n' "${passed}" "${failed}" "${#test_scenes[@]}"

coverage_report="${log_dir}/gdscript-coverage.json"
coverage_command=(
	python3
	"${PROJECT_ROOT}/tools/coverage/collect_gdscript_coverage.py"
	--project-root "${PROJECT_ROOT}"
	--godot-bin "${godot_bin}"
	--output "${coverage_report}"
)
if [[ -n "${GDSCRIPT_COVERAGE_PROVIDER_REPORT:-}" ]]; then
	coverage_command+=(--provider-report "${GDSCRIPT_COVERAGE_PROVIDER_REPORT}")
fi
set +e
coverage_output="$("${coverage_command[@]}" 2>&1)"
coverage_status=$?
set -e
printf '%s\n' "${coverage_output}"

coverage_failed=false
case "${coverage_status}" in
	0|3)
		;;
	*)
		coverage_failed=true
		printf '[  FAILED  ] GDScript coverage evidence is invalid (exit %d)\n' "${coverage_status}" >&2
		;;
esac

(( failed == 0 )) && [[ "${coverage_failed}" == false ]]
