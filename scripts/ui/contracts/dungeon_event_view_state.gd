class_name DungeonEventViewState
extends RefCounted

const Rules := preload("res://scripts/ui/contracts/dungeon_view_state_rules.gd")
const Events := preload("res://scripts/dungeon/dungeon_event_definition.gd")
const MerchantViewScript := preload("res://scripts/ui/contracts/merchant_view_state.gd")
const SelectionOfferScript := preload("res://scripts/application/selection_offer.gd")
const SCHEMA_VERSION := 1
const FIELDS := ["schema_version", "run_id", "phase", "event_id", "name_key", "description_key", "prompt_key", "options", "revision", "result_key", "pending_kind"]
const OPTION_FIELDS := ["id", "label_key", "eligible", "disabled_reason_key", "outcome_visibility", "visible_preview"]
const PHASES := ["open", "resolved", "pending_reward", "pending_encounter", "dismissed"]
const REWARD_FIELDS := ["schema_version", "offer_id", "category", "title_key", "revision", "can_skip", "options", "continuation_id"]


static func validate(value: Variant):
	var fields := FIELDS.duplicate()
	if value is Dictionary and value.has("reward_offer"):
		fields.append("reward_offer")
	if not Rules.header(value, fields):
		return Rules.reject(value, "root")
	var state := value as Dictionary
	if not Events.EVENT_IDS.has(state["event_id"]) or not PHASES.has(state["phase"]) or not state["options"] is Array or state["options"].is_empty() or state["options"].size() > 12:
		return Rules.reject(value, "event")
	for field: String in ["name_key", "description_key", "prompt_key"]:
		if not Rules.key(state[field]):
			return Rules.reject(value, field)
	if not Rules.key(state["result_key"], state["phase"] in ["open", "pending_reward", "pending_encounter"]) or state["pending_kind"] != ("reward" if state["phase"] == "pending_reward" else "encounter" if state["phase"] == "pending_encounter" else ""):
		return Rules.reject(value, "result")
	if state["phase"] == "pending_reward":
		if not _valid_reward(state.get("reward_offer"), int(state["revision"])):
			return Rules.reject(value, "reward_offer")
	elif state.get("reward_offer") != null:
		return Rules.reject(value, "reward_offer.phase")
	var ids: Dictionary = {}
	for option_value: Variant in state["options"]:
		if not Rules.exact(option_value, OPTION_FIELDS):
			return Rules.reject(value, "options")
		var option := option_value as Dictionary
		if option["id"] not in ["commit", "decline"] or ids.has(option["id"]) or not Rules.key(option["label_key"]) or not Rules.availability(option, "eligible") or not Events.OUTCOME_VISIBILITY.has(option["outcome_visibility"]) or not option["visible_preview"] is Array or option["visible_preview"].size() > 32:
			return Rules.reject(value, "options.identity")
		if option["outcome_visibility"] == "hidden_until_commit" and not option["visible_preview"].is_empty():
			return Rules.reject(value, "options.hidden")
		for preview: Variant in option["visible_preview"]:
			if not Rules.key(preview):
				return Rules.reject(value, "options.preview")
		ids[option["id"]] = true
	return Rules.accept(state)


static func copy_of(value: Dictionary) -> Dictionary:
	return value.duplicate(true) if validate(value).ok else {}


static func _valid_reward(value: Variant, revision: int) -> bool:
	if not Rules.exact(value, REWARD_FIELDS):
		return false
	var offer := value as Dictionary
	if not Rules.integer(offer["schema_version"]) or offer["schema_version"] != 1 or not Rules.identifier(offer["offer_id"]) or not Rules.identifier(offer["continuation_id"]) or offer["category"] not in ["item", "blessing", "curse"] or not Rules.key(offer["title_key"]) or not Rules.integer(offer["revision"]) or int(offer["revision"]) != revision or typeof(offer["can_skip"]) != TYPE_BOOL or not offer["options"] is Array or offer["options"].is_empty() or offer["options"].size() > 4:
		return false
	var option_fields := SelectionOfferScript.REQUIRED_OPTION_FIELDS.duplicate()
	option_fields.append("effect_summary_keys")
	var seen: Dictionary = {}
	for option_value: Variant in offer["options"]:
		if not Rules.exact(option_value, option_fields):
			return false
		var option := option_value as Dictionary
		if not Rules.identifier(option["option_id"]) or seen.has(option["option_id"]) or not MerchantViewScript.known_content(offer["category"], option["content_id"]) or not Rules.identifier(option["icon_id"]) or option["rarity"] not in ["common", "uncommon", "rare", "legendary", "unique"]:
			return false
		for field: String in ["name_key", "description_key", "archetype_key", "role_key"]:
			if not Rules.key(option[field]):
				return false
		if not option["effect_summary_keys"] is Array or option["effect_summary_keys"].size() > 32:
			return false
		for key: Variant in option["effect_summary_keys"]:
			if not Rules.key(key):
				return false
		seen[option["option_id"]] = true
	return true
