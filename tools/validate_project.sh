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
command -v python3 >/dev/null 2>&1 || fail "python3 is required for repository contracts"

if [[ -n "${VALIDATION_LOG_DIR:-}" ]]; then
	validation_log_dir="${VALIDATION_LOG_DIR}"
	mkdir -p "${validation_log_dir}"
else
	validation_log_dir="$(mktemp -d "${TMPDIR:-/tmp}/planewalker-validation.XXXXXX")"
fi
validation_log_dir="$(cd "${validation_log_dir}" && pwd)"

print_import_logs() {
	local label="$1"
	local stdout_log="$2"
	local engine_log="$3"
	printf '%s\n' "--- ${label} stdout/stderr log ---" >&2
	tail -120 "${stdout_log}" >&2 || true
	printf '%s\n' "--- ${label} Godot engine log ---" >&2
	tail -120 "${engine_log}" >&2 || true
}

validate_import_logs() {
	local phase="$1"
	local stdout_log="$2"
	local engine_log="$3"
	local errors_file="${validation_log_dir}/${phase}-import.errors.txt"
	local remaining_errors_file="${validation_log_dir}/${phase}-import.remaining-errors.txt"
	local has_editor_cannot_save=false
	local has_editor_save_error=false
	local has_macos_ca_error=false
	local has_unclassified_error=false
	local line=""

	if grep -Eq \
		-e 'SCRIPT ERROR:' \
		-e 'Error calling deferred method:' \
		-e 'Parse Error:' \
		-e 'Failed to load script' \
		-- "${stdout_log}" "${engine_log}"; then
		printf 'ERROR: %s import contains a script failure\n' "${phase}" >&2
		return 1
	fi
	if grep -Eq \
		-e 'ObjectDB instances leaked at exit' \
		-e 'RID allocations leaked at exit' \
		-- "${stdout_log}" "${engine_log}"; then
		printf 'ERROR: %s import contains an engine object leak\n' "${phase}" >&2
		return 1
	fi

	grep -h '^ERROR:' "${stdout_log}" "${engine_log}" 2>/dev/null \
		| LC_ALL=C sort -u >"${errors_file}" || true
	if ! (cd "${PROJECT_ROOT}" && PYTHONDONTWRITEBYTECODE=1 python3 -m tools.validate_import_translations \
		--project-root "${PROJECT_ROOT}" --phase "${phase}" \
		--errors-file "${errors_file}" --remaining-errors-file "${remaining_errors_file}"); then
		return 1
	fi

	while IFS= read -r line; do
		case "${line}" in
			'ERROR: Condition "ret != noErr" is true. Returning: ""')
				has_macos_ca_error=true
				;;
			*)
				if [[ "${line}" =~ ^ERROR:\ Cannot\ save\ file\ \'.*/Godot/editor_settings-[0-9.]+\.tres\'\.$ ]]; then
					has_editor_cannot_save=true
				elif [[ "${line}" =~ ^ERROR:\ Error\ saving\ editor\ settings\ to\ .*/Godot/editor_settings-[0-9.]+\.tres$ ]]; then
					has_editor_save_error=true
				else
					has_unclassified_error=true
					printf 'UNCLASSIFIED ERROR: %s\n' "${line}" >&2
				fi
				;;
		esac
	done <"${remaining_errors_file}"

	if [[ "${has_editor_cannot_save}" != "${has_editor_save_error}" ]]; then
		printf 'ERROR: incomplete editor settings environment error signature\n' >&2
		has_unclassified_error=true
	fi
	if [[ "${has_editor_cannot_save}" == true ]]; then
		printf 'ENVIRONMENT WARNING: %s import cannot persist global Godot editor settings; project validation continues.\n' "${phase}" >&2
	fi

	if [[ "${has_macos_ca_error}" == true ]]; then
		if grep -Eq 'at: get_system_ca_certificates \(platform/macos/os_macos\.mm:[0-9]+\)' "${stdout_log}" "${engine_log}"; then
			printf 'ENVIRONMENT WARNING: %s import cannot read the macOS system CA store in this sandbox; project validation continues.\n' "${phase}" >&2
		else
			printf 'ERROR: macOS CA error signature is missing its expected call site\n' >&2
			has_unclassified_error=true
		fi
	fi

	[[ "${has_unclassified_error}" == false ]]
}

run_import_phase() {
	local phase="$1"
	local stdout_log="${validation_log_dir}/${phase}-import.stdout.log"
	local engine_log="${validation_log_dir}/${phase}-import.godot.log"
	local import_status=0

	set +e
	"${godot_bin}" \
		--headless \
		--editor \
		--import \
		--path "${PROJECT_ROOT}" \
		--log-file "${engine_log}" >"${stdout_log}" 2>&1
	import_status=$?
	set -e

	if (( import_status != 0 )); then
		print_import_logs "${phase} import" "${stdout_log}" "${engine_log}"
		fail "Godot ${phase} import failed with exit ${import_status}"
	fi
	if ! validate_import_logs "${phase}" "${stdout_log}" "${engine_log}"; then
		print_import_logs "${phase} import" "${stdout_log}" "${engine_log}"
		fail "Godot ${phase} import contains an unapproved error"
	fi
}

printf 'Validation logs: %s\n' "${validation_log_dir}"
if [[ "${SKIP_CI_CONTRACT:-false}" != true ]]; then
	printf '\n== Shell and CI contract ==\n'
	"${SCRIPT_DIR}/test_ci_contract.sh"
fi

cd "${PROJECT_ROOT}"
if ! PYTHONDONTWRITEBYTECODE=1 python3 -c 'import jsonschema' >/dev/null 2>&1; then
	fail "missing Python validation dependencies; run: python3 -m pip install --requirement requirements-dev.txt"
fi
printf '\n== Documentation governance contracts ==\n'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py \
	--baseline tools/document_governance_baseline.json

printf '\n== Content schema contracts ==\n'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
	tests.contract.content_schema.test_active_item_entry_schema \
	tests.contract.content_schema.test_character_runtime_profile_schema \
	tests.contract.content_schema.test_archetype_profile_schema \
	tests.contract.content_schema.test_p14_dungeon_schemas \
	tests.contract.content_schema.test_p15_hostile_schemas \
	tests.contract.content_schema.test_p16_hub_schemas \
	tests.contract.content_schema.test_p16_profile_schemas \
	tests.contract.content_schema.test_p16_material_policy \
	tests.contract.content_schema.test_p16_narrative_sources

printf '\n== Localization contracts ==\n'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.localization.test_validate_localization
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.localization.test_import_translations
PYTHONDONTWRITEBYTECODE=1 python3 tools/validate_localization.py

printf '\n== Playtest data contracts ==\n'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.playtest.test_playtest_data
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
	tests.contract.playtest.test_weapon_simulation_report \
	tests.contract.playtest.test_character_weapon_simulation_report
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
	tests.contract.playtest.test_native_boss_matrix_report \
	tests.contract.playtest.test_synthetic_hostile_matrix_report \
	tests.contract.performance.test_native_performance_probe \
	tests.contract.test_runtime_log_validation

printf '\n== Launch pool simulation contracts ==\n'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
	tests.contract.simulation.test_launch_pool_report

printf '\n== M1 release gate contracts ==\n'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.m1.test_m1_gate

printf '\n== GDScript coverage contracts ==\n'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.coverage.test_gdscript_coverage

printf '\n== Export contracts ==\n'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
	tests.contract.export.test_export_preflight \
	tests.contract.export.test_export_executor \
	tests.contract.export.test_certify_checkout \
	tests.contract.export.test_portable_runtime
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.export.test_packaged_startup
PYTHONDONTWRITEBYTECODE=1 python3 tools/export/preflight.py \
	--mode contract \
	--json-output "${validation_log_dir}/export-preflight.json"

printf '\n== Godot bootstrap import ==\n'
run_import_phase bootstrap
printf 'PASS: bootstrap import completed with only approved generated-resource/environment diagnostics\n'

printf '\n== Godot clean second import ==\n'
run_import_phase clean
printf 'PASS: clean second import completed without project errors\n'

printf '\n== Native content pack export contracts ==\n'
PYTHONDONTWRITEBYTECODE=1 GODOT_BIN="${godot_bin}" python3 -m unittest \
	tests.contract.export.test_content_pack_source_export

printf '\n== Five-floor dungeon simulation contracts ==\n'
PYTHONDONTWRITEBYTECODE=1 GODOT_BIN="${godot_bin}" python3 -m unittest \
	tests.contract.simulation.test_dungeon_simulation_report

printf '\n== Godot scene tests ==\n'
TEST_LOG_DIR="${TEST_LOG_DIR:-${validation_log_dir}/scene-tests}" \
	GODOT_BIN="${godot_bin}" \
	"${SCRIPT_DIR}/run_tests.sh"

if [[ -n "${GDSCRIPT_COVERAGE_PYTHON:-}" ]]; then
	[[ -x "${GDSCRIPT_COVERAGE_PYTHON}" ]] || fail "coverage Python is not runnable: ${GDSCRIPT_COVERAGE_PYTHON}"
	printf '\n== Instrumented runtime line coverage ==\n'
	PYTHONDONTWRITEBYTECODE=1 GODOT_BIN="${godot_bin}" "${GDSCRIPT_COVERAGE_PYTHON}" \
		-m unittest tests.contract.coverage.test_instrumented_provider
	PYTHONDONTWRITEBYTECODE=1 "${GDSCRIPT_COVERAGE_PYTHON}" -m tools.coverage.instrumented_provider \
		--project-root "${PROJECT_ROOT}" --godot-bin "${godot_bin}" \
		--timeout "${TEST_TIMEOUT_SECONDS:-300}" \
		--output-dir "${validation_log_dir}/runtime-line-coverage"
	PYTHONDONTWRITEBYTECODE=1 python3 tools/coverage/collect_gdscript_coverage.py \
		--project-root "${PROJECT_ROOT}" --godot-bin "${godot_bin}" \
		--provider-report "${validation_log_dir}/runtime-line-coverage/provider-report.json" \
		--output "${TEST_LOG_DIR:-${validation_log_dir}/scene-tests}/gdscript-coverage.json"
fi

printf '\nPASS: project validation completed\n'
