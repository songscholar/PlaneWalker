class_name RunViewStateProjector
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const ArchetypeProfileScript := preload("res://scripts/progression/archetype_profile.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunViewStateScript := preload("res://scripts/ui/contracts/run_view_state.gd")
const TimeAbilityIdsScript := preload("res://scripts/time_system/time_ability_ids.gd")
const DungeonViewRulesScript := preload("res://scripts/ui/contracts/dungeon_view_state_rules.gd")
const DungeonMapViewScript := preload("res://scripts/ui/contracts/dungeon_map_view_state.gd")
const MerchantViewScript := preload("res://scripts/ui/contracts/merchant_view_state.gd")
const DungeonEventViewScript := preload("res://scripts/ui/contracts/dungeon_event_view_state.gd")
const RoomInteractionViewScript := preload("res://scripts/ui/contracts/room_interaction_view_state.gd")
const FloorTransitionViewScript := preload("res://scripts/ui/contracts/floor_transition_view_state.gd")
const FloorDefinitionScript := preload("res://scripts/dungeon/floor_definition.gd")
const DungeonEventRuntimeScript := preload("res://scripts/events/dungeon_event_runtime.gd")

var _last_run_id: String = ""
var _view_revision: int = -1
var _latest_view_state: Dictionary = {}


func project_dungeon_map(authoritative: Dictionary, choices: Array, floor: Dictionary):
	var plan_value: Variant = authoritative.get("floor_plan")
	if not plan_value is Dictionary or not _dungeon_authority_valid(authoritative):
		return DungeonViewRulesScript.reject(authoritative, "floor_plan")
	var plan := plan_value as Dictionary
	if (
		floor.get("id") != plan.get("floor_id")
		or not floor.get("name_key") is String
		or not plan.get("nodes") is Array
		or not plan.get("edges") is Array
		or not plan.get("selected_edge_ids") is Array
	):
		return DungeonViewRulesScript.reject(authoritative, "floor")
	var view := _dungeon_header(authoritative)
	view.merge({
		"floor_id": plan.get("floor_id"),
		"floor_index": plan.get("floor_index"),
		"floor_name_key": floor["name_key"],
		"gold": _dungeon_gold(authoritative),
		"current_node_id": plan.get("current_node_id"),
		"boss_distance": 0,
		"nodes": [],
		"edges": [],
		"routes": [],
	})
	var nodes_by_id: Dictionary = {}
	var boss_layer := -1
	var current_layer := -1
	for node_value: Variant in plan["nodes"]:
		if not node_value is Dictionary:
			return DungeonViewRulesScript.reject(authoritative, "nodes")
		var node := node_value as Dictionary
		if not node.get("revealed") is bool or not node.get("layer") is int:
			return DungeonViewRulesScript.reject(authoritative, "nodes.knowledge")
		var room_type := str(node.get("room_type", "")) if bool(node["revealed"]) else "unknown"
		var projected := {
			"id": node.get("id"),
			"layer": node["layer"],
			"room_type": room_type,
			"name_key": _dungeon_room_key(room_type),
			"revealed": node["revealed"],
			"visited": node.get("visited"),
			"cleared": node.get("cleared"),
			"current": node.get("id") == plan.get("current_node_id"),
		}
		(view["nodes"] as Array).append(projected)
		nodes_by_id[str(node.get("id", ""))] = projected
		if node.get("id") == plan.get("boss_node_id"):
			boss_layer = int(node["layer"])
		if node.get("id") == plan.get("current_node_id"):
			current_layer = int(node["layer"])
	if boss_layer < 0 or current_layer < 0:
		return DungeonViewRulesScript.reject(authoritative, "current_node_id")
	view["boss_distance"] = maxi(0, boss_layer - current_layer)
	var selected: Array = plan.get("selected_edge_ids", [])
	for edge_value: Variant in plan["edges"]:
		if not edge_value is Dictionary:
			return DungeonViewRulesScript.reject(authoritative, "edges")
		var edge := edge_value as Dictionary
		(view["edges"] as Array).append({
			"id": edge.get("id"),
			"source_node_id": edge.get("source_node_id"),
			"destination_node_id": edge.get("destination_node_id"),
			"selected": selected.has(edge.get("id")),
		})
	for choice_value: Variant in choices:
		if not choice_value is Dictionary:
			return DungeonViewRulesScript.reject(authoritative, "routes")
		var choice := choice_value as Dictionary
		var node_value: Variant = nodes_by_id.get(str(choice.get("node_id", "")))
		if not node_value is Dictionary:
			return DungeonViewRulesScript.reject(authoritative, "routes.node_id")
		var node := node_value as Dictionary
		var phase := int(authoritative.get("phase", -1))
		var initial_route: bool = (
			phase == RunPhaseScript.Value.ROOM_ACTIVE
			and node.get("layer") == 1
			and plan.get("current_node_id") == "entry"
		)
		var available: bool = (
			not bool(authoritative.get("suspended", false))
			and (phase == RunPhaseScript.Value.ROOM_RESOLVING or initial_route)
		)
		(view["routes"] as Array).append({
			"edge_id": choice.get("edge_id"),
			"node_id": node["id"],
			"choice_order": choice.get("choice_order"),
			"room_type": node["room_type"],
			"name_key": node["name_key"],
			"available": available,
			"disabled_reason_key": "" if available else "UI_ROUTE_UNAVAILABLE",
		})
	return DungeonMapViewScript.validate(view)


func project_merchant(authoritative: Dictionary, source: Dictionary, content: Array, services: Array = []):
	var source_fields := [
		"node_key", "merchant_id", "name_key", "description_key", "intro_key",
		"farewell_key", "services", "gold", "economy_revision", "inventory",
		"service_state", "visibility",
	]
	if (
		not _dungeon_authority_valid(authoritative)
		or not DungeonViewRulesScript.exact(source, source_fields)
		or not source.get("inventory") is Dictionary
		or not source["inventory"].get("offers") is Array
		or not source.get("services") is Array
	):
		return DungeonViewRulesScript.reject(authoritative, "merchant")
	for service: Variant in services:
		if not service is Dictionary or not (source["services"] as Array).has(service.get("action_id")):
			return DungeonViewRulesScript.reject(authoritative, "services.action_id")
	var content_by_id: Dictionary = {}
	for definition_value: Variant in content:
		if not definition_value is Dictionary:
			return DungeonViewRulesScript.reject(authoritative, "content")
		var definition := definition_value as Dictionary
		if content_by_id.has(definition.get("id")):
			return DungeonViewRulesScript.reject(authoritative, "content.id")
		content_by_id[definition.get("id")] = definition
	var view := _dungeon_header(authoritative)
	view.merge({
		"merchant_id": source["merchant_id"],
		"name_key": source["name_key"],
		"description_key": source["description_key"],
		"intro_key": source["intro_key"],
		"gold": source["gold"],
		"offers": [],
		"services": services.duplicate(true),
	})
	for offer_value: Variant in source["inventory"]["offers"]:
		if not offer_value is Dictionary or not DungeonViewRulesScript.exact(offer_value, ["offer_id", "reward_id", "category", "rarity", "price", "sold"]):
			return DungeonViewRulesScript.reject(authoritative, "offers")
		var offer := offer_value as Dictionary
		var definition_value: Variant = content_by_id.get(offer["reward_id"])
		if not definition_value is Dictionary or not offer["price"] is int or not source["gold"] is int or not offer["sold"] is bool:
			return DungeonViewRulesScript.reject(authoritative, "offers.content_id")
		var definition := definition_value as Dictionary
		if definition.get("category") != offer["category"] or definition.get("rarity") != offer["rarity"]:
			return DungeonViewRulesScript.reject(authoritative, "offers.content")
		var affordable := int(source["gold"]) >= int(offer["price"])
		var available := affordable and not bool(offer["sold"])
		(view["offers"] as Array).append({
			"offer_id": offer["offer_id"],
			"content_id": offer["reward_id"],
			"category": offer["category"],
			"rarity": offer["rarity"],
			"name_key": definition.get("name_key"),
			"description_key": definition.get("description_key"),
			"price": offer["price"],
			"sold": offer["sold"],
			"affordable": affordable,
			"available": available,
			"disabled_reason_key": (
				"" if available
				else "UI_MERCHANT_SOLD" if offer["sold"]
				else "UI_MERCHANT_INSUFFICIENT_GOLD"
			),
		})
	return MerchantViewScript.validate(view)


func project_dungeon_event(authoritative: Dictionary, source: Dictionary, reward_offer: Dictionary = {}):
	if not _dungeon_authority_valid(authoritative) or not DungeonViewRulesScript.exact(source, DungeonEventRuntimeScript.VIEW_FIELDS) or source.get("revision") != authoritative.get("revision"):
		return DungeonViewRulesScript.reject(authoritative, "event")
	var view := source.duplicate(true)
	view.merge(_dungeon_header(authoritative), true)
	if not reward_offer.is_empty():
		view["reward_offer"] = reward_offer.duplicate(true)
	return DungeonEventViewScript.validate(view)


func project_room_interaction(authoritative: Dictionary, source: Dictionary):
	if not _dungeon_authority_valid(authoritative) or not DungeonViewRulesScript.exact(source, ["room_type", "node_id", "name_key", "description_key", "choices"]):
		return DungeonViewRulesScript.reject(authoritative, "room")
	var view := source.duplicate(true)
	view.merge(_dungeon_header(authoritative), true)
	return RoomInteractionViewScript.validate(view)


func project_floor_transition(authoritative: Dictionary, floors: Array):
	if not _dungeon_authority_valid(authoritative) or not authoritative.get("completed_floor_ids") is Array:
		return DungeonViewRulesScript.reject(authoritative, "completed_floor_ids")
	var completed: Array = authoritative["completed_floor_ids"]
	if completed.is_empty() or completed.size() >= 5 or floors.size() != 5:
		return DungeonViewRulesScript.reject(authoritative, "completed_floor_ids")
	var index := completed.size() - 1
	for floor_index: int in range(floors.size()):
		if not floors[floor_index] is Dictionary or floors[floor_index].get("id") != FloorDefinitionScript.FLOOR_IDS[floor_index]:
			return DungeonViewRulesScript.reject(authoritative, "floors")
	for floor_index: int in range(completed.size()):
		if completed[floor_index] != FloorDefinitionScript.FLOOR_IDS[floor_index]:
			return DungeonViewRulesScript.reject(authoritative, "completed_floor_ids")
	var view := _dungeon_header(authoritative)
	view.merge({
		"completed_floor_id": floors[index]["id"],
		"completed_floor_index": index,
		"completed_name_key": floors[index]["name_key"],
		"next_floor_id": floors[index + 1]["id"],
		"next_floor_index": index + 1,
		"next_name_key": floors[index + 1]["name_key"],
		"gold": _dungeon_gold(authoritative),
		"available": int(authoritative.get("phase", RunPhaseScript.Value.RUN_PREPARING)) == RunPhaseScript.Value.RUN_PREPARING,
	})
	return FloorTransitionViewScript.validate(view)


func _dungeon_header(authoritative: Dictionary) -> Dictionary:
	return {"schema_version": 1, "revision": authoritative["revision"], "run_id": authoritative["run_id"]}


func _dungeon_authority_valid(authoritative: Dictionary) -> bool:
	return DungeonViewRulesScript.identifier(authoritative.get("run_id")) and DungeonViewRulesScript.integer(authoritative.get("revision")) and int(authoritative["revision"]) >= 0


func _dungeon_gold(authoritative: Dictionary) -> int:
	var economy: Variant = authoritative.get("run_economy", {})
	if not economy is Dictionary or not DungeonViewRulesScript.integer(economy.get("balance")):
		return -1
	return int(economy["balance"])


func _dungeon_room_key(room_type: String) -> String:
	return "UI_ROOM_UNKNOWN" if room_type == "unknown" else "ROOM_TYPE_%s" % room_type.to_upper()


func project(
	authoritative: Dictionary,
	room_definition: Dictionary,
	player_snapshot: Dictionary,
	boss_snapshot: Variant,
	run_time_ms: int,
	ui_context: Dictionary = {}
):
	var run_id := str(authoritative.get("run_id", ""))
	if run_id.is_empty():
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			maxi(0, _view_revision),
			{"field": "authoritative.run_id"}
		)
	var phase := int(authoritative.get("phase", -1))
	var phase_name := _phase_name(phase)
	if phase_name.is_empty():
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			maxi(0, _view_revision),
			{"field": "authoritative.phase"}
		)
	var room_index := int(authoritative.get("current_room", 0))
	var room_total := int(authoritative.get("room_total", 0))
	if room_index <= 0 or room_total <= 0 or room_index > room_total:
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			maxi(0, _view_revision),
			{"field": "authoritative.current_room"}
		)
	var room_type := str(room_definition.get("type", ""))
	if room_type.is_empty():
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			maxi(0, _view_revision),
			{"field": "room_definition.type"}
		)

	var next_revision := 0 if run_id != _last_run_id else _view_revision + 1
	var build: Dictionary = authoritative.get("build", {})
	var build_domain_validation := _validate_build_domain(
		build,
		authoritative.get("config", {})
	)
	if not bool(build_domain_validation.get("ok", false)):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			maxi(0, _view_revision),
			{"field": str(build_domain_validation.get("field", "authoritative.build"))}
		)
	var open_offer: Dictionary = authoritative.get("open_offer", {})
	var result: Dictionary = authoritative.get("result", {})
	var suspended := bool(authoritative.get("suspended", false))
	var player_view := player_snapshot.duplicate(true)
	var weapon_projection := _weapon_view(player_view.get("weapon"))
	if not bool(weapon_projection.get("ok", false)):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			maxi(0, _view_revision),
			{"field": str(weapon_projection.get("field", "player.weapon"))}
		)
	var character_projection := _character_view(player_view.get("character"))
	if not bool(character_projection.get("ok", false)):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			maxi(0, _view_revision),
			{"field": str(character_projection.get("field", "player.character"))}
		)
	var active_item_projection := _active_item_view(player_view.get("active_item"))
	if not bool(active_item_projection.get("ok", false)):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			maxi(0, _view_revision),
			{"field": str(active_item_projection.get("field", "player.active_item"))}
		)
	player_view.erase("weapon")
	player_view.erase("character")
	player_view.erase("active_item")
	var view_state := {
		"schema_version": RunViewStateScript.SCHEMA_VERSION,
		"revision": next_revision,
		"run_id": run_id,
		"phase": phase_name,
		"suspended": suspended,
		"run_time_ms": maxi(0, run_time_ms),
		"room": {
			"index": room_index,
			"total": room_total,
			"type": room_type,
			"title_key": _dungeon_room_key(room_type) if str(room_definition.get("runtime_mode", "")) == "launch" else "ROOM_M1_%02d" % room_index,
		},
		"player": player_view,
		"weapon_state": (weapon_projection["weapon_state"] as Dictionary).duplicate(true),
		"character_state": (
			(character_projection["character_state"] as Dictionary).duplicate(true)
			if character_projection.get("character_state") is Dictionary
			else null
		),
		"active_item_state": (
			(active_item_projection["active_item_state"] as Dictionary).duplicate(true)
			if active_item_projection.get("active_item_state") is Dictionary
			else null
		),
		"build": _build_view(build),
		"selection": open_offer.duplicate(true) if not open_offer.is_empty() else null,
		"boss": _boss_view(phase, boss_snapshot),
		"result": result.duplicate(true) if not result.is_empty() else null,
		"ui_flags": {
			"show_hud": _shows_hud(phase),
			"accept_gameplay_input": _accepts_gameplay_input(phase, suspended),
			"show_pause": suspended or bool(ui_context.get("show_pause", false)),
		},
	}
	if ui_context.has("dungeon_state"):
		var dungeon_validation = DungeonMapViewScript.validate(ui_context["dungeon_state"])
		if not dungeon_validation.ok:
			return dungeon_validation
		view_state["dungeon_state"] = (ui_context["dungeon_state"] as Dictionary).duplicate(true)
	var validation = RunViewStateScript.validate(view_state)
	if not validation.ok:
		return validation

	_last_run_id = run_id
	_view_revision = next_revision
	_latest_view_state = RunViewStateScript.copy_of(view_state)
	return CommandResultScript.success(
		_view_revision,
		{"view_state": _latest_view_state}
	)


func latest_view_state() -> Dictionary:
	return _latest_view_state.duplicate(true)


func _active_item_view(value: Variant) -> Dictionary:
	if value == null:
		return {"ok": true, "active_item_state": null}
	if not value is Dictionary:
		return {"ok": false, "field": "player.active_item"}
	var source := value as Dictionary
	if not bool(source.get("equipped", false)):
		return {"ok": true, "active_item_state": null}
	for field: String in ["content_id", "name_key", "icon_id", "archetype"]:
		if typeof(source.get(field)) != TYPE_STRING or str(source.get(field, "")).is_empty():
			return {"ok": false, "field": "player.active_item.%s" % field}
	for field: String in ["cooldown_remaining_frames", "cooldown_max_frames"]:
		if typeof(source.get(field)) != TYPE_INT:
			return {"ok": false, "field": "player.active_item.%s" % field}
	return {
		"ok": true,
		"active_item_state": {
			"content_id": str(source["content_id"]),
			"name_key": str(source["name_key"]),
			"icon_id": str(source["icon_id"]),
			"archetype": str(source["archetype"]),
			"cooldown_current": int(source["cooldown_remaining_frames"]),
			"cooldown_max": int(source["cooldown_max_frames"]),
			"ready": bool(source.get("ready", false)),
		},
	}


func _validate_build_domain(build: Dictionary, config_value: Variant) -> Dictionary:
	if not config_value is Dictionary:
		return {"ok": false, "field": "authoritative.config"}
	var config := config_value as Dictionary
	if typeof(config.get("milestone")) != TYPE_STRING:
		return {"ok": false, "field": "authoritative.config.milestone"}
	var milestone := str(config["milestone"])
	var expected_ids: Array[String] = []
	if milestone in ["M1", "CURRENT", "NEXT"]:
		expected_ids = RunViewStateScript.M1_ARCHETYPE_IDS
	elif milestone in ["LAUNCH", "EXPANSION"]:
		expected_ids = ArchetypeProfileScript.ARCHETYPE_IDS
	else:
		return {"ok": false, "field": "authoritative.config.milestone"}
	var scores_value: Variant = build.get("archetypes", {})
	if not scores_value is Dictionary:
		return {"ok": false, "field": "authoritative.build.archetypes"}
	var scores := scores_value as Dictionary
	if scores.size() != expected_ids.size():
		return {"ok": false, "field": "authoritative.build.archetypes"}
	for archetype_id: String in expected_ids:
		if not scores.has(archetype_id):
			return {"ok": false, "field": "authoritative.build.archetypes"}
	return {"ok": true, "field": ""}


func _character_view(value: Variant) -> Dictionary:
	if value == null:
		return {"ok": true, "character_state": null}
	if not value is Dictionary:
		return {"ok": false, "field": "player.character"}
	var source := value as Dictionary
	if source.is_empty() or str(source.get("runtime_kind", "")) == "wanderer_m1_compat":
		return {"ok": true, "character_state": null}
	var runtime_kind := str(source.get("runtime_kind", source.get("character_id", "")))
	var profile := _character_profile(runtime_kind)
	if profile.is_empty():
		return {"ok": false, "field": "player.character.runtime_kind"}
	var runtime_frame_value: Variant = source.get("runtime_frame", 0)
	if typeof(runtime_frame_value) != TYPE_INT or int(runtime_frame_value) < 0:
		return {"ok": false, "field": "player.character.runtime_frame"}
	var runtime_frame := int(runtime_frame_value)
	var cooldown_until_value: Variant = source.get("skill_cooldown_until_frame", -1)
	if typeof(cooldown_until_value) != TYPE_INT or int(cooldown_until_value) < -1:
		return {"ok": false, "field": "player.character.skill_cooldown_until_frame"}
	var cooldown_max := int(profile["cooldown_max"])
	var cooldown_current := clampi(int(cooldown_until_value) - runtime_frame, 0, cooldown_max)
	var status := _character_status(runtime_kind, source, runtime_frame)
	if not bool(status.get("ok", false)):
		return status
	var meter_max_value: Variant = source.get("resource_maximum", profile["meter_max"])
	return {
		"ok": true,
		"character_state": {
			"character_id": runtime_kind,
			"skill_id": str(profile["skill_id"]),
			"phase": str(source.get("phase", "READY")),
			"cooldown_current": cooldown_current,
			"cooldown_max": cooldown_max,
			"meter_kind": str(profile["meter_kind"]),
			"meter_current": source.get("resource_value", 0),
			"meter_max": meter_max_value,
			"status_id": str(status["status_id"]),
			"status_stacks": int(status["status_stacks"]),
			"status_remaining": status["status_remaining"],
			"secondary_id": str(status["secondary_id"]),
			"secondary_value": status["secondary_value"],
		},
	}


func _character_profile(runtime_kind: String) -> Dictionary:
	match runtime_kind:
		"wanderer":
			return {"skill_id": "waypoint_recall", "cooldown_max": 720, "meter_kind": "path_marks", "meter_max": 5}
		"time_guardian":
			return {"skill_id": "chrono_fortress", "cooldown_max": 600, "meter_kind": "ward", "meter_max": 3}
		"void_walker":
			return {"skill_id": "void_devour", "cooldown_max": 480, "meter_kind": "void_debt", "meter_max": 100}
		"primordial_knight":
			return {"skill_id": "realm_cleave", "cooldown_max": 540, "meter_kind": "resonance", "meter_max": 3}
		"time_lord":
			return {"skill_id": "codex_dominion", "cooldown_max": 480, "meter_kind": "codex_pages", "meter_max": 3}
		_:
			return {}


func _character_status(runtime_kind: String, source: Dictionary, runtime_frame: int) -> Dictionary:
	var status_id := "ready"
	var status_stacks := 0
	var status_remaining: Variant = 0
	var secondary_id := ""
	var secondary_value: Variant = 0
	match runtime_kind:
		"wanderer":
			if bool(source.get("anchor_active", false)):
				status_id = "anchor"
				status_remaining = maxi(0, int(source.get("anchor_expires_frame", -1)) - runtime_frame)
			elif bool(source.get("wayfarer_active", false)):
				status_id = "wayfarer"
				status_remaining = maxi(0, int(source.get("wayfarer_until_frame", -1)) - runtime_frame)
			var path_progress := int(source.get("path_progress", 0))
			if path_progress > 0:
				secondary_id = "path_progress"
				secondary_value = path_progress
		"time_guardian":
			if bool(source.get("guard_active", false)):
				status_id = "guarding"
			elif bool(source.get("fortress_active", false)):
				status_id = "fortress"
				status_remaining = maxi(0, int(source.get("fortress_until_frame", -1)) - runtime_frame)
			elif bool(source.get("rebuke_active", false)):
				status_id = "rebuke"
				status_remaining = maxi(0, int(source.get("rebuke_until_frame", -1)) - runtime_frame)
		"void_walker":
			if bool(source.get("skill_active", false)):
				status_id = "devouring"
			elif bool(source.get("corruption_active", false)):
				status_id = "corruption"
				status_remaining = maxi(0, int(source.get("next_corruption_frame", -1)) - runtime_frame)
			var threshold := int(source.get("corruption_threshold", 0))
			if threshold > 0:
				secondary_id = "corruption_threshold"
				secondary_value = threshold
		"primordial_knight":
			var pending_echoes := int(source.get("pending_echo_count", 0))
			if bool(source.get("armor_active", false)):
				status_id = "armored"
			elif pending_echoes > 0:
				status_id = "echo_pending"
				status_stacks = pending_echoes
			if pending_echoes > 0:
				secondary_id = "pending_echoes"
				secondary_value = pending_echoes
		"time_lord":
			var dominion_remaining := maxi(0, int(source.get("dominion_until_frame", -1)) - runtime_frame)
			var infusion_remaining := maxi(0, int(source.get("infusion_until_frame", -1)) - runtime_frame)
			var primer_remaining := maxi(0, int(source.get("primer_expires_frame", -1)) - runtime_frame)
			var primer_id := str(source.get("primer_ability_id", ""))
			if dominion_remaining > 0:
				status_id = "dominion"
				status_remaining = dominion_remaining
			elif infusion_remaining > 0:
				status_id = "infusion"
				status_remaining = infusion_remaining
			elif not primer_id.is_empty():
				if not TimeAbilityIdsScript.is_canonical_id(primer_id):
					return {"ok": false, "field": "player.character.primer_ability_id"}
				status_id = "primer"
				status_remaining = primer_remaining
				secondary_id = "primer"
				secondary_value = primer_id
	if status_id != "ready" and status_stacks == 0:
		status_stacks = 1
	return {
		"ok": true,
		"status_id": status_id,
		"status_stacks": status_stacks,
		"status_remaining": status_remaining,
		"secondary_id": secondary_id,
		"secondary_value": secondary_value,
	}


func _weapon_view(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "field": "player.weapon"}
	var source := value as Dictionary
	var runtime_value: Variant = source.get("runtime", {})
	var runtime := runtime_value as Dictionary if runtime_value is Dictionary else {}
	var weapon_id := str(source.get("weapon_id", runtime.get("weapon_id", "")))
	var runtime_weapon_id := str(runtime.get("weapon_id", weapon_id))
	if weapon_id.is_empty() or (not runtime_weapon_id.is_empty() and runtime_weapon_id != weapon_id):
		return {"ok": false, "field": "player.weapon.weapon_id"}
	var action_id := str(source.get("action_id", runtime.get("action_id", "")))
	var phase := str(source.get("phase", runtime.get("phase", "READY")))
	match weapon_id:
		"sword":
			return _sword_weapon_view(action_id, phase, runtime)
		"bow":
			return _bow_weapon_view(action_id, phase, source, runtime)
		"gun":
			return _gun_weapon_view(action_id, phase, runtime)
		"staff":
			return _staff_weapon_view(action_id, phase, runtime)
		"gauntlets":
			return _gauntlets_weapon_view(action_id, phase, runtime)
		_:
			return {
				"ok": true,
				"weapon_state": _weapon_state(
					weapon_id,
					action_id,
					phase,
					"unknown",
					0,
					1,
					"ready",
					0,
					0,
					"",
					0
				),
			}


func _sword_weapon_view(action_id: String, phase: String, runtime: Dictionary) -> Dictionary:
	var ready := phase == "READY"
	var combo_step: Variant = runtime.get("combo_step", 0)
	return {
		"ok": true,
		"weapon_state": _weapon_state(
			"sword",
			action_id,
			phase,
			"counter",
			1 if ready else 0,
			1,
			"counter_ready" if ready else "acting",
			1 if ready else 0,
			0,
			"combo",
			combo_step
		),
	}


func _bow_weapon_view(
	action_id: String,
	phase: String,
	source: Dictionary,
	runtime: Dictionary
) -> Dictionary:
	var charge_current: Variant = _first_value(source, runtime, ["charge_frames", "effective_hold_frames"], 0.0)
	var charge_maximum: Variant = _first_value(source, runtime, ["maximum_charge_frames", "maximum_hold_frames"], 1.0)
	var full_charge := bool(source.get("full_charge", runtime.get("full_charge", false)))
	var status_id := "ready"
	if full_charge:
		status_id = "full_charge"
	elif phase == "HOLD":
		status_id = "charging"
	elif phase != "READY":
		status_id = "acting"
	var holding := phase == "HOLD"
	return {
		"ok": true,
		"weapon_state": _weapon_state(
			"bow",
			action_id,
			phase,
			"charge",
			charge_current,
			charge_maximum,
			status_id,
			0 if status_id in ["ready", "acting"] else 1,
			0,
			"hold" if holding else "",
			charge_current if holding else 0
		),
	}


func _gun_weapon_view(action_id: String, phase: String, runtime: Dictionary) -> Dictionary:
	var reloading := action_id == "reload" and phase != "READY"
	var reload_frame: Variant = runtime.get("reload_frame", 0)
	var ammo: Variant = runtime.get("ammo", 0)
	var ammo_maximum: Variant = runtime.get("ammo_maximum", 0)
	var time_load_remaining: Variant = runtime.get("time_load_remaining_frames", 0)
	var time_load_source := str(runtime.get("time_load_source", ""))
	var has_time_load := not time_load_source.is_empty() or not _is_zero_finite_number(time_load_remaining)
	var reload_window_value: Variant = runtime.get("reload_window", {})
	var reload_window := reload_window_value as Dictionary if reload_window_value is Dictionary else {}
	var perfect_reload := reloading and (
		bool(reload_window.get("perfect_confirm", false))
		or time_load_source == "perfect_reload"
	)
	var status_id := "ready"
	if perfect_reload:
		status_id = "perfect_reload"
	elif reloading:
		status_id = "reloading"
	elif has_time_load:
		status_id = "time_load"
	elif phase != "READY":
		status_id = "acting"
	var secondary_time_load := has_time_load and status_id != "time_load"
	return {
		"ok": true,
		"weapon_state": _weapon_state(
			"gun",
			action_id,
			phase,
			"reload" if reloading else "ammo",
			reload_frame if reloading else ammo,
			48 if reloading else ammo_maximum,
			status_id,
			0 if status_id in ["ready", "acting"] else 1,
			time_load_remaining if status_id == "time_load" else 0,
			"time_load" if secondary_time_load else "",
			time_load_remaining if secondary_time_load else 0
		),
	}


func _staff_weapon_view(action_id: String, phase: String, runtime: Dictionary) -> Dictionary:
	var mana: Variant = runtime.get("mana", 0.0)
	var mana_maximum: Variant = runtime.get("mana_maximum", 100.0)
	var element_field := "element" if runtime.has("element") else "current_element"
	var current_element := str(runtime.get(element_field, "fire"))
	var element_code := _staff_element_code(current_element)
	if element_code == 0:
		return {"ok": false, "field": "player.weapon.runtime.%s" % element_field}
	var sequence_first_element := str(runtime.get(
		"combo_element",
		runtime.get("sequence_first_element", "")
	))
	var sequence_remaining: Variant = runtime.get(
		"combo_remaining_frames",
		runtime.get("sequence_remaining_frames", 0)
	)
	var has_sequence := not sequence_first_element.is_empty() and not _is_zero_finite_number(sequence_remaining)
	var status_id := "element_%s" % current_element
	if has_sequence:
		status_id = "sequence_ready"
	elif phase == "HOLD":
		status_id = "channeling"
	elif phase != "READY":
		status_id = "acting"
	return {
		"ok": true,
		"weapon_state": _weapon_state(
			"staff",
			action_id,
			phase,
			"mana",
			mana,
			mana_maximum,
			status_id,
			0 if status_id == "acting" else 1,
			sequence_remaining if has_sequence else 0,
			"element",
			element_code
		),
	}


func _staff_element_code(element_id: String) -> int:
	match element_id:
		"fire":
			return 1
		"ice":
			return 2
		"lightning":
			return 3
		_:
			return 0


func _gauntlets_weapon_view(action_id: String, phase: String, runtime: Dictionary) -> Dictionary:
	var combo_field := "combo_count" if runtime.has("combo_count") else "combo"
	var combo_value: Variant = runtime.get(combo_field, 0)
	if typeof(combo_value) != TYPE_INT or int(combo_value) < 0 or int(combo_value) > 999:
		return {"ok": false, "field": "player.weapon.runtime.%s" % combo_field}
	var combo_count := int(combo_value)
	var chain_step_value: Variant = runtime.get("chain_step", 0)
	if typeof(chain_step_value) != TYPE_INT or int(chain_step_value) < 0 or int(chain_step_value) > 4:
		return {"ok": false, "field": "player.weapon.runtime.chain_step"}
	var combo_remaining: Variant = runtime.get(
		"combo_remaining_frames",
		runtime.get("combo_timeout_remaining_frames", 0)
	)
	if typeof(combo_remaining) != TYPE_INT or int(combo_remaining) < 0:
		return {"ok": false, "field": "player.weapon.runtime.combo_remaining_frames"}
	var counter_ready_value: Variant = runtime.get("counter_ready", false)
	if typeof(counter_ready_value) != TYPE_BOOL:
		return {"ok": false, "field": "player.weapon.runtime.counter_ready"}
	var counter_ready := bool(counter_ready_value)
	var meter_kind := "counter" if counter_ready else "combo"
	var meter_current: Variant = 1 if counter_ready else mini(combo_count, 30)
	var meter_max: Variant = 1 if counter_ready else 30
	var status_id := "ready"
	if counter_ready:
		status_id = "counter_ready"
	elif phase != "READY":
		status_id = "acting"
	elif combo_count >= 5:
		status_id = "combo_active"
	return {
		"ok": true,
		"weapon_state": _weapon_state(
			"gauntlets",
			action_id,
			phase,
			meter_kind,
			meter_current,
			meter_max,
			status_id,
			0 if status_id in ["ready", "acting"] else 1,
			combo_remaining if status_id == "combo_active" else 0,
			"combo" if combo_count > 0 else "",
			combo_count if combo_count > 0 else 0
		),
	}


func _weapon_state(
	weapon_id: String,
	action_id: String,
	phase: String,
	meter_kind: String,
	meter_current: Variant,
	meter_max: Variant,
	status_id: String,
	status_stacks: int,
	status_remaining: Variant,
	secondary_id: String,
	secondary_value: Variant
) -> Dictionary:
	return {
		"weapon_id": weapon_id,
		"action_id": action_id,
		"phase": phase,
		"meter_kind": meter_kind,
		"meter_current": meter_current,
		"meter_max": meter_max,
		"status_id": status_id,
		"status_stacks": status_stacks,
		"status_remaining": status_remaining,
		"secondary_id": secondary_id,
		"secondary_value": secondary_value,
	}


func _first_value(
	primary: Dictionary,
	secondary: Dictionary,
	fields: Array[String],
	fallback: Variant
) -> Variant:
	for field: String in fields:
		if primary.has(field):
			return primary[field]
		if secondary.has(field):
			return secondary[field]
	return fallback


func _is_zero_finite_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) == 0
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	return is_zero_approx(float(value))


func _build_view(build: Dictionary) -> Dictionary:
	return {
		"items": (build.get("items", []) as Array).duplicate(),
		"blessings": (build.get("blessings", []) as Array).duplicate(),
		"curses": (build.get("curses", []) as Array).duplicate(),
		"talents": (build.get("talents", []) as Array).duplicate(),
		"dominant_archetype": str(build.get("dominant_archetype", "")),
		"archetype_scores": (build.get("archetypes", {}) as Dictionary).duplicate(true),
	}


func _boss_view(phase: int, boss_snapshot: Variant) -> Variant:
	if phase != RunPhaseScript.Value.BOSS_ACTIVE or not boss_snapshot is Dictionary:
		return null
	var boss := boss_snapshot as Dictionary
	return boss.duplicate(true) if not boss.is_empty() else null


func _shows_hud(phase: int) -> bool:
	return phase in [
		RunPhaseScript.Value.ROOM_ACTIVE,
		RunPhaseScript.Value.ROOM_ENTERING,
		RunPhaseScript.Value.COMBAT_ACTIVE,
		RunPhaseScript.Value.ROOM_RESOLVING,
		RunPhaseScript.Value.SELECTION_ACTIVE,
		RunPhaseScript.Value.ROOM_TRANSITION,
		RunPhaseScript.Value.BOSS_ACTIVE,
	]


func _accepts_gameplay_input(phase: int, suspended: bool) -> bool:
	return not suspended and phase in [
		RunPhaseScript.Value.COMBAT_ACTIVE,
		RunPhaseScript.Value.BOSS_ACTIVE,
	]


func _phase_name(phase: int) -> String:
	match phase:
		RunPhaseScript.Value.BOOT:
			return "BOOT"
		RunPhaseScript.Value.HUB:
			return "HUB"
		RunPhaseScript.Value.RUN_PREPARING:
			return "RUN_PREPARING"
		RunPhaseScript.Value.ROOM_ENTERING:
			return "ROOM_ENTERING"
		RunPhaseScript.Value.COMBAT_ACTIVE:
			return "COMBAT_ACTIVE"
		RunPhaseScript.Value.ROOM_RESOLVING:
			return "ROOM_RESOLVING"
		RunPhaseScript.Value.SELECTION_ACTIVE:
			return "SELECTION_ACTIVE"
		RunPhaseScript.Value.ROOM_TRANSITION:
			return "ROOM_TRANSITION"
		RunPhaseScript.Value.BOSS_ACTIVE:
			return "BOSS_ACTIVE"
		RunPhaseScript.Value.VICTORY:
			return "VICTORY"
		RunPhaseScript.Value.DEFEAT:
			return "DEFEAT"
		RunPhaseScript.Value.ROOM_ACTIVE:
			return "ROOM_ACTIVE"
		_:
			return ""
