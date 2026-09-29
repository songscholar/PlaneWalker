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
var resources: Dictionary = {}
var stats: Dictionary = {"kills": 0}
var events: Array = []
var build_state: RefCounted
var open_offer: Dictionary = {}
var consumed_offer_ids: Dictionary = {}
var result: Dictionary = {}
var config: Dictionary = {}


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
	resources = {}
	stats = {"kills": 0}
	events = []
	if build_state == null:
		build_state = RunBuildStateScript.new()
	build_state.reset()
	open_offer = {}
	consumed_offer_ids = {}
	result = {}


func advance_revision() -> int:
	revision += 1
	return revision


func is_terminal() -> bool:
	return RunPhaseScript.is_terminal(phase)


func has_consumed_offer(offer_id: String) -> bool:
	return consumed_offer_ids.has(offer_id)


func mark_offer_consumed(offer_id: String) -> bool:
	if offer_id.is_empty() or has_consumed_offer(offer_id):
		return false
	consumed_offer_ids[offer_id] = true
	return true


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
