class_name RunRuntimeFacade
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")
const RunConfigScript := preload("res://scripts/application/run_config.gd")
const RunLoadoutPolicyScript := preload("res://scripts/application/run_loadout_policy.gd")
const RunRewardReplaySealScript := preload(
	"res://scripts/application/run_reward_replay_seal.gd"
)
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const EncounterCatalogScript := preload("res://scripts/dungeon/encounter_catalog.gd")
const M1RoomPlanScript := preload("res://scripts/dungeon/m1_room_plan.gd")
const FloorDefinitionScript := preload("res://scripts/dungeon/floor_definition.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const RoomTemplateDefinitionScript := preload(
	"res://scripts/dungeon/room_template_definition.gd"
)
const RunDirectorScript := preload("res://scripts/dungeon/run_director.gd")
const RoomRuntimeScript := preload("res://scripts/dungeon/room_runtime.gd")
const DraftServiceScript := preload("res://scripts/rewards/draft_service.gd")
const SeedServiceScript := preload("res://scripts/core/seed_service.gd")
const CrumblingGroundRuleScript := preload(
	"res://scripts/dungeon/floor_rules/crumbling_ground_rule.gd"
)
const VoidSporesRuleScript := preload(
	"res://scripts/dungeon/floor_rules/void_spores_rule.gd"
)
const TemporalDistortionRuleScript := preload(
	"res://scripts/dungeon/floor_rules/temporal_distortion_rule.gd"
)
const ForgeVentsRuleScript := preload(
	"res://scripts/dungeon/floor_rules/forge_vents_rule.gd"
)
const CollapsingPlaneRuleScript := preload(
	"res://scripts/dungeon/floor_rules/collapsing_plane_rule.gd"
)

const GAME_VERSION := "0.4.0-dev"
const DEFAULT_CONTENT_PATH := "res://data/content_packs/base/pack.json"
const DEFAULT_ENCOUNTER_PATH := "res://data/encounters/m1_encounters.json"

var _registry: RefCounted
var _encounter_catalog: RefCounted
var _draft: RefCounted
var _orchestrator: RefCounted
var _room_definitions: Array[Dictionary] = []
var _accepted_loadout: Dictionary = {}
var _booted: bool = false
var _selection_reservations: Dictionary = {}
var _next_selection_reservation_id: int = 1
var _last_atomic_transition_revision: int = -1
var _reward_replay_seal: RefCounted
var _director: Node
var _floor_definitions: Array[Dictionary] = []
var _room_templates: Array[Dictionary] = []
var _route_transactions: Dictionary = {}
var _floor_rule_runtime: RefCounted
var _floor_rule_effect_authority: Variant = null


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if _director != null and is_instance_valid(_director):
		_director.free()
	_director = null


func boot(
	content_path: String = DEFAULT_CONTENT_PATH,
	encounter_path: String = DEFAULT_ENCOUNTER_PATH
):
	_booted = false
	_registry = ContentRegistryScript.new()
	_encounter_catalog = EncounterCatalogScript.new()
	_draft = DraftServiceScript.new()
	_orchestrator = RunOrchestratorScript.new()
	_room_definitions.clear()
	_accepted_loadout.clear()
	_selection_reservations.clear()
	_next_selection_reservation_id = 1
	_last_atomic_transition_revision = -1
	_reward_replay_seal = RunRewardReplaySealScript.new()
	if _director != null and is_instance_valid(_director):
		_director.free()
	_director = RunDirectorScript.new()
	_floor_definitions.clear()
	_room_templates.clear()
	_route_transactions.clear()
	_floor_rule_runtime = null
	_floor_rule_effect_authority = null

	var report
	if content_path.to_lower().ends_with("pack.json"):
		report = _registry.load_packs(
			[{"path": content_path, "required": true}],
			GAME_VERSION,
			&"M1"
		)
	else:
		report = _registry.load_manifest(content_path)
	if report.has_blocking_errors():
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE",
			0,
			{"errors": report.blocking_errors.duplicate(true)}
		)
	var encounter_report = _encounter_catalog.load_path(encounter_path)
	if encounter_report.has_blocking_errors():
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE",
			0,
			{"errors": encounter_report.blocking_errors.duplicate(true)}
		)

	_director.configure_from_definitions(M1RoomPlanScript.definitions(_encounter_catalog, 0))
	for room_number: int in range(1, _director.room_count() + 1):
		_room_definitions.append(_director.room_definition_for(room_number))
	var hub_result = _orchestrator.enter_hub()
	_booted = hub_result.ok
	return hub_result


func start_run(config: Dictionary, run_id: String):
	var readiness = _require_booted("start_run")
	if not readiness.ok:
		return readiness
	var normalized := RunConfigScript.normalized(config)
	var config_validation = RunConfigScript.validate(normalized)
	if not config_validation.ok:
		return CommandResultScript.failure(
			config_validation.code,
			_revision(),
			config_validation.context
		)
	var loadout_validation = RunLoadoutPolicyScript.new().validate(normalized, _registry)
	if not loadout_validation.ok:
		return CommandResultScript.failure(
			loadout_validation.code,
			_revision(),
			loadout_validation.context
		)
	var loadout_value: Variant = loadout_validation.context.get("loadout", {})
	if not loadout_value is Dictionary or (loadout_value as Dictionary).is_empty():
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE",
			_revision(),
			{"field": "loadout", "reason": "validated_context_missing"}
		)
	if _orchestrator.phase() != RunPhaseScript.Value.HUB:
		return CommandResultScript.failure(&"INVALID_PHASE", _revision())
	var floor_plan_run := _is_floor_plan_milestone(
		str(normalized.get("milestone", ""))
	)
	if floor_plan_run:
		var launch_content = _configure_launch_content(
			StringName(str(normalized.get("milestone", "")))
		)
		if not launch_content.ok:
			return launch_content

	var candidate_orchestrator = RunOrchestratorScript.new()
	var candidate_director = RunDirectorScript.new()
	var candidate_hub = candidate_orchestrator.enter_hub()
	if not candidate_hub.ok:
		candidate_director.free()
		return CommandResultScript.failure(
			&"INTEGRITY_FAILURE", _revision(), {"stage": "candidate_enter_hub"}
		)
	var started = candidate_orchestrator.start_run(normalized, run_id)
	if not started.ok:
		candidate_director.free()
		return CommandResultScript.failure(started.code, _revision(), started.context)

	var accepted_result = started
	var candidate_rooms: Array[Dictionary] = []
	if floor_plan_run:
		accepted_result = _start_floor_at(
			0, candidate_orchestrator, candidate_director
		)
	else:
		candidate_rooms = M1RoomPlanScript.definitions(
			_encounter_catalog,
			int(candidate_orchestrator.snapshot().get("run_seed", 0))
		)
		candidate_director.configure_from_definitions(candidate_rooms)
		accepted_result = candidate_orchestrator.preparation_completed()
	if not accepted_result.ok:
		candidate_director.free()
		return CommandResultScript.failure(
			accepted_result.code, _revision(), accepted_result.context
		)

	if _director != null and is_instance_valid(_director):
		_director.free()
	_orchestrator = candidate_orchestrator
	_director = candidate_director
	_room_definitions = candidate_rooms.duplicate(true)
	_accepted_loadout = (loadout_value as Dictionary).duplicate(true)
	_draft.reset()
	_selection_reservations.clear()
	_last_atomic_transition_revision = -1
	_route_transactions.clear()
	_floor_rule_runtime = null
	_floor_rule_effect_authority = null
	return accepted_result


func start_next_floor():
	var readiness = _require_booted("start_next_floor")
	if not readiness.ok:
		return readiness
	if not _is_floor_plan_run():
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _revision(), {"operation": "start_next_floor"}
		)
	var completed: Array = _orchestrator.snapshot().get("completed_floor_ids", [])
	var started = _start_floor_at(completed.size())
	if started.ok:
		_floor_rule_runtime = null
		_floor_rule_effect_authority = null
	return started


func route_choices() -> Array[Dictionary]:
	if not _is_floor_plan_run():
		return []
	var state: Dictionary = _orchestrator.snapshot()
	var plan: Dictionary = state.get("floor_plan", {})
	var source_id := str(plan.get("current_node_id", ""))
	var abandoned: Array = plan.get("abandoned_node_ids", [])
	var selected: Array = plan.get("selected_edge_ids", [])
	var choices: Array[Dictionary] = []
	for edge_value: Variant in plan.get("edges", []):
		if not edge_value is Dictionary:
			continue
		var edge: Dictionary = edge_value
		var destination_id := str(edge.get("destination_node_id", ""))
		if (
			str(edge.get("source_node_id", "")) != source_id
			or bool(edge.get("locked", false))
			or selected.has(str(edge.get("id", "")))
			or abandoned.has(destination_id)
		):
			continue
		var target: Dictionary = _director.room_definition_for_node(StringName(destination_id))
		if target.is_empty():
			continue
		choices.append({
			"edge_id": str(edge.get("id", "")),
			"choice_order": int(edge.get("choice_order", 0)),
			"node_id": destination_id,
			"floor_id": str(plan.get("floor_id", "")),
			"floor_index": int(plan.get("floor_index", -1)),
			"room_type": str(target.get("room_type", "")),
			"template_id": str(target.get("template_id", "")),
			"scene_path": str(target.get("scene_path", "")),
			"route_summary_facts": (
				(edge.get("route_summary_facts", {}) as Dictionary).duplicate(true)
			),
		})
	choices.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left["choice_order"]) < int(right["choice_order"])
	)
	return choices


func begin_route_transition(edge_id: StringName, expected_revision: int):
	var readiness = _require_booted("begin_route_transition")
	if not readiness.ok:
		return readiness
	if not _is_floor_plan_run():
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _revision(), {"operation": "begin_route_transition"}
		)
	if not _route_transactions.is_empty():
		return CommandResultScript.failure(
			&"INVALID_PHASE", _revision(), {"operation": "begin_route_transition"}
		)
	var before: Dictionary = _orchestrator.floor_transaction_snapshot()
	var begun = _orchestrator.begin_route_transition(edge_id, expected_revision)
	if not begun.ok:
		return begun
	var transition_id := str(begun.context.get("transition_id", ""))
	_route_transactions[transition_id] = {
		"before": before.duplicate(true),
		"edge_id": str(edge_id),
		"node_id": str(begun.context.get("node_id", "")),
		"stage": "begun",
		"floor_rule_runtime": _floor_rule_runtime,
		"floor_rule_effect_authority": _floor_rule_effect_authority,
	}
	var context: Dictionary = begun.context.duplicate(true)
	context["target"] = current_room_definition()
	context["scene_context"] = _scene_context_for_target(context["target"] as Dictionary)
	return CommandResultScript.success(begun.new_revision, context)


func finalize_route_transition(transition_id: String, expected_revision: int):
	var readiness = _require_booted("finalize_route_transition")
	if not readiness.ok:
		return readiness
	if not _route_transactions.has(transition_id):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _revision(), {"field": "transition_id"}
		)
	var reservation: Dictionary = _route_transactions[transition_id]
	if str(reservation.get("stage", "")) != "begun":
		return CommandResultScript.failure(
			&"INVALID_PHASE", _revision(), {"operation": "finalize_route_transition"}
		)
	var finalized = _orchestrator.finalize_route_transition(
		transition_id, expected_revision
	)
	if not finalized.ok:
		return finalized
	var target: Dictionary = current_room_definition()
	var entered = _orchestrator.enter_floor_node(
		str(target.get("node_id", "")), finalized.new_revision
	)
	if not entered.ok:
		var before: Dictionary = reservation.get("before", {}).duplicate(true)
		if not _orchestrator.restore_floor_transaction_snapshot(before):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE",
				_revision(),
				{"stage": "route_finalize_entry_rollback", "transition_id": transition_id}
			)
		_route_transactions.erase(transition_id)
		var failure_context: Dictionary = entered.context.duplicate(true)
		failure_context["route_rolled_back"] = true
		failure_context["transition_id"] = transition_id
		return CommandResultScript.failure(
			entered.code, _revision(), failure_context, entered.message_key
		)
	reservation["stage"] = "finalized"
	reservation["final_revision"] = int(entered.new_revision)
	_route_transactions[transition_id] = reservation
	var context: Dictionary = finalized.context.duplicate(true)
	context["target"] = target.duplicate(true)
	context["enter_revision"] = int(entered.new_revision)
	return CommandResultScript.success(entered.new_revision, context)


func rollback_route_transition(transition_id: String, expected_revision: int):
	var readiness = _require_booted("rollback_route_transition")
	if not readiness.ok:
		return readiness
	if not _route_transactions.has(transition_id):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _revision(), {"field": "transition_id"}
		)
	if expected_revision != _revision():
		return CommandResultScript.failure(
			&"STALE_REVISION",
			_revision(),
			{"received_revision": expected_revision, "last_revision": _revision()}
		)
	var reservation: Dictionary = _route_transactions[transition_id]
	var rolled_back = null
	if str(reservation.get("stage", "")) == "begun":
		rolled_back = _orchestrator.rollback_route_transition(
			transition_id, expected_revision
		)
	else:
		var before: Dictionary = reservation.get("before", {}).duplicate(true)
		if not _orchestrator.restore_floor_transaction_snapshot(before):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE",
				_revision(),
				{"stage": "route_finalized_rollback", "transition_id": transition_id}
			)
		rolled_back = CommandResultScript.success(
			_revision(), {"transition_id": transition_id, "rolled_back": true}
		)
	if rolled_back.ok:
		_floor_rule_runtime = reservation.get("floor_rule_runtime") as RefCounted
		_floor_rule_effect_authority = reservation.get("floor_rule_effect_authority")
		_route_transactions.erase(transition_id)
	return rolled_back


func confirm_route_transition(transition_id: String, expected_revision: int):
	var readiness = _require_booted("confirm_route_transition")
	if not readiness.ok:
		return readiness
	var preflight = can_confirm_route_transition(transition_id, expected_revision)
	if not preflight.ok:
		return preflight
	_route_transactions.erase(transition_id)
	if _orchestrator.snapshot().get("floor_rule_state", {}).is_empty():
		_floor_rule_runtime = null
		_floor_rule_effect_authority = null
	return CommandResultScript.success(
		_revision(), {"transition_id": transition_id, "confirmed": true}
	)


func can_confirm_route_transition(transition_id: String, expected_revision: int):
	var readiness = _require_booted("can_confirm_route_transition")
	if not readiness.ok:
		return readiness
	if expected_revision != _revision():
		return CommandResultScript.failure(
			&"STALE_REVISION",
			_revision(),
			{"received_revision": expected_revision, "last_revision": _revision()}
		)
	if not _route_transactions.has(transition_id):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _revision(), {"field": "transition_id"}
		)
	var reservation: Dictionary = _route_transactions[transition_id]
	if str(reservation.get("stage", "")) != "finalized":
		return CommandResultScript.failure(
			&"INVALID_PHASE", _revision(), {"operation": "confirm_route_transition"}
		)
	return CommandResultScript.success(
		_revision(), {"transition_id": transition_id, "confirmable": true}
	)


func configure_floor_rule(
	rule_id: StringName,
	configuration: Dictionary,
	effect_authority: Variant,
	expected_revision: int
):
	var readiness = _require_booted("configure_floor_rule")
	if not readiness.ok:
		return readiness
	if expected_revision != _revision():
		return CommandResultScript.failure(
			&"STALE_REVISION",
			_revision(),
			{"received_revision": expected_revision, "last_revision": _revision()}
		)
	if not (_orchestrator.snapshot().get("floor_rule_state", {}) as Dictionary).is_empty():
		return CommandResultScript.failure(
			&"INVALID_PHASE", _revision(), {"operation": "configure_floor_rule"}
		)
	var runtime := _new_floor_rule_runtime(rule_id)
	if runtime == null:
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _revision(), {"field": "rule_id", "rule_id": str(rule_id)}
		)
	var configured: Dictionary = runtime.call(
		"configure", configuration.duplicate(true), effect_authority
	)
	if not bool(configured.get("ok", false)):
		return CommandResultScript.failure(
			StringName(str(configured.get("code", &"INVALID_ARGUMENT"))),
			_revision(),
			(configured.get("context", {}) as Dictionary).duplicate(true)
		)
	var committed = _orchestrator.commit_floor_rule_state(
		(configured.get("snapshot", {}) as Dictionary).duplicate(true), expected_revision
	)
	if not committed.ok:
		return committed
	_floor_rule_runtime = runtime
	_floor_rule_effect_authority = effect_authority
	return committed


func advance_floor_rule_frame(
	runtime_frame: int,
	context: Dictionary,
	expected_revision: int
):
	var readiness = _require_booted("advance_floor_rule_frame")
	if not readiness.ok:
		return readiness
	if expected_revision != _revision():
		return CommandResultScript.failure(
			&"STALE_REVISION",
			_revision(),
			{"received_revision": expected_revision, "last_revision": _revision()}
		)
	if _floor_rule_runtime == null:
		return CommandResultScript.failure(
			&"INVALID_PHASE", _revision(), {"operation": "advance_floor_rule_frame"}
		)
	var before: Dictionary = _floor_rule_runtime.call("snapshot")
	if before != _orchestrator.snapshot().get("floor_rule_state", {}):
		return CommandResultScript.failure(
			&"INTEGRITY_FAILURE", _revision(), {"stage": "floor_rule_runtime_drift"}
		)
	var advanced: Dictionary = _floor_rule_runtime.call(
		"advance_frame", runtime_frame, context.duplicate(true)
	)
	if not bool(advanced.get("ok", false)):
		return CommandResultScript.failure(
			StringName(str(advanced.get("code", &"INVALID_ARGUMENT"))),
			_revision(),
			(advanced.get("context", {}) as Dictionary).duplicate(true)
		)
	var committed = _orchestrator.commit_floor_rule_observation(
		(advanced.get("snapshot", {}) as Dictionary).duplicate(true), expected_revision
	)
	if not committed.ok:
		_floor_rule_runtime.call("restore_snapshot", before)
		return committed
	var result_context: Dictionary = committed.context.duplicate(true)
	result_context["facts"] = (advanced.get("facts", []) as Array).duplicate(true)
	result_context["presentation"] = (advanced.get("presentation", []) as Array).duplicate(true)
	return CommandResultScript.success(committed.new_revision, result_context)


func restore_floor_rule_snapshot(
	value: Dictionary,
	effect_authority: Variant,
	expected_revision: int
):
	var readiness = _require_booted("restore_floor_rule_snapshot")
	if not readiness.ok:
		return readiness
	if expected_revision != _revision():
		return CommandResultScript.failure(
			&"STALE_REVISION", _revision(),
			{"received_revision": expected_revision, "last_revision": _revision()}
		)
	for field: String in ["rule_id", "room_id", "room_seed", "zones", "safe_zone_ids", "reduced_motion", "hit_flash_enabled"]:
		if not value.has(field):
			return CommandResultScript.failure(
				&"INVALID_ARGUMENT", _revision(), {"field": "floor_rule_state.%s" % field}
			)
	if not value["zones"] is Array or not value["safe_zone_ids"] is Array:
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _revision(), {"field": "floor_rule_state"}
		)
	var runtime := _new_floor_rule_runtime(StringName(str(value.get("rule_id", ""))))
	if runtime == null:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", _revision(), {"field": "rule_id"})
	var configuration := {
		"room_id": value.get("room_id"),
		"room_seed": value.get("room_seed"),
		"zones": (value.get("zones", []) as Array).duplicate(true),
		"safe_zone_ids": (value.get("safe_zone_ids", []) as Array).duplicate(),
		"reduced_motion": value.get("reduced_motion"),
		"hit_flash_enabled": value.get("hit_flash_enabled"),
	}
	var configured: Dictionary = runtime.call("configure", configuration, effect_authority)
	if not bool(configured.get("ok", false)) or not bool(runtime.call("restore_snapshot", value.duplicate(true))):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _revision(), {"field": "floor_rule_state"}
		)
	var committed = _orchestrator.commit_floor_rule_state(value.duplicate(true), expected_revision)
	if not committed.ok:
		return committed
	_floor_rule_runtime = runtime
	_floor_rule_effect_authority = effect_authority
	return committed


func enter_current_room():
	var readiness = _require_booted("enter_current_room")
	if not readiness.ok:
		return readiness
	var room := current_room_definition()
	if room.is_empty():
		return CommandResultScript.failure(
			&"INVALID_PHASE",
			_revision(),
			{"operation": "enter_current_room"}
		)
	if _is_floor_plan_run():
		var active_phase := _active_phase_for_room_type(str(room.get("room_type", "")))
		if _orchestrator.phase() == active_phase:
			return CommandResultScript.success(
				_revision(), {"already_entered": true, "node_id": str(room.get("node_id", ""))}
			)
		return _orchestrator.enter_floor_node(
			str(room.get("node_id", "")), _revision()
		)
	return _orchestrator.room_entered(str(room.get("type", "")) == "boss")


func complete_current_room():
	var readiness = _require_booted("complete_current_room")
	if not readiness.ok:
		return readiness
	if _orchestrator.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", _revision())
	if not _route_transactions.is_empty():
		return CommandResultScript.failure(
			&"INVALID_PHASE", _revision(), {"operation": "complete_current_room"}
		)

	var room := current_room_definition()
	if _is_floor_plan_run():
		if room.is_empty():
			return CommandResultScript.failure(
				&"INVALID_PHASE", _revision(), {"operation": "complete_current_room"}
			)
		var completed = _orchestrator.complete_floor_node(
			str(room.get("node_id", "")), _revision()
		)
		if not completed.ok:
			return completed
		if str(room.get("room_type", "")) != "boss":
			return completed
		var floor_completed = _orchestrator.complete_floor(
			{
				"result": "victory",
				"room_id": str(room.get("node_id", "")),
				"floor_id": str(room.get("floor_id", "")),
				"current_room": int(room.get("room_number", 0)),
			},
			completed.new_revision
		)
		if floor_completed.ok:
			_floor_rule_runtime = null
			_floor_rule_effect_authority = null
		return floor_completed
	if str(room.get("type", "")) == "boss":
		return CommandResultScript.failure(
			&"INVALID_PHASE",
			_revision(),
			{"operation": "complete_current_room"}
		)
	if _orchestrator.phase() != RunPhaseScript.Value.COMBAT_ACTIVE:
		return CommandResultScript.failure(
			&"INVALID_PHASE",
			_revision(),
			{"operation": "complete_current_room"}
		)
	var prospective_snapshot: Dictionary = _orchestrator.snapshot()
	prospective_snapshot["revision"] = _revision() + 1
	prospective_snapshot["phase"] = RunPhaseScript.Value.ROOM_RESOLVING
	var created = _draft.create_offer(_registry, prospective_snapshot, room)
	if not created.ok:
		return created
	var offer: Dictionary = created.context["offer"]
	var cleared = _orchestrator.room_cleared()
	if not cleared.ok:
		_draft.close_offer(str(offer.get("offer_id", "")))
		return cleared
	var opened = _orchestrator.open_selection(offer)
	if not opened.ok:
		_draft.close_offer(str(offer.get("offer_id", "")))
		return opened
	return CommandResultScript.success(opened.new_revision, {"offer": offer})


func submit_selection(offer_id: String, option_id: String, revision: int):
	var reserved = reserve_selection(offer_id, option_id, revision)
	if not reserved.ok:
		return reserved
	var reservation_id := str(reserved.context.get("reservation_id", ""))
	var committed = commit_reserved_selection(reservation_id)
	if not committed.ok:
		cancel_reserved_selection(reservation_id)
	return committed


func reserve_selection(offer_id: String, option_id: String, revision: int):
	var readiness = _require_booted("submit_selection")
	if not readiness.ok:
		return readiness
	if _orchestrator.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", _revision())
	if _orchestrator.has_consumed_offer(offer_id):
		return CommandResultScript.failure(
			&"ALREADY_CONSUMED",
			_revision(),
			{"offer_id": offer_id}
		)
	if _orchestrator.phase() != RunPhaseScript.Value.SELECTION_ACTIVE:
		return CommandResultScript.failure(
			&"INVALID_PHASE",
			_revision(),
			{"operation": "submit_selection"}
		)

	var canonical: Dictionary = _orchestrator.snapshot().get("open_offer", {})
	if str(canonical.get("offer_id", "")) != offer_id:
		return CommandResultScript.failure(
			&"OFFER_CLOSED",
			_revision(),
			{"offer_id": offer_id}
		)
	if int(canonical.get("revision", -1)) != revision:
		return CommandResultScript.failure(
			&"STALE_REVISION",
			_revision(),
			{
				"offer_id": offer_id,
				"received_revision": revision,
				"last_revision": int(canonical.get("revision", -1)),
			}
		)

	var resolved = _draft.resolve_option(canonical, StringName(option_id))
	if not resolved.ok:
		return resolved
	var definition: Dictionary = resolved.context["definition"]
	var validation = _orchestrator.validate_selection_commit(definition)
	if not validation.ok:
		return validation
	for reservation_value: Variant in _selection_reservations.values():
		if (
			reservation_value is Dictionary
			and str((reservation_value as Dictionary).get("offer_id", "")) == offer_id
		):
			return CommandResultScript.failure(
				&"SELECTION_RESERVED",
				_revision(),
				{"offer_id": offer_id}
			)
	var reservation_id := "%s:reservation-%d" % [offer_id, _next_selection_reservation_id]
	_next_selection_reservation_id += 1
	_selection_reservations[reservation_id] = {
		"reservation_id": reservation_id,
		"offer_id": offer_id,
		"option_id": option_id,
		"offer_revision": revision,
		"state_revision": _revision(),
		"definition": definition.duplicate(true),
	}
	return CommandResultScript.success(
		_revision(),
		{
			"reservation_id": reservation_id,
			"definition": definition.duplicate(true),
			"offer_id": offer_id,
		}
	)


func commit_reserved_selection(reservation_id: String):
	var readiness = _require_booted("commit_reserved_selection")
	if not readiness.ok:
		return readiness
	if not _selection_reservations.has(reservation_id):
		return CommandResultScript.failure(
			&"RESERVATION_NOT_FOUND",
			_revision(),
			{"reservation_id": reservation_id}
		)
	var reservation: Dictionary = _selection_reservations[reservation_id]
	if int(reservation.get("state_revision", -1)) != _revision():
		return CommandResultScript.failure(
			&"STALE_REVISION",
			_revision(),
			{
				"reservation_id": reservation_id,
				"reserved_revision": int(reservation.get("state_revision", -1)),
				"last_revision": _revision(),
			}
		)
	var before: Dictionary = _orchestrator.selection_transaction_snapshot()
	var committed = _orchestrator.commit_selection_and_transition(
		(reservation.get("definition", {}) as Dictionary).duplicate(true)
	)
	if not committed.ok:
		return committed
	var offer_id := str(reservation.get("offer_id", ""))
	if not _draft.close_offer(offer_id):
		if not _orchestrator.restore_selection_transaction_snapshot(before):
			push_error("Selection authority rollback failed after DraftService close rejection")
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE",
				_revision(),
				{"reservation_id": reservation_id, "offer_id": offer_id}
			)
		return CommandResultScript.failure(
			&"COMMIT_FAILED",
			_revision(),
			{"reservation_id": reservation_id, "offer_id": offer_id}
		)
	_selection_reservations.erase(reservation_id)
	_last_atomic_transition_revision = int(committed.new_revision)
	return CommandResultScript.success(
		committed.new_revision,
		{
			"reservation_id": reservation_id,
			"definition": (reservation.get("definition", {}) as Dictionary).duplicate(true),
			"offer_id": offer_id,
			"selection_revision": int(committed.context.get("selection_revision", committed.new_revision)),
			"transition_completed": true,
		}
	)


func cancel_reserved_selection(reservation_id: String):
	if not _selection_reservations.has(reservation_id):
		return CommandResultScript.failure(
			&"RESERVATION_NOT_FOUND",
			_revision(),
			{"reservation_id": reservation_id}
		)
	_selection_reservations.erase(reservation_id)
	return CommandResultScript.success(_revision(), {"reservation_id": reservation_id})


func complete_transition():
	var readiness = _require_booted("complete_transition")
	if not readiness.ok:
		return readiness
	if (
		_orchestrator.phase() == RunPhaseScript.Value.ROOM_ENTERING
		and _last_atomic_transition_revision == _revision()
	):
		_last_atomic_transition_revision = -1
		return CommandResultScript.success(
			_revision(),
			{"already_completed": true}
		)
	return _orchestrator.transition_completed()


func player_died(context: Dictionary = {}):
	var readiness = _require_booted("player_died")
	if not readiness.ok:
		return readiness
	return _orchestrator.player_died(context)


func boss_defeated(context: Dictionary = {}):
	var readiness = _require_booted("boss_defeated")
	if not readiness.ok:
		return readiness
	return _orchestrator.boss_defeated(context)


func pause_run():
	var readiness = _require_booted("pause_run")
	if not readiness.ok:
		return readiness
	return _orchestrator.pause_run()


func resume_run():
	var readiness = _require_booted("resume_run")
	if not readiness.ok:
		return readiness
	return _orchestrator.resume_run()


func advance_time(delta_seconds: float):
	var readiness = _require_booted("advance_time")
	if not readiness.ok:
		return readiness
	return _orchestrator.advance_time(delta_seconds)


func snapshot() -> Dictionary:
	if _orchestrator == null:
		return {}
	return _orchestrator.snapshot()


func reward_replay_snapshot() -> Dictionary:
	if (
		not _booted
		or _registry == null
		or _orchestrator == null
		or _reward_replay_seal == null
	):
		return {}
	var build_state_value: Dictionary = _orchestrator.reward_replay_build_snapshot()
	if build_state_value.is_empty():
		return {}
	return _reward_replay_seal.call(
		"capture", _registry, build_state_value.duplicate(true)
	)


func can_restore_reward_replay_snapshot(value: Dictionary) -> bool:
	if (
		not _booted
		or _registry == null
		or _orchestrator == null
		or _reward_replay_seal == null
	):
		return false
	var current: Dictionary = reward_replay_snapshot()
	if current.is_empty():
		return false
	var milestone := str(_orchestrator.snapshot().get("config", {}).get("milestone", ""))
	var validated: Dictionary = _reward_replay_seal.call(
		"validate", value.duplicate(true), _registry, milestone
	)
	if not bool(validated.get("ok", false)):
		return false
	return bool(_reward_replay_seal.call(
		"prefix_matches",
		(value.get("reward_prefix", {}) as Dictionary).duplicate(true),
		(current.get("reward_facts", []) as Array).duplicate(true)
	))


func restore_reward_replay_snapshot(value: Dictionary) -> bool:
	if not can_restore_reward_replay_snapshot(value):
		return false
	var before: Dictionary = _orchestrator.reward_replay_build_snapshot()
	var target_build := (value.get("build_state", {}) as Dictionary).duplicate(true)
	if not _orchestrator.restore_reward_replay_build_snapshot(target_build):
		return false
	if reward_replay_snapshot() == value:
		return true
	if not _orchestrator.restore_reward_replay_build_snapshot(before):
		push_error("RunRuntimeFacade failed to roll back a rejected reward Replay restore")
	return false


func active_loadout() -> Dictionary:
	return _accepted_loadout.duplicate(true)


func current_room_definition() -> Dictionary:
	if not _booted or _orchestrator == null:
		return {}
	if _is_floor_plan_run():
		var plan: Dictionary = _orchestrator.snapshot().get("floor_plan", {})
		var node_id := str(plan.get("current_node_id", ""))
		if node_id.is_empty() or node_id == str(plan.get("entry_node_id", "entry")):
			return {}
		var launch_definition: Dictionary = _director.room_definition_for_node(
			StringName(node_id)
		)
		if launch_definition.is_empty():
			return {}
		launch_definition["room_number"] = int(
			_orchestrator.snapshot().get("current_room", 0)
		)
		return launch_definition
	if _room_definitions.is_empty():
		return {}
	var room_number := int(_orchestrator.snapshot().get("current_room", 0))
	if room_number <= 0 or room_number > _room_definitions.size():
		return {}
	return _room_definitions[room_number - 1].duplicate(true)


func current_encounter_definition() -> Dictionary:
	if not _booted or _encounter_catalog == null or _orchestrator == null:
		return {}
	var room := current_room_definition()
	if room.is_empty():
		return {}
	if _is_floor_plan_run():
		var encounter_id := str(room.get("encounter_id", ""))
		if encounter_id.is_empty():
			return {}
		return _encounter_catalog.encounter_definition(
			encounter_id,
			int(_orchestrator.snapshot().get("run_seed", 0)),
			int(room.get("room_number", 0))
		)
	return _encounter_catalog.encounter_definition(
		str(room.get("encounter_id", "")),
		int(_orchestrator.snapshot().get("run_seed", 0)),
		int(room.get("room_number", 0))
	)


func room_plan() -> Array[Dictionary]:
	if _is_floor_plan_run() and _director != null:
		var definitions: Array[Dictionary] = []
		for room_number: int in range(1, _director.room_count() + 1):
			definitions.append(_director.room_definition_for(room_number))
		return definitions
	return _room_definitions.duplicate(true)


func encounter_catalog() -> RefCounted:
	return _encounter_catalog


func content_registry() -> RefCounted:
	return _registry


func create_room_runtime(encounter_runner: Node) -> Node:
	if not _booted or _orchestrator == null or _encounter_catalog == null or encounter_runner == null:
		return null
	var runtime := RoomRuntimeScript.new()
	runtime.configure(
		self,
		_encounter_catalog,
		room_plan(),
		int(_orchestrator.snapshot().get("run_seed", 0)),
		encounter_runner
	)
	return runtime


func _require_booted(operation: String):
	if _booted and _orchestrator != null:
		return CommandResultScript.success(_revision())
	return CommandResultScript.failure(
		&"INVALID_PHASE",
		_revision(),
		{"operation": operation}
	)


func _revision() -> int:
	if _orchestrator == null:
		return 0
	return _orchestrator.revision()


func _configure_launch_content(milestone: StringName):
	var canonical_floors: Array[Dictionary] = []
	var canonical_templates: Array[Dictionary] = []
	for floor_value: Variant in _registry.call("get_floor_definitions", milestone):
		if not floor_value is Dictionary:
			return CommandResultScript.failure(
				&"CONTENT_NOT_AVAILABLE",
				_revision(),
				{"category": "floor_definition", "reason": "expected_dictionary"}
			)
		var canonical_floor := _canonical_floor_definition(floor_value as Dictionary)
		if not bool(canonical_floor.get("ok", false)):
			return CommandResultScript.failure(
				&"CONTENT_NOT_AVAILABLE",
				_revision(),
				(canonical_floor.get("context", {}) as Dictionary).duplicate(true)
			)
		canonical_floors.append(
			(canonical_floor.get("definition", {}) as Dictionary).duplicate(true)
		)
	for template_value: Variant in _registry.call(
		"get_by_category", &"room_template", milestone
	):
		if not template_value is Dictionary:
			return CommandResultScript.failure(
				&"CONTENT_NOT_AVAILABLE",
				_revision(),
				{"category": "room_template", "reason": "expected_dictionary"}
			)
		var canonical_template := _canonical_room_template(template_value as Dictionary)
		if not bool(canonical_template.get("ok", false)):
			return CommandResultScript.failure(
				&"CONTENT_NOT_AVAILABLE",
				_revision(),
				(canonical_template.get("context", {}) as Dictionary).duplicate(true)
			)
		canonical_templates.append(
			(canonical_template.get("definition", {}) as Dictionary).duplicate(true)
		)
	if canonical_floors.size() != 5 or canonical_templates.size() != 30:
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE",
			_revision(),
			{
				"floor_count": canonical_floors.size(),
				"room_template_count": canonical_templates.size(),
			}
		)
	_floor_definitions = canonical_floors.duplicate(true)
	_room_templates = canonical_templates.duplicate(true)
	return CommandResultScript.success(_revision())


func _canonical_floor_definition(source: Dictionary) -> Dictionary:
	var parser_source := _definition_fields(source, FloorDefinitionScript.ROOT_FIELDS)
	var result: Dictionary = FloorDefinitionScript.new().configure(parser_source)
	if bool(result.get("ok", false)):
		return {
			"ok": true,
			"definition": (result.get("definition", {}) as Dictionary).duplicate(true),
			"context": {},
		}
	var context: Dictionary = (result.get("context", {}) as Dictionary).duplicate(true)
	context["category"] = "floor_definition"
	context["content_id"] = str(source.get("id", ""))
	return {"ok": false, "definition": {}, "context": context}


func _canonical_room_template(source: Dictionary) -> Dictionary:
	var parser_source := _definition_fields(
		source, RoomTemplateDefinitionScript.ROOT_FIELDS
	)
	var result: Dictionary = RoomTemplateDefinitionScript.new().configure(parser_source)
	if bool(result.get("ok", false)):
		return {
			"ok": true,
			"definition": (result.get("definition", {}) as Dictionary).duplicate(true),
			"context": {},
		}
	var context: Dictionary = (result.get("context", {}) as Dictionary).duplicate(true)
	context["category"] = "room_template"
	context["content_id"] = str(source.get("id", ""))
	return {"ok": false, "definition": {}, "context": context}


func _definition_fields(source: Dictionary, fields: Array[String]) -> Dictionary:
	var canonical_source: Dictionary = {}
	for field: String in fields:
		if not source.has(field):
			continue
		var value: Variant = source[field]
		canonical_source[field] = (
			value.duplicate(true) if value is Array or value is Dictionary else value
		)
	return canonical_source


func _start_floor_at(
	floor_index: int,
	orchestrator_override: RefCounted = null,
	director_override: Node = null
):
	var run_authority = (
		orchestrator_override if orchestrator_override != null else _orchestrator
	)
	var run_director: Node = (
		director_override if director_override != null else _director
	)
	var authority_revision := int(run_authority.revision())
	if floor_index < 0 or floor_index >= _floor_definitions.size():
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			authority_revision,
			{"field": "floor_index", "floor_index": floor_index}
		)
	var floor: Dictionary = _floor_definitions[floor_index]
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(
		int(run_authority.snapshot().get("run_seed", 0)),
		floor,
		_room_templates
	)
	if not bool(generated.get("ok", false)):
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE",
			authority_revision,
			(generated.get("context", {}) as Dictionary).duplicate(true)
		)
	var before: Dictionary = run_authority.floor_transaction_snapshot()
	var started = run_authority.start_floor(
		(generated.get("plan", {}) as Dictionary).duplicate(true),
		floor.duplicate(true),
		_room_templates.duplicate(true),
		authority_revision
	)
	if not started.ok:
		return started
	if not run_director.configure_launch_plan(
		run_authority.snapshot().get("floor_plan", {}), _registry
	):
		if not run_authority.restore_floor_transaction_snapshot(before):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE",
				int(run_authority.revision()),
				{"stage": "launch_director_configuration_rollback"}
			)
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE",
			int(run_authority.revision()),
			{"field": "floor_plan", "reason": "launch_director_configuration_failed"}
		)
	return started


func _is_floor_plan_run() -> bool:
	if _orchestrator == null:
		return false
	return _is_floor_plan_milestone(
		str(_orchestrator.snapshot().get("config", {}).get("milestone", ""))
	)


func _is_floor_plan_milestone(milestone: String) -> bool:
	return milestone in ["LAUNCH", "EXPANSION"]


func _active_phase_for_room_type(room_type: String) -> int:
	if room_type == "boss":
		return RunPhaseScript.Value.BOSS_ACTIVE
	if room_type == "combat" or room_type == "elite":
		return RunPhaseScript.Value.COMBAT_ACTIVE
	return RunPhaseScript.Value.ROOM_ACTIVE


func _new_floor_rule_runtime(rule_id: StringName) -> RefCounted:
	match str(rule_id):
		"rule_crumbling_ground":
			return CrumblingGroundRuleScript.new()
		"rule_void_spores":
			return VoidSporesRuleScript.new()
		"rule_temporal_distortion":
			return TemporalDistortionRuleScript.new()
		"rule_forge_vents":
			return ForgeVentsRuleScript.new()
		"rule_collapsing_plane":
			return CollapsingPlaneRuleScript.new()
	return null


func _scene_context_for_target(target: Dictionary) -> Dictionary:
	if target.is_empty() or _orchestrator == null:
		return {}
	var state: Dictionary = _orchestrator.snapshot()
	var floor_index := int(state.get("current_floor_index", -1))
	if floor_index < 0 or floor_index >= _floor_definitions.size():
		return {}
	var floor: Dictionary = _floor_definitions[floor_index]
	var node_id := str(target.get("node_id", ""))
	var floor_id := str(floor.get("id", ""))
	if node_id.is_empty() or floor_id.is_empty():
		return {}
	return {
		"floor_id": floor_id,
		"palette_id": str(floor.get("palette_id", "")),
		"environment_rule_id": str(floor.get("environment_rule_id", "")),
		"room_seed": SeedServiceScript.derive_node_seed(
			int(state.get("run_seed", 0)),
			StringName(floor_id),
			StringName(node_id),
			&"room_scene"
		),
		"reduced_motion": false,
		"hit_flash_enabled": true,
	}
