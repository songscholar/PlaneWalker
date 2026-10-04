class_name RunRuntimeFacade
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")
const RunConfigScript := preload("res://scripts/application/run_config.gd")
const RunLoadoutPolicyScript := preload("res://scripts/application/run_loadout_policy.gd")
const MetaCatalogFactory := preload("res://scripts/progression/meta_catalog_factory.gd")
const MetaRunProjectionScript := preload("res://scripts/progression/meta_run_projection.gd")
const RunRewardReplaySealScript := preload(
	"res://scripts/application/run_reward_replay_seal.gd"
)
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const EncounterCatalogScript := preload("res://scripts/dungeon/encounter_catalog.gd")
const LaunchEncounterCatalogScript := preload("res://scripts/dungeon/launch_encounter_catalog.gd")
const M1RoomPlanScript := preload("res://scripts/dungeon/m1_room_plan.gd")
const FloorDefinitionScript := preload("res://scripts/dungeon/floor_definition.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const RoomTemplateDefinitionScript := preload(
	"res://scripts/dungeon/room_template_definition.gd"
)
const DungeonEventDefinitionScript := preload(
	"res://scripts/dungeon/dungeon_event_definition.gd"
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
const EconomyProfileScript := preload("res://scripts/dungeon/economy_profile.gd")
const MerchantDefinitionScript := preload("res://scripts/dungeon/merchant_definition.gd")
const MerchantInventoryServiceScript := preload(
	"res://scripts/economy/merchant_inventory_service.gd"
)
const MerchantRunStateScript := preload("res://scripts/economy/merchant_run_state.gd")
const MerchantRuntimeScript := preload("res://scripts/economy/merchant_runtime.gd")
const MerchantRewardRuntimeScript := preload("res://scripts/economy/merchant_reward_runtime.gd")
const EventModifierLifetimeScript := preload("res://scripts/events/event_modifier_lifetime.gd")
const MerchantServiceAuthorityScript := preload(
	"res://scripts/economy/merchant_service_authority.gd"
)
const MerchantServiceRouterScript := preload(
	"res://scripts/economy/merchant_service_router.gd"
)
const FloorPlanVisibilityAuthorityScript := preload(
	"res://scripts/economy/floor_plan_visibility_authority.gd"
)
const RewardBuildMutationAuthorityScript := preload(
	"res://scripts/economy/reward_build_mutation_authority.gd"
)
const MerchantWeaponUpgradeAuthorityScript := preload(
	"res://scripts/economy/merchant_weapon_upgrade_authority.gd"
)
const MerchantHealthTradeAuthorityScript := preload(
	"res://scripts/economy/merchant_health_trade_authority.gd"
)
const RunEconomyStateScript := preload("res://scripts/economy/run_economy_state.gd")
const ShopPriceServiceScript := preload("res://scripts/economy/shop_price_service.gd")
const DungeonEventRuntimeScript := preload("res://scripts/events/dungeon_event_runtime.gd")
const DungeonEventSelectorScript := preload("res://scripts/events/dungeon_event_selector.gd")
const DungeonEventRunStateScript := preload("res://scripts/events/dungeon_event_run_state.gd")
const EventRequirementServiceScript := preload("res://scripts/events/event_requirement_service.gd")
const DungeonEventConsequenceRuntimeScript := preload(
	"res://scripts/events/dungeon_event_consequence_runtime.gd"
)
const EventResourceAuthorityScript := preload("res://scripts/events/event_resource_authority.gd")
const EventHealthAuthorityScript := preload("res://scripts/events/event_health_authority.gd")
const EventModifierAuthorityScript := preload("res://scripts/events/event_modifier_authority.gd")
const EventRouteAuthorityScript := preload("res://scripts/events/event_route_authority.gd")
const RoomRewardPolicyScript := preload("res://scripts/dungeon/reward_policy_protocol.gd")
const PlayerRewardTransactionScript := preload("res://scripts/application/player_reward_transaction.gd")
const RunBuildStateScript := preload("res://scripts/progression/run_build_state.gd")
const RewardCompatibilityScript := preload("res://scripts/rewards/reward_compatibility.gd")

const GAME_VERSION := "0.4.0-dev"
const DEFAULT_CONTENT_PATH := "res://data/content_packs/base/pack.json"
const DEFAULT_ENCOUNTER_PATH := "res://data/encounters/m1_encounters.json"

var _registry: RefCounted
var _encounter_catalog: RefCounted
var _launch_encounter_catalog: RefCounted
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
var _economy_profile: Dictionary = {}
var _merchant_definitions: Array[Dictionary] = []
var _merchant_definitions_by_id: Dictionary = {}
var _merchant_reward_definitions: Array[Dictionary] = []
var _launch_content_fingerprint: String = ""
var _economy_state: RefCounted
var _merchant_run_state: RefCounted
var _merchant_sessions: Dictionary = {}
var _merchant_reward_runtime: Object
var _merchant_player: Object
var _merchant_run_start_player_baseline: Dictionary = {}
var _event_definitions: Array[Dictionary] = []
var _event_content_fingerprint: String = ""
var _event_runtime: RefCounted
var _published_event_fact_ids: Dictionary = {}
var _pending_event_reward_definition: Dictionary = {}


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if _director != null and is_instance_valid(_director):
		_director.free()
	_director = null


func boot(
	content_path: String = DEFAULT_CONTENT_PATH,
	encounter_path: String = DEFAULT_ENCOUNTER_PATH,
	pack_specs: Array = []
):
	_booted = false
	_registry = ContentRegistryScript.new()
	_encounter_catalog = EncounterCatalogScript.new()
	_launch_encounter_catalog = null
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
	_economy_profile.clear()
	_merchant_definitions.clear()
	_merchant_definitions_by_id.clear()
	_merchant_reward_definitions.clear()
	_launch_content_fingerprint = ""
	_economy_state = null
	_merchant_run_state = null
	_merchant_sessions.clear()
	_merchant_reward_runtime = null
	_merchant_player = null
	_merchant_run_start_player_baseline.clear()
	_event_definitions.clear()
	_event_content_fingerprint = ""
	_event_runtime = null
	_published_event_fact_ids.clear()

	var report
	if not pack_specs.is_empty():
		report = _registry.load_packs(pack_specs, GAME_VERSION, &"EXPANSION")
	elif content_path.to_lower().ends_with("pack.json"):
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


func start_meta_run(config: Dictionary, run_id: String, projection: Dictionary):
	if projection.is_empty():
		return CommandResultScript.failure(&"INVALID_ARGUMENT", _revision(), {"field": "meta_run_projection"})
	return start_run(config, run_id, projection)


func start_run(config: Dictionary, run_id: String, meta_projection: Dictionary = {}):
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
	var meta_catalog: RefCounted = null
	if not meta_projection.is_empty():
		var loaded: Dictionary = MetaCatalogFactory.from_profile_registry(_registry, meta_projection)
		if not _is_floor_plan_milestone(str(normalized.milestone)) or not loaded.ok or not MetaRunProjectionScript.validate(meta_projection, loaded.context.catalog):
			return CommandResultScript.failure(&"INVALID_ARGUMENT", _revision(), {"field": "meta_run_projection"})
		meta_catalog = loaded.context.catalog
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
	if meta_catalog != null and not candidate_orchestrator.bind_meta_run_projection(meta_projection, meta_catalog):
		candidate_director.free()
		return CommandResultScript.failure(&"INVALID_ARGUMENT", _revision(), {"field": "meta_run_projection"})

	var accepted_result = started
	var candidate_rooms: Array[Dictionary] = []
	var candidate_economy: RefCounted = null
	var candidate_merchant_state: RefCounted = null
	var candidate_event_runtime: RefCounted = null
	if floor_plan_run:
		candidate_economy = RunEconomyStateScript.new()
		var economy_configured: Dictionary = candidate_economy.call(
			"configure", _economy_profile.duplicate(true), 0
		)
		candidate_merchant_state = MerchantRunStateScript.new()
		var merchant_configured: Dictionary = candidate_merchant_state.call(
			"configure", _launch_content_fingerprint
		)
		if (
			not bool(economy_configured.get("ok", false))
			or not bool(merchant_configured.get("ok", false))
		):
			candidate_director.free()
			return CommandResultScript.failure(
				&"CONTENT_NOT_AVAILABLE", _revision(), {"stage": "launch_economy_configuration"}
			)
		var initialized = candidate_orchestrator.initialize_launch_economy(
			candidate_economy.call("snapshot"),
			candidate_merchant_state.call("snapshot"),
			candidate_orchestrator.revision()
		)
		if not initialized.ok:
			candidate_director.free()
			return CommandResultScript.failure(
				initialized.code, _revision(), initialized.context
			)
		accepted_result = _start_floor_at(
			0, candidate_orchestrator, candidate_director
		)
		if accepted_result.ok:
			var event_candidate := _event_runtime_candidate(
				candidate_orchestrator,
				candidate_director,
				candidate_economy,
				{}
			)
			if not bool(event_candidate.get("ok", false)):
				candidate_director.free()
				return CommandResultScript.failure(
					&"AUTHORED_RUNTIME_CONFIGURATION_FAILED",
					_revision(),
					(event_candidate.get("context", {}) as Dictionary).duplicate(true)
				)
			candidate_event_runtime = event_candidate["runtime"] as RefCounted
			accepted_result = candidate_orchestrator.initialize_launch_events(
				candidate_event_runtime.call("snapshot"),
				candidate_orchestrator.revision()
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
	_economy_state = candidate_economy
	_merchant_run_state = candidate_merchant_state
	_event_runtime = candidate_event_runtime
	_published_event_fact_ids.clear()
	_merchant_sessions.clear()
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
		"event_facts": [],
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
		if not _restore_route_runtime_adapters_after_rollback():
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE",
				_revision(),
				{"stage": "route_runtime_adapter_rollback", "transition_id": transition_id}
			)
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
	var reservation := (_route_transactions[transition_id] as Dictionary).duplicate(true)
	_route_transactions.erase(transition_id)
	if _orchestrator.snapshot().get("floor_rule_state", {}).is_empty():
		_floor_rule_runtime = null
		_floor_rule_effect_authority = null
	return CommandResultScript.success(
		_revision(), {
			"transition_id": transition_id,
			"confirmed": true,
			"event_facts": (reservation.get("event_facts", []) as Array).duplicate(true),
		}
	)


func publish_confirmed_route_event_facts(facts: Array) -> bool:
	if not _route_transactions.is_empty():
		return false
	for value: Variant in facts:
		if not value is Dictionary:
			return false
		var fact := value as Dictionary
		if (
			fact.size() != 2
			or not fact.has("fact_id")
			or not fact.has("payload")
			or typeof(fact["fact_id"]) != TYPE_STRING
			or not fact["payload"] is Dictionary
			or not _publish_event_fact_immediate(
				str(fact["fact_id"]),
				(fact["payload"] as Dictionary).duplicate(true)
			)
		):
			return false
	return true


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
		var is_boss := str(room.get("room_type", "")) == "boss"
		var floor_before: Dictionary = _orchestrator.floor_transaction_snapshot()
		var economy_before: Dictionary = (
			_economy_state.call("snapshot")
			if _economy_state != null
			else {}
		)
		var completed = _orchestrator.complete_floor_node(
			str(room.get("node_id", "")), _revision()
		)
		if not completed.ok:
			return completed
		if not _sync_player_event_modifiers():
			_restore_floor_and_economy(floor_before, economy_before)
			_sync_player_event_modifiers()
			return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision(), {"stage": "event_modifier_projection"})
		var payout := RoomRewardPolicyScript.gold_for(str(room.get("room_type", "")), int(room.get("floor_index", -1)))
		if payout > 0:
			var granted = grant_run_gold(
				"room_gold:%s:%s" % [room["floor_id"], room["node_id"]], payout,
				"room_reward:%s" % room["reward_policy_id"]
			)
			if not granted.ok:
				if not _restore_floor_and_economy(floor_before, economy_before) or not _refresh_event_runtime_from_state():
					return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision(), {"stage": "room_gold_rollback"})
				return granted
			completed = CommandResultScript.success(_revision(), {"room_gold": payout})
		if not is_boss:
			return completed
		if _economy_state == null or _merchant_run_state == null:
			if not _restore_floor_and_economy(floor_before, economy_before):
				return CommandResultScript.failure(
					&"INTEGRITY_FAILURE", _revision(), {"stage": "floor_settlement_missing_authority"}
				)
			return CommandResultScript.failure(
				&"INVALID_PHASE", _revision(), {"operation": "floor_settlement"}
			)
		var floor_index := int(room.get("floor_index", -1))
		var settlement: Dictionary = _economy_state.call(
			"apply_floor_transition",
			floor_index,
			int(_economy_state.call("revision")),
			"tx_floor_%d_settlement" % (floor_index + 1)
		)
		if not bool(settlement.get("ok", false)):
			if not _restore_floor_and_economy(floor_before, economy_before):
				return CommandResultScript.failure(
					&"INTEGRITY_FAILURE", _revision(), {"stage": "floor_settlement_prepare_rollback"}
				)
			return CommandResultScript.failure(
				StringName(str(settlement.get("code", &"COMMIT_FAILED"))),
				_revision(),
				(settlement.get("context", {}) as Dictionary).duplicate(true)
			)
		var economy_committed = _orchestrator.commit_economy_transaction(
			_economy_state.call("snapshot"),
			_merchant_run_state.call("snapshot"),
			completed.new_revision
		)
		if not economy_committed.ok:
			if not _restore_floor_and_economy(floor_before, economy_before):
				return CommandResultScript.failure(
					&"INTEGRITY_FAILURE", _revision(), {"stage": "floor_settlement_state_rollback"}
				)
			return economy_committed
		var floor_completed = _orchestrator.complete_floor(
			{
				"result": "victory",
				"room_id": str(room.get("node_id", "")),
				"floor_id": str(room.get("floor_id", "")),
				"current_room": int(room.get("room_number", 0)),
			},
			economy_committed.new_revision
		)
		if not floor_completed.ok:
			if not _restore_floor_and_economy(floor_before, economy_before):
				return CommandResultScript.failure(
					&"INTEGRITY_FAILURE", _revision(), {"stage": "floor_completion_rollback"}
				)
			return floor_completed
		_floor_rule_runtime = null
		_floor_rule_effect_authority = null
		if not _sync_player_event_modifiers():
			return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision(), {"stage": "terminal_event_modifiers"})
		var completion_context: Dictionary = floor_completed.context.duplicate(true)
		completion_context["economy_settlement"] = settlement.duplicate(true)
		return CommandResultScript.success(
			floor_completed.new_revision, completion_context, floor_completed.message_key
		)
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


func _dungeon_command(expected_revision: int):
	var readiness = _require_booted("dungeon_interaction")
	if not readiness.ok:
		return readiness
	if expected_revision != _revision():
		return CommandResultScript.failure(&"STALE_REVISION", _revision())
	var state: Dictionary = _orchestrator.snapshot()
	if not _is_floor_plan_run() or not _route_transactions.is_empty() or bool(state.get("suspended", false)):
		return CommandResultScript.failure(&"INVALID_PHASE", _revision())
	if _orchestrator.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", _revision())
	return CommandResultScript.success(_revision())


func _launch_reward_room(kind: String = "") -> Dictionary:
	var room := current_room_definition()
	if room.is_empty():
		return {}
	room["room_number"] = int(room["floor_index"]) * 16 + int(room["room_number"])
	var state: Dictionary = _orchestrator.snapshot()
	room["reward_kind"] = kind if not kind.is_empty() else (
		"starter" if str(state.get("build", {}).get("dominant_archetype", "")).is_empty() else "reinforcement"
	)
	return room


func open_current_room_reward(expected_revision: int, reward_kind: String = ""):
	var ready = _dungeon_command(expected_revision)
	if not ready.ok:
		return ready
	var state: Dictionary = _orchestrator.snapshot()
	if int(state["phase"]) == RunPhaseScript.Value.SELECTION_ACTIVE:
		return CommandResultScript.success(_revision(), {"offer": state["open_offer"].duplicate(true)})
	var room := _launch_reward_room(reward_kind)
	if _orchestrator.phase() != RunPhaseScript.Value.ROOM_RESOLVING or str(room.get("room_type", "")) not in ["combat", "elite", "treasure", "rest"]:
		return CommandResultScript.failure(&"INVALID_PHASE", _revision())
	var prefix := "%s:room-%02d:" % [state["run_id"], room["room_number"]]
	for id: String in state["consumed_offer_ids"]:
		if id.begins_with(prefix):
			return CommandResultScript.failure(&"ALREADY_CONSUMED", _revision())
	var created = _draft.create_offer(_registry, state, room)
	if not created.ok:
		return created
	var offer: Dictionary = created.context["offer"]
	var opened = _orchestrator.open_selection(offer)
	if not opened.ok:
		_draft.close_offer(offer["offer_id"])
		return opened
	return CommandResultScript.success(_revision(), {"offer": offer})


func commit_current_reward(offer_id: String, option_id: String, offer_revision: int):
	if not _is_floor_plan_run() or _merchant_player == null:
		return CommandResultScript.failure(&"INVALID_PHASE", _revision())
	var reserved = reserve_selection(offer_id, option_id, offer_revision)
	if not reserved.ok:
		return reserved
	var transaction = PlayerRewardTransactionScript.new()
	transaction.configure(_merchant_player, _merchant_reward_runtime)
	if not transaction.apply(reserved.context["definition"]):
		cancel_reserved_selection(reserved.context["reservation_id"])
		return CommandResultScript.failure(&"COMMIT_FAILED" if transaction.rollback() else &"INTEGRITY_FAILURE", _revision())
	var committed = commit_reserved_selection(reserved.context["reservation_id"])
	if not committed.ok:
		cancel_reserved_selection(reserved.context["reservation_id"])
		if not transaction.rollback():
			return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision())
		return committed
	if not transaction.commit() or not _sync_player_health_observation():
		return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision(), {"committed": true})
	return committed


func room_interaction_view_state() -> Dictionary:
	var room := current_room_definition()
	var kind := str(room.get("room_type", ""))
	if kind not in ["treasure", "rest"]:
		return {}
	var description := "UI_TREASURE_PROMPT" if kind == "treasure" else "UI_REST_PROMPT"
	var choices: Array[Dictionary] = []
	var health := _physical_health()
	if kind == "treasure":
		choices.append(_room_choice("claim", "UI_TREASURE_CLAIM", description, true))
	else:
		choices.append(_room_choice("heal", "UI_MERCHANT_HEAL", "UI_REST_HEAL_DESC", not health.is_empty() and float(health["current_hp"]) < float(health["max_hp"]), "UI_HEAL_NOT_NEEDED"))
		var owned: Array = _orchestrator.snapshot().get("build", {}).get("talents", [])
		var available := false
		for definition: Dictionary in _registry.get_by_category(&"talent", &"LAUNCH"):
			if (definition.get("compatibility", {}).get("character_ids", []) as Array).has(str(_orchestrator.snapshot()["config"]["character_id"])) and not owned.has(definition["id"]):
				available = true
		choices.append(_room_choice("upgrade", "UI_REST_UPGRADE", "UI_REST_UPGRADE_DESC", available, "UI_REST_UPGRADE_UNAVAILABLE"))
	choices.append(_room_choice("leave", "UI_ROOM_LEAVE", description, true))
	return {"room_type": kind, "node_id": room["node_id"], "name_key": "ROOM_TYPE_%s" % kind.to_upper(), "description_key": description, "choices": choices}


func _room_choice(id: String, key: String, description: String, available: bool, reason: String = "") -> Dictionary:
	return {"id": id, "label_key": key, "description_key": description, "available": available, "disabled_reason_key": "" if available else reason}


func resolve_current_room_interaction(choice_id: StringName, expected_revision: int):
	var readiness = _dungeon_command(expected_revision)
	if not readiness.ok:
		return readiness
	if _orchestrator.phase() != RunPhaseScript.Value.ROOM_ACTIVE:
		return CommandResultScript.failure(&"INVALID_PHASE", _revision())
	var source := room_interaction_view_state()
	var eligible := false
	for choice: Dictionary in source.get("choices", []):
		if choice["id"] == str(choice_id) and choice["available"]:
			eligible = true
	if not eligible:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", _revision())
	var transaction = PlayerRewardTransactionScript.new()
	var healing := str(choice_id) == "heal"
	if healing:
		var health := _physical_health()
		transaction.configure(_merchant_player, _merchant_reward_runtime)
		if not transaction.apply({"id": "rest_heal", "category": "item", "effects": {"heal": float(health["max_hp"]) * 0.4}}):
			return CommandResultScript.failure(&"COMMIT_FAILED" if transaction.rollback() else &"INTEGRITY_FAILURE", _revision())
	var before: Dictionary = _orchestrator.floor_transaction_snapshot()
	var economy_before: Dictionary = _economy_state.call("snapshot")
	var completed = complete_current_room()
	if not completed.ok:
		if healing and not transaction.rollback():
			return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision())
		return completed
	var context := {"room_completed": true}
	if str(choice_id) in ["claim", "upgrade"]:
		var opened = open_current_room_reward(_revision(), "talent" if str(choice_id) == "upgrade" else "")
		if not opened.ok:
			if not _restore_floor_and_economy(before, economy_before) or not _refresh_event_runtime_from_state():
				return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision())
			return opened
		context["offer"] = opened.context["offer"]
	if healing and (not transaction.commit() or not _sync_player_health_observation()):
		return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision(), {"committed": true})
	return CommandResultScript.success(_revision(), context)


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
	if _is_floor_plan_run() and bool(_orchestrator.snapshot().get("suspended", false)):
		return CommandResultScript.failure(&"INVALID_PHASE", _revision())

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
	if not resolved.ok and resolved.code == &"OFFER_CLOSED" and _is_floor_plan_run():
		var restored_state: Dictionary = _orchestrator.snapshot()
		restored_state["revision"] = int(canonical["revision"])
		var kind := "talent" if canonical["category"] == "talent" else "contract" if canonical["category"] == "contract" else ""
		var recreated = _draft.create_offer(_registry, restored_state, _launch_reward_room(kind))
		if not recreated.ok or recreated.context.get("offer", {}) != canonical:
			return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision(), {"stage": "restored_offer"})
		resolved = _draft.resolve_option(canonical, StringName(option_id))
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
	if not _refresh_event_runtime_from_state():
		if (
			not _orchestrator.restore_selection_transaction_snapshot(before)
			or not _refresh_event_runtime_from_state()
		):
			push_error("Selection authority rollback failed after event runtime refresh rejection")
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
	if not _draft.close_offer(offer_id):
		if (
			not _orchestrator.restore_selection_transaction_snapshot(before)
			or not _refresh_event_runtime_from_state()
		):
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
	var result = _orchestrator.player_died(context)
	if result.ok and not _sync_player_event_modifiers():
		return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision(), {"stage": "terminal_event_modifiers"})
	return result


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
	_sync_player_health_observation()
	_sync_player_event_modifiers()
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
	if _refresh_event_runtime_from_state() and reward_replay_snapshot() == value:
		return true
	if (
		not _orchestrator.restore_reward_replay_build_snapshot(before)
		or not _refresh_event_runtime_from_state()
	):
		push_error("RunRuntimeFacade failed to roll back a rejected reward Replay restore")
	return false


func active_loadout() -> Dictionary:
	return _accepted_loadout.duplicate(true)


func native_run_state() -> RefCounted:
	return _orchestrator.native_run_state() if _orchestrator != null else null


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


func current_room_restore_target() -> Dictionary:
	var room := current_room_definition()
	if not _is_floor_plan_run() or room.is_empty() or not room.get("template") is Dictionary:
		return {}
	var target := room.duplicate(true)
	target["node_id"] = str(snapshot().floor_plan.current_node_id)
	target["scene_context"] = _scene_context_for_target(target)
	return target


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
		if _launch_encounter_catalog == null:
			return {}
		var room_type := str(room.get("type", "combat"))
		if room_type in ["combat", "elite"]:
			return _launch_encounter_catalog.resolve_for_node(
				encounter_id,
				int(_orchestrator.snapshot().get("run_seed", 0)),
				str(room.get("node_id", "")),
				room_type,
				str(room.get("template", {}).get("id", ""))
			)
		return _launch_encounter_catalog.encounter_definition(
			encounter_id,
			int(_orchestrator.snapshot().get("run_seed", 0)),
			int(room.get("room_number", 0)),
			str(room.get("type", "combat"))
		)
	return _encounter_catalog.encounter_definition(
		str(room.get("encounter_id", "")),
		int(_orchestrator.snapshot().get("run_seed", 0)),
		int(room.get("room_number", 0))
	)


func event_encounter_definition(profile_id: String) -> Dictionary:
	if not _booted or not _is_floor_plan_run() or _launch_encounter_catalog == null:
		return {}
	var room := current_room_definition()
	if room.get("type") != "event" or not room.get("template") is Dictionary:
		return {}
	var continuation := _current_event_continuation()
	if continuation.get("kind") != "encounter" or continuation.get("encounter_id") != profile_id:
		return {}
	return _launch_encounter_catalog.resolve_for_event(
		profile_id,
		int(_orchestrator.snapshot().get("run_seed", 0)),
		str(room.get("node_id", "")),
		room.template
	)


func open_current_event(runtime_context: Dictionary = {}):
	var readiness = _require_event_room("open_current_event")
	if not readiness.ok:
		return readiness
	if not _sync_event_runtime_floor_plan():
		return CommandResultScript.failure(
			&"INTEGRITY_FAILURE", _revision(), {"stage": "event_route_sync"}
		)
	var room := current_room_definition()
	var opened: Dictionary = _event_runtime.call(
		"open_event",
		{
			"floor_id": str(room.get("floor_id", "")),
			"floor_index": int(room.get("floor_index", -1)),
			"node_id": str(room.get("node_id", "")),
			"primary_event_id": str(room.get("event_id", "")),
		},
		runtime_context.duplicate(true)
	)
	if bool(opened.get("ok", false)):
		if not _overlay_event_assignments(_director, _event_runtime.call("snapshot")):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE", _revision(), {"stage": "event_open_overlay"}
			)
	return _event_command_result(opened)


func event_view_state() -> Dictionary:
	if _event_runtime == null:
		return {}
	var value: Variant = _event_runtime.call("view_state")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func choose_current_event_option(option_id: StringName, expected_revision: int):
	if not _sync_player_health_observation():
		return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision())
	var readiness = _require_event_room("choose_current_event_option")
	if not readiness.ok:
		return readiness
	var result = _event_command_result(
		_event_runtime.call("choose_option", option_id, expected_revision)
	)
	if result.ok:
		_sync_player_health_observation()
	return result


func complete_current_event_reward(
	continuation_id: String,
	result: Dictionary,
	expected_revision: int
):
	var readiness = _require_event_room("complete_current_event_reward")
	if not readiness.ok:
		return readiness
	return _event_command_result(_event_runtime.call(
		"complete_reward",
		continuation_id,
		result.duplicate(true),
		expected_revision
	))


func event_reward_offer() -> Dictionary:
	var continuation := _current_event_continuation()
	if continuation.get("kind") != "reward":
		return {}
	var category := str(continuation["pool_id"]).trim_prefix("rare_")
	var owned := _orchestrator.snapshot().get("build", {}) as Dictionary
	var candidates: Array[Dictionary] = []
	for definition: Dictionary in _registry.get_by_category(StringName(category), &"LAUNCH"):
		if not RewardCompatibilityScript.matches(definition, RewardCompatibilityScript.context_for(_orchestrator.snapshot()["config"])):
			continue
		if (owned.get("items", []) as Array).has(definition["id"]) or (owned.get("blessings", []) as Array).has(definition["id"]):
			continue
		if str(continuation["pool_id"]).begins_with("rare_") and definition.get("rarity") not in ["rare", "legendary", "unique"]:
			continue
		candidates.append(definition)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	var state: Dictionary = _orchestrator.snapshot()
	var rng := SeedServiceScript.make_rng(int(state["run_seed"]), StringName("event_reward:%s" % continuation["continuation_id"]), int(state["current_floor"]), int(state["current_room"]), 0)
	for i: int in range(candidates.size() - 1, 0, -1):
		var other := rng.randi_range(0, i)
		var value := candidates[i]
		candidates[i] = candidates[other]
		candidates[other] = value
	var options: Array[Dictionary] = []
	for definition: Dictionary in candidates.slice(0, mini(int(continuation["count"]), candidates.size())):
		options.append(_draft.call("option_for_definition", definition))
	if options.is_empty():
		return {}
	return {"schema_version": 1, "offer_id": "reward:%s" % continuation["continuation_id"], "category": category, "title_key": "CHOICE_TITLE_%s" % category.to_upper(), "revision": _revision(), "can_skip": false, "options": options, "continuation_id": continuation["continuation_id"]}


func submit_current_event_reward(option_id: StringName, expected_revision: int):
	var ready = _dungeon_command(expected_revision)
	if not ready.ok:
		return ready
	var offer := event_reward_offer()
	var definition: Dictionary = {}
	for option: Dictionary in offer.get("options", []):
		if option["option_id"] == str(option_id):
			definition = _registry.get_content(StringName(option["content_id"]))
	if definition.is_empty() or _merchant_player == null:
		return CommandResultScript.failure(&"OPTION_NOT_FOUND", _revision())
	var transaction = PlayerRewardTransactionScript.new()
	transaction.configure(_merchant_player, _merchant_reward_runtime)
	if not transaction.apply(definition):
		return CommandResultScript.failure(&"COMMIT_FAILED" if transaction.rollback() else &"INTEGRITY_FAILURE", _revision())
	_pending_event_reward_definition = definition.duplicate(true)
	var result = complete_current_event_reward(offer["continuation_id"], {"content_id": definition["id"]}, expected_revision)
	_pending_event_reward_definition.clear()
	if not result.ok and not bool(result.context.get("committed", false)):
		if not transaction.rollback():
			return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision())
		return result
	if not transaction.commit() or not _sync_player_health_observation():
		return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision(), {"committed": true})
	return result


func complete_current_event_encounter(
	continuation_id: String,
	success: bool,
	context: Dictionary,
	expected_revision: int
):
	var readiness = _require_event_room("complete_current_event_encounter")
	if not readiness.ok:
		return readiness
	return _event_command_result(_event_runtime.call(
		"complete_encounter",
		continuation_id,
		success,
		context.duplicate(true),
		expected_revision
	))


func dismiss_current_event(expected_revision: int):
	var readiness = _require_event_room("dismiss_current_event")
	if not readiness.ok:
		return readiness
	return _event_command_result(
		_event_runtime.call("dismiss_result", expected_revision)
	)


func _require_event_room(operation: String):
	var readiness = _require_booted(operation)
	if not readiness.ok:
		return readiness
	var room := current_room_definition()
	if (
		_event_runtime == null
		or room.is_empty()
		or str(room.get("runtime_mode", "")) != "launch"
		or str(room.get("room_type", room.get("type", ""))) != "event"
	):
		return CommandResultScript.failure(
			&"INVALID_PHASE", _revision(), {"operation": operation}
		)
	return CommandResultScript.success(_revision())


func _event_command_result(value: Variant):
	if not value is Dictionary:
		return CommandResultScript.failure(
			&"INTEGRITY_FAILURE", _revision(), {"stage": "event_result_shape"}
		)
	var result := value as Dictionary
	if not bool(result.get("ok", false)):
		var failure_context := (
			(result.get("context", {}) as Dictionary).duplicate(true)
			if result.get("context", {}) is Dictionary
			else {}
		)
		if bool(result.get("committed", false)):
			failure_context["committed"] = true
			failure_context["pending_publication"] = bool(
				result.get("pending_publication", false)
			)
		return CommandResultScript.failure(
			StringName(str(result.get("code", "INVALID_ARGUMENT"))),
			_revision(),
			failure_context
		)
	var view_value: Variant = result.get("view_state", event_view_state())
	var view := (
		(view_value as Dictionary).duplicate(true)
		if view_value is Dictionary
		else event_view_state()
	)
	var context := {"view_state": view}
	var continuation := _current_event_continuation()
	if not continuation.is_empty():
		context["continuation"] = continuation
	return CommandResultScript.success(_revision(), context)


func _sync_event_runtime_floor_plan() -> bool:
	if _event_runtime == null or _orchestrator == null or _economy_state == null:
		return false
	var runtime_snapshot: Dictionary = _event_runtime.call("snapshot")
	var current_plan := _orchestrator.snapshot().get("floor_plan", {}) as Dictionary
	var consequence := runtime_snapshot.get("consequence_runtime", {}) as Dictionary
	var participants := consequence.get("participant_snapshots", {}) as Dictionary
	var route := participants.get("route", {}) as Dictionary
	if current_plan.is_empty() or route.is_empty():
		return false
	if route.get("plan", {}) == current_plan:
		return true
	route["plan"] = current_plan.duplicate(true)
	participants["route"] = route
	consequence["participant_snapshots"] = participants
	runtime_snapshot["consequence_runtime"] = consequence
	var candidate := _event_runtime_candidate(
		_orchestrator, _director, _economy_state, runtime_snapshot
	)
	if not bool(candidate.get("ok", false)):
		return false
	_event_runtime = candidate["runtime"] as RefCounted
	return _sync_player_event_modifiers()


func _refresh_event_runtime_from_state() -> bool:
	if _orchestrator == null:
		return false
	var runtime_snapshot := (
		_orchestrator.snapshot().get("dungeon_event_runtime", {}) as Dictionary
	).duplicate(true)
	if runtime_snapshot.is_empty():
		return _event_runtime == null
	if _event_runtime == null or _economy_state == null:
		return false
	var candidate := _event_runtime_candidate(
		_orchestrator, _director, _economy_state, runtime_snapshot
	)
	if not bool(candidate.get("ok", false)):
		return false
	_event_runtime = candidate["runtime"] as RefCounted
	return _sync_player_event_modifiers()


func _restore_route_runtime_adapters_after_rollback() -> bool:
	if _orchestrator == null or _director == null or _economy_state == null:
		return false
	var state: Dictionary = _orchestrator.snapshot()
	var plan := (state.get("floor_plan", {}) as Dictionary).duplicate(true)
	var candidate_director = RunDirectorScript.new()
	if not candidate_director.configure_launch_plan(plan, _registry):
		candidate_director.free()
		return false
	var event_value := (
		state.get("dungeon_event_runtime", {}) as Dictionary
	).duplicate(true)
	var event_candidate := _event_runtime_candidate(
		_orchestrator,
		candidate_director,
		_economy_state,
		event_value
	)
	if not bool(event_candidate.get("ok", false)):
		candidate_director.free()
		return false
	var merchant_value := (
		state.get("merchant_state", {}) as Dictionary
	).duplicate(true)
	if (
		_merchant_run_state == null
		or not bool(_merchant_run_state.call("restore_snapshot", merchant_value))
	):
		candidate_director.free()
		return false
	var previous_director = _director
	_director = candidate_director
	_event_runtime = event_candidate["runtime"] as RefCounted
	_merchant_sessions.clear()
	if not _restore_current_merchant_session_from_snapshot():
		_director = previous_director
		candidate_director.free()
		return false
	if previous_director != null and is_instance_valid(previous_director):
		previous_director.free()
	return true


func _current_event_continuation() -> Dictionary:
	if _event_runtime == null:
		return {}
	var runtime_snapshot: Dictionary = _event_runtime.call("snapshot")
	var consequence := runtime_snapshot.get("consequence_runtime", {}) as Dictionary
	var participants := consequence.get("participant_snapshots", {}) as Dictionary
	var event_state := participants.get("event_state", {}) as Dictionary
	var reward := event_state.get("pending_reward", {}) as Dictionary
	if not reward.is_empty():
		return {
			"kind": "reward",
			"continuation_id": str(reward.get("continuation_id", "")),
			"pool_id": str(reward.get("pool_id", "")),
			"count": int(reward.get("count", 0)),
		}
	var encounter := event_state.get("pending_encounter", {}) as Dictionary
	if not encounter.is_empty():
		return {
			"kind": "encounter",
			"continuation_id": str(encounter.get("continuation_id", "")),
			"encounter_id": str(encounter.get("encounter_id", "")),
		}
	return {}


func room_plan() -> Array[Dictionary]:
	if _is_floor_plan_run() and _director != null:
		var definitions: Array[Dictionary] = []
		for room_number: int in range(1, _director.room_count() + 1):
			definitions.append(_director.room_definition_for(room_number))
		return definitions
	return _room_definitions.duplicate(true)


func encounter_catalog() -> RefCounted:
	return _launch_encounter_catalog if _is_floor_plan_run() else _encounter_catalog


func content_registry() -> RefCounted:
	return _registry


func active_meta_catalog() -> RefCounted:
	var projection: Dictionary = snapshot().get("resources", {}).get("meta_run_projection", {})
	if projection.is_empty():
		return null
	var loaded := MetaCatalogFactory.from_profile_registry(_registry, projection)
	return loaded.context.catalog if loaded.ok else null


func create_room_runtime(encounter_runner: Node) -> Node:
	if not _booted or _orchestrator == null or _encounter_catalog == null or encounter_runner == null:
		return null
	var runtime := RoomRuntimeScript.new()
	runtime.configure(
		self,
		encounter_catalog(),
		room_plan(),
		int(_orchestrator.snapshot().get("run_seed", 0)),
		encounter_runner
	)
	return runtime


func configure_merchant_effect_authority(
	reward_runtime: Object,
	player: Object
) -> bool:
	if (
		reward_runtime == null
		or not is_instance_valid(reward_runtime)
		or player == null
		or not is_instance_valid(player)
	):
		return false
	for method_name: StringName in [&"prepare", &"commit", &"rollback"]:
		if not reward_runtime.has_method(method_name):
			return false
	for method_name: StringName in [
		&"reward_effect_snapshot",
		&"restore_reward_effect_snapshot",
		&"reward_effect_apply_operation",
		&"reward_effect_begin_publication",
		&"reward_effect_publication_can_commit",
		&"reward_effect_commit_publication",
		&"reward_effect_rollback_publication",
	]:
		if not player.has_method(method_name):
			return false
	_merchant_reward_runtime = reward_runtime
	_merchant_player = player
	var baseline_value: Variant = player.call("reward_effect_snapshot")
	if baseline_value is Dictionary and not (baseline_value as Dictionary).is_empty():
		_merchant_run_start_player_baseline = (baseline_value as Dictionary).duplicate(true)
		var state: Dictionary = _orchestrator.snapshot()
		var stored_baseline: Variant = state.get("resources", {}).get("player_reward_run_start_baseline", {})
		if stored_baseline is Dictionary and not stored_baseline.is_empty():
			_merchant_run_start_player_baseline = stored_baseline.duplicate(true)
		elif _is_floor_plan_run() and baseline_value.has("schema_version") and state.get("build", {}).get("reward_history", []).is_empty():
			if not _orchestrator.bind_player_reward_baseline(baseline_value):
				return false
	return _sync_player_health_observation() and _sync_player_event_modifiers()


func _physical_health() -> Dictionary:
	if _merchant_player == null or not is_instance_valid(_merchant_player):
		return {}
	var value: Variant = _merchant_player.call("reward_effect_snapshot")
	if not value is Dictionary or not value.get("health") is Dictionary:
		return {}
	return (value["health"] as Dictionary).duplicate(true)


func apply_meta_floor_entrance(player: Node) -> Dictionary:
	var before: Dictionary = snapshot()
	var projection: Dictionary = before.get("resources", {}).get("meta_run_projection", {})
	if projection.is_empty():
		return {"ok": true, "code": &"OK", "context": {"applied": false}}
	if player == null or not is_instance_valid(player) or player != _merchant_player or not player.has_method("meta_run_projection_snapshot") or player.call("meta_run_projection_snapshot") != projection or str(player.call("current_run_id")) != str(before.run_id) or not _route_transactions.is_empty():
		return {"ok": false, "code": &"PLAYER_IDENTITY_INVALID", "context": {}}
	var floor_index := int(before.current_floor_index)
	if (before.resources.get("meta_floor_entrances", []) as Array).has(floor_index):
		return {"ok": true, "code": &"OK", "context": {"applied": false}}
	if not _sync_player_health_observation():
		return {"ok": false, "code": &"HEALTH_SYNC_FAILED", "context": {}}
	before = snapshot()
	var physical_before: Dictionary = player.call("reward_effect_snapshot")
	var physical_after := physical_before.duplicate(true)
	var current := float(physical_before.health.current_hp)
	var maximum := float(physical_before.health.max_hp)
	physical_after.health.current_hp = minf(maximum, current + maximum * float(projection.stat_bonuses.entrance_healing))
	if not bool(player.call("restore_reward_effect_snapshot", physical_after, false)):
		return {"ok": false, "code": &"COMMIT_FAILED", "context": {}}
	var committed = _orchestrator.commit_meta_floor_entrance(current, maximum, float(physical_after.health.current_hp), int(before.revision))
	if not committed.ok or not _refresh_event_runtime_from_state():
		var domain_restored: bool = _orchestrator.restore_launch_run_snapshot(before, _floor_definitions[floor_index], _room_templates)
		var physical_restored := bool(player.call("restore_reward_effect_snapshot", physical_before, false))
		var event_restored := _refresh_event_runtime_from_state()
		return {"ok": false, "code": &"COMMIT_FAILED" if domain_restored and physical_restored and event_restored else &"INTEGRITY_FAILURE", "context": {}}
	var healed := float(physical_after.health.current_hp) - current
	if healed > 0.0:
		player.get_node("HealthComponent").emit_signal("healed", healed, float(physical_after.health.current_hp))
	return {"ok": true, "code": &"OK", "context": {"applied": true, "healed": healed, "revision": committed.new_revision}}


func _sync_player_event_modifiers() -> bool:
	if _merchant_player == null or not is_instance_valid(_merchant_player):
		return true
	if not _merchant_player.has_method("sync_event_temporary_modifiers"):
		return true
	if _orchestrator == null:
		return false
	var state: Dictionary = _orchestrator.snapshot()
	var runtime := state.get("dungeon_event_runtime", {}) as Dictionary
	if runtime.is_empty() or _orchestrator.is_terminal():
		return bool(_merchant_player.call("sync_event_temporary_modifiers", []))
	var parts := runtime["consequence_runtime"]["participant_snapshots"] as Dictionary
	var event_state := parts["event_state"] as Dictionary
	var projection := EventModifierLifetimeScript.active_projection(
		state["events"], event_state["selected_event_by_node"],
		(parts["modifier"] as Dictionary)["temporary_modifiers"]
	)
	return bool(projection.get("ok", false)) and bool(_merchant_player.call(
		"sync_event_temporary_modifiers", projection["context"]["modifiers"]
	))


func _sync_player_health_observation() -> bool:
	if _merchant_player == null or _event_runtime == null or _orchestrator == null:
		return true
	if not _route_transactions.is_empty():
		return true
	var physical := _physical_health()
	if not physical.get("current_hp") is float and not physical.get("current_hp") is int:
		return false
	var current := float(physical["current_hp"])
	var maximum := float(physical.get("max_hp", 0.0))
	var runtime_snapshot: Dictionary = _orchestrator.snapshot()["dungeon_event_runtime"].duplicate(true)
	var participants := runtime_snapshot["consequence_runtime"]["participant_snapshots"] as Dictionary
	var health := participants["health"] as Dictionary
	if float(health["current"]) == current and float(health["maximum"]) == maximum:
		return true
	health["current"] = current
	health["maximum"] = maximum
	var candidate := _event_runtime_candidate(_orchestrator, _director, _economy_state, runtime_snapshot)
	if not bool(candidate.get("ok", false)) or not _orchestrator.observe_player_health(current, maximum):
		return false
	_event_runtime = candidate["runtime"]
	return true


func grant_run_gold(
	transaction_id: String,
	amount: int,
	source_id: String
):
	var readiness = _require_booted("grant_run_gold")
	if not readiness.ok:
		return readiness
	if (
		not _is_floor_plan_run()
		or _economy_state == null
		or _merchant_run_state == null
		or amount <= 0
		or source_id.is_empty()
	):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_revision(),
			{"operation": "grant_run_gold"}
		)
	var prepared: Dictionary = _economy_state.call(
		"prepare_transaction",
		transaction_id,
		amount,
		int(_economy_state.call("revision")),
		{"operation": "gold_delta", "source_id": source_id}
	)
	if not bool(prepared.get("ok", false)):
		return CommandResultScript.failure(
			StringName(str(prepared.get("code", &"PREPARE_FAILED"))),
			_revision(),
			(prepared.get("context", {}) as Dictionary).duplicate(true)
		)
	var ticket := (prepared.get("ticket", {}) as Dictionary).duplicate(true)
	var committed: Dictionary = _economy_state.call("commit_transaction", ticket)
	if not bool(committed.get("ok", false)):
		_economy_state.call("rollback_transaction", ticket)
		return CommandResultScript.failure(
			StringName(str(committed.get("code", &"COMMIT_FAILED"))),
			_revision(),
			(committed.get("context", {}) as Dictionary).duplicate(true)
		)
	var receipt := (committed.get("receipt", {}) as Dictionary).duplicate(true)
	var state_committed = _orchestrator.commit_economy_transaction(
		_economy_state.call("snapshot"),
		_merchant_run_state.call("snapshot"),
		_revision()
	)
	if not state_committed.ok:
		var rolled_back: Dictionary = _economy_state.call(
			"rollback_transaction", receipt
		)
		if not bool(rolled_back.get("ok", false)):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE",
				_revision(),
				{"stage": "gold_income_state_rollback", "transaction_id": transaction_id}
			)
		return state_committed
	return CommandResultScript.success(
		state_committed.new_revision,
		{
			"transaction_id": transaction_id,
			"amount": amount,
			"source_id": source_id,
			"balance": int(_economy_state.call("balance")),
			"ledger_entry": (
				(committed.get("ledger_entry", {}) as Dictionary).duplicate(true)
			),
		}
	)


func restore_launch_run(value: Dictionary, effect_authority: Variant = null):
	var readiness = _require_booted("restore_launch_run")
	if not readiness.ok:
		return readiness
	if (
		_orchestrator.phase() != RunPhaseScript.Value.HUB
		or value.is_empty()
		or not value.get("config") is Dictionary
		or not value.get("floor_plan") is Dictionary
		or (value.get("floor_plan", {}) as Dictionary).is_empty()
	):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _revision(), {"operation": "restore_launch_run"}
		)
	value = value.duplicate(true)
	var restore_parts: Dictionary = {}
	var restore_runtime: Variant = value.get("dungeon_event_runtime", {})
	if restore_runtime is Dictionary and restore_runtime.get("consequence_runtime") is Dictionary:
		var participant_value: Variant = restore_runtime["consequence_runtime"].get("participant_snapshots", {})
		if participant_value is Dictionary:
			restore_parts = participant_value
	if value.get("events") is Array and restore_parts.get("event_state") is Dictionary and restore_parts.get("modifier") is Dictionary:
		var baseline := EventModifierLifetimeScript.normalize_legacy_baselines(
			value["events"], restore_parts["event_state"].get("selected_event_by_node", {}),
			restore_parts["modifier"].get("temporary_modifiers", [])
		)
		if not bool(baseline.get("ok", false)):
			return CommandResultScript.failure(&"INVALID_ARGUMENT", _revision(), {"field": "events", "stage": "event_modifier_migration"})
		value["events"] = (baseline["context"]["events"] as Array).duplicate(true)
	var config := RunConfigScript.normalized(value.get("config", {}) as Dictionary)
	var validation = RunConfigScript.validate(config)
	if not validation.ok or not _is_floor_plan_milestone(str(config.get("milestone", ""))):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _revision(), {"field": "config"}
		)
	var loadout_validation = RunLoadoutPolicyScript.new().validate(config, _registry)
	if not loadout_validation.ok:
		return CommandResultScript.failure(
			loadout_validation.code, _revision(), loadout_validation.context
		)
	var launch_content = _configure_launch_content(StringName(str(config["milestone"])))
	if not launch_content.ok:
		return launch_content
	var floor_index := int(value.get("current_floor_index", -1))
	if floor_index < 0 or floor_index >= _floor_definitions.size():
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _revision(), {"field": "current_floor_index"}
		)
	var meta_catalog: RefCounted
	var projection: Variant = value.get("resources", {}).get("meta_run_projection", {})
	if not projection is Dictionary:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", _revision(), {"field": "meta_run_projection"})
	if not projection.is_empty():
		var loaded := MetaCatalogFactory.from_profile_registry(_registry, projection)
		if not loaded.ok or not MetaRunProjectionScript.validate(projection, loaded.context.catalog):
			return CommandResultScript.failure(&"INVALID_ARGUMENT", _revision(), {"field": "meta_run_projection"})
		meta_catalog = loaded.context.catalog
	var candidate_orchestrator = RunOrchestratorScript.new()
	var candidate_director = RunDirectorScript.new()
	if not candidate_orchestrator.enter_hub().ok:
		candidate_director.free()
		return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision())
	var candidate_started = candidate_orchestrator.start_run(
		config,
		str(value.get("run_id", ""))
	)
	if not candidate_started.ok:
		candidate_director.free()
		return CommandResultScript.failure(
			candidate_started.code, _revision(), candidate_started.context
		)
	if not candidate_orchestrator.restore_launch_run_snapshot(
		value.duplicate(true),
		_floor_definitions[floor_index].duplicate(true),
		_room_templates.duplicate(true),
		meta_catalog
	):
		candidate_director.free()
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _revision(), {"field": "snapshot"}
		)
	if not candidate_director.configure_launch_plan(
		value.get("floor_plan", {}) as Dictionary,
		_registry
	):
		candidate_director.free()
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE", _revision(), {"field": "floor_plan"}
		)
	var economy_value := value.get("run_economy", {}) as Dictionary
	var merchant_value := value.get("merchant_state", {}) as Dictionary
	var candidate_economy = RunEconomyStateScript.new()
	var economy_configured: Dictionary = candidate_economy.call(
		"configure",
		_economy_profile.duplicate(true),
		int(economy_value.get("initial_gold", -1))
	)
	var candidate_merchant = MerchantRunStateScript.new()
	var merchant_configured: Dictionary = candidate_merchant.call(
		"configure", _launch_content_fingerprint
	)
	if (
		not bool(economy_configured.get("ok", false))
		or not bool(merchant_configured.get("ok", false))
		or not bool(candidate_economy.call("restore_snapshot", economy_value.duplicate(true)))
		or not bool(candidate_merchant.call("restore_snapshot", merchant_value.duplicate(true)))
	):
		candidate_director.free()
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _revision(), {"field": "run_economy_or_merchant_state"}
		)
	var event_value := value.get("dungeon_event_runtime", {}) as Dictionary
	var event_candidate := _event_runtime_candidate(
		candidate_orchestrator,
		candidate_director,
		candidate_economy,
		event_value
	)
	if not bool(event_candidate.get("ok", false)):
		candidate_director.free()
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_revision(),
			{
				"field": "dungeon_event_runtime",
				"cause": (event_candidate.get("context", {}) as Dictionary).duplicate(true),
			}
		)
	var candidate_event_runtime := event_candidate["runtime"] as RefCounted
	var candidate_floor_rule_runtime: RefCounted = null
	var floor_rule_value := value.get("floor_rule_state", {}) as Dictionary
	if not floor_rule_value.is_empty():
		var floor_rule_candidate := _floor_rule_runtime_restore_candidate(
			floor_rule_value,
			effect_authority
		)
		if not bool(floor_rule_candidate.get("ok", false)):
			candidate_director.free()
			return CommandResultScript.failure(
				StringName(str(floor_rule_candidate.get("code", &"INVALID_ARGUMENT"))),
				_revision(),
				(floor_rule_candidate.get("context", {}) as Dictionary).duplicate(true)
			)
		candidate_floor_rule_runtime = floor_rule_candidate["runtime"] as RefCounted

	var previous_orchestrator = _orchestrator
	var previous_director = _director
	var previous_economy = _economy_state
	var previous_merchant = _merchant_run_state
	var previous_floor_rule_runtime = _floor_rule_runtime
	var previous_floor_rule_effect_authority: Variant = _floor_rule_effect_authority
	var previous_event_runtime = _event_runtime
	var previous_loadout := _accepted_loadout.duplicate(true)
	var previous_sessions := _merchant_sessions.duplicate()
	var previous_player_baseline := _merchant_run_start_player_baseline.duplicate(true)
	_orchestrator = candidate_orchestrator
	_director = candidate_director
	_economy_state = candidate_economy
	_merchant_run_state = candidate_merchant
	_event_runtime = candidate_event_runtime
	_accepted_loadout = (
		(loadout_validation.context.get("loadout", {}) as Dictionary).duplicate(true)
	)
	_room_definitions.clear()
	_route_transactions.clear()
	_selection_reservations.clear()
	_floor_rule_runtime = candidate_floor_rule_runtime
	_floor_rule_effect_authority = (
		effect_authority if candidate_floor_rule_runtime != null else null
	)
	_merchant_sessions.clear()
	var saved_baseline: Variant = value.get("resources", {}).get("player_reward_run_start_baseline", {})
	if saved_baseline is Dictionary and not saved_baseline.is_empty():
		_merchant_run_start_player_baseline = saved_baseline.duplicate(true)
	if not _restore_current_merchant_session_from_snapshot() or not _sync_player_event_modifiers():
		_orchestrator = previous_orchestrator
		_director = previous_director
		_economy_state = previous_economy
		_merchant_run_state = previous_merchant
		_event_runtime = previous_event_runtime
		_floor_rule_runtime = previous_floor_rule_runtime
		_floor_rule_effect_authority = previous_floor_rule_effect_authority
		_accepted_loadout = previous_loadout
		_merchant_sessions = previous_sessions
		_merchant_run_start_player_baseline = previous_player_baseline
		candidate_director.free()
		return CommandResultScript.failure(
			&"AUTHORED_RUNTIME_CONFIGURATION_FAILED",
			_revision(),
			{"stage": "merchant_session_restore"}
		)
	_published_event_fact_ids.clear()
	if previous_director != null and is_instance_valid(previous_director):
		previous_director.free()
	return CommandResultScript.success(
		_revision(), {"snapshot": snapshot(), "restored": true}
	)


func _floor_rule_runtime_restore_candidate(
	value: Dictionary,
	effect_authority: Variant
) -> Dictionary:
	for field: String in [
		"rule_id", "room_id", "room_seed", "zones", "safe_zone_ids",
		"reduced_motion", "hit_flash_enabled",
	]:
		if not value.has(field):
			return {
				"ok": false,
				"code": &"INVALID_ARGUMENT",
				"context": {"field": "floor_rule_state.%s" % field},
			}
	if not value["zones"] is Array or not value["safe_zone_ids"] is Array:
		return {
			"ok": false,
			"code": &"INVALID_ARGUMENT",
			"context": {"field": "floor_rule_state"},
		}
	var runtime := _new_floor_rule_runtime(StringName(str(value.get("rule_id", ""))))
	if runtime == null:
		return {
			"ok": false,
			"code": &"INVALID_ARGUMENT",
			"context": {"field": "floor_rule_state.rule_id"},
		}
	var configuration := {
		"room_id": value.get("room_id"),
		"room_seed": value.get("room_seed"),
		"zones": (value.get("zones", []) as Array).duplicate(true),
		"safe_zone_ids": (value.get("safe_zone_ids", []) as Array).duplicate(),
		"reduced_motion": value.get("reduced_motion"),
		"hit_flash_enabled": value.get("hit_flash_enabled"),
	}
	var configured: Dictionary = runtime.call(
		"configure",
		configuration,
		effect_authority
	)
	if (
		not bool(configured.get("ok", false))
		or not bool(runtime.call("restore_snapshot", value.duplicate(true)))
		or runtime.call("snapshot") != value
	):
		return {
			"ok": false,
			"code": StringName(str(configured.get("code", &"INVALID_ARGUMENT"))),
			"context": {"field": "floor_rule_state"},
		}
	return {"ok": true, "code": &"OK", "runtime": runtime}


func open_current_merchant():
	var readiness = _require_booted("open_current_merchant")
	if not readiness.ok:
		return readiness
	var room := current_room_definition()
	if (
		not _is_floor_plan_run()
		or str(room.get("room_type", "")) != "shop"
		or _economy_state == null
		or _merchant_run_state == null
		or _merchant_player == null
		or _merchant_reward_runtime == null
	):
		return CommandResultScript.failure(
			&"INVALID_PHASE", _revision(), {"operation": "open_current_merchant"}
		)
	var merchant_id := str(room.get("merchant_id", ""))
	var node_key := "%s:%s" % [str(room.get("floor_id", "")), str(room.get("node_id", ""))]
	if merchant_id.is_empty() or not _merchant_definitions_by_id.has(merchant_id):
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE", _revision(), {"merchant_id": merchant_id}
		)
	if _merchant_sessions.has(node_key):
		return CommandResultScript.success(
			_revision(), {"merchant": merchant_view_state()}
		)
	var merchant: Dictionary = (
		_merchant_definitions_by_id[merchant_id] as Dictionary
	).duplicate(true)
	var floor_number := int(room.get("floor_index", -1)) + 1
	var price_service = ShopPriceServiceScript.new()
	var inventory = MerchantInventoryServiceScript.new()
	var inventory_configured: Dictionary = inventory.configure(
		int(_orchestrator.snapshot().get("run_seed", 0)),
		merchant,
		_economy_profile,
		floor_number,
		StringName(str(room.get("node_id", ""))),
		_merchant_reward_definitions,
		_merchant_compatibility_context(),
		Callable(price_service, "reward_price")
	)
	if not bool(inventory_configured.get("ok", false)):
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE", _revision(), inventory_configured.get("context", {})
		)
	var generated: Dictionary = inventory.generate()
	if not bool(generated.get("ok", false)):
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE", _revision(), generated.get("context", {})
		)
	var service_result := _create_merchant_service_router(
		merchant, floor_number, inventory, _orchestrator.snapshot().get("floor_plan", {})
	)
	if not bool(service_result.get("ok", false)):
		return CommandResultScript.failure(
			&"AUTHORED_RUNTIME_CONFIGURATION_FAILED",
			_revision(), service_result.get("context", {})
		)
	var service_authority: Object = service_result["router"]
	var runtime = MerchantRuntimeScript.new()
	if not runtime.configure(
		_economy_state,
		inventory,
		MerchantRewardRuntimeScript.new(_merchant_reward_runtime, _merchant_player),
		_merchant_player,
		service_authority,
		Callable(self, "_commit_merchant_state_payload").bind(node_key, merchant_id)
	):
		return CommandResultScript.failure(
			&"AUTHORED_RUNTIME_CONFIGURATION_FAILED", _revision(), {"merchant_id": merchant_id}
		)
	var previous_merchant_snapshot: Dictionary = _merchant_run_state.call("snapshot")
	var upserted: Dictionary = _merchant_run_state.call("upsert_node", {
		"floor_id": str(room["floor_id"]),
		"floor_index": int(room["floor_index"]),
		"node_id": str(room["node_id"]),
		"merchant_id": merchant_id,
		"inventory": inventory.snapshot(),
		"runtime": runtime.snapshot(),
		"service": service_authority.snapshot(),
		"visibility": service_authority.visibility_snapshot(),
		"transactions": [],
	})
	if not bool(upserted.get("ok", false)):
		return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision(), {"stage": "merchant_node"})
	var state_committed = _orchestrator.commit_merchant_transaction(
		_economy_state.call("snapshot"),
		_merchant_run_state.call("snapshot"),
		_revision()
	)
	if not state_committed.ok:
		_merchant_run_state.call("restore_snapshot", previous_merchant_snapshot)
		return state_committed
	_merchant_sessions[node_key] = {
		"merchant": merchant,
		"inventory": inventory,
		"runtime": runtime,
		"service": service_authority,
		"price": price_service,
	}
	return CommandResultScript.success(
		state_committed.new_revision, {"merchant": merchant_view_state()}
	)


func merchant_view_state() -> Dictionary:
	var room := current_room_definition()
	var node_key := "%s:%s" % [str(room.get("floor_id", "")), str(room.get("node_id", ""))]
	if not _merchant_sessions.has(node_key) or _economy_state == null:
		return {}
	var session := _merchant_sessions[node_key] as Dictionary
	var merchant := session["merchant"] as Dictionary
	var inventory: Object = session["inventory"]
	var service: Object = session["service"]
	return {
		"node_key": node_key,
		"merchant_id": str(merchant["id"]),
		"name_key": str(merchant["name_key"]),
		"description_key": str(merchant["description_key"]),
		"intro_key": str(merchant["intro_key"]),
		"farewell_key": str(merchant["farewell_key"]),
		"services": (merchant["services"] as Array).duplicate(),
		"gold": int(_economy_state.call("balance")),
		"economy_revision": int(_economy_state.call("revision")),
		"inventory": inventory.call("snapshot"),
		"service_state": service.call("snapshot"),
		"visibility": (
			service.call("visibility_snapshot")
			if service.has_method("visibility_snapshot")
			else {}
		),
	}


func merchant_service_choices() -> Array[Dictionary]:
	var source := merchant_view_state()
	var result: Array[Dictionary] = []
	if source.is_empty():
		return result
	var room := current_room_definition()
	var floor_number := int(room["floor_index"]) + 1
	var price = ShopPriceServiceScript.new()
	var health := _physical_health()
	var build := _orchestrator.snapshot()["build"] as Dictionary
	var service_state := source["service_state"] as Dictionary
	for id: String in source["services"]:
		if id == "purchase_reward":
			continue
		var targets: Array[String] = ["player"]
		var cost_kind := "gold"
		var amount := 0
		var available := true
		var reason := "UI_MERCHANT_INSUFFICIENT_GOLD"
		if id == "reroll":
			var quote: Dictionary = price.reroll_price(_economy_profile, int(source["inventory"].get("reroll_count", 0)))
			available = bool(quote.get("ok", false))
			amount = int(quote.get("price", 0))
		elif id == "health_trade":
			targets.clear()
			for offer: Dictionary in source["inventory"]["offers"]:
				if not offer["sold"]:
					targets.append(str(offer["offer_id"]))
			cost_kind = "health"
			amount = ceili(float(health.get("current_hp", 0.0)) * MerchantHealthTradeAuthorityScript.HEALTH_COST_RATIO)
			available = float(health.get("current_hp", 0.0)) - amount >= 1.0
			reason = "UI_REQUIREMENT_UNMET"
		elif id == "sell_reward":
			targets.clear()
			for definition: Dictionary in build["reward_history"]:
				if definition["category"] == "blessing" or (definition["category"] == "item" and definition.get("item_mode") == "passive"):
					targets.append(str(definition["id"]))
			cost_kind = "reward"
		elif id == "cleanse_curse":
			targets.assign(build["curses"])
		if id in ["heal", "weapon_upgrade", "cleanse_curse", "route_reveal"]:
			var quote: Dictionary = price.service_price(_economy_profile, StringName(id), floor_number)
			available = bool(quote.get("ok", false))
			amount = int(quote.get("price", 0))
		if cost_kind == "gold" and amount > int(source["gold"]):
			available = false
		if id == "heal" and float(health.get("current_hp", 0.0)) >= float(health.get("max_hp", 0.0)):
			available = false
			reason = "UI_HEAL_NOT_NEEDED"
		if id == "weapon_upgrade" and int(service_state.get("authorities", {}).get("weapon_upgrade", {}).get("level", 0)) >= MerchantWeaponUpgradeAuthorityScript.MAX_LEVEL:
			available = false
			reason = "UI_REST_UPGRADE_UNAVAILABLE"
		for target: String in targets:
			result.append({"action_id": id, "target_id": target, "label_key": "UI_MERCHANT_%s" % id.to_upper(), "cost_kind": cost_kind, "price": amount, "available": available, "disabled_reason_key": "" if available else reason})
	return result


func purchase_current_merchant(transaction_id: String, offer_id: String):
	var session_result := _current_merchant_session("purchase_current_merchant")
	if not bool(session_result.get("ok", false)):
		return session_result["result"]
	var session := session_result["session"] as Dictionary
	var inventory: Object = session["inventory"]
	var runtime: Object = session["runtime"]
	var result: Dictionary = runtime.call(
		"purchase_reward",
		transaction_id,
		offer_id,
		int((inventory.call("snapshot") as Dictionary)["revision"]),
		int(_economy_state.call("revision"))
	)
	if not bool(result.get("ok", false)):
		return CommandResultScript.failure(
			StringName(str(result.get("code", &"COMMIT_FAILED"))),
			_revision(), result.get("context", {})
		)
	if not _refresh_current_reward_mutation_authority():
		return CommandResultScript.failure(
			&"INTEGRITY_FAILURE", _revision(), {"stage": "merchant_reward_mutation_refresh"}
		)
	return CommandResultScript.success(
		_revision(), {"transaction": result, "merchant": merchant_view_state()}
	)


func reroll_current_merchant(transaction_id: String):
	var session_result := _current_merchant_session("reroll_current_merchant")
	if not bool(session_result.get("ok", false)):
		return session_result["result"]
	var session := session_result["session"] as Dictionary
	var inventory: Object = session["inventory"]
	var runtime: Object = session["runtime"]
	var result: Dictionary = runtime.call(
		"reroll",
		transaction_id,
		int((inventory.call("snapshot") as Dictionary)["revision"]),
		int(_economy_state.call("revision"))
	)
	if not bool(result.get("ok", false)):
		return CommandResultScript.failure(
			StringName(str(result.get("code", &"COMMIT_FAILED"))),
			_revision(), result.get("context", {})
		)
	return CommandResultScript.success(
		_revision(), {"transaction": result, "merchant": merchant_view_state()}
	)


func execute_current_merchant_service(
	transaction_id: String,
	service_id: StringName,
	target_id: String = "player"
):
	var session_result := _current_merchant_session("execute_current_merchant_service")
	if not bool(session_result.get("ok", false)):
		return session_result["result"]
	var runtime: Object = (session_result["session"] as Dictionary)["runtime"]
	var result: Dictionary = runtime.call(
		"execute_service",
		transaction_id,
		service_id,
		target_id,
		int(_economy_state.call("revision"))
	)
	if not bool(result.get("ok", false)):
		return CommandResultScript.failure(
			StringName(str(result.get("code", &"COMMIT_FAILED"))),
			_revision(), result.get("context", {})
		)
	if not _refresh_current_reward_mutation_authority():
		return CommandResultScript.failure(
			&"INTEGRITY_FAILURE", _revision(), {"stage": "merchant_reward_mutation_refresh"}
		)
	return CommandResultScript.success(
		_revision(), {"transaction": result, "merchant": merchant_view_state()}
	)


func _current_merchant_session(operation: String) -> Dictionary:
	var room := current_room_definition()
	var node_key := "%s:%s" % [str(room.get("floor_id", "")), str(room.get("node_id", ""))]
	if (
		str(room.get("room_type", "")) != "shop"
		or not _merchant_sessions.has(node_key)
		or _economy_state == null
	):
		return {
			"ok": false,
			"result": CommandResultScript.failure(
				&"INVALID_PHASE", _revision(), {"operation": operation}
			),
		}
	return {
		"ok": true,
		"session": (_merchant_sessions[node_key] as Dictionary).duplicate(),
	}


func _refresh_current_reward_mutation_authority() -> bool:
	var room := current_room_definition()
	var node_key := "%s:%s" % [str(room.get("floor_id", "")), str(room.get("node_id", ""))]
	if not _merchant_sessions.has(node_key):
		return false
	var session := _merchant_sessions[node_key] as Dictionary
	var router: Object = session["service"]
	if not router.has_method("authority") or router.call("authority", "reward_mutation") == null:
		return true
	var node: Dictionary = _merchant_run_state.call("node_state", node_key)
	var persisted_service := (node.get("service", {}) as Dictionary).duplicate(true)
	var authorities := (
		(persisted_service.get("authorities", {}) as Dictionary)
		if persisted_service.get("authorities", {}) is Dictionary
		else {}
	)
	var mutation_snapshot := (
		(authorities.get("reward_mutation", {}) as Dictionary)
		if authorities.get("reward_mutation", {}) is Dictionary
		else {}
	)
	var baseline := (
		(mutation_snapshot.get("run_start_player_baseline", {}) as Dictionary).duplicate(true)
		if mutation_snapshot.get("run_start_player_baseline", {}) is Dictionary
		else {}
	)
	if baseline.is_empty():
		return false
	var authority: Object = router.call("authority", "reward_mutation") as Object
	if authority == null or not authority.has_method("synchronize_live_state"):
		return false
	var build_participant: Object = _orchestrator.reward_build_participant()
	var build_snapshot: Dictionary = build_participant.call("transaction_snapshot")
	var ledger: Array[Dictionary] = []
	for definition_value: Variant in build_snapshot.get("reward_history", []):
		if not definition_value is Dictionary:
			return false
		ledger.append((definition_value as Dictionary).duplicate(true))
	var synchronized: Dictionary = authority.call(
		"synchronize_live_state", ledger, build_snapshot
	)
	return (
		bool(synchronized.get("ok", false))
		and router.call("snapshot") == persisted_service
	)


func _restore_current_merchant_session_from_snapshot() -> bool:
	var room := current_room_definition()
	if str(room.get("room_type", "")) != "shop":
		return true
	if (
		_merchant_player == null
		or not is_instance_valid(_merchant_player)
		or _merchant_reward_runtime == null
		or not is_instance_valid(_merchant_reward_runtime)
	):
		return false
	var merchant_id := str(room.get("merchant_id", ""))
	var node_key := "%s:%s" % [str(room.get("floor_id", "")), str(room.get("node_id", ""))]
	if not _merchant_definitions_by_id.has(merchant_id):
		return false
	var node: Dictionary = _merchant_run_state.call("node_state", node_key)
	if node.is_empty() or str(node.get("merchant_id", "")) != merchant_id:
		return false
	var merchant := (
		_merchant_definitions_by_id[merchant_id] as Dictionary
	).duplicate(true)
	var floor_number := int(room.get("floor_index", -1)) + 1
	var price_service = ShopPriceServiceScript.new()
	var inventory = MerchantInventoryServiceScript.new()
	var inventory_configured: Dictionary = inventory.configure(
		int(_orchestrator.snapshot().get("run_seed", 0)),
		merchant,
		_economy_profile,
		floor_number,
		StringName(str(room.get("node_id", ""))),
		_merchant_reward_definitions,
		_merchant_compatibility_context(),
		Callable(price_service, "reward_price")
	)
	if (
		not bool(inventory_configured.get("ok", false))
		or not bool(inventory.call(
			"restore_snapshot", (node.get("inventory", {}) as Dictionary).duplicate(true)
		))
	):
		return false
	var service_result := _create_merchant_service_router(
		merchant,
		floor_number,
		inventory,
		_orchestrator.snapshot().get("floor_plan", {}),
		(node.get("service", {}) as Dictionary).duplicate(true)
	)
	if not bool(service_result.get("ok", false)):
		return false
	var service_authority: Object = service_result["router"]
	if not bool(service_authority.call(
		"restore_snapshot", (node.get("service", {}) as Dictionary).duplicate(true)
	)):
		return false
	if service_authority.call("visibility_snapshot") != node.get("visibility", {}):
		return false
	var runtime = MerchantRuntimeScript.new()
	if not runtime.configure(
		_economy_state,
		inventory,
		MerchantRewardRuntimeScript.new(_merchant_reward_runtime, _merchant_player),
		_merchant_player,
		service_authority,
		Callable(self, "_commit_merchant_state_payload").bind(node_key, merchant_id)
	):
		return false
	if not bool(runtime.call(
		"restore_snapshot", (node.get("runtime", {}) as Dictionary).duplicate(true)
	)):
		return false
	_merchant_sessions[node_key] = {
		"merchant": merchant,
		"inventory": inventory,
		"runtime": runtime,
		"service": service_authority,
		"price": price_service,
	}
	var matches: bool = merchant_view_state().get("inventory") == node.get("inventory")
	return matches


func _create_merchant_service_router(
	merchant: Dictionary,
	floor_number: int,
	inventory: Object,
	floor_plan_value: Variant,
	restore_value: Dictionary = {}
) -> Dictionary:
	var services := merchant.get("services", []) as Array
	var authorities: Dictionary = {}
	if services.has("heal"):
		var heal = MerchantServiceAuthorityScript.new()
		var heal_configured: Dictionary = heal.configure(
			merchant,
			_economy_profile,
			floor_number,
			_merchant_player,
			_merchant_reward_runtime
		)
		if not bool(heal_configured.get("ok", false)):
			return _merchant_service_configuration_failure("heal", heal_configured)
		authorities["heal"] = heal
	if services.has("weapon_upgrade"):
		var weapon_upgrade = MerchantWeaponUpgradeAuthorityScript.new()
		var weapon_configured: Dictionary = weapon_upgrade.configure(
			merchant, _economy_profile, floor_number, _merchant_player
		)
		if not bool(weapon_configured.get("ok", false)):
			return _merchant_service_configuration_failure(
				"weapon_upgrade", weapon_configured
			)
		authorities["weapon_upgrade"] = weapon_upgrade
	if services.has("health_trade"):
		var health_trade = MerchantHealthTradeAuthorityScript.new()
		var health_configured: Dictionary = health_trade.configure(
			merchant, _merchant_player, _merchant_reward_runtime, inventory
		)
		if not bool(health_configured.get("ok", false)):
			return _merchant_service_configuration_failure(
				"health_trade", health_configured
			)
		authorities["health_trade"] = health_trade
	if services.has("route_reveal"):
		if not floor_plan_value is Dictionary:
			return _merchant_service_configuration_failure(
				"route_reveal", {"code": &"FLOOR_PLAN_INVALID"}
			)
		var visibility = FloorPlanVisibilityAuthorityScript.new()
		var visibility_configured: Dictionary = visibility.configure(
			(floor_plan_value as Dictionary).duplicate(true)
		)
		if not bool(visibility_configured.get("ok", false)):
			return _merchant_service_configuration_failure(
				"route_reveal", visibility_configured
			)
		authorities["visibility"] = visibility
	if services.has("cleanse_curse") or services.has("sell_reward"):
		var baseline := _merchant_run_start_player_baseline.duplicate(true)
		var saved_authorities := (
			(restore_value.get("authorities", {}) as Dictionary)
			if restore_value.get("authorities", {}) is Dictionary
			else {}
		)
		var saved_mutation := (
			(saved_authorities.get("reward_mutation", {}) as Dictionary)
			if saved_authorities.get("reward_mutation", {}) is Dictionary
			else {}
		)
		if saved_mutation.get("run_start_player_baseline", {}) is Dictionary:
			var saved_baseline := saved_mutation.get(
				"run_start_player_baseline", {}
			) as Dictionary
			if not saved_baseline.is_empty():
				var run_baseline: Dictionary = _orchestrator.snapshot().get("resources", {}).get("player_reward_run_start_baseline", {})
				if not run_baseline.is_empty() and run_baseline != saved_baseline:
					return _merchant_service_configuration_failure("reward_mutation", {"code": &"BASELINE_MISMATCH"})
				baseline = saved_baseline.duplicate(true)
				_merchant_run_start_player_baseline = baseline.duplicate(true)
		if baseline.is_empty():
			return _merchant_service_configuration_failure(
				"reward_mutation", {"code": &"BASELINE_INVALID"}
			)
		var build_participant: Object = _orchestrator.reward_build_participant()
		var build_snapshot: Dictionary = build_participant.call(
			"transaction_snapshot"
		)
		var definition_ledger: Array[Dictionary] = []
		for definition_value: Variant in build_snapshot.get("reward_history", []):
			if not definition_value is Dictionary:
				return _merchant_service_configuration_failure(
					"reward_mutation", {"code": &"LEDGER_INVALID"}
				)
			definition_ledger.append((definition_value as Dictionary).duplicate(true))
		var mutation = RewardBuildMutationAuthorityScript.new()
		var mutation_configured: Dictionary = mutation.configure(
			baseline,
			definition_ledger,
			build_snapshot,
			build_participant,
			_merchant_player,
			_merchant_reward_runtime
		)
		if not bool(mutation_configured.get("ok", false)):
			return _merchant_service_configuration_failure(
				"reward_mutation", mutation_configured
			)
		authorities["reward_mutation"] = mutation
	var router = MerchantServiceRouterScript.new()
	var floor_plan := (
		(floor_plan_value as Dictionary).duplicate(true)
		if floor_plan_value is Dictionary
		else {}
	)
	var configured: Dictionary = router.configure(
		merchant,
		_economy_profile,
		floor_number,
		inventory,
		floor_plan,
		authorities
	)
	if not bool(configured.get("ok", false)):
		return _merchant_service_configuration_failure("router", configured)
	return {"ok": true, "code": &"OK", "router": router}


func _merchant_service_configuration_failure(
	service_id: String,
	cause: Dictionary
) -> Dictionary:
	return {
		"ok": false,
		"code": StringName(str(cause.get("code", &"CONFIGURATION_FAILED"))),
		"context": {
			"service_id": service_id,
			"cause": cause.duplicate(true),
		},
	}


func _commit_merchant_state_payload(
	payload: Dictionary,
	node_key: String,
	merchant_id: String
) -> bool:
	if (
		_merchant_run_state == null
		or _economy_state == null
		or not _merchant_sessions.has(node_key)
		or not payload.get("transaction") is Dictionary
		or not payload.get("economy") is Dictionary
		or not payload.get("inventory") is Dictionary
		or not payload.get("runtime") is Dictionary
		or not payload.get("service") is Dictionary
		or not payload.get("visibility") is Dictionary
	):
		return false
	var before: Dictionary = _merchant_run_state.call("snapshot")
	var existing: Dictionary = _merchant_run_state.call("node_state", node_key)
	if existing.is_empty():
		return false
	var transaction := payload["transaction"] as Dictionary
	var economy_snapshot := payload["economy"] as Dictionary
	var inventory_snapshot := payload["inventory"] as Dictionary
	var runtime_snapshot := payload["runtime"] as Dictionary
	var session := _merchant_sessions[node_key] as Dictionary
	var service_router: Object = session["service"]
	var build_participant: Object = _orchestrator.reward_build_participant()
	var build_before: Dictionary = build_participant.call("transaction_snapshot")
	var reward_definition := _merchant_transaction_reward_definition(transaction)
	if not reward_definition.is_empty():
		var build_applied: Dictionary = build_participant.call(
			"apply_definition", reward_definition.duplicate(true)
		)
		if not bool(build_applied.get("ok", false)):
			return false
	var service_snapshot: Dictionary = service_router.call("snapshot")
	if not reward_definition.is_empty():
		service_snapshot = _service_snapshot_with_build_ledger(
			service_snapshot,
			build_participant.call("transaction_snapshot")
		)
		if service_snapshot.is_empty():
			build_participant.call(
				"restore_transaction_snapshot", build_before.duplicate(true)
			)
			return false
	var visibility_snapshot: Dictionary = (
		service_router.call("visibility_snapshot")
		if service_router.has_method("visibility_snapshot")
		else (payload["visibility"] as Dictionary).duplicate(true)
	)
	var node := existing.duplicate(true)
	node["inventory"] = inventory_snapshot.duplicate(true)
	node["runtime"] = runtime_snapshot.duplicate(true)
	node["service"] = service_snapshot.duplicate(true)
	node["visibility"] = visibility_snapshot.duplicate(true)
	var upserted: Dictionary = _merchant_run_state.call("upsert_node", node)
	if not bool(upserted.get("ok", false)):
		build_participant.call("restore_transaction_snapshot", build_before.duplicate(true))
		return false
	var kind := str(transaction.get("kind", ""))
	var inventory_receipt: Dictionary = (
		(transaction.get("inventory_receipt", {}) as Dictionary).duplicate(true)
		if transaction.get("inventory_receipt", {}) is Dictionary
		else {}
	)
	var offer: Dictionary = (
		(inventory_receipt.get("offer", {}) as Dictionary).duplicate(true)
		if inventory_receipt.get("offer", {}) is Dictionary
		else {}
	)
	var fact := {
		"sequence": _merchant_transaction_count(before) + 1,
		"transaction_id": str(transaction.get("transaction_id", "")),
		"kind": kind,
		"offer_id": str(transaction.get("offer_id", offer.get("offer_id", ""))),
		"reward_id": str(transaction.get("reward_id", offer.get("reward_id", ""))),
		"service_id": str(transaction.get("service_id", "")),
		"cost_kind": str(transaction.get("cost_kind", "gold")),
		"amount": int(transaction.get("amount", transaction.get("price", 0))),
		"economy_revision": int(economy_snapshot.get("revision", -1)),
		"inventory_revision": int(inventory_snapshot.get("revision", -1)),
	}
	var recorded: Dictionary = _merchant_run_state.call(
		"record_transaction", node_key, fact
	)
	if not bool(recorded.get("ok", false)):
		_merchant_run_state.call("restore_snapshot", before)
		build_participant.call("restore_transaction_snapshot", build_before.duplicate(true))
		return false
	var committed = _orchestrator.commit_merchant_transaction(
		economy_snapshot,
		_merchant_run_state.call("snapshot"),
		_revision()
	)
	if not committed.ok:
		_merchant_run_state.call("restore_snapshot", before)
		build_participant.call("restore_transaction_snapshot", build_before.duplicate(true))
		return false
	return true


func _merchant_transaction_reward_definition(transaction: Dictionary) -> Dictionary:
	var inventory_receipt := (
		(transaction.get("inventory_receipt", {}) as Dictionary)
		if transaction.get("inventory_receipt", {}) is Dictionary
		else {}
	)
	if inventory_receipt.is_empty() and str(transaction.get("service_id", "")) == "health_trade":
		var service_receipt := (
			(transaction.get("service_receipt", {}) as Dictionary)
			if transaction.get("service_receipt", {}) is Dictionary
			else {}
		)
		var delegate_receipt := (
			(service_receipt.get("delegate_receipt", {}) as Dictionary)
			if service_receipt.get("delegate_receipt", {}) is Dictionary
			else {}
		)
		inventory_receipt = (
			(delegate_receipt.get("inventory_receipt", {}) as Dictionary)
			if delegate_receipt.get("inventory_receipt", {}) is Dictionary
			else {}
		)
	var offer := (
		(inventory_receipt.get("offer", {}) as Dictionary)
		if inventory_receipt.get("offer", {}) is Dictionary
		else {}
	)
	return (
		(offer.get("definition", {}) as Dictionary).duplicate(true)
		if offer.get("definition", {}) is Dictionary
		else {}
	)


func _service_snapshot_with_build_ledger(
	service_snapshot: Dictionary,
	build_snapshot: Variant
) -> Dictionary:
	if not build_snapshot is Dictionary:
		return {}
	var authorities := (
		(service_snapshot.get("authorities", {}) as Dictionary).duplicate(true)
		if service_snapshot.get("authorities", {}) is Dictionary
		else {}
	)
	if not authorities.has("reward_mutation"):
		return service_snapshot.duplicate(true)
	var mutation := (
		(authorities["reward_mutation"] as Dictionary).duplicate(true)
		if authorities["reward_mutation"] is Dictionary
		else {}
	)
	if mutation.is_empty() or not (build_snapshot as Dictionary).get("reward_history", []) is Array:
		return {}
	mutation["definition_ledger"] = (
		((build_snapshot as Dictionary)["reward_history"] as Array).duplicate(true)
	)
	authorities["reward_mutation"] = mutation
	var candidate := service_snapshot.duplicate(true)
	candidate["authorities"] = authorities
	return candidate


func _merchant_transaction_count(snapshot_value: Dictionary) -> int:
	var count := 0
	for node_value: Variant in snapshot_value.get("nodes", []):
		if node_value is Dictionary:
			count += ((node_value as Dictionary).get("transactions", []) as Array).size()
	return count


func _restore_floor_and_economy(
	floor_snapshot: Dictionary,
	economy_snapshot: Dictionary
) -> bool:
	if floor_snapshot.is_empty() or economy_snapshot.is_empty():
		return false
	var floor_restored: bool = bool(_orchestrator.restore_floor_transaction_snapshot(
		floor_snapshot.duplicate(true)
	))
	var economy_restored := bool(_economy_state.call(
		"restore_snapshot", economy_snapshot.duplicate(true)
	))
	return floor_restored and economy_restored and _sync_player_event_modifiers()


func _merchant_compatibility_context() -> Dictionary:
	return RewardCompatibilityScript.context_for(_orchestrator.snapshot()["config"])


func _event_runtime_candidate(
	orchestrator: RefCounted,
	director: Node,
	economy: RefCounted,
	restore_value: Dictionary
) -> Dictionary:
	if (
		orchestrator == null
		or director == null
		or economy == null
		or _event_definitions.size() != 18
		or _event_content_fingerprint.length() != 64
	):
		return {"ok": false, "context": {"stage": "event_dependencies"}}
	var state: Dictionary = orchestrator.call("snapshot")
	var plan := state.get("floor_plan", {}) as Dictionary
	if plan.is_empty():
		return {"ok": false, "context": {"stage": "event_floor_plan"}}
	var build := state.get("build", {}) as Dictionary
	var participants: Dictionary = {}
	if not restore_value.is_empty():
		var consequence_value := restore_value.get("consequence_runtime", {}) as Dictionary
		participants = (
			consequence_value.get("participant_snapshots", {}) as Dictionary
		).duplicate(true)
		if participants.size() != 6:
			return {"ok": false, "context": {"stage": "event_restore_participants"}}

	var resource = EventResourceAuthorityScript.new()
	var resource_values := {"time_shard": 2, "forge_essence": 1}
	if not participants.is_empty():
		resource_values = (
			(participants.get("resource", {}) as Dictionary).get("resources", {}) as Dictionary
		).duplicate(true)
	if not resource.configure(resource_values):
		return {"ok": false, "context": {"stage": "event_resource"}}

	var health = EventHealthAuthorityScript.new()
	var health_current := 100.0
	var health_maximum := 100.0
	if not participants.is_empty():
		var health_value := participants.get("health", {}) as Dictionary
		health_current = float(health_value.get("current", 0.0))
		health_maximum = float(health_value.get("maximum", 0.0))
	if not health.configure(health_current, health_maximum):
		return {"ok": false, "context": {"stage": "event_health"}}

	var modifier = EventModifierAuthorityScript.new()
	var curse_ids: Array = (build.get("curses", []) as Array).duplicate()
	curse_ids.sort()
	var narrative_flags: Dictionary = {}
	var temporary_modifiers: Array = []
	if not participants.is_empty():
		var modifier_value := participants.get("modifier", {}) as Dictionary
		curse_ids = (modifier_value.get("curse_ids", []) as Array).duplicate()
		narrative_flags = (
			modifier_value.get("narrative_flags", {}) as Dictionary
		).duplicate(true)
		temporary_modifiers = (
			modifier_value.get("temporary_modifiers", []) as Array
		).duplicate(true)
	if not modifier.configure(curse_ids, narrative_flags, temporary_modifiers):
		return {"ok": false, "context": {"stage": "event_modifier"}}

	var route = EventRouteAuthorityScript.new()
	var route_plan := plan.duplicate(true)
	if not participants.is_empty():
		route_plan = (
			(participants.get("route", {}) as Dictionary).get("plan", {}) as Dictionary
		).duplicate(true)
	if route_plan != plan or not route.configure(route_plan):
		return {"ok": false, "context": {"stage": "event_route"}}

	var event_state = DungeonEventRunStateScript.new()
	if not bool(event_state.configure(_event_content_fingerprint).get("ok", false)):
		return {"ok": false, "context": {"stage": "event_state"}}
	var consequence = DungeonEventConsequenceRuntimeScript.new()
	if not consequence.configure(resource, health, economy, modifier, route, event_state):
		return {"ok": false, "context": {"stage": "event_consequence"}}
	var runtime = DungeonEventRuntimeScript.new()
	var publication_secret := _digest_canonical({
		"schema": "event_publication_secret_v1",
		"content_fingerprint": _event_content_fingerprint,
		"run_id": str(state.get("run_id", "")),
		"run_seed": int(state.get("run_seed", 0)),
	})
	if not runtime.configure(
		_event_definitions,
		DungeonEventSelectorScript.new(),
		event_state,
		EventRequirementServiceScript.new(),
		consequence,
		Callable(self, "_event_runtime_context"),
		Callable(self, "_commit_event_runtime_state"),
		Callable(self, "_publish_event_fact"),
		publication_secret
	):
		return {"ok": false, "context": {"stage": "event_runtime"}}
	if not restore_value.is_empty() and not runtime.restore_snapshot(restore_value):
		return {"ok": false, "context": {"stage": "event_runtime_restore"}}
	if not restore_value.is_empty() and not _overlay_event_assignments(
		director, runtime.snapshot()
	):
		return {"ok": false, "context": {"stage": "event_director_overlay"}}
	return {"ok": true, "runtime": runtime, "context": {}}


func _event_runtime_context() -> Dictionary:
	if _event_runtime == null or _orchestrator == null:
		return {}
	var runtime_snapshot: Dictionary = _event_runtime.call("snapshot")
	var consequence := runtime_snapshot.get("consequence_runtime", {}) as Dictionary
	var participants := consequence.get("participant_snapshots", {}) as Dictionary
	if participants.size() != 6:
		return {}
	var resource := participants.get("resource", {}) as Dictionary
	var health := participants.get("health", {}) as Dictionary
	var economy := participants.get("economy", {}) as Dictionary
	var modifier := participants.get("modifier", {}) as Dictionary
	var state: Dictionary = _orchestrator.snapshot()
	var config := state.get("config", {}) as Dictionary
	var resources := (
		resource.get("resources", {}) as Dictionary
	).duplicate(true)
	var health_context := {
		"current": float(health.get("current", 0.0)),
		"maximum": float(health.get("maximum", 0.0)),
	}
	var curse_ids := (modifier.get("curse_ids", []) as Array).duplicate()
	var narrative_flags := (
		modifier.get("narrative_flags", {}) as Dictionary
	).duplicate(true)
	var enabled_time_skills := config.get("enabled_time_skills", []) as Array
	return {
		"global_revision": _revision(),
		"requirements": {
			"resources": resources.duplicate(true),
			"health": health_context.duplicate(true),
			"gold": int(economy.get("balance", 0)),
			"reward_tags": [],
			"curse_ids": curse_ids.duplicate(),
			"narrative_flags": narrative_flags.duplicate(true),
			"floor_index": int(state.get("current_floor_index", -1)),
		},
		"selection": {
			"run_seed": int(state.get("run_seed", 0)),
			"floor_index": int(state.get("current_floor_index", -1)),
			"availability": str(config.get("milestone", "LAUNCH")),
			"health": health_context.duplicate(true),
			"economy": {"gold": int(economy.get("balance", 0))},
			"build": {"curse_ids": curse_ids.duplicate()},
			"resources": resources.duplicate(true),
			"flags": narrative_flags.duplicate(true),
			"meta": {
				"perfect_rewind_available": (
					enabled_time_skills.has("rewind")
					and not bool(narrative_flags.get("perfect_rewind_claimed", false))
				),
				"old_reunion_eligible": bool(
					narrative_flags.get("old_reunion_eligible", false)
				),
			},
		},
	}


func _commit_event_runtime_state(command: Dictionary, expected_revision: int) -> Dictionary:
	if _event_runtime == null or _orchestrator == null:
		return {"ok": false, "code": &"INVALID_PHASE", "new_revision": _revision(), "context": {}}
	var runtime_snapshot: Dictionary = _event_runtime.call("snapshot")
	var publication := command.get("publication_state", {}) as Dictionary
	var event_state := command.get("event_state", {}) as Dictionary
	if runtime_snapshot.is_empty() or publication.is_empty() or event_state.is_empty():
		return {"ok": false, "code": &"INVALID_ARGUMENT", "new_revision": _revision(), "context": {}}
	for field: String in [
		"emitted_fact_ids", "pending_facts", "encounter_success_by_transaction",
		"publication_ledger", "publication_digest",
	]:
		if not publication.has(field):
			return {"ok": false, "code": &"INVALID_ARGUMENT", "new_revision": _revision(), "context": {}}
		runtime_snapshot[field] = (
			publication[field].duplicate(true)
			if publication[field] is Array or publication[field] is Dictionary
			else publication[field]
		)
	var consequence := runtime_snapshot.get("consequence_runtime", {}) as Dictionary
	var participants := consequence.get("participant_snapshots", {}) as Dictionary
	if participants.size() != 6:
		return {"ok": false, "code": &"INVALID_ARGUMENT", "new_revision": _revision(), "context": {}}
	participants["event_state"] = event_state.duplicate(true)
	consequence["participant_snapshots"] = participants
	runtime_snapshot["consequence_runtime"] = consequence
	var modifier := participants.get("modifier", {}) as Dictionary
	var build_participant: Variant = _orchestrator.call("reward_build_participant")
	if build_participant == null or not build_participant.has_method("transaction_snapshot"):
		return {"ok": false, "code": &"INTEGRITY_FAILURE", "new_revision": _revision(), "context": {"stage": "event_build_participant"}}
	var build := (build_participant.call("transaction_snapshot") as Dictionary).duplicate(true)
	var candidate_build = RunBuildStateScript.new()
	if not candidate_build.restore_transaction_snapshot(build):
		return {"ok": false, "code": &"INTEGRITY_FAILURE", "new_revision": _revision(), "context": {"stage": "event_build_candidate"}}
	var physical_transactions: Array = []
	var curse_definitions: Array[Dictionary] = []
	if str(command.get("operation", "")) == "complete_reward" and not _pending_event_reward_definition.is_empty():
		if not bool(candidate_build.apply_definition(_pending_event_reward_definition).get("ok", false)):
			return {"ok": false, "code": &"INVALID_ARGUMENT", "new_revision": _revision(), "context": {"stage": "event_reward_build"}}
	for curse_id: String in modifier.get("curse_ids", []):
		if (build.get("curses", []) as Array).has(curse_id):
			continue
		var curse := _registry.get_content(StringName(curse_id)) as Dictionary
		if curse.is_empty() or not bool(candidate_build.apply_definition(curse).get("ok", false)):
			return {"ok": false, "code": &"INVALID_ARGUMENT", "new_revision": _revision(), "context": {"stage": "event_curse_content"}}
		curse_definitions.append(curse)
	build = candidate_build.transaction_snapshot()
	build["curses"] = (modifier.get("curse_ids", []) as Array).duplicate()
	var route := participants.get("route", {}) as Dictionary
	var candidate := {
		"dungeon_event_runtime": runtime_snapshot.duplicate(true),
		"run_economy": (participants.get("economy", {}) as Dictionary).duplicate(true),
		"floor_plan": (route.get("plan", {}) as Dictionary).duplicate(true),
		"resources": {
			"resource": (participants.get("resource", {}) as Dictionary).duplicate(true),
			"health": (participants.get("health", {}) as Dictionary).duplicate(true),
		},
		"build": build,
	}
	var projection := EventModifierLifetimeScript.active_projection(
		_orchestrator.snapshot()["events"], event_state["selected_event_by_node"],
		modifier["temporary_modifiers"]
	)
	if not bool(projection.get("ok", false)):
		return {"ok": false, "code": &"INVALID_ARGUMENT", "new_revision": _revision(), "context": {"stage": "event_modifier_lifetime"}}
	if _economy_state == null or _economy_state.call("snapshot") != candidate["run_economy"]:
		return {"ok": false, "code": &"INTEGRITY_FAILURE", "new_revision": _revision(), "context": {"stage": "event_economy_drift"}}
	var candidate_director = RunDirectorScript.new()
	if not candidate_director.configure_launch_plan(candidate["floor_plan"], _registry):
		candidate_director.free()
		return {"ok": false, "code": &"INTEGRITY_FAILURE", "new_revision": _revision(), "context": {"stage": "event_director_plan"}}
	if not _overlay_event_assignments(candidate_director, runtime_snapshot):
		candidate_director.free()
		return {"ok": false, "code": &"INTEGRITY_FAILURE", "new_revision": _revision(), "context": {"stage": "event_director_overlay"}}
	if _merchant_player != null:
		for curse: Dictionary in curse_definitions:
			var transaction = PlayerRewardTransactionScript.new()
			transaction.configure(_merchant_player, _merchant_reward_runtime)
			physical_transactions.append(transaction)
			if not transaction.apply(curse):
				var rolled_back := _compensate_event_physical_state(physical_transactions)
				candidate_director.free()
				return {"ok": false, "code": &"COMMIT_FAILED" if rolled_back else &"INTEGRITY_FAILURE", "new_revision": _revision(), "context": {"stage": "event_curse_effect"}}
	var physical_before: Dictionary = {}
	if _merchant_player != null and str(command.get("operation", "")) == "choose_option":
		physical_before = _merchant_player.call("reward_effect_snapshot")
		var physical_after := physical_before.duplicate(true)
		var old_health := _orchestrator.snapshot().get("resources", {}).get("health", {}) as Dictionary
		var target := float(candidate["resources"]["health"]["current"])
		var delta := target - float(old_health.get("current", target))
		physical_after["health"]["current_hp"] = clampf(float(physical_after["health"]["current_hp"]) + delta, 0.0, float(physical_after["health"]["max_hp"]))
		if physical_after["health"].has("dead"):
			physical_after["health"]["dead"] = float(physical_after["health"]["current_hp"]) <= 0.0
		var health_applied := bool(_merchant_player.call("restore_reward_effect_snapshot", physical_after))
		health_applied = _merchant_player.call("reward_effect_snapshot") == physical_after and health_applied
		if not health_applied:
			var rolled_back := _compensate_event_physical_state(physical_transactions, physical_before)
			candidate_director.free()
			return {"ok": false, "code": &"COMMIT_FAILED" if rolled_back else &"INTEGRITY_FAILURE", "new_revision": _revision(), "context": {"stage": "event_physical_health"}}
	var committed = _orchestrator.commit_event_transaction(candidate, expected_revision)
	if not committed.ok:
		var rolled_back := _compensate_event_physical_state(physical_transactions, physical_before)
		var failure_context: Dictionary = committed.context.duplicate(true)
		if not rolled_back:
			failure_context["compensation_failed"] = true
			failure_context["cause_code"] = str(committed.code)
		candidate_director.free()
		return {
			"ok": false,
			"code": committed.code if rolled_back else &"INTEGRITY_FAILURE",
			"new_revision": committed.new_revision,
			"context": failure_context,
		}
	if not _sync_player_event_modifiers():
		candidate_director.free()
		return {"ok": false, "code": &"INTEGRITY_FAILURE", "new_revision": _revision(), "context": {"committed": true, "stage": "event_modifier_projection"}}
	for transaction: Variant in physical_transactions:
		if not transaction.commit():
			candidate_director.free()
			return {"ok": false, "code": &"INTEGRITY_FAILURE", "new_revision": _revision(), "context": {"committed": true, "stage": "event_curse_publication"}}
	var previous_director = _director
	_director = candidate_director
	if previous_director != null and is_instance_valid(previous_director):
		previous_director.free()
	return {
		"ok": true,
		"code": &"OK",
		"new_revision": committed.new_revision,
		"context": committed.context.duplicate(true),
	}


func _compensate_event_physical_state(
	transactions: Array,
	health_preimage: Dictionary = {}
) -> bool:
	var restored := true
	if not health_preimage.is_empty():
		if _merchant_player == null or not is_instance_valid(_merchant_player):
			restored = false
		else:
			restored = bool(_merchant_player.call(
				"restore_reward_effect_snapshot", health_preimage.duplicate(true)
			))
			restored = _merchant_player.call("reward_effect_snapshot") == health_preimage and restored
	# Every compensation is attempted, even after an earlier participant refuses.
	for index: int in range(transactions.size() - 1, -1, -1):
		restored = bool(transactions[index].rollback()) and restored
	return restored


func _overlay_event_assignments(director: Node, runtime_snapshot: Dictionary) -> bool:
	if director == null or runtime_snapshot.is_empty():
		return false
	var consequence := runtime_snapshot.get("consequence_runtime", {}) as Dictionary
	var participants := consequence.get("participant_snapshots", {}) as Dictionary
	var event_state := participants.get("event_state", {}) as Dictionary
	var assignments := event_state.get("selected_event_by_node", {}) as Dictionary
	var route := participants.get("route", {}) as Dictionary
	var floor_id := str((route.get("plan", {}) as Dictionary).get("floor_id", ""))
	for node_key_value: Variant in assignments.keys():
		var assignment := assignments[node_key_value] as Dictionary
		if not floor_id.is_empty() and str(assignment.get("floor_id", "")) != floor_id:
			continue
		if not director.call(
			"overlay_event_assignment",
			StringName(str(assignment.get("node_id", ""))),
			StringName(str(assignment.get("event_id", "")))
		):
			return false
	return true


func _publish_event_fact(fact_id: String, payload: Dictionary) -> bool:
	var transition_id := _finalized_route_transition_id()
	if not transition_id.is_empty():
		if not _event_fact_is_valid(fact_id, payload):
			return false
		var reservation := _route_transactions[transition_id] as Dictionary
		var facts := reservation.get("event_facts", []) as Array
		for value: Variant in facts:
			if (
				value is Dictionary
				and str((value as Dictionary).get("fact_id", "")) == fact_id
			):
				return (value as Dictionary).get("payload", {}) == payload
		facts.append({
			"fact_id": fact_id,
			"payload": payload.duplicate(true),
		})
		reservation["event_facts"] = facts
		_route_transactions[transition_id] = reservation
		return true
	return _publish_event_fact_immediate(fact_id, payload)


func _publish_event_fact_immediate(fact_id: String, payload: Dictionary) -> bool:
	if _orchestrator == null:
		return false
	var run_id := str(_orchestrator.snapshot().get("run_id", ""))
	if run_id.is_empty() or not _event_fact_is_valid(fact_id, payload):
		return false
	var event_id := StringName(str(payload.get("event_id", "")))
	var node_key := str(payload.get("node_key", ""))
	var kind := str(payload.get("kind", ""))
	var publication_id := "%s:%s" % [run_id, fact_id]
	if _published_event_fact_ids.has(publication_id):
		return true
	_published_event_fact_ids[publication_id] = true
	match kind:
		"event_opened":
			EventBus.event_opened.emit(run_id, event_id, node_key, _revision())
		"event_committed":
			EventBus.event_committed.emit(
				run_id, event_id, node_key,
				StringName(str(payload.get("phase", ""))),
				StringName(str(payload.get("pending_kind", ""))),
				StringName(str(payload.get("result_key", ""))),
				_revision()
			)
		"event_reward_completed":
			EventBus.event_reward_completed.emit(
				run_id, event_id, node_key,
				StringName(str(payload.get("result_key", ""))), _revision()
			)
		"event_encounter_completed":
			EventBus.event_encounter_completed.emit(
				run_id, event_id, node_key,
				StringName(str(payload.get("result_key", ""))),
				bool(payload.get("success", false)), _revision()
			)
		"event_dismissed":
			EventBus.event_dismissed.emit(
				run_id, event_id, node_key,
				StringName(str(payload.get("result_key", ""))), _revision()
			)
	return true


func _event_fact_is_valid(fact_id: String, payload: Dictionary) -> bool:
	return (
		not fact_id.is_empty()
		and not str(payload.get("event_id", "")).is_empty()
		and not str(payload.get("node_key", "")).is_empty()
		and str(payload.get("kind", "")) in [
			"event_opened",
			"event_committed",
			"event_reward_completed",
			"event_encounter_completed",
			"event_dismissed",
		]
	)


func _finalized_route_transition_id() -> String:
	for transition_id_value: Variant in _route_transactions.keys():
		var transition_id := str(transition_id_value)
		var reservation := _route_transactions[transition_id] as Dictionary
		if str(reservation.get("stage", "")) == "finalized":
			return transition_id
	return ""


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
	var launch_catalog := LaunchEncounterCatalogScript.new()
	var encounter_report: Dictionary = launch_catalog.configure(_registry)
	if not encounter_report.ok:
		return CommandResultScript.failure(&"CONTENT_NOT_AVAILABLE", _revision(), {"category": "launch_encounter", "detail": encounter_report.context})
	var canonical_floors: Array[Dictionary] = []
	var canonical_templates: Array[Dictionary] = []
	var canonical_merchants: Array[Dictionary] = []
	var canonical_rewards: Array[Dictionary] = []
	var canonical_events: Array[Dictionary] = []
	var economy_profile: Dictionary = {}
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
	for merchant_value: Variant in _registry.call(
		"get_by_category", &"merchant_definition", milestone
	):
		if not merchant_value is Dictionary:
			return CommandResultScript.failure(
				&"CONTENT_NOT_AVAILABLE", _revision(), {"category": "merchant_definition"}
			)
		var merchant_source := _definition_fields(
			merchant_value as Dictionary, MerchantDefinitionScript.ROOT_FIELDS
		)
		var merchant_result: Dictionary = MerchantDefinitionScript.new().configure(merchant_source)
		if not bool(merchant_result.get("ok", false)):
			return CommandResultScript.failure(
				&"CONTENT_NOT_AVAILABLE", _revision(), {"category": "merchant_definition"}
			)
		canonical_merchants.append(
			(merchant_result.get("definition", {}) as Dictionary).duplicate(true)
		)
	var economy_values: Array = _registry.call(
		"get_by_category", &"economy_profile", milestone
	)
	if economy_values.size() == 1 and economy_values[0] is Dictionary:
		var economy_source := _definition_fields(
			economy_values[0] as Dictionary, EconomyProfileScript.ROOT_FIELDS
		)
		var economy_result: Dictionary = EconomyProfileScript.new().configure(economy_source)
		if bool(economy_result.get("ok", false)):
			economy_profile = (
				economy_result.get("definition", {}) as Dictionary
			).duplicate(true)
	for category: StringName in [&"item", &"blessing", &"curse"]:
		for definition_value: Variant in _registry.call("get_by_category", category, milestone):
			if definition_value is Dictionary:
				canonical_rewards.append((definition_value as Dictionary).duplicate(true))
	for event_value: Variant in _registry.call(
		"get_by_category", &"dungeon_event", milestone
	):
		if not event_value is Dictionary:
			return CommandResultScript.failure(
				&"CONTENT_NOT_AVAILABLE", _revision(), {"category": "dungeon_event"}
			)
		var event_source := _definition_fields(
			event_value as Dictionary, DungeonEventDefinitionScript.ROOT_FIELDS
		)
		var event_result: Dictionary = DungeonEventDefinitionScript.new().configure(
			event_source
		)
		if not bool(event_result.get("ok", false)):
			return CommandResultScript.failure(
				&"CONTENT_NOT_AVAILABLE", _revision(), {"category": "dungeon_event"}
			)
		canonical_events.append(
			(event_result.get("definition", {}) as Dictionary).duplicate(true)
		)
	if (
		canonical_floors.size() != 5
		or canonical_templates.size() != 30
		or canonical_merchants.size() != 5
		or canonical_events.size() != 18
		or economy_profile.is_empty()
		or canonical_rewards.is_empty()
	):
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE",
			_revision(),
			{
				"floor_count": canonical_floors.size(),
				"room_template_count": canonical_templates.size(),
				"merchant_count": canonical_merchants.size(),
				"event_count": canonical_events.size(),
				"economy_profile_count": 0 if economy_profile.is_empty() else 1,
				"merchant_reward_count": canonical_rewards.size(),
			}
		)
	_floor_definitions = canonical_floors.duplicate(true)
	_launch_encounter_catalog = launch_catalog
	_room_templates = canonical_templates.duplicate(true)
	_economy_profile = economy_profile.duplicate(true)
	_merchant_definitions = canonical_merchants.duplicate(true)
	_merchant_definitions_by_id.clear()
	for merchant: Dictionary in _merchant_definitions:
		_merchant_definitions_by_id[str(merchant["id"])] = merchant.duplicate(true)
	_merchant_reward_definitions = canonical_rewards.duplicate(true)
	_event_definitions = canonical_events.duplicate(true)
	_event_content_fingerprint = _digest_canonical({"events": _event_definitions})
	_launch_content_fingerprint = _digest_canonical({
		"economy_profile": _economy_profile,
		"merchants": _merchant_definitions,
		"rewards": _merchant_reward_definitions,
	})
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


func _digest_canonical(value: Variant) -> String:
	return var_to_bytes(_canonicalize_digest_value(value)).hex_encode().sha256_text()


func _canonicalize_digest_value(value: Variant) -> Variant:
	if value is Dictionary:
		var source := value as Dictionary
		var keys: Array[String] = []
		var source_keys: Dictionary = {}
		for key_value: Variant in source.keys():
			var key := str(key_value)
			keys.append(key)
			source_keys[key] = key_value
		keys.sort()
		var normalized: Dictionary = {}
		for key: String in keys:
			normalized[key] = _canonicalize_digest_value(source[source_keys[key]])
		return normalized
	if value is Array:
		var normalized_array: Array = []
		for entry: Variant in value as Array:
			normalized_array.append(_canonicalize_digest_value(entry))
		return normalized_array
	if typeof(value) == TYPE_STRING_NAME:
		return str(value)
	return value


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
