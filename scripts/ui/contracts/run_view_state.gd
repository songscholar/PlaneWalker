class_name RunViewState
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const TimeAbilityIdsScript := preload("res://scripts/time_system/time_ability_ids.gd")

const SCHEMA_VERSION := 2
const PHASES: Array[String] = [
	"BOOT",
	"HUB",
	"RUN_PREPARING",
	"ROOM_ENTERING",
	"COMBAT_ACTIVE",
	"ROOM_RESOLVING",
	"SELECTION_ACTIVE",
	"ROOM_TRANSITION",
	"BOSS_ACTIVE",
	"VICTORY",
	"DEFEAT",
]


static func validate(value: Variant):
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(0, "root", "expected dictionary")
	var state := value as Dictionary
	var revision := _revision_of(state)

	if not state.has("schema_version"):
		return _failure(revision, "schema_version", "missing field")
	if not _is_integer(state["schema_version"]) or int(state["schema_version"]) != SCHEMA_VERSION:
		return _failure(revision, "schema_version", "unsupported schema version")
	if not state.has("revision") or not _is_integer(state["revision"]) or revision < 0:
		return _failure(revision, "revision", "expected non-negative integer")
	if not _is_non_empty_string(state.get("run_id")):
		return _failure(revision, "run_id", "expected non-empty string")
	if not _is_non_empty_string(state.get("phase")) or not PHASES.has(str(state["phase"])):
		return _failure(revision, "phase", "unknown phase")
	if typeof(state.get("suspended")) != TYPE_BOOL:
		return _failure(revision, "suspended", "expected boolean")
	if not _is_integer(state.get("run_time_ms")) or int(state["run_time_ms"]) < 0:
		return _failure(revision, "run_time_ms", "expected non-negative integer")

	var room_result = _validate_room(state.get("room"), revision)
	if not room_result.ok:
		return room_result
	var player_result = _validate_player(state.get("player"), revision)
	if not player_result.ok:
		return player_result
	var build_result = _validate_build(state.get("build"), revision)
	if not build_result.ok:
		return build_result
	var boss_result = _validate_boss(state.get("boss"), revision)
	if not boss_result.ok:
		return boss_result
	var flags_result = _validate_ui_flags(state.get("ui_flags"), revision)
	if not flags_result.ok:
		return flags_result

	for optional_key: String in ["selection", "result"]:
		var optional_value: Variant = state.get(optional_key)
		if optional_value != null and typeof(optional_value) != TYPE_DICTIONARY:
			return _failure(revision, optional_key, "expected dictionary or null")

	return CommandResultScript.success(revision)


static func copy_of(value: Variant) -> Dictionary:
	var validation = validate(value)
	if not validation.ok:
		return {}
	return (value as Dictionary).duplicate(true)


static func _validate_room(value: Variant, revision: int):
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(revision, "room", "expected dictionary")
	var room := value as Dictionary
	if not _is_integer(room.get("index")) or not _is_integer(room.get("total")):
		return _failure(revision, "room", "index and total must be integers")
	var index := int(room["index"])
	var total := int(room["total"])
	if total <= 0 or index <= 0 or index > total:
		return _failure(revision, "room.index", "room index must be within total")
	if not _is_non_empty_string(room.get("type")):
		return _failure(revision, "room.type", "expected non-empty string")
	if not _is_non_empty_string(room.get("title_key")):
		return _failure(revision, "room.title_key", "expected non-empty string")
	return CommandResultScript.success(revision)


static func _validate_player(value: Variant, revision: int):
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(revision, "player", "expected dictionary")
	var player := value as Dictionary
	for field: String in ["hp", "max_hp", "energy", "max_energy"]:
		if not _is_number(player.get(field)):
			return _failure(revision, "player.%s" % field, "expected number")
	var hp := float(player["hp"])
	var max_hp := float(player["max_hp"])
	var energy := float(player["energy"])
	var max_energy := float(player["max_energy"])
	if max_hp <= 0.0 or hp < 0.0 or hp > max_hp:
		return _failure(revision, "player.hp", "hp must be within maximum")
	if max_energy <= 0.0 or energy < 0.0 or energy > max_energy:
		return _failure(revision, "player.energy", "energy must be within maximum")
	if not _is_non_empty_string(player.get("action_state")):
		return _failure(revision, "player.action_state", "expected non-empty string")
	if player.has("cooldowns"):
		return _failure(revision, "player.cooldowns", "legacy cooldown dictionary is not supported")
	if typeof(player.get("time_slots")) != TYPE_ARRAY:
		return _failure(revision, "player.time_slots", "expected array")
	var time_slots := player["time_slots"] as Array
	if time_slots.size() != 2:
		return _failure(revision, "player.time_slots", "expected exactly two entries")
	var ability_ids: Array[StringName] = []
	var action_ids: Array[StringName] = []
	for index: int in range(time_slots.size()):
		var raw_slot: Variant = time_slots[index]
		if typeof(raw_slot) != TYPE_DICTIONARY:
			return _failure(revision, "player.time_slots[%d]" % index, "expected dictionary")
		var slot := raw_slot as Dictionary
		var raw_ability_id: Variant = slot.get("ability_id")
		var raw_action_id: Variant = slot.get("action_id")
		if not _is_non_empty_string(raw_ability_id) or not TimeAbilityIdsScript.is_canonical_id(raw_ability_id):
			return _failure(revision, "player.time_slots[%d].ability_id" % index, "unknown canonical ability")
		if not _is_non_empty_string(raw_action_id) or not TimeAbilityIdsScript.is_action_id(raw_action_id):
			return _failure(revision, "player.time_slots[%d].action_id" % index, "unknown input action")
		if not TimeAbilityIdsScript.pair_matches(raw_ability_id, raw_action_id):
			return _failure(revision, "player.time_slots[%d].action_id" % index, "action does not match ability")
		var ability_id := StringName(str(raw_ability_id))
		var action_id := StringName(str(raw_action_id))
		if ability_ids.has(ability_id):
			return _failure(revision, "player.time_slots", "ability ids must be distinct")
		if action_ids.has(action_id):
			return _failure(revision, "player.time_slots", "action ids must be distinct")
		if not _is_number(slot.get("cooldown")) or float(slot["cooldown"]) < 0.0:
			return _failure(revision, "player.time_slots[%d].cooldown" % index, "expected non-negative finite number")
		ability_ids.append(ability_id)
		action_ids.append(action_id)
	return CommandResultScript.success(revision)


static func _validate_build(value: Variant, revision: int):
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(revision, "build", "expected dictionary")
	var build := value as Dictionary
	for field: String in ["items", "blessings", "curses", "talents"]:
		if typeof(build.get(field)) != TYPE_ARRAY:
			return _failure(revision, "build.%s" % field, "expected array")
		for entry: Variant in build[field]:
			if not _is_non_empty_string(entry):
				return _failure(revision, "build.%s" % field, "entries must be non-empty strings")
	if typeof(build.get("dominant_archetype")) != TYPE_STRING:
		return _failure(revision, "build.dominant_archetype", "expected string")
	if typeof(build.get("archetype_scores")) != TYPE_DICTIONARY:
		return _failure(revision, "build.archetype_scores", "expected dictionary")
	for archetype: Variant in build["archetype_scores"]:
		if not _is_non_empty_string(archetype):
			return _failure(revision, "build.archetype_scores", "archetype id cannot be empty")
		var score: Variant = build["archetype_scores"][archetype]
		if not _is_number(score) or float(score) < 0.0:
			return _failure(revision, "build.archetype_scores.%s" % str(archetype), "expected non-negative number")
	return CommandResultScript.success(revision)


static func _validate_boss(value: Variant, revision: int):
	if value == null:
		return CommandResultScript.success(revision)
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(revision, "boss", "expected dictionary or null")
	var boss := value as Dictionary
	for field: String in ["boss_id", "name_key"]:
		if not _is_non_empty_string(boss.get(field)):
			return _failure(revision, "boss.%s" % field, "expected non-empty string")
	for field: String in ["hp", "max_hp"]:
		if not _is_number(boss.get(field)):
			return _failure(revision, "boss.%s" % field, "expected number")
	var hp := float(boss["hp"])
	var max_hp := float(boss["max_hp"])
	if max_hp <= 0.0 or hp < 0.0 or hp > max_hp:
		return _failure(revision, "boss.hp", "hp must be within maximum")
	if not _is_integer(boss.get("phase_index")) or not _is_integer(boss.get("phase_total")):
		return _failure(revision, "boss.phase", "phase values must be integers")
	var phase_index := int(boss["phase_index"])
	var phase_total := int(boss["phase_total"])
	if phase_total <= 0 or phase_index <= 0 or phase_index > phase_total:
		return _failure(revision, "boss.phase", "phase index must be within total")
	return CommandResultScript.success(revision)


static func _validate_ui_flags(value: Variant, revision: int):
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(revision, "ui_flags", "expected dictionary")
	var flags := value as Dictionary
	for field: String in ["show_hud", "accept_gameplay_input", "show_pause"]:
		if typeof(flags.get(field)) != TYPE_BOOL:
			return _failure(revision, "ui_flags.%s" % field, "expected boolean")
	return CommandResultScript.success(revision)


static func _failure(revision: int, field: String, detail: String):
	return CommandResultScript.failure(
		&"INVALID_ARGUMENT",
		maxi(revision, 0),
		{"field": field, "detail": detail}
	)


static func _revision_of(state: Dictionary) -> int:
	var value: Variant = state.get("revision", 0)
	return int(value) if _is_integer(value) else 0


static func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var numeric := float(value)
	return is_finite(numeric) and is_equal_approx(numeric, roundf(numeric))


static func _is_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(float(value))


static func _is_non_empty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not str(value).strip_edges().is_empty()
