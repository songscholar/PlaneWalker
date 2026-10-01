class_name DraftService
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const SeedServiceScript := preload("res://scripts/core/seed_service.gd")
const SelectionOfferScript := preload("res://scripts/application/selection_offer.gd")

const M1_ARCHETYPES: Array[String] = [
	"freeze_burst",
	"rewind_echo",
	"accelerated_combo",
]
const LAUNCH_ARCHETYPES: Array[String] = [
	"freeze_burst",
	"rewind_echo",
	"rift_trap",
	"accelerated_combo",
	"low_hp_void",
	"perfect_guard",
	"piercing_barrage",
	"echo_legion",
]
const VALID_MILESTONES: Array[String] = ["M1", "CURRENT", "NEXT", "LAUNCH", "EXPANSION"]
const M1_COMPATIBLE_MILESTONES: Array[String] = ["M1", "CURRENT", "NEXT"]

var _offer_records: Dictionary = {}
var _closed_offer_ids: Dictionary = {}


func create_offer(registry, state_snapshot: Dictionary, room_definition: Dictionary):
	var milestone_result := _milestone_from_state(state_snapshot)
	if not bool(milestone_result.get("ok", false)):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			maxi(0, int(state_snapshot.get("revision", 0))),
			{"field": "milestone"}
		)
	var milestone := str(milestone_result["milestone"])
	var profiles: Array[Dictionary] = []
	if not M1_COMPATIBLE_MILESTONES.has(milestone):
		profiles = _launch_profiles(registry, StringName(milestone))
		if profiles.size() != LAUNCH_ARCHETYPES.size():
			return CommandResultScript.failure(
				&"CONTENT_NOT_AVAILABLE",
				maxi(0, int(state_snapshot.get("revision", 0))),
				{"milestone": milestone, "reason": "archetype_profiles"}
			)
	var reward_kind := str(room_definition.get("reward_kind", ""))
	if reward_kind.is_empty() or reward_kind == "none":
		return CommandResultScript.failure(&"INVALID_ARGUMENT", int(state_snapshot.get("revision", 0)), {"field": "reward_kind"})
	var run_id := str(state_snapshot.get("run_id", ""))
	var revision := int(state_snapshot.get("revision", -1))
	var room_index := int(room_definition.get("room_number", state_snapshot.get("current_room", 0)))
	if run_id.is_empty() or revision < 0 or room_index <= 0:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", maxi(0, revision), {"field": "state_snapshot"})
	var category := _category_for_reward_kind(reward_kind)
	if category.is_empty():
		return CommandResultScript.failure(&"INVALID_ARGUMENT", revision, {"field": "reward_kind", "value": reward_kind})
	var offer_id := "%s:room-%02d:%s:%d" % [run_id, room_index, category, revision]
	var offer_identity := _offer_identity(milestone, profiles)
	if _closed_offer_ids.has(offer_id):
		return CommandResultScript.failure(&"OFFER_CLOSED", revision, {"offer_id": offer_id})
	if _offer_records.has(offer_id):
		var existing_record: Dictionary = _offer_records[offer_id]
		if str(existing_record.get("identity", "")) != offer_identity:
			return CommandResultScript.failure(
				&"INVALID_ARGUMENT",
				revision,
				{"field": "offer_identity", "offer_id": offer_id}
			)
		return CommandResultScript.success(
			revision,
			{"offer": (existing_record["offer"] as Dictionary).duplicate(true)}
		)

	var rng_channel := &"draft"
	if not M1_COMPATIBLE_MILESTONES.has(milestone):
		rng_channel = StringName("draft_v2:%s:%s" % [milestone, _profile_digest(profiles)])
	var rng := SeedServiceScript.make_rng(
		int(state_snapshot.get("run_seed", 0)),
		rng_channel,
		1,
		room_index,
		revision
	)
	var owned_ids := _owned_ids(state_snapshot.get("build", {}))
	if not profiles.is_empty():
		var coverage_error := _launch_coverage_error(registry, StringName(milestone), profiles)
		if not coverage_error.is_empty():
			return CommandResultScript.failure(&"CONTENT_NOT_AVAILABLE", revision, coverage_error)
	var definitions: Array[Dictionary] = []
	match reward_kind:
		"starter":
			var starter_candidates := _filter_candidates(
				registry.get_by_category(&"item", StringName(milestone)),
				owned_ids,
				milestone
			)
			definitions = (
				_starter_offer(starter_candidates, rng)
				if M1_COMPATIBLE_MILESTONES.has(milestone)
				else _launch_starter_offer(starter_candidates, LAUNCH_ARCHETYPES, rng)
			)
		"reinforcement":
			var dominant_archetype := str(state_snapshot.get("build", {}).get("dominant_archetype", ""))
			var allowed_archetypes := M1_ARCHETYPES if M1_COMPATIBLE_MILESTONES.has(milestone) else LAUNCH_ARCHETYPES
			if not allowed_archetypes.has(dominant_archetype):
				return CommandResultScript.failure(
					&"INVALID_ARGUMENT",
					revision,
					{"field": "dominant_archetype", "value": dominant_archetype}
				)
			var reinforcement_candidates: Array[Dictionary] = []
			reinforcement_candidates.append_array(registry.get_by_category(&"item", StringName(milestone)))
			reinforcement_candidates.append_array(registry.get_by_category(&"blessing", StringName(milestone)))
			definitions = _reinforcement_offer(
				_filter_candidates(reinforcement_candidates, owned_ids, milestone),
				dominant_archetype,
				rng
			)
		"talent":
			definitions = _talent_offer(
				_filter_candidates(
					registry.get_by_category(&"talent", StringName(milestone)),
					owned_ids,
					milestone
				),
				rng
			)
		"contract":
			definitions = _contract_offer(
				_filter_candidates(
					registry.get_by_category(&"curse", StringName(milestone)),
					owned_ids,
					milestone
				),
				rng,
				milestone
			)

	if definitions.size() != 3:
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE",
			revision,
			{"reward_kind": reward_kind, "option_count": definitions.size()}
		)
	var options: Array[Dictionary] = []
	for definition: Dictionary in definitions:
		options.append(_to_option(definition))
	var offer := {
		"schema_version": 1,
		"offer_id": offer_id,
		"revision": revision,
		"category": category,
		"title_key": _title_key(category),
		"can_skip": false,
		"options": options,
	}
	var validation = SelectionOfferScript.validate(offer)
	if not validation.ok:
		return CommandResultScript.failure(validation.code, revision, validation.context)
	var definition_map: Dictionary = {}
	for definition: Dictionary in definitions:
		definition_map[str(definition["id"])] = definition.duplicate(true)
	_offer_records[offer_id] = {
		"offer": offer.duplicate(true),
		"definitions": definition_map,
		"identity": offer_identity,
	}
	return CommandResultScript.success(revision, {"offer": offer})


func resolve_option(offer: Dictionary, option_id: StringName):
	var revision := int(offer.get("revision", 0))
	var validation = SelectionOfferScript.validate(offer)
	if not validation.ok:
		return CommandResultScript.failure(validation.code, revision, validation.context)
	var offer_id := str(offer.get("offer_id", ""))
	if not _offer_records.has(offer_id):
		return CommandResultScript.failure(&"OFFER_CLOSED", revision, {"offer_id": offer_id})
	var record: Dictionary = _offer_records[offer_id]
	var canonical_offer: Dictionary = record["offer"]
	var canonical_revision := int(canonical_offer["revision"])
	if revision != canonical_revision:
		return CommandResultScript.failure(
			&"STALE_REVISION",
			canonical_revision,
			{"offer_id": offer_id, "received_revision": revision, "last_revision": canonical_revision}
		)
	if str(offer.get("category", "")) != str(canonical_offer["category"]):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			canonical_revision,
			{"field": "category", "offer_id": offer_id}
		)
	if not _offer_has_option(canonical_offer, str(option_id)):
		return CommandResultScript.failure(&"OPTION_NOT_FOUND", canonical_revision, {"option_id": str(option_id)})
	var definition: Variant = (record["definitions"] as Dictionary).get(str(option_id))
	if typeof(definition) != TYPE_DICTIONARY:
		return CommandResultScript.failure(&"OPTION_NOT_FOUND", canonical_revision, {"option_id": str(option_id)})
	return CommandResultScript.success(
		canonical_revision,
		{"definition": (definition as Dictionary).duplicate(true)}
	)


func close_offer(offer_id: String) -> bool:
	if not _offer_records.has(offer_id):
		return false
	_offer_records.erase(offer_id)
	_closed_offer_ids[offer_id] = true
	return true


func reset() -> void:
	_offer_records.clear()
	_closed_offer_ids.clear()


func _starter_offer(candidates: Array[Dictionary], rng: RandomNumberGenerator) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	for archetype: String in M1_ARCHETYPES:
		var route: Array[Dictionary] = candidates.filter(
			func(entry: Dictionary) -> bool:
				return str(entry.get("role", "")) == "starter" and str(entry.get("archetype", "")) == archetype
		)
		if route.is_empty():
			return []
		selected.append(_pick_one(route, rng))
	return selected


func _launch_starter_offer(
	candidates: Array[Dictionary],
	allowed_archetypes: Array[String],
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var available_routes: Array[Dictionary] = []
	for archetype: String in allowed_archetypes:
		var route: Array[Dictionary] = candidates.filter(
			func(entry: Dictionary) -> bool:
				return str(entry.get("role", "")) == "starter" and str(entry.get("archetype", "")) == archetype
		)
		if not route.is_empty():
			available_routes.append({"archetype": archetype, "definitions": route})
	if available_routes.size() < 3:
		return []
	var selected: Array[Dictionary] = []
	for route: Dictionary in _shuffled(available_routes, rng).slice(0, 3):
		selected.append(_pick_one(route["definitions"], rng))
	return selected


func _reinforcement_offer(
	candidates: Array[Dictionary],
	dominant_archetype: String,
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var payoffs: Array[Dictionary] = candidates.filter(
		func(entry: Dictionary) -> bool:
			return str(entry.get("role", "")) == "payoff" and str(entry.get("archetype", "")) == dominant_archetype
	)
	var alternatives: Array[Dictionary] = candidates.filter(
		func(entry: Dictionary) -> bool:
			return str(entry.get("role", "")) == "starter" and str(entry.get("archetype", "")) != dominant_archetype
	)
	var utilities: Array[Dictionary] = candidates.filter(
		func(entry: Dictionary) -> bool:
			return str(entry.get("role", "")) == "utility" or str(entry.get("archetype", "")).is_empty()
	)
	if payoffs.is_empty() or alternatives.is_empty() or utilities.is_empty():
		return []
	return [
		_pick_one(payoffs, rng),
		_pick_one(alternatives, rng),
		_pick_one(utilities, rng),
	]


func _talent_offer(candidates: Array[Dictionary], rng: RandomNumberGenerator) -> Array[Dictionary]:
	if candidates.size() < 3:
		return []
	return _shuffled(candidates, rng).slice(0, 3)


func _contract_offer(
	candidates: Array[Dictionary],
	rng: RandomNumberGenerator,
	milestone: String = "M1"
) -> Array[Dictionary]:
	if candidates.size() < 2:
		return []
	var selected: Array[Dictionary] = _shuffled(candidates, rng).slice(0, 2)
	selected.append({
		"schema_version": 1,
		"id": "decline_contract",
		"category": "contract",
		"availability": [milestone],
		"name_key": "DECLINE_CONTRACT_NAME",
		"description_key": "DECLINE_CONTRACT_DESC",
		"kind": "safe",
		"archetype": "",
		"role": "utility",
		"rarity": "common",
		"effects": {},
	})
	return selected


func _to_option(definition: Dictionary) -> Dictionary:
	var content_id := str(definition.get("id", ""))
	var archetype := str(definition.get("archetype", ""))
	var role := str(definition.get("role", "utility"))
	var effect_summary_keys: Array[String] = []
	var effect_ids: Array = definition.get("effects", {}).keys()
	effect_ids.sort()
	for effect_id: Variant in effect_ids:
		effect_summary_keys.append("EFFECT_%s" % str(effect_id).replace(".", "_").to_upper())
	return {
		"option_id": content_id,
		"content_id": content_id,
		"name_key": str(definition.get("name_key", "")),
		"description_key": str(definition.get("description_key", "")),
		"archetype_key": "ARCHETYPE_GENERAL" if archetype.is_empty() else "ARCHETYPE_%s" % archetype.to_upper(),
		"role_key": "ROLE_%s" % role.to_upper(),
		"rarity": str(definition.get("rarity", "common")),
		"icon_id": str(definition.get("icon_id", "content_%s" % content_id)),
		"effect_summary_keys": effect_summary_keys,
	}


func _filter_candidates(
	candidates: Array[Dictionary],
	owned_ids: Dictionary,
	milestone: String = "M1"
) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for definition: Dictionary in candidates:
		var content_id := str(definition.get("id", ""))
		if content_id.is_empty() or owned_ids.has(content_id):
			continue
		if not definition.get("availability", []).has(milestone):
			continue
		filtered.append(definition.duplicate(true))
	return filtered


func _milestone_from_state(state_snapshot: Dictionary) -> Dictionary:
	if not state_snapshot.has("config"):
		return {"ok": true, "milestone": "M1"}
	var config_value: Variant = state_snapshot.get("config")
	if not config_value is Dictionary:
		return {"ok": false, "milestone": ""}
	var milestone_value: Variant = (config_value as Dictionary).get("milestone", "M1")
	if typeof(milestone_value) != TYPE_STRING or not VALID_MILESTONES.has(str(milestone_value)):
		return {"ok": false, "milestone": ""}
	return {"ok": true, "milestone": str(milestone_value)}


func _launch_profiles(registry, milestone: StringName) -> Array[Dictionary]:
	if not registry.has_method("get_archetype_profiles"):
		return []
	var profile_values: Variant = registry.get_archetype_profiles(milestone)
	if not profile_values is Array:
		return []
	var profiles: Array[Dictionary] = []
	for index: int in range((profile_values as Array).size()):
		var profile_value: Variant = (profile_values as Array)[index]
		if not profile_value is Dictionary or index >= LAUNCH_ARCHETYPES.size():
			return []
		var profile: Dictionary = profile_value
		if str(profile.get("archetype_id", "")) != LAUNCH_ARCHETYPES[index]:
			return []
		profiles.append(profile.duplicate(true))
	return profiles


func _launch_coverage_error(
	registry,
	milestone: StringName,
	profiles: Array[Dictionary]
) -> Dictionary:
	var definitions: Array[Dictionary] = []
	for category: StringName in [&"item", &"blessing", &"curse"]:
		definitions.append_array(registry.get_by_category(category, milestone))
	for profile: Dictionary in profiles:
		var archetype_id := str(profile.get("archetype_id", ""))
		var route: Array[Dictionary] = definitions.filter(
			func(entry: Dictionary) -> bool:
				return str(entry.get("archetype", "")) == archetype_id
		)
		for role: String in ["starter", "payoff", "risk"]:
			var required_count := int(profile.get("%s_min" % role, 0))
			var actual_count := route.filter(
				func(entry: Dictionary) -> bool:
					return str(entry.get("role", "")) == role
			).size()
			if required_count <= 0 or actual_count < required_count:
				return {
					"milestone": str(milestone),
					"archetype_id": archetype_id,
					"role": role,
					"required": required_count,
					"available": actual_count,
				}
	return {}


func _offer_identity(milestone: String, profiles: Array[Dictionary]) -> String:
	return "%s|%s" % [
		milestone,
		"m1-v1" if profiles.is_empty() else _profile_digest(profiles),
	]


func _profile_digest(profiles: Array[Dictionary]) -> String:
	var rows: Array[String] = []
	for profile: Dictionary in profiles:
		rows.append("%s:%d:%d:%d" % [
			str(profile.get("archetype_id", "")),
			int(profile.get("starter_min", 0)),
			int(profile.get("payoff_min", 0)),
			int(profile.get("risk_min", 0)),
		])
	return "|".join(rows).sha256_text()


func _owned_ids(build: Dictionary) -> Dictionary:
	var owned: Dictionary = {}
	for field: String in ["items", "blessings", "curses", "talents"]:
		for content_id: Variant in build.get(field, []):
			owned[str(content_id)] = true
	return owned


func _pick_one(candidates: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	return candidates[rng.randi_range(0, candidates.size() - 1)].duplicate(true)


func _shuffled(candidates: Array[Dictionary], rng: RandomNumberGenerator) -> Array[Dictionary]:
	var shuffled: Array[Dictionary] = candidates.duplicate(true)
	for index: int in range(shuffled.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var previous: Dictionary = shuffled[index]
		shuffled[index] = shuffled[swap_index]
		shuffled[swap_index] = previous
	return shuffled


func _title_key(category: String) -> String:
	match category:
		"talent":
			return "UI_CHOOSE_TALENT"
		"contract":
			return "UI_CHOOSE_CONTRACT"
		_:
			return "UI_CHOOSE_REWARD"


func _category_for_reward_kind(reward_kind: String) -> String:
	match reward_kind:
		"starter", "reinforcement":
			return "item"
		"talent":
			return "talent"
		"contract":
			return "contract"
		_:
			return ""


func _offer_has_option(offer: Dictionary, option_id: String) -> bool:
	for option: Dictionary in offer.get("options", []):
		if str(option.get("option_id", "")) == option_id:
			return true
	return false
