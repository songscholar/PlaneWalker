class_name RunRuntimeFacade
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const EncounterCatalogScript := preload("res://scripts/dungeon/encounter_catalog.gd")
const M1RoomPlanScript := preload("res://scripts/dungeon/m1_room_plan.gd")
const RunDirectorScript := preload("res://scripts/dungeon/run_director.gd")
const RoomRuntimeScript := preload("res://scripts/dungeon/room_runtime.gd")
const DraftServiceScript := preload("res://scripts/rewards/draft_service.gd")

const GAME_VERSION := "0.4.0-dev"
const DEFAULT_CONTENT_PATH := "res://data/content_packs/base/pack.json"
const DEFAULT_ENCOUNTER_PATH := "res://data/encounters/m1_encounters.json"

var _registry: RefCounted
var _encounter_catalog: RefCounted
var _draft: RefCounted
var _orchestrator: RefCounted
var _room_definitions: Array[Dictionary] = []
var _booted: bool = false


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

	var director = RunDirectorScript.new()
	director.configure_from_definitions(M1RoomPlanScript.definitions(_encounter_catalog, 0))
	for room_number: int in range(1, director.room_count() + 1):
		_room_definitions.append(director.room_definition_for(room_number))
	director.free()
	var hub_result = _orchestrator.enter_hub()
	_booted = hub_result.ok
	return hub_result


func start_run(config: Dictionary, run_id: String):
	var readiness = _require_booted("start_run")
	if not readiness.ok:
		return readiness
	var started = _orchestrator.start_run(config, run_id)
	if not started.ok:
		return started
	_room_definitions = M1RoomPlanScript.definitions(
		_encounter_catalog,
		int(_orchestrator.snapshot().get("run_seed", 0))
	)
	_draft.reset()
	return _orchestrator.preparation_completed()


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
	return _orchestrator.room_entered(str(room.get("type", "")) == "boss")


func complete_current_room():
	var readiness = _require_booted("complete_current_room")
	if not readiness.ok:
		return readiness
	if _orchestrator.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", _revision())

	var room := current_room_definition()
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
	var committed = _orchestrator.selection_resolved(definition)
	if not committed.ok:
		return committed
	_draft.close_offer(offer_id)
	return CommandResultScript.success(
		committed.new_revision,
		{
			"definition": definition,
			"offer_id": offer_id,
		}
	)


func complete_transition():
	var readiness = _require_booted("complete_transition")
	if not readiness.ok:
		return readiness
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


func snapshot() -> Dictionary:
	if _orchestrator == null:
		return {}
	return _orchestrator.snapshot()


func current_room_definition() -> Dictionary:
	if not _booted or _orchestrator == null or _room_definitions.is_empty():
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
	return _encounter_catalog.encounter_definition(
		str(room.get("encounter_id", "")),
		int(_orchestrator.snapshot().get("run_seed", 0)),
		int(room.get("room_number", 0))
	)


func room_plan() -> Array[Dictionary]:
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
