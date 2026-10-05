extends RefCounted

const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Rush := preload("res://scripts/modes/boss_rush_catalog.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Handler := preload("res://scripts/content/effects/effect_handler_catalog.gd")
const SOURCE := "res://assets/production/modes/boss_rush_carried.json"
const REWARDS := ["walker_proof", "walker_entry", "eternal_walker", "void_walker", "speedwalker_boots"]

var _registry: RefCounted
var _definition: Dictionary = {}


func configure(registry: RefCounted) -> bool:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not Meta.exact_fields(value, ["schema_version", "mode_id", "hp_multiplier", "damage_multiplier", "starting_hp", "starting_gold", "stage_heal_ratio", "speed_clear_frames", "history_limit", "rewards"]) or value.schema_version != 1 or value.mode_id != "boss_rush_carried" or value.hp_multiplier != 1.2 or value.damage_multiplier != 1.1 or value.starting_hp != 100 or value.starting_gold != 100 or value.stage_heal_ratio != 0.3 or value.speed_clear_frames != 36000 or value.history_limit != 100 or value.rewards != REWARDS:
		return false
	_registry = registry
	_definition = value.duplicate(true)
	return true


func definition() -> Dictionary:
	return _definition.duplicate(true)


static func empty_state() -> Dictionary:
	return {"schema_version": 1, "portable": {}, "gold": 100, "item_ids": [], "blessing_ids": [], "active_item_id": "", "active_cooldown_frames": 0, "choices": [], "choice_receipts": [], "damage_taken": 0.0, "history": [], "archived": {"clears": 0, "no_damage": false, "speed": false}, "reward_ids": []}


func choices(request: Dictionary, stage_index: int, state: Dictionary) -> Array[Dictionary]:
	var blessing := _select("blessing", request, stage_index, state.blessing_ids)
	var item := _select("item", request, stage_index, state.item_ids)
	if blessing.is_empty() or item.is_empty():
		return []
	return [{"kind": "blessing", "id": blessing.id}, {"kind": "item", "id": item.id}, {"kind": "restore", "id": "full_restore"}]


func reward_definition(choice: Dictionary) -> Dictionary:
	return _registry.get_content(StringName(choice.id)) if choice.kind in ["blessing", "item"] else {}


func valid(value: Variant, fingerprint: String, owner: String) -> bool:
	if not value is Dictionary or not value.has("carried") or value.get("schema_version") != 2:
		return false
	var legacy: Dictionary = value.duplicate(true)
	legacy.erase("carried")
	legacy.schema_version = 1
	if not Rush.valid_session(legacy, fingerprint, owner) or not _valid_carried(value.carried):
		return false
	var state: Dictionary = value.carried
	if value.status == "IDLE":
		return Rules.same(state, empty_state())
	if value.status == "STAGE_CLEAR":
		if state.choices.size() != 3 or not Rules.same(state.choices, choices(value.request, int(value.stage_index), state)) or state.choice_receipts.size() != int(value.stage_index):
			return false
	elif not state.choices.is_empty() or state.choice_receipts.size() != int(value.stage_index):
		return false
	for index: int in range(state.choice_receipts.size()):
		var row: Variant = state.choice_receipts[index]
		if not Meta.exact_fields(row, ["stage_index", "kind", "id"]) or row.stage_index != index or row.kind not in ["blessing", "item", "restore"] or not row.id is String or row.kind == "restore" and row.id != "full_restore":
			return false
		if row.kind in ["blessing", "item"] and (not state[row.kind + "_ids"].has(row.id) or _registry.get_content(StringName(row.id)).get("category") != row.kind):
			return false
	var previous := 0
	for row: Dictionary in state.history:
		if not _valid_history(row, fingerprint, owner) or int(row.sequence) <= previous or int(row.sequence) > int(value.session_sequence):
			return false
		previous = int(row.sequence)
	return int(state.archived.clears) + state.history.size() <= int(value.session_sequence) and Rules.same(state.reward_ids, derive_rewards(state.history, state.archived))


func _valid_carried(value: Variant) -> bool:
	if not Meta.exact_fields(value, empty_state().keys()) or value.schema_version != 1 or value.gold != 100 or not value.portable is Dictionary or not value.choices is Array or value.choices.size() not in [0, 3] or not value.choice_receipts is Array or value.choice_receipts.size() > 4 or not value.history is Array or value.history.size() > 100 or not value.damage_taken is float and not value.damage_taken is int or not is_finite(float(value.damage_taken)) or value.damage_taken < 0 or not value.reward_ids is Array or value.reward_ids.size() > 5:
		return false
	if not value.portable.is_empty() and not valid_portable(value.portable):
		return false
	if not Meta.exact_fields(value.archived, ["clears", "no_damage", "speed"]) or not Meta.bounded_int(value.archived.clears, 0, Meta.MAX_VALUE) or not value.archived.no_damage is bool or not value.archived.speed is bool or value.archived.clears == 0 and (value.archived.no_damage or value.archived.speed) or value.archived.clears > 0 and value.history.size() != 100:
		return false
	if not value.active_item_id is String or not Meta.bounded_int(value.active_cooldown_frames, 0, 36000) or not value.active_item_id.is_empty() and (not value.item_ids.has(value.active_item_id) or _registry.get_content(StringName(value.active_item_id)).get("item_mode") != "active"):
		return false
	for category: String in ["item", "blessing"]:
		var ids: Variant = value[category + "_ids"]
		if not ids is Array or ids.size() > 4:
			return false
		var seen := {}
		for id: Variant in ids:
			if not id is String or seen.has(id) or _registry.get_content(StringName(id)).get("category") != category:
				return false
			seen[id] = true
	return true


static func portable(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	if result.is_empty():
		return {}
	result.schema_version = int(result.schema_version)
	result.weapon.runtime = {}
	result.health.invulnerable = false
	result.health.invulnerability_token = 0
	result.health.reward_invulnerability_tokens = []
	result.health.reward_invulnerability_remaining = {}
	result.time.resource_revision = int(result.time.resource_revision)
	return result


static func valid_portable(value: Dictionary) -> bool:
	var normalized := portable(value)
	return not normalized.is_empty() and Rules.same(normalized, value) and Replay.validate_full_player_reward_effect_state(normalized)


static func hydrate(value: Dictionary, fresh: Dictionary) -> Dictionary:
	if not valid_portable(value) or fresh.is_empty():
		return {}
	var result := portable(value)
	result.weapon.runtime = fresh.weapon.runtime.duplicate(true)
	return result


func add_history(candidate: Dictionary) -> void:
	var carried: Dictionary = candidate.carried
	var hp: Dictionary = carried.portable.health
	carried.history.append({"sequence": int(candidate.session_sequence), "run_id": candidate.run_id, "request": candidate.request.duplicate(true), "elapsed_frames": int(candidate.elapsed_frames), "remaining_hp": float(hp.current_hp), "maximum_hp": float(hp.max_hp), "damage_taken": float(carried.damage_taken), "continued": candidate.continued, "completed_stages": candidate.completed_stages.duplicate(true)})
	if carried.history.size() > 100:
		var old: Dictionary = carried.history.pop_front()
		carried.archived.clears = int(carried.archived.clears) + 1
		carried.archived.no_damage = carried.archived.no_damage or _competitive(old) and old.damage_taken == 0.0
		carried.archived.speed = carried.archived.speed or _competitive(old) and old.elapsed_frames < 36000
	carried.reward_ids = derive_rewards(carried.history, carried.archived)


static func derive_rewards(history: Array, archive: Dictionary = {}) -> Array[String]:
	var result: Array[String] = []
	var count := history.size() + int(archive.get("clears", 0))
	if count == 0:
		return result
	result.append_array(["walker_proof", "walker_entry"])
	if count >= 5:
		result.append("eternal_walker")
	if archive.get("no_damage", false):
		result.append("void_walker")
	if archive.get("speed", false):
		result.append("speedwalker_boots")
	for row: Dictionary in history:
		if row.damage_taken == 0.0 and _competitive(row) and not result.has("void_walker"):
			result.append("void_walker")
		if row.elapsed_frames < 36000 and _competitive(row) and not result.has("speedwalker_boots"):
			result.append("speedwalker_boots")
	result.sort()
	return result


static func _competitive(row: Dictionary) -> bool:
	return not row.continued and row.request.accessibility_assists.damage_received_multiplier == 1.0 and row.request.accessibility_assists.enemy_telegraph_scale == 1.0


static func _valid_history(value: Variant, fingerprint: String, owner: String) -> bool:
	if not Meta.exact_fields(value, ["sequence", "run_id", "request", "elapsed_frames", "remaining_hp", "maximum_hp", "damage_taken", "continued", "completed_stages"]) or not Meta.bounded_int(value.sequence, 1, Meta.MAX_VALUE) or not value.remaining_hp is float and not value.remaining_hp is int or not value.maximum_hp is float and not value.maximum_hp is int or not value.damage_taken is float and not value.damage_taken is int or not is_finite(float(value.remaining_hp)) or not is_finite(float(value.maximum_hp)) or not is_finite(float(value.damage_taken)) or value.maximum_hp <= 0 or value.remaining_hp <= 0 or value.remaining_hp > value.maximum_hp or value.damage_taken < 0:
		return false
	var session := Rush.empty_session(fingerprint)
	session.merge({"session_sequence": value.sequence, "run_id": value.run_id, "request": value.request, "stage_index": 4, "status": "VICTORY", "elapsed_frames": value.elapsed_frames, "completed_stages": value.completed_stages, "continued": value.continued}, true)
	return Rush.valid_session(session, fingerprint, owner)


static func validated_reward_aggregate(payload: Variant, owner_id: String, mode_fingerprint: String, registry: RefCounted) -> Dictionary:
	var catalog := Rush.new()
	var rules := load("res://scripts/modes/boss_rush_carried_rules.gd").new() as RefCounted
	if not Meta.exact_fields(payload, ["boss_rush_session"]) or not catalog.configure(registry, true) or catalog.fingerprint() != mode_fingerprint or not rules.configure(registry) or not rules.valid(payload.boss_rush_session, mode_fingerprint, owner_id):
		return {"ok": false}
	return {"ok": true, "source_id": "rush:%s:%s" % [owner_id, mode_fingerprint], "lifetime_participation": int(payload.boss_rush_session.session_sequence), "lifetime_victories": payload.boss_rush_session.carried.history.size() + int(payload.boss_rush_session.carried.archived.clears), "entitlement_ids": payload.boss_rush_session.carried.reward_ids.duplicate(), "owned_ids": []}


func _select(category: String, request: Dictionary, stage_index: int, excluded: Array) -> Dictionary:
	var rows: Array[Dictionary] = []
	var handler := Handler.new()
	for row: Dictionary in _registry.get_catalog_entries(StringName(category), &"LAUNCH"):
		if excluded.has(row.id) or not row.get("effects") is Dictionary or row.effects.is_empty() and row.get("item_mode") != "active" or category == "item" and row.get("rarity") not in ["rare", "legendary"]:
			continue
		var supported := true
		for effect_id: String in row.effects:
			var descriptor: Dictionary = handler.effect_descriptor(StringName(effect_id))
			if descriptor.get("runtime_domain") == "weapon":
				var weapon_match := false
				for capability: Dictionary in descriptor.weapon_capabilities:
					weapon_match = weapon_match or capability.weapon_id == request.weapon_id
				supported = supported and weapon_match
		if supported:
			rows.append(row)
	rows.sort_custom(func(left: Dictionary, right: Dictionary): return str(left.id) < str(right.id))
	if rows.is_empty():
		return {}
	var roll := (str(request.seed) + "|" + str(stage_index) + "|" + category).sha256_text().substr(0, 12).hex_to_int()
	return rows[roll % rows.size()].duplicate(true)
