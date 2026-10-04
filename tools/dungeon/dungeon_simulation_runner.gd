extends RefCounted

const FacadeScript := preload("res://scripts/application/run_runtime_facade.gd")
const EffectRuntimeScript := preload("res://scripts/items/player_reward_effect_runtime.gd")
const ContentSnapshotScript := preload("res://scripts/content/content_snapshot_provider.gd")
const SaveServiceScript := preload("res://scripts/save/save_service.gd")
const SaveFileOpsScript := preload("res://scripts/save/save_file_ops.gd")
const ReplaySealScript := preload("res://scripts/replay/run_dungeon_replay_seal.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const EncounterRunnerScript := preload("res://scripts/dungeon/encounter_runner.gd")
const FloorRuleAuthorityScript := preload("res://scripts/dungeon/floor_rule_effect_authority.gd")

class RuleZoneHost:
	extends Node2D

	var configuration: Dictionary = {}

	func active_room() -> Node2D:
		return self

	func floor_rule_configuration() -> Dictionary:
		return configuration.duplicate(true)

class RuleAuthority:
	extends RefCounted

	var effects: Array = []
	var modifier_observation_count := 0
	var _delegate: RefCounted
	var _zone_host: Node2D
	var _player: Node

	func configure(player: Node, configuration: Dictionary) -> bool:
		_player = player
		if _zone_host == null:
			_zone_host = RuleZoneHost.new()
			player.get_parent().add_child(_zone_host)
		_zone_host.set("configuration", configuration.duplicate(true))
		_delegate = FloorRuleAuthorityScript.new()
		return _delegate.call("configure", player, _zone_host)

	func commit_floor_rule_effects(facts: Array) -> bool:
		var before: Dictionary = _player.call("floor_rule_effect_snapshot")
		if not _delegate.call("commit_floor_rule_effects", facts):
			return false
		if _player.call("floor_rule_effect_snapshot") != before:
			modifier_observation_count += 1
		effects.append_array(facts.duplicate(true))
		return true

	func close() -> void:
		_delegate.call("reset")
		_zone_host.free()
		_zone_host = null
		_player = null

var _facade: RefCounted
var _player: Object
var _effect_runtime: RefCounted
var _config: Dictionary
var _failures: Array[String] = []
var _purchase_count := 0
var _consequence_count := 0
var _save_restored := false
var _replay_restored := false
var _player_replay_restored := false
var _room_types: Array[String] = []


func launch_config(seed_value: int, character_id: String = "wanderer", weapon_id: String = "sword", time_pair: Array = ["stop", "rewind"]) -> Dictionary:
	return {
		"schema_version": 1, "milestone": "LAUNCH", "character_id": character_id,
		"weapon_id": weapon_id, "enabled_time_skills": time_pair.duplicate(),
		"difficulty": "normal", "seed": seed_value,
	}


func initialize(config: Dictionary, player: Object) -> Dictionary:
	_config = config.duplicate(true)
	_player = player
	_facade = FacadeScript.new()
	_effect_runtime = EffectRuntimeScript.new()
	if not _accept(_facade.call("boot"), "boot"):
		return {"ok": false, "failures": _failures.duplicate()}
	var run_id := "p14_dungeon_%d_%s_%s" % [int(config["seed"]), str(config["character_id"]), str(config["weapon_id"])]
	if not _accept(_facade.call("start_run", config, run_id), "start_run"):
		return {"ok": false, "failures": _failures.duplicate()}
	if not player.call("configure_run", StringName(run_id)):
		return {"ok": false, "failures": ["player_run_identity"]}
	return {"ok": true}


func player_config() -> Dictionary:
	var accepted := _facade.call("active_loadout") as Dictionary
	var result := (_facade.call("snapshot") as Dictionary).get("config", {}).duplicate(true) as Dictionary
	result["character_profile"] = accepted.get("character_profile", {}).duplicate(true)
	result["weapon_profile"] = accepted.get("weapon_profile", {}).duplicate(true)
	result["character_talent_definitions"] = accepted.get("character_talents", []).duplicate(true)
	return result


func run_five_floors(certify_restore: bool = false) -> Dictionary:
	var rows: Array[Dictionary] = []
	if not _facade.call("configure_merchant_effect_authority", _effect_runtime, _player):
		_failures.append("merchant_effect_authority")
	for floor_index: int in range(5):
		if not _failures.is_empty():
			break
		var row := await _run_floor(floor_index, certify_restore and floor_index == 0)
		rows.append(row)
		if floor_index < 4 and _failures.is_empty():
			_accept(_facade.call("start_next_floor"), "start_next_floor_%d" % floor_index)
	var state: Dictionary = _facade.call("snapshot")
	return {
		"seed": int(_config["seed"]), "floor_summaries": rows,
		"failures": _failures.duplicate(), "victory": int(state.get("phase", -1)) == RunPhaseScript.Value.VICTORY,
		"merchant_purchase_count": _purchase_count, "event_consequence_count": _consequence_count,
		"save_restored": _save_restored, "replay_restored": _replay_restored,
		"player_replay_restored": _player_replay_restored,
		"room_types": _room_types.duplicate(),
		"runtime_content_digest": str(ContentSnapshotScript.snapshot(_facade.call("content_registry")).get("aggregate_sha256", "")),
	}


func _run_floor(floor_index: int, certify_restore: bool) -> Dictionary:
	var initial: Dictionary = _facade.call("snapshot")
	var plan := initial.get("floor_plan", {}) as Dictionary
	var row := {
		"seed": int(_config["seed"]), "floor_index": floor_index, "floor_id": str(plan.get("floor_id", "")),
		"generator_version": str(plan.get("generator_version", "")), "plan_digest": str(plan.get("generation_digest", "")),
		"route_edge_ids": [], "room_types": [], "merchant_ids": [], "event_ids": [],
		"rule_id": "", "rule_effect_count": 0, "merchant_purchases": [], "event_consequence_count": 0,
		"rule_health_loss": 0.0, "rule_modifier_observation_count": 0,
		"gold_start": int(initial.get("run_economy", {}).get("balance", 0)),
		"economy_start_revision": int(initial.get("run_economy", {}).get("revision", 0)),
		"gold_earned": 0, "gold_spent": 0, "gold_remainder": 0, "gold_settled": 0,
		"all_buy_count": 0, "completed": false, "failures": [], "gold_ledger": [],
	}
	var authority := RuleAuthority.new()
	var rule_exercised := false
	for step: int in range(16):
		if not _failures.is_empty():
			break
		var choices: Array = _facade.call("route_choices")
		if choices.is_empty():
			_failures.append("empty_route_floor_%d_step_%d" % [floor_index, step])
			break
		var choice := choices[(int(_config["seed"]) + step) % choices.size()] as Dictionary
		if not _route(str(choice["edge_id"])):
			break
		var room: Dictionary = _facade.call("current_room_definition")
		var room_type := str(room.get("room_type", ""))
		EventBus.room_started.emit(str(_player.call("current_run_id")), StringName(str(room["node_id"])), _revision())
		_player.call("advance_action_frame", {})
		(row["route_edge_ids"] as Array).append(str(choice["edge_id"]))
		(row["room_types"] as Array).append(room_type)
		if not _room_types.has(room_type):
			_room_types.append(room_type)
		if not rule_exercised and room_type in ["combat", "elite", "boss"]:
			var registry: RefCounted = _facade.call("content_registry")
			var floor: Dictionary = registry.call("get_content", StringName(str(row["floor_id"])))
			var rule_id := str(floor.get("environment_rule_id", ""))
			if not rule_id.is_empty():
				row["rule_id"] = rule_id
				var health_before_rule := float(_player.get_node("HealthComponent").get("current_hp"))
				rule_exercised = _exercise_rule(rule_id, room, authority)
				row["rule_health_loss"] = float(row["rule_health_loss"]) + health_before_rule - float(_player.get_node("HealthComponent").get("current_hp"))
		var already_completed := false
		if room_type == "shop":
			_visit_merchant(row)
		elif room_type == "event":
			await _visit_event(row)
		elif room_type in ["rest", "treasure"]:
			already_completed = _visit_interaction(room_type)
		if not _failures.is_empty():
			break
		if room_type == "boss" and certify_restore:
			if (_facade.call("snapshot") as Dictionary).get("floor_rule_state", {}).is_empty():
				var health_before_rule := float(_player.get_node("HealthComponent").get("current_hp"))
				_exercise_rule(str(row["rule_id"]), room, authority)
				row["rule_health_loss"] = float(row["rule_health_loss"]) + health_before_rule - float(_player.get_node("HealthComponent").get("current_hp"))
			_certify_save_and_replay(authority)
			if not _failures.is_empty():
				break
		if not already_completed:
			var completed = _facade.call("complete_current_room")
			if not _accept(completed, "complete_%s" % room_type):
				break
		if room_type in ["combat", "elite"] and _facade.has_method("open_current_room_reward"):
			_accept(_facade.call("open_current_room_reward", _revision()), "room_reward_open")
		_resolve_open_reward()
		if room_type == "boss":
			row["completed"] = true
			break
	var final_state: Dictionary = _facade.call("snapshot")
	var final_economy := final_state.get("run_economy", {}) as Dictionary
	row["gold_remainder"] = int(final_economy.get("balance", 0))
	for ledger_value: Variant in final_economy.get("ledger", []):
		var ledger := ledger_value as Dictionary
		if int(ledger.get("revision", 0)) <= int(initial.get("run_economy", {}).get("revision", 0)):
			continue
		var amount := int(ledger.get("amount", 0))
		(row["gold_ledger"] as Array).append(ledger.duplicate(true))
		var operation := str(ledger.get("operation", ""))
		if operation == "gold_decay":
			row["gold_settled"] = int(row["gold_settled"]) + amount
		elif amount >= 0:
			row["gold_earned"] = int(row["gold_earned"]) + amount
		else:
			row["gold_spent"] = int(row["gold_spent"]) - amount
	row["rule_effect_count"] = authority.effects.size()
	row["rule_modifier_observation_count"] = authority.modifier_observation_count
	if row["rule_id"].is_empty() or int(row["rule_effect_count"]) == 0:
		_failures.append("floor_rule_not_exercised")
	var rolling_balance := int(row["gold_start"])
	var minimum_balance := rolling_balance
	for ledger_value: Variant in row["gold_ledger"]:
		rolling_balance += int(ledger_value["amount"])
		minimum_balance = mini(minimum_balance, rolling_balance)
	row["minimum_gold_balance"] = minimum_balance
	if rolling_balance != int(row["gold_remainder"]):
		_failures.append("economy_ledger_balance_drift")
	row["failures"] = _failures.duplicate()
	if not row["rule_id"].is_empty():
		authority.close()
	return row


func _route(edge_id: String) -> bool:
	var begun = _facade.call("begin_route_transition", StringName(edge_id), _revision())
	if not _accept(begun, "route_begin"):
		return false
	var transition_id := str(begun.get("context").get("transition_id", ""))
	var finalized = _facade.call("finalize_route_transition", transition_id, _revision())
	if not _accept(finalized, "route_finalize"):
		return false
	var confirmed = _facade.call("confirm_route_transition", transition_id, _revision())
	if not _accept(confirmed, "route_confirm"):
		return false
	if not _facade.call("publish_confirmed_route_event_facts", confirmed.get("context").get("event_facts", [])):
		_failures.append("route_event_publication")
	return _failures.is_empty()


func _exercise_rule(rule_id: String, room: Dictionary, authority: RefCounted) -> bool:
	var configuration := {
		"room_id": str(room["node_id"]), "room_seed": int(_config["seed"]),
		"zones": [
			{"id": "hazard_west", "bounds": {"x": 32.0, "y": 48.0, "width": 160.0, "height": 120.0}},
			{"id": "safe_core", "bounds": {"x": 224.0, "y": 96.0, "width": 192.0, "height": 168.0}},
		],
		"safe_zone_ids": ["safe_core"], "reduced_motion": false, "hit_flash_enabled": true,
	}
	if not authority.call("configure", _player, configuration):
		_failures.append("production_floor_rule_authority")
		return false
	_player.set("global_position", Vector2(96.0, 96.0))
	if not _accept(_facade.call("configure_floor_rule", StringName(rule_id), configuration, authority, _revision()), "rule_configure"):
		return false
	for frame: int in [90, 180, 360, 720]:
		if not _accept(_facade.call("advance_floor_rule_frame", frame, {}, _revision()), "rule_advance"):
			return false
	return true


func _visit_merchant(row: Dictionary) -> void:
	if not _accept(_facade.call("open_current_merchant"), "merchant_open"):
		return
	var view: Dictionary = _facade.call("merchant_view_state")
	(row["merchant_ids"] as Array).append(str(view.get("merchant_id", "")))
	var offers := view.get("inventory", {}).get("offers", []) as Array
	offers = offers.duplicate(true)
	offers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left["price"]) != int(right["price"]):
			return int(left["price"]) < int(right["price"])
		return str(left["offer_id"]) < str(right["offer_id"])
	)
	var registry: RefCounted = _facade.call("content_registry")
	var economy_profile: Dictionary = registry.call("get_content", &"launch_economy_v1")
	var spend_min := int(economy_profile["floor_income_budgets"][int(row["floor_index"])]["spend_min"])
	var purchased := 0
	var total_price := 0
	for value: Variant in offers:
		if not bool(value.get("sold", false)):
			total_price += int(value.get("price", 0))
	row["all_buy_count"] = int(total_price > 0 and total_price <= int(view.get("gold", 0)))
	for offer_value: Variant in offers:
		var live: Dictionary = _facade.call("snapshot")
		var spent := 0
		for ledger_value: Variant in live.get("run_economy", {}).get("ledger", []):
			if int(ledger_value.get("revision", 0)) > int(row["economy_start_revision"]) and int(ledger_value.get("amount", 0)) < 0 and str(ledger_value.get("operation", "")) != "gold_decay":
				spent -= int(ledger_value["amount"])
		if spent >= spend_min:
			break
		var offer := offer_value as Dictionary
		var owned := live.get("build", {}) as Dictionary
		if bool(offer.get("sold", false)) or (owned.get("items", []) as Array).has(str(offer.get("reward_id", ""))) or (owned.get("blessings", []) as Array).has(str(offer.get("reward_id", ""))) or int(offer.get("price", 0)) > int(live.get("run_economy", {}).get("balance", 0)):
			continue
		var transaction_id := "tx_p14_buy_%d_%d" % [int(row["floor_index"]), purchased]
		var bought = _facade.call("purchase_current_merchant", transaction_id, str(offer["offer_id"]))
		if not _accept(bought, "merchant_purchase_%s_floor_%d" % [str(offer.get("reward_id", "")), int(row["floor_index"]) + 1]):
			return
		(row["merchant_purchases"] as Array).append({"offer_id": str(offer["offer_id"]), "price": int(offer["price"]), "transaction_id": transaction_id})
		_purchase_count += 1
		purchased += 1


func _visit_event(row: Dictionary) -> void:
	var host: Node = _player.get_parent()
	var enemies := Node.new()
	var encounter_runner := EncounterRunnerScript.new()
	host.add_child(enemies)
	host.add_child(encounter_runner)
	encounter_runner.configure(enemies)
	encounter_runner.set_timing_override(0.0)
	var room_runtime: Node = _facade.call("create_room_runtime", encounter_runner)
	host.add_child(room_runtime)
	room_runtime.spawn_requested.connect(func(spawn: Dictionary) -> void:
		var entity := Node.new()
		enemies.add_child(entity)
		if room_runtime.call("register_spawned", entity, spawn):
			room_runtime.call("report_entity_died", entity)
		entity.queue_free()
	)
	if not _accept(room_runtime.call("begin_current_room"), "event_open"):
		room_runtime.free()
		encounter_runner.free()
		enemies.free()
		return
	var view: Dictionary = _facade.call("event_view_state")
	(row["event_ids"] as Array).append(str(view.get("event_id", "")))
	var option_id := "decline"
	for value: Variant in view.get("options", []):
		var option := value as Dictionary
		if str(option.get("id", "")) == "commit" and bool(option.get("eligible", false)):
			option_id = "commit"
	if not _accept(room_runtime.call("choose_current_event_option", StringName(option_id), _revision()), "event_choose_%s_%s_floor_%d" % [str(view.get("event_id", "")), option_id, int(row["floor_index"]) + 1]):
		room_runtime.free()
		encounter_runner.free()
		enemies.free()
		return
	view = _facade.call("event_view_state")
	if str(view.get("phase", "")) == "pending_reward":
		if _facade.has_method("event_reward_offer") and _facade.has_method("submit_current_event_reward"):
			var offer: Dictionary = _facade.call("event_reward_offer")
			var options := offer.get("options", []) as Array
			if options.is_empty():
				_failures.append("event_reward_offer_empty")
			else:
				_accept(_facade.call("submit_current_event_reward", StringName(str(options[0]["option_id"])), _revision()), "event_reward")
		else:
			_failures.append("event_reward_requires_production_api")
		view = _facade.call("event_view_state")
	if str(view.get("phase", "")) == "pending_encounter":
		for _frame: int in range(128):
			if not encounter_runner.is_active():
				break
			await host.get_tree().process_frame
		view = _facade.call("event_view_state")
	room_runtime.free()
	encounter_runner.free()
	enemies.free()
	if str(view.get("phase", "")) != "resolved":
		_failures.append("event_unresolved_%s" % str(view.get("phase", "")))
		return
	if option_id == "commit":
		_consequence_count += 1
		row["event_consequence_count"] = int(row["event_consequence_count"]) + 1
	_accept(_facade.call("dismiss_current_event", _revision()), "event_dismiss")


func _visit_interaction(room_type: String) -> bool:
	if not _facade.has_method("resolve_current_room_interaction"):
		_failures.append("room_interaction_requires_production_api")
		return false
	var source: Dictionary = _facade.call("room_interaction_view_state")
	var choice_id := &"claim" if room_type == "treasure" else &"leave"
	if room_type == "rest":
		for choice: Dictionary in source.get("choices", []):
			if str(choice.get("id", "")) in ["heal", "upgrade"] and bool(choice.get("available", false)):
				choice_id = StringName(str(choice["id"]))
				break
	var result = _facade.call("resolve_current_room_interaction", choice_id, _revision())
	if not _accept(result, "%s_interaction" % room_type):
		return false
	_resolve_open_reward()
	return bool(result.get("context").get("room_completed", false))


func _resolve_open_reward() -> void:
	var state: Dictionary = _facade.call("snapshot")
	var offer := state.get("open_offer", {}) as Dictionary
	if offer.is_empty():
		return
	var options := offer.get("options", []) as Array
	if options.is_empty():
		_failures.append("empty_reward_offer")
		return
	var method := &"commit_current_reward" if _facade.has_method("commit_current_reward") else &"submit_selection"
	_accept(_facade.call(method, str(offer["offer_id"]), str(options[0]["option_id"]), int(offer["revision"])), "reward_selection_%s" % str(options[0]["option_id"]))
	if int((_facade.call("snapshot") as Dictionary).get("phase", -1)) == RunPhaseScript.Value.ROOM_TRANSITION:
		_accept(_facade.call("complete_transition"), "reward_transition")


func _certify_save_and_replay(authority: RefCounted) -> void:
	var state: Dictionary = _facade.call("snapshot")
	var registry: RefCounted = _facade.call("content_registry")
	var content := ContentSnapshotScript.snapshot(registry)
	var base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if base.is_empty():
		base = OS.get_temp_dir().path_join("planewalker-p14")
	var save_root := base.path_join("dungeon_%d_%s_%s" % [OS.get_process_id(), str(_config["character_id"]), str(_config["weapon_id"])])
	var service = SaveServiceScript.new()
	if not _accept(service.configure(save_root, "0.4.0-dev", content), "save_configure"):
		return
	var saved = service.save_profile("slot_1", "base", {"active_run_state": state})
	if not _accept(saved, "save_write"):
		return
	var loaded = service.load_profile("slot_1", "base")
	if not _accept(loaded, "save_read"):
		return
	if loaded.payload.get("active_run_state", {}) != state:
		_failures.append("save_round_trip_drift:%s" % _first_drift(state, loaded.payload.get("active_run_state", {})))
	var restored = FacadeScript.new()
	_accept(restored.call("boot"), "save_facade_boot")
	restored.call("configure_merchant_effect_authority", EffectRuntimeScript.new(), _player)
	if _accept(restored.call("restore_launch_run", loaded.payload.get("active_run_state", {}), authority), "save_facade_restore"):
		_save_restored = restored.call("snapshot") == state
		if not _save_restored:
			_failures.append("save_facade_drift:%s" % _first_drift(state, restored.call("snapshot")))
	var plan := state["floor_plan"] as Dictionary
	var event_runtime := state["dungeon_event_runtime"] as Dictionary
	var event_state := event_runtime.get("consequence_runtime", {}).get("participant_snapshots", {}).get("event_state", {}) as Dictionary
	var secret := _digest({
		"schema": "event_publication_secret_v1", "content_fingerprint": str(event_state.get("content_fingerprint", "")),
		"run_id": str(state["run_id"]), "run_seed": int(state["run_seed"]),
	})
	var seal = ReplaySealScript.new(secret)
	var room_facts := _room_facts(plan)
	var transitions: Array = [{"sequence": 0, "from_floor_id": "", "to_floor_id": str(plan["floor_id"]), "completed_plan_digest": ""}]
	var captured: Dictionary = seal.call("capture", registry, plan, plan["selected_edge_ids"], room_facts, state["run_economy"], state["merchant_state"], event_runtime, transitions, state["floor_rule_state"], state["events"])
	if captured.is_empty():
		_failures.append("replay_capture")
		return
	var player_replay: Dictionary = _player.call("full_player_replay_snapshot")
	if player_replay.is_empty():
		_failures.append("player_replay_capture")
		return
	var replay_path := save_root.path_join("checkpoint.replay")
	var replay_file := FileAccess.open(replay_path, FileAccess.WRITE)
	if replay_file == null:
		_failures.append("replay_write")
		return
	replay_file.store_var({"dungeon": captured, "player": player_replay, "run_state": state, "run_state_digest": _digest(state)}, false)
	replay_file.close()
	replay_file = FileAccess.open(replay_path, FileAccess.READ)
	var restored_bundle: Variant = replay_file.get_var(false)
	replay_file.close()
	SaveFileOpsScript.new().remove_tree(save_root)
	if not restored_bundle is Dictionary:
		_failures.append("replay_read")
		return
	var checkpoint_state := restored_bundle.get("run_state", {}) as Dictionary
	if checkpoint_state != state or _digest(checkpoint_state) != restored_bundle.get("run_state_digest", ""):
		_failures.append("replay_run_state_checkpoint_drift")
		return
	var decoded := restored_bundle.get("dungeon", {}) as Dictionary
	var validated: Dictionary = seal.call("validate", decoded, registry, checkpoint_state["floor_plan"], checkpoint_state["run_economy"], checkpoint_state["merchant_state"], checkpoint_state["dungeon_event_runtime"], checkpoint_state["floor_rule_state"], checkpoint_state["events"])
	if not _accept(validated, "replay_validate"):
		return
	var time_manager: Node = _player.get_node("TimeManager")
	time_manager.set("energy", 0.0)
	_player_replay_restored = _player.call("restore_full_player_replay_snapshot", restored_bundle.get("player", {})) and _player.call("full_player_replay_snapshot") == player_replay
	if not _player_replay_restored:
		_failures.append("player_replay_restore")
	var replay_restored = FacadeScript.new()
	_accept(replay_restored.call("boot"), "replay_facade_boot")
	replay_restored.call("configure_merchant_effect_authority", EffectRuntimeScript.new(), _player)
	_replay_restored = _accept(replay_restored.call("restore_launch_run", checkpoint_state, authority), "replay_facade_restore") and replay_restored.call("snapshot") == checkpoint_state
	if not _replay_restored:
		_failures.append("replay_facade_drift")


func _room_facts(plan: Dictionary) -> Array:
	var facts: Array = []
	for node_id: Variant in plan.get("visited_node_ids", []):
		if str(node_id) == str(plan.get("entry_node_id", "entry")):
			continue
		facts.append({"node_id": str(node_id), "fact_type": "room_entered", "sequence": facts.size()})
		for value: Variant in plan.get("nodes", []):
			var node := value as Dictionary
			if str(node.get("id", "")) == str(node_id) and bool(node.get("cleared", false)):
				facts.append({"node_id": str(node_id), "fact_type": "room_cleared", "sequence": facts.size()})
	return facts


func _revision() -> int:
	return int((_facade.call("snapshot") as Dictionary).get("revision", -1))


func _accept(result: Variant, operation: String) -> bool:
	if result != null and bool(result.get("ok")):
		return true
	_failures.append("%s:%s:%s" % [operation, str(result.get("code")) if result != null else "NULL", str(result.get("context")) if result != null else ""])
	return false


func _digest(value: Variant) -> String:
	return var_to_bytes(_canonical(value)).hex_encode().sha256_text()


func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key: Variant in keys:
			result[str(key)] = _canonical(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value:
			result.append(_canonical(entry))
		return result
	return str(value) if typeof(value) == TYPE_STRING_NAME else value


func _first_drift(expected: Variant, actual: Variant, path: String = "") -> String:
	if expected is Dictionary and actual is Dictionary:
		for key: Variant in expected:
			if not actual.has(key):
				return "%s.%s:missing" % [path, key]
			if expected[key] != actual[key]:
				return _first_drift(expected[key], actual[key], "%s.%s" % [path, key])
	elif expected is Array and actual is Array:
		if expected.size() != actual.size():
			return "%s:size_%d_%d" % [path, expected.size(), actual.size()]
		for index: int in range(expected.size()):
			if expected[index] != actual[index]:
				return _first_drift(expected[index], actual[index], "%s[%d]" % [path, index])
	return "%s:%s:%s" % [path, str(expected), str(actual)]
