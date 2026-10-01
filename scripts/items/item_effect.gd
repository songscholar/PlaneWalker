class_name ItemEffect
extends RefCounted

const EffectHandlerCatalogScript := preload("res://scripts/content/effects/effect_handler_catalog.gd")
const PlayerRewardEffectRuntimeScript := preload(
	"res://scripts/items/player_reward_effect_runtime.gd"
)


static func apply_to_player(
	player: Node,
	effects: Dictionary,
	definition_id: String = "legacy_item_effect",
	category: String = ""
) -> Dictionary:
	if player == null or not is_instance_valid(player):
		return {"ok": false, "code": &"INVALID_PLAYER"}
	if effects.is_empty():
		return {"ok": true, "code": &"NO_EFFECTS", "receipt": {}}
	if (
		not player.has_method("reward_effect_snapshot")
		or not player.has_method("reward_effect_begin_publication")
		or not player.has_method("reward_effect_publication_can_commit")
		or not player.has_method("reward_effect_commit_publication")
		or not player.has_method("reward_effect_rollback_publication")
	):
		return {"ok": false, "code": &"INVALID_PLAYER"}
	if not bool(player.call("reward_effect_begin_publication")):
		return {"ok": false, "code": &"PUBLICATION_UNAVAILABLE"}
	var result: Dictionary
	if category.is_empty():
		result = _apply_legacy_composite(player, effects, definition_id)
	else:
		result = _apply_definition(player, {
			"id": definition_id,
			"category": category,
			"effects": effects.duplicate(true),
		})
	return _settle_publication(player, result)


static func _apply_definition(player: Node, definition: Dictionary) -> Dictionary:
	var snapshot_value: Variant = player.call("reward_effect_snapshot")
	if not snapshot_value is Dictionary or (snapshot_value as Dictionary).is_empty():
		return {"ok": false, "code": &"INVALID_PLAYER_SNAPSHOT"}
	var runtime = PlayerRewardEffectRuntimeScript.new()
	var prepared: Dictionary = runtime.prepare(
		definition.duplicate(true),
		(snapshot_value as Dictionary).duplicate(true)
	)
	if not bool(prepared.get("ok", false)):
		return prepared
	return runtime.commit(
		(prepared.get("plan", {}) as Dictionary).duplicate(true),
		player
	)


static func _apply_legacy_composite(
	player: Node,
	effects: Dictionary,
	definition_id: String
) -> Dictionary:
	var catalog = EffectHandlerCatalogScript.new()
	var normalized: Dictionary = catalog.normalize_effects(effects)
	if normalized.is_empty() or normalized.size() != effects.size():
		return {"ok": false, "code": &"INVALID_EFFECTS"}
	var effect_ids: Array[String] = []
	for effect_id_value: Variant in normalized.keys():
		effect_ids.append(str(effect_id_value))
	effect_ids.sort()
	var receipts: Array[Dictionary] = []
	var runtime = PlayerRewardEffectRuntimeScript.new()
	for effect_id: String in effect_ids:
		var descriptor: Dictionary = catalog.effect_descriptor(StringName(effect_id))
		if (
			str(descriptor.get("runtime_domain", "")) == "weapon"
			and not _legacy_weapon_effect_matches_player(
				player,
				descriptor.get("weapon_capabilities", []) as Array
			)
		):
			continue
		var categories_value: Variant = descriptor.get("allowed_categories", [])
		if not categories_value is Array or (categories_value as Array).is_empty():
			return _rollback_legacy_receipts(runtime, player, receipts, {
				"ok": false,
				"code": &"INVALID_EFFECTS",
			})
		var selected_category := str((categories_value as Array)[0])
		var result := _apply_definition(player, {
			"id": "%s:%s" % [definition_id, effect_id],
			"category": selected_category,
			"effects": {effect_id: normalized[effect_id]},
		})
		if not bool(result.get("ok", false)):
			return _rollback_legacy_receipts(runtime, player, receipts, result)
		var receipt_value: Variant = result.get("receipt", {})
		if receipt_value is Dictionary and not (receipt_value as Dictionary).is_empty():
			receipts.append((receipt_value as Dictionary).duplicate(true))
	return {
		"ok": true,
		"code": &"OK",
		"receipts": receipts.duplicate(true),
	}


static func _rollback_legacy_receipts(
	runtime: RefCounted,
	player: Node,
	receipts: Array[Dictionary],
	failure: Dictionary
) -> Dictionary:
	for receipt_index: int in range(receipts.size() - 1, -1, -1):
		var rolled_back: Dictionary = runtime.call(
			"rollback",
			receipts[receipt_index].duplicate(true),
			player
		)
		if not bool(rolled_back.get("ok", false)):
			return {
				"ok": false,
				"code": &"ROLLBACK_FAILED",
				"cause": failure.duplicate(true),
				"rollback": rolled_back,
			}
	return failure.duplicate(true)


static func _settle_publication(player: Node, result: Dictionary) -> Dictionary:
	if not bool(result.get("ok", false)):
		if not bool(player.call("reward_effect_rollback_publication")):
			return {
				"ok": false,
				"code": &"ROLLBACK_FAILED",
				"cause": result.duplicate(true),
			}
		return result
	if not bool(player.call("reward_effect_publication_can_commit")):
		var state_rollback := _rollback_committed_result(player, result)
		var publication_rollback := bool(player.call("reward_effect_rollback_publication"))
		return {
			"ok": false,
			"code": &"ROLLBACK_FAILED" if not state_rollback or not publication_rollback else &"PUBLICATION_REJECTED",
		}
	if not bool(player.call("reward_effect_commit_publication")):
		return {"ok": false, "code": &"PUBLICATION_FAILED"}
	return result


static func _rollback_committed_result(player: Node, result: Dictionary) -> bool:
	var receipts: Array[Dictionary] = []
	var receipt_value: Variant = result.get("receipt", {})
	if receipt_value is Dictionary and not (receipt_value as Dictionary).is_empty():
		receipts.append((receipt_value as Dictionary).duplicate(true))
	var receipts_value: Variant = result.get("receipts", [])
	if receipts_value is Array:
		for entry_value: Variant in receipts_value as Array:
			if entry_value is Dictionary and not (entry_value as Dictionary).is_empty():
				receipts.append((entry_value as Dictionary).duplicate(true))
	var runtime = PlayerRewardEffectRuntimeScript.new()
	for receipt_index: int in range(receipts.size() - 1, -1, -1):
		var rolled_back: Dictionary = runtime.call(
			"rollback",
			receipts[receipt_index].duplicate(true),
			player
		)
		if not bool(rolled_back.get("ok", false)):
			return false
	return true


static func _legacy_weapon_effect_matches_player(
	player: Node,
	weapon_capabilities: Array
) -> bool:
	var loadout_value: Variant = player.get("loadout_runtime")
	if not loadout_value is Object or not (loadout_value as Object).has_method("has_weapon"):
		return false
	for mapping_value: Variant in weapon_capabilities:
		if (
			mapping_value is Dictionary
			and bool((loadout_value as Object).call(
				"has_weapon",
				StringName(str((mapping_value as Dictionary).get("weapon_id", "")))
			))
		):
			return true
	return false


static func _apply_weapon_effects(player: Node, effects: Dictionary) -> bool:
	var effect_catalog = EffectHandlerCatalogScript.new()
	var routes: Array[Dictionary] = effect_catalog.weapon_capability_routes(effects)
	if routes.is_empty():
		return true
	if player.has_method("apply_weapon_capability_effects"):
		return bool(player.call("apply_weapon_capability_effects", routes))
	if not player.has_method("apply_weapon_capability_effect"):
		return false
	var applied_any := false
	for route: Dictionary in routes:
		if bool(player.call(
			"apply_weapon_capability_effect",
			StringName(str(route["capability"])),
			route["value"],
			float(route["base_value"]),
			StringName(str(route["stack_rule"])),
			StringName(str(route["weapon_id"]))
		)):
			applied_any = true
	return applied_any
