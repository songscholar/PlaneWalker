class_name RunViewStateProjector
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunViewStateScript := preload("res://scripts/ui/contracts/run_view_state.gd")

var _last_run_id: String = ""
var _view_revision: int = -1
var _latest_view_state: Dictionary = {}


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
	var open_offer: Dictionary = authoritative.get("open_offer", {})
	var result: Dictionary = authoritative.get("result", {})
	var suspended := bool(authoritative.get("suspended", false))
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
			"title_key": "ROOM_M1_%02d" % room_index,
		},
		"player": player_snapshot.duplicate(true),
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
		_:
			return ""
