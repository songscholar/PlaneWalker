class_name ModeCombatHudViewState
extends RefCounted

const RunView := preload("res://scripts/ui/contracts/run_view_state.gd")
const Result := preload("res://scripts/application/command_result.gd")
const FIELDS := ["schema_version", "revision", "run_id", "mode_id", "stage_index", "stage_total", "elapsed_frames", "suspended", "player", "weapon_state", "character_state", "active_item_state", "boss"]
const MODES := ["boss_rush", "daily", "authored", "endless"]


static func validate(value: Variant):
	if not value is Dictionary or value.size() != FIELDS.size():
		return Result.failure(&"INVALID_ARGUMENT", 0, {"field": "root"})
	for field: String in FIELDS:
		if not value.has(field):
			return Result.failure(&"INVALID_ARGUMENT", 0, {"field": field})
	for field: String in ["schema_version", "revision", "stage_index", "stage_total", "elapsed_frames"]:
		if not value[field] is int or value[field] < 0:
			return Result.failure(&"INVALID_ARGUMENT", 0, {"field": field})
	var revision: int = value.revision
	if value.schema_version != 1 or not value.run_id is String or value.run_id.strip_edges().is_empty() or value.mode_id not in MODES or not value.suspended is bool or value.stage_total < 1 or value.stage_index >= value.stage_total:
		return Result.failure(&"INVALID_ARGUMENT", revision, {"field": "metadata"})
	for validation in [
		RunView._validate_player(value.player, revision),
		RunView._validate_weapon_state(value.weapon_state, revision),
		RunView._validate_character_state(value.character_state, revision),
		RunView._validate_active_item_state(value.active_item_state, revision),
		RunView._validate_boss(value.boss, revision),
	]:
		if not validation.ok:
			return Result.failure(&"INVALID_ARGUMENT", revision, validation.context.duplicate(true))
	return Result.success(revision)
