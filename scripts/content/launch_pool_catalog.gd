class_name LaunchPoolCatalog
extends RefCounted

const ArchetypeProfileScript := preload("res://scripts/progression/archetype_profile.gd")

const SCHEMA_VERSION := 1
const ROOT_FIELDS: Array[String] = ["schema_version", "items", "blessings", "curses", "talents"]
const ITEM_FIELDS: Array[String] = ["id", "item_mode", "archetype", "role"]
const ROUTE_FIELDS: Array[String] = ["id", "archetype", "role"]
const TALENT_FIELDS: Array[String] = ["id", "character_id"]
const ITEM_MODES: Array[String] = ["passive", "active"]
const PASSIVE_ROUTE_ROLES: Array[String] = ["starter", "payoff"]
const ROUTE_ROLES: Array[String] = ["starter", "payoff"]
const EXACT_ITEM_ROWS: Array[String] = [
	"frozen_burst|passive|freeze_burst|starter",
	"stasis_lens|passive|freeze_burst|starter",
	"brittle_clock|passive|freeze_burst|starter",
	"weakpoint_prism|passive|freeze_burst|payoff",
	"frozen_afterimage|passive|freeze_burst|payoff",
	"absolute_zero_device|active|freeze_burst|risk",
	"rewind_echo|passive|rewind_echo|starter",
	"anchor_thread|passive|rewind_echo|starter",
	"history_blade|passive|rewind_echo|starter",
	"echo_reservoir|passive|rewind_echo|payoff",
	"pathbreaker_lens|passive|rewind_echo|payoff",
	"paradox_beacon|active|rewind_echo|risk",
	"rift_engine|passive|rift_trap|starter",
	"rift_anchor|passive|rift_trap|starter",
	"folded_corridor|passive|rift_trap|starter",
	"rift_conductor|passive|rift_trap|payoff",
	"rift_snare|passive|rift_trap|payoff",
	"gravity_snare_device|active|rift_trap|risk",
	"accelerated_combo|passive|accelerated_combo|starter",
	"cadence_core|passive|accelerated_combo|starter",
	"overdrive_heart|passive|accelerated_combo|starter",
	"accelerant_window|passive|accelerated_combo|payoff",
	"efficient_overdrive|passive|accelerated_combo|payoff",
	"redline_injector|active|accelerated_combo|risk",
	"void_brink|passive|low_hp_void|starter",
	"void_contract|passive|low_hp_void|starter",
	"hunger_edge|passive|low_hp_void|payoff",
	"abyssal_siphon|passive|low_hp_void|payoff",
	"blood_price_relic|active|low_hp_void|risk",
	"cleaving_moment|passive|perfect_guard|starter",
	"evasive_guard_route|passive|perfect_guard|starter",
	"counter_battery|passive|perfect_guard|payoff",
	"warded_edge|passive|perfect_guard|payoff",
	"aegis_reversal|active|perfect_guard|risk",
	"piercing_draw|passive|piercing_barrage|starter",
	"tempo_barrage|passive|piercing_barrage|starter",
	"focused_draw|passive|piercing_barrage|payoff",
	"ricochet_matrix|passive|piercing_barrage|payoff",
	"railshot_module|active|piercing_barrage|risk",
	"mirror_seed|passive|echo_legion|starter",
	"phantom_lens|passive|echo_legion|starter",
	"legion_core|passive|echo_legion|payoff",
	"decoy_crown|passive|echo_legion|payoff",
	"army_of_yesterday|active|echo_legion|risk",
	"chronal_battery|passive||utility",
	"quickened_blade|passive||utility",
	"rewind_salve|passive||utility",
	"rift_current|passive||utility",
	"sword_edge|passive||utility",
	"tempered_guard|passive||utility",
]
const EXACT_BLESSING_ROWS: Array[String] = [
	"bls_stop_weakpoint|freeze_burst|payoff",
	"bls_stasis_shatter|freeze_burst|starter",
	"bls_cold_execution|freeze_burst|payoff",
	"bls_rewind_path|rewind_echo|payoff",
	"bls_anchor_memory|rewind_echo|starter",
	"bls_echo_harvest|rewind_echo|payoff",
	"bls_folded_ground|rift_trap|starter",
	"bls_projectile_slow|rift_trap|payoff",
	"bls_rift_bloom|rift_trap|payoff",
	"bls_sword_tempo|accelerated_combo|payoff",
	"bls_cadence_chain|accelerated_combo|starter",
	"bls_overdrive_refund|accelerated_combo|payoff",
	"bls_void_threshold|low_hp_void|starter",
	"bls_hunger_conversion|low_hp_void|payoff",
	"bls_bloodless_focus|low_hp_void|payoff",
	"bls_counter_window|perfect_guard|starter",
	"bls_guard_reserve|perfect_guard|payoff",
	"bls_aegis_tempo|perfect_guard|payoff",
	"bls_piercing_line|piercing_barrage|starter",
	"bls_weakpoint_refund|piercing_barrage|payoff",
	"bls_ballistic_clock|piercing_barrage|payoff",
	"bls_mirror_action|echo_legion|starter",
	"bls_legion_focus|echo_legion|payoff",
	"bls_decoy_stride|echo_legion|payoff",
	"bls_survive_thread||utility",
	"bls_chronal_reserve||utility",
	"bls_wayfinder_mercy||utility",
	"bls_adaptive_arsenal||utility",
]
const EXACT_CURSE_ROWS: Array[String] = [
	"curse_stasis_fracture|freeze_burst|risk",
	"curse_thaw_debt|freeze_burst|risk",
	"curse_blood_memory|rewind_echo|risk",
	"curse_erased_present|rewind_echo|risk",
	"curse_starved_horizon|rift_trap|risk",
	"curse_folded_hunger|rift_trap|risk",
	"curse_glass_cadence|accelerated_combo|risk",
	"curse_burnout_clock|accelerated_combo|risk",
	"curse_brittle_pact|low_hp_void|risk",
	"curse_empty_veins|low_hp_void|risk",
	"curse_narrow_counter|perfect_guard|risk",
	"curse_shattered_aegis|perfect_guard|risk",
	"curse_recoil_tax|piercing_barrage|risk",
	"curse_empty_magazine|piercing_barrage|risk",
	"curse_divided_self|echo_legion|risk",
	"curse_phantom_attention|echo_legion|risk",
	"curse_fickle_time||utility",
	"curse_brittle_fortune||utility",
]
const EXACT_TALENT_ROWS: Array[String] = [
	"tal_eternity_reserve|wanderer",
	"tal_ruin_execute|wanderer",
	"tal_steel_recover|wanderer",
	"widened_guard|time_guardian",
	"fortress_core|time_guardian",
	"temporal_rebuke|time_guardian",
	"deep_debt|void_walker",
	"bounded_devour|void_walker",
	"risk_step|void_walker",
	"resonant_plate|primordial_knight",
	"echo_forge|primordial_knight",
	"realm_collapse|primordial_knight",
	"codex_margin|time_lord",
	"efficient_inscription|time_lord",
	"dominion_cadence|time_lord",
]
const CHARACTER_IDS: Array[String] = [
	"wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord",
]
const TALENT_CHARACTER_BY_ID := {
	"tal_eternity_reserve": "wanderer",
	"tal_ruin_execute": "wanderer",
	"tal_steel_recover": "wanderer",
	"widened_guard": "time_guardian",
	"fortress_core": "time_guardian",
	"temporal_rebuke": "time_guardian",
	"deep_debt": "void_walker",
	"bounded_devour": "void_walker",
	"risk_step": "void_walker",
	"resonant_plate": "primordial_knight",
	"echo_forge": "primordial_knight",
	"realm_collapse": "primordial_knight",
	"codex_margin": "time_lord",
	"efficient_inscription": "time_lord",
	"dominion_cadence": "time_lord",
}

var _snapshot: Dictionary = {}


func configure(source: Dictionary) -> Dictionary:
	_snapshot.clear()
	if not _has_exact_fields(source, ROOT_FIELDS):
		return _failure("root", "fields")
	if (
		typeof(source["schema_version"]) not in [TYPE_INT, TYPE_FLOAT]
		or float(source["schema_version"]) != float(SCHEMA_VERSION)
	):
		return _failure("schema_version", "unsupported")
	for field: String in ["items", "blessings", "curses", "talents"]:
		if not source[field] is Array:
			return _failure(field, "type")
	if (source["items"] as Array).size() != EXACT_ITEM_ROWS.size():
		return _failure("items", "count")
	if (source["blessings"] as Array).size() != EXACT_BLESSING_ROWS.size():
		return _failure("blessings", "count")
	if (source["curses"] as Array).size() != EXACT_CURSE_ROWS.size():
		return _failure("curses", "count")
	if (source["talents"] as Array).size() != EXACT_TALENT_ROWS.size():
		return _failure("talents", "count")

	var seen: Dictionary = {}
	var item_result := _normalize_items(source["items"] as Array, seen)
	if not bool(item_result.get("ok", false)):
		return item_result
	var blessing_result := _normalize_routes(
		source["blessings"] as Array,
		seen,
		"blessings",
		ROUTE_ROLES
	)
	if not bool(blessing_result.get("ok", false)):
		return blessing_result
	var curse_result := _normalize_routes(
		source["curses"] as Array,
		seen,
		"curses",
		["risk"]
	)
	if not bool(curse_result.get("ok", false)):
		return curse_result
	var talent_result := _normalize_talents(source["talents"] as Array, seen)
	if not bool(talent_result.get("ok", false)):
		return talent_result
	for exact_case: Dictionary in [
		{"field": "items", "rows": item_result["rows"], "fields": ITEM_FIELDS, "expected": EXACT_ITEM_ROWS},
		{"field": "blessings", "rows": blessing_result["rows"], "fields": ROUTE_FIELDS, "expected": EXACT_BLESSING_ROWS},
		{"field": "curses", "rows": curse_result["rows"], "fields": ROUTE_FIELDS, "expected": EXACT_CURSE_ROWS},
		{"field": "talents", "rows": talent_result["rows"], "fields": TALENT_FIELDS, "expected": EXACT_TALENT_ROWS},
	]:
		var exact_error := _exact_rows_error(
			exact_case["rows"] as Array,
			exact_case["fields"] as Array[String],
			exact_case["expected"] as Array[String],
			str(exact_case["field"])
		)
		if not exact_error.is_empty():
			return exact_error

	_snapshot = {
		"schema_version": SCHEMA_VERSION,
		"items": item_result["rows"],
		"blessings": blessing_result["rows"],
		"curses": curse_result["rows"],
		"talents": talent_result["rows"],
	}
	return {"ok": true, "context": {}}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func _normalize_items(rows: Array, seen: Dictionary) -> Dictionary:
	var normalized: Array[Dictionary] = []
	var active_by_archetype: Dictionary = {}
	var passive_count := 0
	var active_count := 0
	for index: int in range(rows.size()):
		var row_value: Variant = rows[index]
		if not row_value is Dictionary or not _has_exact_fields(row_value as Dictionary, ITEM_FIELDS):
			return _failure("items", "row_fields", {"index": index})
		var row: Dictionary = row_value
		var id_result := _claim_id(row["id"], seen, "items", index)
		if not bool(id_result.get("ok", false)):
			return id_result
		if typeof(row["item_mode"]) != TYPE_STRING or not ITEM_MODES.has(str(row["item_mode"])):
			return _failure("items.item_mode", "value", {"index": index})
		if typeof(row["archetype"]) != TYPE_STRING or typeof(row["role"]) != TYPE_STRING:
			return _failure("items", "type", {"index": index})
		var archetype := str(row["archetype"])
		var role := str(row["role"])
		var item_mode := str(row["item_mode"])
		if archetype.is_empty():
			if item_mode != "passive" or role != "utility":
				return _failure("items", "utility_contract", {"index": index})
		elif not ArchetypeProfileScript.ARCHETYPE_IDS.has(archetype):
			return _failure("items.archetype", "unknown", {"index": index})
		elif item_mode == "active":
			if role != "risk" or active_by_archetype.has(archetype):
				return _failure("items", "active_route", {"index": index})
			active_by_archetype[archetype] = true
		else:
			if not PASSIVE_ROUTE_ROLES.has(role):
				return _failure("items.role", "unsupported", {"index": index})
		if item_mode == "active":
			active_count += 1
		else:
			passive_count += 1
		normalized.append({
			"id": str(row["id"]),
			"item_mode": item_mode,
			"archetype": archetype,
			"role": role,
		})
	if passive_count != 42 or active_count != 8:
		return _failure("items", "mode_counts")
	for archetype: String in ArchetypeProfileScript.ARCHETYPE_IDS:
		if not active_by_archetype.has(archetype):
			return _failure("items", "active_route_missing", {"archetype": archetype})
	return {"ok": true, "rows": normalized, "context": {}}


func _normalize_routes(
	rows: Array,
	seen: Dictionary,
	field: String,
	allowed_route_roles: Array[String]
) -> Dictionary:
	var normalized: Array[Dictionary] = []
	for index: int in range(rows.size()):
		var row_value: Variant = rows[index]
		if not row_value is Dictionary or not _has_exact_fields(row_value as Dictionary, ROUTE_FIELDS):
			return _failure(field, "row_fields", {"index": index})
		var row: Dictionary = row_value
		var id_result := _claim_id(row["id"], seen, field, index)
		if not bool(id_result.get("ok", false)):
			return id_result
		if typeof(row["archetype"]) != TYPE_STRING or typeof(row["role"]) != TYPE_STRING:
			return _failure(field, "type", {"index": index})
		var archetype := str(row["archetype"])
		var role := str(row["role"])
		if archetype.is_empty():
			if role != "utility":
				return _failure(field, "utility_contract", {"index": index})
		elif not ArchetypeProfileScript.ARCHETYPE_IDS.has(archetype):
			return _failure("%s.archetype" % field, "unknown", {"index": index})
		elif not allowed_route_roles.has(role):
			return _failure("%s.role" % field, "unsupported", {"index": index})
		normalized.append({
			"id": str(row["id"]),
			"archetype": archetype,
			"role": role,
		})
	return {"ok": true, "rows": normalized, "context": {}}


func _normalize_talents(rows: Array, seen: Dictionary) -> Dictionary:
	var normalized: Array[Dictionary] = []
	var count_by_character: Dictionary = {}
	for index: int in range(rows.size()):
		var row_value: Variant = rows[index]
		if not row_value is Dictionary or not _has_exact_fields(row_value as Dictionary, TALENT_FIELDS):
			return _failure("talents", "row_fields", {"index": index})
		var row: Dictionary = row_value
		var id_result := _claim_id(row["id"], seen, "talents", index)
		if not bool(id_result.get("ok", false)):
			return id_result
		if typeof(row["character_id"]) != TYPE_STRING:
			return _failure("talents.character_id", "type", {"index": index})
		var talent_id := str(row["id"])
		var character_id := str(row["character_id"])
		if (
			not CHARACTER_IDS.has(character_id)
			or str(TALENT_CHARACTER_BY_ID.get(talent_id, "")) != character_id
		):
			return _failure("talents.character_id", "mismatch", {"index": index})
		count_by_character[character_id] = int(count_by_character.get(character_id, 0)) + 1
		normalized.append({"id": talent_id, "character_id": character_id})
	for character_id: String in CHARACTER_IDS:
		if int(count_by_character.get(character_id, 0)) != 3:
			return _failure("talents", "character_count", {"character_id": character_id})
	return {"ok": true, "rows": normalized, "context": {}}


func _claim_id(value: Variant, seen: Dictionary, field: String, index: int) -> Dictionary:
	if typeof(value) != TYPE_STRING or not _valid_id(str(value)):
		return _failure("%s.id" % field, "invalid", {"index": index})
	var content_id := str(value)
	if seen.has(content_id):
		return _failure("%s.id" % field, "duplicate", {"index": index, "id": content_id})
	seen[content_id] = true
	return {"ok": true, "context": {}}


func _exact_rows_error(
	rows: Array,
	fields: Array[String],
	expected_rows: Array[String],
	field: String
) -> Dictionary:
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var values: Array[String] = []
		for row_field: String in fields:
			values.append(str(row.get(row_field, "")))
		var actual := "|".join(values)
		if actual != expected_rows[index]:
			return _failure(
				field,
				"catalog_drift",
				{"index": index, "expected": expected_rows[index], "actual": actual}
			)
	return {}


func _valid_id(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile("^[a-z0-9][a-z0-9_.-]{0,63}$") == OK and regex.search(value) != null


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _failure(field: String, reason: String, extra: Dictionary = {}) -> Dictionary:
	var context := {"field": field, "reason": reason}
	for key: Variant in extra.keys():
		context[key] = extra[key]
	return {"ok": false, "context": context}
