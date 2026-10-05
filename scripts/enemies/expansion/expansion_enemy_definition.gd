class_name ExpansionEnemyDefinition
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Common := preload("res://scripts/enemies/launch/hostile_definition_contract.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const IDS := ["echo_lancer", "mire_cantor", "parallax_guard", "cinder_drake", "prism_seer"]
const ACTION_IDS := [["echo_lancer.echo_thrust"], ["mire_cantor.mire_verse"], ["parallax_guard.split_ray"], ["cinder_drake.cinder_charge", "cinder_drake.cinder_fan"], ["prism_seer.prism_sequence"]]
const HANDLERS := [["melee"], ["zone"], ["melee"], ["charge", "projectile_volley"], ["projectile_volley"]]
const FIELDS := ["category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "references", "floor_id", "runtime_kind", "max_hp", "defense", "move_speed", "threat_cost", "collision_radius_px", "sprite_asset", "actions", "mechanisms"]
const RUNTIME_FIELDS := ["id", "actor_kind", "runtime_kind", "max_hp", "defense", "move_speed", "collision_radius_px", "actions", "mechanisms"]
const MECHANISM_RULES := {"first_attack_stagger_frames": [0, 60, true], "kite_min_px": [0, 160, false], "kite_max_px": [0, 240, false]}
var _definition := {}


func configure(source: Dictionary) -> Dictionary:
	_definition.clear()
	if not Contract.exact_fields(source, FIELDS) or source.category != "expansion_enemy_definition" or not Contract.integer_in_range(source.schema_version, 1, 1) or not IDS.has(source.id):
		return Common.failure("expansion_enemy", "identity")
	var index: int = IDS.find(source.id)
	var floor_id: String = Ids.FLOOR_IDS[index]
	if source.availability != ["EXPANSION"] or source.floor_id != floor_id or source.runtime_kind != source.id or not Common.localization_key(source.name_key) or not Common.localization_key(source.description_key):
		return Common.failure("metadata", "identity")
	if not source.compatibility is Dictionary or source.compatibility != {"floor_ids": [floor_id], "actor_kinds": ["enemy"]} or source.references != [floor_id]:
		return Common.failure("compatibility", "identity")
	var tags := Common.string_list(source.tags, [], 1, 8, "tags")
	var stats := Common.numeric_fields(source, {"max_hp": [1, 1000, false], "defense": [0, 100, false], "move_speed": [0, 240, false], "threat_cost": [1, 5, true], "collision_radius_px": [1, 32, false]})
	var mechanisms := Common.mechanisms(source.mechanisms, MECHANISM_RULES)
	var actions := Common.actions(source.actions, "enemy", source.id + ".", 30, {})
	if not tags.ok or not stats.ok or not mechanisms.ok or not actions.ok:
		return Common.failure("fields", "invalid")
	if mechanisms.value.kite_min_px > mechanisms.value.kite_max_px or source.sprite_asset != "assets/" + source.id + ".png" or actions.value.size() != ACTION_IDS[index].size():
		return Common.failure("pattern", "identity")
	for action_index: int in range(actions.value.size()):
		var action: Dictionary = actions.value[action_index]
		if action.id != ACTION_IDS[index][action_index] or action.handler_id != HANDLERS[index][action_index]:
			return Common.failure("actions", "unsupported_pattern")
		if action.handler_id == "charge" and (action.geometry.size() != 1 or action.hit_schedule.size() != 1):
			return Common.failure("charge", "single_lane_required")
	_definition = source.duplicate(true)
	_definition.merge(stats.value, true)
	_definition.tags = tags.value
	_definition.actions = actions.value
	_definition.mechanisms = mechanisms.value
	return {"ok": true, "definition": snapshot(), "context": {}}


func snapshot() -> Dictionary:
	return _definition.duplicate(true)


func runtime_projection() -> Dictionary:
	if _definition.is_empty():
		return {}
	var result := {"actor_kind": "enemy"}
	for field: String in RUNTIME_FIELDS:
		if field != "actor_kind":
			result[field] = _definition[field]
	return result.duplicate(true)


static func floor_index(enemy_id: String) -> int:
	return IDS.find(enemy_id) + 1
