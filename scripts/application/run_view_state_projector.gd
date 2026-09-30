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
	var player_view := player_snapshot.duplicate(true)
	var weapon_projection := _weapon_view(player_view.get("weapon"))
	if not bool(weapon_projection.get("ok", false)):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			maxi(0, _view_revision),
			{"field": str(weapon_projection.get("field", "player.weapon"))}
		)
	player_view.erase("weapon")
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
		"player": player_view,
		"weapon_state": (weapon_projection["weapon_state"] as Dictionary).duplicate(true),
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
			0 if status_id == "ready" else 1,
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
