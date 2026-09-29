class_name DraftService
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const SeedServiceScript := preload("res://scripts/core/seed_service.gd")
const SelectionOfferScript := preload("res://scripts/application/selection_offer.gd")

const STARTER_ARCHETYPES: Array[String] = [
	"freeze_burst",
	"rewind_echo",
	"accelerated_combo",
]

var _offer_records: Dictionary = {}
var _closed_offer_ids: Dictionary = {}


func create_offer(registry, state_snapshot: Dictionary, room_definition: Dictionary):
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
	if _closed_offer_ids.has(offer_id):
		return CommandResultScript.failure(&"OFFER_CLOSED", revision, {"offer_id": offer_id})
	if _offer_records.has(offer_id):
		var existing_record: Dictionary = _offer_records[offer_id]
		return CommandResultScript.success(
			revision,
			{"offer": (existing_record["offer"] as Dictionary).duplicate(true)}
		)

	var rng := SeedServiceScript.make_rng(
		int(state_snapshot.get("run_seed", 0)),
		&"draft",
		1,
		room_index,
		revision
	)
	var owned_ids := _owned_ids(state_snapshot.get("build", {}))
	var definitions: Array[Dictionary] = []
	match reward_kind:
		"starter":
			definitions = _starter_offer(
				_filter_candidates(registry.get_by_category(&"item", &"M1"), owned_ids),
				rng
			)
		"reinforcement":
			var reinforcement_candidates: Array[Dictionary] = []
			reinforcement_candidates.append_array(registry.get_by_category(&"item", &"M1"))
			reinforcement_candidates.append_array(registry.get_by_category(&"blessing", &"M1"))
			definitions = _reinforcement_offer(
				_filter_candidates(reinforcement_candidates, owned_ids),
				str(state_snapshot.get("build", {}).get("dominant_archetype", "")),
				rng
			)
		"talent":
			definitions = _talent_offer(
				_filter_candidates(registry.get_by_category(&"talent", &"M1"), owned_ids),
				rng
			)
		"contract":
			definitions = _contract_offer(
				_filter_candidates(registry.get_by_category(&"curse", &"M1"), owned_ids),
				rng
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
	for archetype: String in STARTER_ARCHETYPES:
		var route: Array[Dictionary] = candidates.filter(
			func(entry: Dictionary) -> bool:
				return str(entry.get("role", "")) == "starter" and str(entry.get("archetype", "")) == archetype
		)
		if route.is_empty():
			return []
		selected.append(_pick_one(route, rng))
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


func _contract_offer(candidates: Array[Dictionary], rng: RandomNumberGenerator) -> Array[Dictionary]:
	if candidates.size() < 2:
		return []
	var selected: Array[Dictionary] = _shuffled(candidates, rng).slice(0, 2)
	selected.append({
		"schema_version": 1,
		"id": "decline_contract",
		"category": "contract",
		"availability": ["M1"],
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


func _filter_candidates(candidates: Array[Dictionary], owned_ids: Dictionary) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for definition: Dictionary in candidates:
		var content_id := str(definition.get("id", ""))
		if content_id.is_empty() or owned_ids.has(content_id):
			continue
		if not definition.get("availability", []).has("M1"):
			continue
		filtered.append(definition.duplicate(true))
	return filtered


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
