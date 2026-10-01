class_name RunState
extends RefCounted

const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunConfigScript := preload("res://scripts/application/run_config.gd")
const RunBuildStateScript := preload("res://scripts/progression/run_build_state.gd")

var run_id: String = ""
var revision: int = 0
var phase: int = RunPhaseScript.Value.BOOT
var suspended: bool = false
var run_seed: int = 0
var current_floor: int = 1
var current_room: int = 0
var room_total: int = 5
var run_time_ms: int = 0
var _run_time_fraction_ms: float = 0.0
var resources: Dictionary = {}
var stats: Dictionary = {"kills": 0}
var events: Array = []
var build_state: RefCounted
var open_offer: Dictionary = {}
var consumed_offer_ids: Dictionary = {}
var result: Dictionary = {}
var config: Dictionary = {}

const SELECTION_TRANSACTION_FIELDS: Array[String] = [
	"schema_version",
	"revision",
	"phase",
	"suspended",
	"current_room",
	"open_offer",
	"consumed_offer_ids",
	"build",
]


func _init() -> void:
	build_state = RunBuildStateScript.new()


func reset_domain(p_config: Dictionary, p_run_id: String) -> void:
	config = RunConfigScript.normalized(p_config)
	run_id = p_run_id
	suspended = false
	run_seed = int(config["seed"])
	current_floor = 1
	current_room = 0
	room_total = 5
	run_time_ms = 0
	_run_time_fraction_ms = 0.0
	resources = {}
	stats = {"kills": 0}
	events = []
	if build_state == null:
		build_state = RunBuildStateScript.new()
	build_state.reset(str(config["milestone"]))
	open_offer = {}
	consumed_offer_ids = {}
	result = {}


func advance_revision() -> int:
	revision += 1
	return revision


func advance_time(delta_seconds: float) -> int:
	var total_ms := _run_time_fraction_ms + maxf(0.0, delta_seconds) * 1000.0
	var whole_ms := int(floor(total_ms + 0.000001))
	_run_time_fraction_ms = total_ms - float(whole_ms)
	run_time_ms += whole_ms
	return whole_ms


func is_terminal() -> bool:
	return RunPhaseScript.is_terminal(phase)


func has_consumed_offer(offer_id: String) -> bool:
	return consumed_offer_ids.has(offer_id)


func mark_offer_consumed(offer_id: String) -> bool:
	if offer_id.is_empty() or has_consumed_offer(offer_id):
		return false
	consumed_offer_ids[offer_id] = true
	return true


func selection_transaction_snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"revision": revision,
		"phase": phase,
		"suspended": suspended,
		"current_room": current_room,
		"open_offer": open_offer.duplicate(true),
		"consumed_offer_ids": consumed_offer_ids.duplicate(true),
		"build": build_state.transaction_snapshot(),
	}


func can_restore_selection_transaction_snapshot(value: Dictionary) -> bool:
	if value.size() != SELECTION_TRANSACTION_FIELDS.size():
		return false
	for field: String in SELECTION_TRANSACTION_FIELDS:
		if not value.has(field):
			return false
	return (
		typeof(value["schema_version"]) == TYPE_INT
		and int(value["schema_version"]) == 1
		and typeof(value["revision"]) == TYPE_INT
		and int(value["revision"]) >= 0
		and typeof(value["phase"]) == TYPE_INT
		and typeof(value["suspended"]) == TYPE_BOOL
		and typeof(value["current_room"]) == TYPE_INT
		and int(value["current_room"]) > 0
		and value["open_offer"] is Dictionary
		and value["consumed_offer_ids"] is Dictionary
		and value["build"] is Dictionary
		and build_state.can_restore_transaction_snapshot(value["build"] as Dictionary)
	)


func restore_selection_transaction_snapshot(value: Dictionary) -> bool:
	if not can_restore_selection_transaction_snapshot(value):
		return false
	if not build_state.restore_transaction_snapshot(value["build"] as Dictionary):
		return false
	revision = int(value["revision"])
	phase = int(value["phase"])
	suspended = bool(value["suspended"])
	current_room = int(value["current_room"])
	open_offer = (value["open_offer"] as Dictionary).duplicate(true)
	consumed_offer_ids = (value["consumed_offer_ids"] as Dictionary).duplicate(true)
	return selection_transaction_snapshot() == value


func snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"run_id": run_id,
		"revision": revision,
		"phase": phase,
		"suspended": suspended,
		"run_seed": run_seed,
		"current_floor": current_floor,
		"current_room": current_room,
		"room_total": room_total,
		"run_time_ms": run_time_ms,
		"resources": resources.duplicate(true),
		"stats": stats.duplicate(true),
		"events": events.duplicate(true),
		"build": build_state.to_dictionary().duplicate(true),
		"open_offer": open_offer.duplicate(true),
		"consumed_offer_ids": consumed_offer_ids.keys().duplicate(),
		"result": result.duplicate(true),
		"config": config.duplicate(true),
	}
