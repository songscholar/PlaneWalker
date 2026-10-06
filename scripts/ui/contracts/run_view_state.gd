class_name RunViewState
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const ArchetypeProfileScript := preload("res://scripts/progression/archetype_profile.gd")
const DungeonMapViewStateScript := preload("res://scripts/ui/contracts/dungeon_map_view_state.gd")

const M1_ARCHETYPE_IDS: Array[String] = [
	"freeze_burst",
	"rewind_echo",
	"accelerated_combo",
]
const TimeAbilityIdsScript := preload("res://scripts/time_system/time_ability_ids.gd")

const SCHEMA_VERSION := 5
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
	"ROOM_ACTIVE",
]
const WEAPON_PHASES: Array[String] = [
	"READY",
	"HOLD",
	"CHANNEL",
	"WINDUP",
	"ACTIVE",
	"RESOURCE_ACTION",
	"RECOVERY",
]
const WEAPON_STATE_FIELDS: Array[String] = [
	"weapon_id",
	"action_id",
	"phase",
	"meter_kind",
	"meter_current",
	"meter_max",
	"status_id",
	"status_stacks",
	"status_remaining",
	"secondary_id",
	"secondary_value",
]
const CHARACTER_PHASES: Array[String] = [
	"READY",
	"HOLD",
	"WINDUP",
	"ACTIVE",
	"RECOVERY",
]
const CHARACTER_STATE_FIELDS: Array[String] = [
	"character_id",
	"skill_id",
	"phase",
	"cooldown_current",
	"cooldown_max",
	"meter_kind",
	"meter_current",
	"meter_max",
	"status_id",
	"status_stacks",
	"status_remaining",
	"secondary_id",
	"secondary_value",
]
const ACTIVE_ITEM_STATE_FIELDS: Array[String] = [
	"content_id",
	"name_key",
	"icon_id",
	"archetype",
	"cooldown_current",
	"cooldown_max",
	"ready",
]
const CHARACTER_CONTRACTS := {
	"wanderer": {
		"skill_id": "waypoint_recall",
		"meter_kind": "path_marks",
		"status_ids": ["ready", "wayfarer", "anchor"],
		"secondary_ids": ["", "path_progress"],
	},
	"time_guardian": {
		"skill_id": "chrono_fortress",
		"meter_kind": "ward",
		"status_ids": ["ready", "guarding", "fortress", "rebuke"],
		"secondary_ids": [""],
	},
	"void_walker": {
		"skill_id": "void_devour",
		"meter_kind": "void_debt",
		"status_ids": ["ready", "corruption", "devouring"],
		"secondary_ids": ["", "corruption_threshold"],
	},
	"primordial_knight": {
		"skill_id": "realm_cleave",
		"meter_kind": "resonance",
		"status_ids": ["ready", "armored", "echo_pending"],
		"secondary_ids": ["", "pending_echoes"],
	},
	"time_lord": {
		"skill_id": "codex_dominion",
		"meter_kind": "codex_pages",
		"status_ids": ["ready", "primer", "infusion", "dominion"],
		"secondary_ids": ["", "primer"],
	},
}
const LEGACY_CHARACTER_FIELDS: Array[String] = [
	"character",
	"path_marks",
	"ward",
	"void_debt",
	"resonance",
	"codex_pages",
	"primer_ability_id",
]
const LEGACY_WEAPON_FIELDS: Array[String] = [
	"weapon",
	"sword_state",
	"bow_state",
	"gun_state",
	"staff_state",
	"gauntlets_state",
]
const LEGACY_TOP_LEVEL_WEAPON_FIELDS: Array[String] = [
	"weapon_id",
	"action_id",
	"meter_kind",
	"meter_current",
	"meter_max",
	"status_id",
	"status_stacks",
	"status_remaining",
	"secondary_id",
	"secondary_value",
	"ammo",
	"ammo_maximum",
	"reload_frame",
	"charge_frames",
	"combo_step",
	"mana",
	"element",
	"guard",
	"counter",
]
const METER_KINDS_BY_WEAPON := {
	"sword": ["guard", "charge", "counter"],
	"bow": ["charge", "hold"],
	"gun": ["ammo", "reload"],
	"staff": ["mana", "element", "sequence"],
	"gauntlets": ["combo", "timeout", "counter"],
}
const STATUS_IDS_BY_WEAPON := {
	"sword": ["ready", "acting", "guarding", "charging", "counter_ready"],
	"bow": ["ready", "acting", "charging", "full_charge", "holding"],
	"gun": ["ready", "acting", "reloading", "perfect_reload", "time_load"],
	"staff": ["ready", "acting", "channeling", "element_fire", "element_ice", "element_lightning", "sequence_ready"],
	"gauntlets": ["ready", "acting", "counter_ready", "combo_active"],
}
const STATUS_IDS_BY_METER := {
	"sword": {
		"guard": ["ready", "acting", "guarding"],
		"charge": ["ready", "acting", "charging"],
		"counter": ["ready", "acting", "counter_ready"],
	},
	"bow": {
		"charge": ["ready", "acting", "charging", "full_charge"],
		"hold": ["ready", "acting", "holding"],
	},
	"gun": {
		"ammo": ["ready", "acting", "time_load"],
		"reload": ["reloading", "perfect_reload"],
	},
	"staff": {
		"mana": ["ready", "acting", "channeling", "element_fire", "element_ice", "element_lightning", "sequence_ready"],
		"element": ["ready", "acting", "element_fire", "element_ice", "element_lightning"],
		"sequence": ["ready", "acting", "sequence_ready"],
	},
	"gauntlets": {
		"combo": ["ready", "acting", "combo_active"],
		"timeout": ["ready", "acting", "combo_active"],
		"counter": ["ready", "acting", "counter_ready"],
	},
}
const SECONDARY_IDS_BY_WEAPON := {
	"sword": ["", "combo", "counter"],
	"bow": ["", "hold"],
	"gun": ["", "time_load", "reload_window"],
	"staff": ["", "element", "sequence"],
	"gauntlets": ["", "combo", "timeout", "counter"],
}


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
	if state.has("dungeon_state"):
		var dungeon_validation = DungeonMapViewStateScript.validate(state["dungeon_state"])
		if not dungeon_validation.ok:
			return _failure(revision, "dungeon_state", "invalid dungeon projection")
		if str(state["dungeon_state"]["run_id"]) != str(state["run_id"]):
			return _failure(revision, "dungeon_state.run_id", "run identity mismatch")
	for legacy_field: String in LEGACY_WEAPON_FIELDS:
		if state.has(legacy_field):
			return _failure(revision, legacy_field, "legacy weapon field is not supported")
	for legacy_field: String in LEGACY_TOP_LEVEL_WEAPON_FIELDS:
		if state.has(legacy_field):
			return _failure(revision, legacy_field, "weapon state must use the weapon_state union")
	for legacy_field: String in LEGACY_CHARACTER_FIELDS:
		if state.has(legacy_field):
			return _failure(revision, legacy_field, "character state must use the character_state union")

	var room_result = _validate_room(state.get("room"), revision)
	if not room_result.ok:
		return room_result
	if str(state.room.type) == "entry" and str(state.phase) != "ROOM_ACTIVE":
		return _failure(revision, "room.type", "entry requires the active dungeon-entry phase")
	var player_result = _validate_player(state.get("player"), revision)
	if not player_result.ok:
		return player_result
	var weapon_result = _validate_weapon_state(state.get("weapon_state"), revision)
	if not weapon_result.ok:
		return weapon_result
	if not state.has("character_state"):
		return _failure(revision, "character_state", "missing field")
	var character_result = _validate_character_state(state["character_state"], revision)
	if not character_result.ok:
		return character_result
	if not state.has("active_item_state"):
		return _failure(revision, "active_item_state", "missing field")
	var active_item_result = _validate_active_item_state(state["active_item_state"], revision)
	if not active_item_result.ok:
		return active_item_result
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


static func _validate_active_item_state(value: Variant, revision: int):
	if value == null:
		return CommandResultScript.success(revision)
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(revision, "active_item_state", "expected dictionary or null")
	var active := value as Dictionary
	if active.size() != ACTIVE_ITEM_STATE_FIELDS.size():
		return _failure(revision, "active_item_state", "unexpected field count")
	for field: String in ACTIVE_ITEM_STATE_FIELDS:
		if not active.has(field):
			return _failure(revision, "active_item_state.%s" % field, "missing field")
	for field: String in ["content_id", "name_key", "icon_id"]:
		if not _is_non_empty_string(active[field]):
			return _failure(revision, "active_item_state.%s" % field, "expected non-empty string")
	var archetype := str(active.get("archetype", ""))
	if not ArchetypeProfileScript.ARCHETYPE_IDS.has(archetype):
		return _failure(revision, "active_item_state.archetype", "unknown archetype")
	if (
		not _is_integer(active.get("cooldown_current"))
		or not _is_integer(active.get("cooldown_max"))
	):
		return _failure(revision, "active_item_state.cooldown_current", "expected integer frames")
	var cooldown_current := int(active["cooldown_current"])
	var cooldown_max := int(active["cooldown_max"])
	if cooldown_max <= 0 or cooldown_current < 0 or cooldown_current > cooldown_max:
		return _failure(revision, "active_item_state.cooldown_current", "cooldown outside maximum")
	if typeof(active.get("ready")) != TYPE_BOOL:
		return _failure(revision, "active_item_state.ready", "expected boolean")
	if bool(active["ready"]) != (cooldown_current == 0):
		return _failure(revision, "active_item_state.ready", "ready must match cooldown")
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
	var entry := str(room.get("type", "")) == "entry"
	if total <= 0 or index < 0 or index > total or (index == 0 and not entry) or (entry and index != 0):
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
	for legacy_field: String in LEGACY_WEAPON_FIELDS:
		if player.has(legacy_field):
			return _failure(revision, "player.%s" % legacy_field, "raw weapon state is not supported")
	if player.has("weapon_state"):
		return _failure(revision, "player.weapon_state", "weapon state must be top-level")
	if player.has("character") or player.has("character_state"):
		return _failure(revision, "player.character_state", "character state must be top-level")
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


static func _validate_character_state(value: Variant, revision: int):
	if value == null:
		return CommandResultScript.success(revision)
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(revision, "character_state", "expected dictionary or null")
	var character := value as Dictionary
	for field: String in CHARACTER_STATE_FIELDS:
		if not character.has(field):
			return _failure(revision, "character_state.%s" % field, "missing field")
	for raw_field: Variant in character:
		var field := str(raw_field)
		if not CHARACTER_STATE_FIELDS.has(field):
			return _failure(revision, "character_state.%s" % field, "unexpected field")

	var character_id := str(character.get("character_id", ""))
	if not _is_non_empty_string(character.get("character_id")) or not CHARACTER_CONTRACTS.has(character_id):
		return _failure(revision, "character_state.character_id", "unknown character")
	var contract := CHARACTER_CONTRACTS[character_id] as Dictionary
	if str(character.get("skill_id", "")) != str(contract["skill_id"]):
		return _failure(revision, "character_state.skill_id", "skill is not supported by character")
	if not _is_non_empty_string(character.get("phase")) or not CHARACTER_PHASES.has(str(character["phase"])):
		return _failure(revision, "character_state.phase", "unknown phase")
	if not _is_number(character.get("cooldown_current")) or not _is_number(character.get("cooldown_max")):
		return _failure(revision, "character_state.cooldown_current", "cooldown values must be finite numbers")
	var cooldown_current := float(character["cooldown_current"])
	var cooldown_max := float(character["cooldown_max"])
	if cooldown_max <= 0.0 or cooldown_current < 0.0 or cooldown_current > cooldown_max:
		return _failure(revision, "character_state.cooldown_current", "cooldown must be within a positive maximum")

	if str(character.get("meter_kind", "")) != str(contract["meter_kind"]):
		return _failure(revision, "character_state.meter_kind", "meter is not supported by character")
	if not _is_number(character.get("meter_current")) or not _is_number(character.get("meter_max")):
		return _failure(revision, "character_state.meter_current", "meter values must be finite numbers")
	var meter_current := float(character["meter_current"])
	var meter_max := float(character["meter_max"])
	if meter_max <= 0.0 or meter_current < 0.0 or meter_current > meter_max:
		return _failure(revision, "character_state.meter_current", "meter must be within a positive maximum")

	var status_id := str(character.get("status_id", ""))
	if not _is_non_empty_string(character.get("status_id")) or not (contract["status_ids"] as Array).has(status_id):
		return _failure(revision, "character_state.status_id", "status is not supported by character")
	if not _is_integer(character.get("status_stacks")) or int(character["status_stacks"]) < 0:
		return _failure(revision, "character_state.status_stacks", "expected non-negative integer")
	if not _is_number(character.get("status_remaining")) or float(character["status_remaining"]) < 0.0:
		return _failure(revision, "character_state.status_remaining", "expected non-negative finite number")
	if status_id == "ready" and int(character["status_stacks"]) != 0:
		return _failure(revision, "character_state.status_stacks", "ready status cannot carry stacks")
	if status_id != "ready" and int(character["status_stacks"]) <= 0:
		return _failure(revision, "character_state.status_stacks", "active status requires a stack")
	if status_id in ["wayfarer", "anchor", "fortress", "rebuke", "corruption", "primer", "infusion", "dominion"] and float(character["status_remaining"]) <= 0.0:
		return _failure(revision, "character_state.status_remaining", "timed status requires remaining time")

	if typeof(character.get("secondary_id")) != TYPE_STRING:
		return _failure(revision, "character_state.secondary_id", "expected string")
	var secondary_id := str(character["secondary_id"])
	if not (contract["secondary_ids"] as Array).has(secondary_id):
		return _failure(revision, "character_state.secondary_id", "secondary state is not supported by character")
	var secondary_value: Variant = character["secondary_value"]
	if secondary_id == "primer":
		if character_id != "time_lord" or not TimeAbilityIdsScript.is_canonical_id(secondary_value):
			return _failure(revision, "character_state.secondary_value", "Primer requires a canonical ability id")
		if status_id != "primer":
			return _failure(revision, "character_state.secondary_id", "Primer secondary requires Primer status")
	else:
		if not _is_number(secondary_value) or float(secondary_value) < 0.0:
			return _failure(revision, "character_state.secondary_value", "expected non-negative finite number")
		if secondary_id.is_empty() and not is_zero_approx(float(secondary_value)):
			return _failure(revision, "character_state.secondary_value", "empty secondary state must be zero")

	return CommandResultScript.success(revision)


static func _validate_weapon_state(value: Variant, revision: int):
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(revision, "weapon_state", "expected dictionary")
	var weapon := value as Dictionary
	for field: String in WEAPON_STATE_FIELDS:
		if not weapon.has(field):
			return _failure(revision, "weapon_state.%s" % field, "missing field")
	for raw_field: Variant in weapon:
		var field := str(raw_field)
		if not WEAPON_STATE_FIELDS.has(field):
			return _failure(revision, "weapon_state.%s" % field, "unexpected field")

	var weapon_id := str(weapon.get("weapon_id", ""))
	if not _is_non_empty_string(weapon.get("weapon_id")) or not METER_KINDS_BY_WEAPON.has(weapon_id):
		return _failure(revision, "weapon_state.weapon_id", "unknown weapon")
	if typeof(weapon.get("action_id")) != TYPE_STRING:
		return _failure(revision, "weapon_state.action_id", "expected string")
	var action_id := str(weapon["action_id"])
	if not _is_non_empty_string(weapon.get("phase")) or not WEAPON_PHASES.has(str(weapon["phase"])):
		return _failure(revision, "weapon_state.phase", "unknown phase")
	var phase := str(weapon["phase"])
	if phase == "READY" and not action_id.is_empty():
		return _failure(revision, "weapon_state.action_id", "ready phase cannot expose an active action")
	if phase != "READY" and action_id.is_empty():
		return _failure(revision, "weapon_state.action_id", "active phase requires an action")

	if not _is_non_empty_string(weapon.get("meter_kind")):
		return _failure(revision, "weapon_state.meter_kind", "expected non-empty string")
	var meter_kind := str(weapon["meter_kind"])
	var allowed_meters := METER_KINDS_BY_WEAPON[weapon_id] as Array
	if not allowed_meters.has(meter_kind):
		return _failure(revision, "weapon_state.meter_kind", "meter is not supported by weapon")
	if not _is_number(weapon.get("meter_current")) or not _is_number(weapon.get("meter_max")):
		return _failure(revision, "weapon_state.meter_current", "meter values must be finite numbers")
	var meter_current := float(weapon["meter_current"])
	var meter_max := float(weapon["meter_max"])
	if meter_max <= 0.0 or meter_current < 0.0 or meter_current > meter_max:
		return _failure(revision, "weapon_state.meter_current", "meter must be within a positive maximum")
	if weapon_id == "gun" and meter_kind in ["ammo", "reload"]:
		if not _is_integer(weapon["meter_current"]) or not _is_integer(weapon["meter_max"]):
			return _failure(revision, "weapon_state.meter_current", "Gun meter values must be integers")

	if not _is_non_empty_string(weapon.get("status_id")):
		return _failure(revision, "weapon_state.status_id", "expected non-empty string")
	var status_id := str(weapon["status_id"])
	var allowed_statuses := STATUS_IDS_BY_WEAPON[weapon_id] as Array
	if not allowed_statuses.has(status_id):
		return _failure(revision, "weapon_state.status_id", "status is not supported by weapon")
	var statuses_by_meter := STATUS_IDS_BY_METER[weapon_id] as Dictionary
	var allowed_meter_statuses := statuses_by_meter[meter_kind] as Array
	if not allowed_meter_statuses.has(status_id):
		return _failure(revision, "weapon_state.status_id", "status is not supported by weapon meter")
	if not _is_integer(weapon.get("status_stacks")) or int(weapon["status_stacks"]) < 0:
		return _failure(revision, "weapon_state.status_stacks", "expected non-negative integer")
	if not _is_number(weapon.get("status_remaining")) or float(weapon["status_remaining"]) < 0.0:
		return _failure(revision, "weapon_state.status_remaining", "expected non-negative finite number")
	if status_id in ["ready", "acting"] and int(weapon["status_stacks"]) != 0:
		return _failure(revision, "weapon_state.status_stacks", "neutral status cannot carry stacks")
	if status_id not in ["ready", "acting"] and int(weapon["status_stacks"]) <= 0:
		return _failure(revision, "weapon_state.status_stacks", "active status requires a stack")

	if typeof(weapon.get("secondary_id")) != TYPE_STRING:
		return _failure(revision, "weapon_state.secondary_id", "expected string")
	var secondary_id := str(weapon["secondary_id"])
	var allowed_secondaries := SECONDARY_IDS_BY_WEAPON[weapon_id] as Array
	if not allowed_secondaries.has(secondary_id):
		return _failure(revision, "weapon_state.secondary_id", "secondary state is not supported by weapon")
	if not _is_number(weapon.get("secondary_value")) or float(weapon["secondary_value"]) < 0.0:
		return _failure(revision, "weapon_state.secondary_value", "expected non-negative finite number")
	if secondary_id.is_empty() and not is_zero_approx(float(weapon["secondary_value"])):
		return _failure(revision, "weapon_state.secondary_value", "empty secondary state must be zero")

	if weapon_id == "gun":
		if meter_kind == "reload" and action_id != "reload":
			return _failure(revision, "weapon_state.meter_kind", "reload meter requires reload action")
		if status_id == "time_load" and secondary_id == "time_load":
			return _failure(revision, "weapon_state.secondary_id", "Time Load cannot be duplicated")
	if weapon_id == "staff":
		if secondary_id != "element" or not _is_integer(weapon["secondary_value"]):
			return _failure(revision, "weapon_state.secondary_id", "Staff Mana state requires an integer element code")
		var element_code := int(weapon["secondary_value"])
		if element_code < 1 or element_code > 3:
			return _failure(revision, "weapon_state.secondary_value", "unknown Staff element code")
		var status_element_codes := {
			"element_fire": 1,
			"element_ice": 2,
			"element_lightning": 3,
		}
		if status_element_codes.has(status_id) and int(status_element_codes[status_id]) != element_code:
			return _failure(revision, "weapon_state.status_id", "Staff element status must match the element code")
		if status_id == "sequence_ready" and float(weapon["status_remaining"]) <= 0.0:
			return _failure(revision, "weapon_state.status_remaining", "Staff sequence window must have remaining time")

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
	var scores: Dictionary = build["archetype_scores"]
	var archetype_order: Array[String] = []
	if _has_exact_keys(scores, M1_ARCHETYPE_IDS):
		archetype_order = M1_ARCHETYPE_IDS
	elif _has_exact_keys(scores, ArchetypeProfileScript.ARCHETYPE_IDS):
		archetype_order = ArchetypeProfileScript.ARCHETYPE_IDS
	else:
		return _failure(revision, "build.archetype_scores", "unexpected archetype domain")
	for archetype: Variant in scores:
		if not _is_non_empty_string(archetype):
			return _failure(revision, "build.archetype_scores", "archetype id cannot be empty")
		var score: Variant = scores[archetype]
		if not _is_integer(score) or int(score) < 0:
			return _failure(revision, "build.archetype_scores.%s" % str(archetype), "expected non-negative integer")
	var dominant_archetype := str(build["dominant_archetype"])
	var expected_dominant := ""
	var highest_score := 0
	for archetype_id: String in archetype_order:
		var score := int(scores[archetype_id])
		if score > highest_score:
			highest_score = score
			expected_dominant = archetype_id
	if dominant_archetype != expected_dominant:
		return _failure(revision, "build.dominant_archetype", "must match canonical score order")
	return CommandResultScript.success(revision)


static func _has_exact_keys(values: Dictionary, expected: Array[String]) -> bool:
	if values.size() != expected.size():
		return false
	for key: String in expected:
		if not values.has(key):
			return false
	return true


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
