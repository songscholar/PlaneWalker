class_name RewardPool
extends RefCounted

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const BASE_PACK_PATH := "res://data/content_packs/base/pack.json"
const GAME_VERSION := "0.4.0-dev"

const ARCHETYPE_LABELS := {
	"freeze_burst": "ARCHETYPE_FREEZE_BURST",
	"rewind_echo": "ARCHETYPE_REWIND_ECHO",
	"rift_trap": "ARCHETYPE_RIFT_TRAP",
	"accelerated_combo": "ARCHETYPE_ACCELERATED_COMBO",
	"low_hp_void": "ARCHETYPE_LOW_HP_VOID",
	"perfect_guard": "ARCHETYPE_PERFECT_GUARD",
	"piercing_barrage": "ARCHETYPE_PIERCING_BARRAGE",
	"echo_legion": "ARCHETYPE_ECHO_LEGION",
}

const ROLE_LABELS := {
	"starter": "ROLE_STARTER",
	"payoff": "ROLE_PAYOFF",
	"risk": "ROLE_RISK",
	"route": "ROLE_ROUTE",
	"utility": "ROLE_UTILITY",
}


static func roll_options(
	count: int,
	seed_value: int,
	room_index: int,
	owned_ids: Array = []
) -> Array[Dictionary]:
	return _roll(all_rewards(), count, seed_value, room_index, owned_ids, "item")


static func all_rewards() -> Array[Dictionary]:
	return _definitions(&"item")


static func get_archetype_label(archetype: String) -> String:
	var key := str(ARCHETYPE_LABELS.get(archetype, "ARCHETYPE_" + archetype.to_upper()))
	return TranslationServer.translate(key)


static func get_role_label(role: String) -> String:
	var key := str(ROLE_LABELS.get(role, "ROLE_" + role.to_upper()))
	return TranslationServer.translate(key)


static func get_reward_route_label(reward_data: Dictionary) -> String:
	var archetype := str(reward_data.get("archetype", ""))
	var role := str(reward_data.get("role", ""))
	if archetype.is_empty() and role.is_empty():
		var kind := str(reward_data.get("kind", ""))
		if kind.is_empty():
			return TranslationServer.translate("UI_FALLBACK_REWARD")
		return TranslationServer.translate("KIND_" + kind.to_upper())
	if role.is_empty():
		return get_archetype_label(archetype)
	if archetype.is_empty():
		return get_role_label(role)
	return "%s - %s" % [get_role_label(role), get_archetype_label(archetype)]


static func _definitions(category: StringName) -> Array[Dictionary]:
	var registry = ContentRegistryScript.new()
	var report = registry.load_packs(
		[{"path": BASE_PACK_PATH, "required": true}],
		GAME_VERSION,
		&"M1"
	)
	if report.has_blocking_errors():
		push_error("Base content pack failed to load: %s" % str(report.blocking_errors))
		return []
	return registry.get_by_category(category)


static func _roll(
	candidates: Array[Dictionary],
	count: int,
	seed_value: int,
	room_index: int,
	owned_ids: Array,
	channel: String
) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%s:%s" % [channel, seed_value, room_index])
	_shuffle_with_rng(candidates, rng)
	var options: Array[Dictionary] = []
	for definition: Dictionary in candidates:
		if owned_ids.has(definition.get("id", "")):
			continue
		options.append(definition.duplicate(true))
		if options.size() >= count:
			break
	return options


static func _shuffle_with_rng(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var previous: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = previous
