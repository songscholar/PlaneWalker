extends Node

const CharacterRuntimeFactoryScript := preload(
	"res://scripts/player/characters/character_runtime_factory.gd"
)
const CharacterRuntimeProfileScript := preload(
	"res://scripts/player/characters/character_runtime_profile.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PROFILE_CATALOG_PATH := (
	"res://data/content_packs/base/content/character_runtime_profiles.json"
)
const TALENT_CATALOG_PATH := "res://data/content_packs/base/content/talents.json"

var _suite
var _definition: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_definition = _load_definition("time_lord_launch_v1")
	_test_factory_pages_rate_cap_and_infusion()
	_test_primer_boundaries_same_ability_and_rollback()
	_test_all_six_base_and_enhanced_pairs()
	_test_skill_boundaries_talents_snapshot_rewind_and_reset()
	_suite.finish(get_tree())


func _test_factory_pages_rate_cap_and_infusion() -> void:
	var fixture := _fixture(PackedStringArray(["efficient_inscription"]))
	var runtime: RefCounted = fixture.runtime
	_suite.assert_equal(str(runtime.get_script().resource_path), "res://scripts/player/characters/time_lord_character_runtime.gd", "factory creates the real Time Lord strategy")
	_bind_room(runtime)
	_suite.assert_true(_event_exists(runtime.on_weapon_mastery_confirmed(_mastery(1, 0)), &"character_resource_changed"), "first mastery grants a Codex Page")
	runtime.advance_frame({"runtime_frame": 59})
	_suite.assert_true(not _event_exists(runtime.on_weapon_mastery_confirmed(_mastery(2, 59)), &"character_resource_changed"), "frame 59 is rate capped")
	runtime.advance_frame({"runtime_frame": 60})
	_suite.assert_true(_event_exists(runtime.on_weapon_mastery_confirmed(_mastery(3, 60)), &"character_resource_changed"), "frame 60 grants the second Page")
	_suite.assert_equal(int(runtime.snapshot().resource_value), 2, "Page grants remain bounded")
	var before_duplicate: Dictionary = runtime.snapshot()
	_suite.assert_equal(runtime.on_weapon_mastery_confirmed(_mastery(3, 60)), [], "duplicate mastery token is ignored")
	_suite.assert_equal(runtime.snapshot(), before_duplicate, "duplicate mastery has zero mutation")

	var tap: Dictionary = runtime.plan_character_skill(_skill_intent(12), _skill_context(60, 5.0))
	_suite.assert_true(tap.ok, "Efficient Inscription accepts exact five energy")
	_suite.assert_equal(int(tap.plan.energy_cost), 5, "Efficient Inscription freezes five energy")
	var armed: Dictionary = runtime.commit_character_skill(tap.plan, 11)
	_suite.assert_true(armed.ok, "Infusion commits")
	_suite.assert_equal(int(runtime.snapshot().infusion_until_frame), 360, "Infusion arms for 300 frames")
	_suite.assert_equal(int(runtime.snapshot().skill_cooldown_until_frame), 180, "Infusion starts the exact 120-frame cooldown")
	runtime.advance_frame({"runtime_frame": 120})
	var echo_events: Array = runtime.on_weapon_mastery_confirmed(_mastery(4, 120, 24.0, Vector2(8, 9)))
	var echo: Dictionary = _event_context(echo_events, &"codex_infusion_echo_requested")
	_suite.assert_close(float(echo.get("damage", 0.0)), 48.0, "Infusion echo is exactly 2.0 attack")
	_suite.assert_equal(int(runtime.snapshot().infusion_until_frame), -1, "eligible mastery consumes Infusion exactly once")
	_suite.assert_equal(int(runtime.snapshot().resource_value), 3, "third eligible grant reaches the exact Page cap")
	runtime.advance_frame({"runtime_frame": 180})
	_suite.assert_true(not _event_exists(runtime.on_weapon_mastery_confirmed(_mastery(5, 180)), &"character_resource_changed"), "a fourth Page is rejected at the cap")
	_suite.assert_equal(int(runtime.snapshot().resource_value), 3, "Page resource never exceeds three")
	fixture.owner.free()


func _test_primer_boundaries_same_ability_and_rollback() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture.runtime
	_bind_room(runtime)
	runtime.on_weapon_mastery_confirmed(_mastery(1, 0))
	var first: Array = _commit_time(runtime, &"stop", 0, 1, 1, [&"stop", &"rewind"])
	_suite.assert_true(_event_exists(first, &"codex_primer_opened"), "first equipped ability opens Primer")
	_suite.assert_equal(int(runtime.snapshot().resource_value), 1, "opening Primer does not consume a Page")
	var before_same: Dictionary = runtime.snapshot()
	_suite.assert_equal(_commit_time(runtime, &"stop", 0, 2, 2, [&"stop", &"rewind"]), [], "same ability neither resolves nor refreshes Primer")
	_suite.assert_equal(int(runtime.snapshot().primer_expires_frame), int(before_same.primer_expires_frame), "same ability preserves original expiry")

	runtime.advance_frame({"runtime_frame": 299})
	var before_pair: Dictionary = runtime.snapshot()
	var pair_events: Array = _commit_time(runtime, &"rewind", 299, 3, 3, [&"stop", &"rewind"], {"pre_return_position": Vector2(20, 30)})
	_suite.assert_true(_event_exists(pair_events, &"time_pair_conversion_requested"), "frame 299 resolves inside the base window")
	_suite.assert_equal(int(runtime.snapshot().resource_value), 0, "pair completion consumes exactly one Page")
	_suite.assert_true(runtime.restore_snapshot(before_pair), "transaction rollback can restore Page and Primer")
	_suite.assert_equal(runtime.snapshot(), before_pair, "rollback reinstalls exact prepared state")

	runtime.advance_frame({"runtime_frame": 300})
	var boundary_events: Array = _commit_time(runtime, &"rewind", 300, 4, 4, [&"stop", &"rewind"], {"pre_return_position": Vector2(20, 30)})
	_suite.assert_true(not _event_exists(boundary_events, &"time_pair_conversion_requested"), "frame 300 cannot complete expired Primer")
	_suite.assert_equal(str(runtime.snapshot().primer_ability_id), "rewind", "frame 300 may open a fresh Primer without resolving the expired one")
	fixture.owner.free()


func _test_all_six_base_and_enhanced_pairs() -> void:
	var pairs: Array[Array] = [
		[&"stop", &"rewind", &"stasis_zone", "radius", 96.0, 128.0],
		[&"stop", &"rift", &"rift_projectile_slow", "hostile_projectile_speed_scalar", 0.50, 0.35],
		[&"stop", &"accelerate", &"recovery_acceleration", "recovery_multiplier", 0.80, 0.65],
		[&"rewind", &"rift", &"rift_rewind_pulse", "damage_multiplier", 1.25, 1.75],
		[&"rewind", &"accelerate", &"next_mastery_echo", "echo_multiplier", 0.75, 1.10],
		[&"rift", &"accelerate", &"rift_tick_acceleration", "tick_interval_multiplier", 0.75, 0.50],
	]
	for row: Array in pairs:
		for enhanced: bool in [false, true]:
			var fixture := _fixture()
			var runtime: RefCounted = fixture.runtime
			_bind_room(runtime)
			runtime.on_weapon_mastery_confirmed(_mastery(1, 0))
			if enhanced:
				runtime.advance_frame({"runtime_frame": 60})
				runtime.on_weapon_mastery_confirmed(_mastery(2, 60))
				runtime.advance_frame({"runtime_frame": 120})
				runtime.on_weapon_mastery_confirmed(_mastery(3, 120))
				var dominion: Dictionary = runtime.plan_character_skill(_skill_intent(60), _skill_context(120, 60.0, row.slice(0, 2)))
				_suite.assert_true(dominion.ok, "Dominion plans for every equipped pair")
				_suite.assert_true(runtime.commit_character_skill(dominion.plan, 10).ok, "Dominion arms for every equipped pair")
			var frame := 120 if enhanced else 0
			var first_extra := _time_extra(row[0])
			var second_extra := _time_extra(row[1])
			_commit_time(runtime, row[0], frame, 20, 1, row.slice(0, 2), first_extra)
			var events: Array = _commit_time(runtime, row[1], frame, 21, 2, row.slice(0, 2), second_extra)
			var requested: Dictionary = _event_context(events, &"time_pair_conversion_requested")
			_suite.assert_equal(StringName(str(requested.get("conversion_id", ""))), row[2], "pair conversion identity is exact")
			_suite.assert_equal(bool(requested.get("enhanced", false)), enhanced, "Dominion enhancement flag is exact")
			var parameters := requested.get("parameters", {}) as Dictionary
			_suite.assert_close(float(parameters.get(row[3], 0.0)), float(row[5] if enhanced else row[4]), "pair base/enhanced value is exact")
			_suite.assert_equal(int(runtime.snapshot().resource_value), 0 if enhanced else 0, "pair spends one Page after optional Dominion cost")
			if enhanced:
				_suite.assert_equal(int(runtime.snapshot().dominion_until_frame), -1, "enhanced pair consumes Dominion exactly once")
			fixture.owner.free()


func _test_skill_boundaries_talents_snapshot_rewind_and_reset() -> void:
	var fixture := _fixture(PackedStringArray(["codex_margin", "dominion_cadence"]))
	var runtime: RefCounted = fixture.runtime
	_bind_room(runtime)
	runtime.on_weapon_mastery_confirmed(_mastery(1, 0))
	runtime.advance_frame({"runtime_frame": 60})
	runtime.on_weapon_mastery_confirmed(_mastery(2, 60))
	var tap_59: Dictionary = runtime.plan_character_skill(_skill_intent(59), _skill_context(60, 10.0))
	_suite.assert_equal(StringName(tap_59.plan.mode), &"infusion", "hold frame 59 remains Infusion")
	var hold_60: Dictionary = runtime.plan_character_skill(_skill_intent(60), _skill_context(60, 45.0, [&"stop", &"rewind"]))
	_suite.assert_true(hold_60.ok, "Dominion Cadence accepts exact 45 energy at frame 60")
	_suite.assert_equal(int(hold_60.plan.cooldown_frames), 360, "Dominion Cadence freezes 360-frame cooldown")
	var pre_dominion: Dictionary = runtime.snapshot()
	_suite.assert_true(runtime.commit_character_skill(hold_60.plan, 50).ok, "Dominion commits")
	_suite.assert_equal(int(runtime.snapshot().resource_value), 0, "Dominion consumes exactly two Pages")
	var irreversible: Dictionary = runtime.snapshot()
	_suite.assert_true(runtime.restore_gameplay_rewind_snapshot(pre_dominion), "Gameplay Rewind validates an earlier Time Lord snapshot")
	_suite.assert_equal(runtime.snapshot(), irreversible, "Gameplay Rewind does not refund Dominion costs")
	_suite.assert_equal(int(runtime.presentation_snapshot().pair_window_frames), 420, "Codex Margin exposes 420-frame window")
	_suite.assert_equal(int(runtime.presentation_snapshot().dominion_energy_cost), 45, "Dominion Cadence exposes exact cost")
	_suite.assert_true(runtime.can_restore_snapshot(irreversible), "Replay snapshot validates")
	runtime.reset_runtime_state(&"loadout_replacement")
	var reset: Dictionary = runtime.snapshot()
	_suite.assert_equal(int(reset.resource_value), 0, "reset clears Pages")
	_suite.assert_equal(str(reset.primer_ability_id), "", "reset clears Primer")
	_suite.assert_equal(int(reset.infusion_until_frame), -1, "reset clears Infusion")
	_suite.assert_equal(int(reset.dominion_until_frame), -1, "reset clears Dominion")
	fixture.owner.free()


func _fixture(talents: PackedStringArray = PackedStringArray()) -> Dictionary:
	var owner := Node.new()
	var profile: Variant = CharacterRuntimeProfileScript.from_definition(_definition.duplicate(true))
	var runtime: Variant = CharacterRuntimeFactoryScript.create(&"time_lord")
	_suite.assert_true(profile != null, "Time Lord profile parses")
	_suite.assert_true(runtime.configure(owner, profile, talents), "Time Lord runtime configures")
	_suite.assert_true(
		runtime.configure_talent_definitions(_talent_definitions(talents)),
		"Time Lord installs authoritative Talent definitions"
	)
	return {"owner": owner, "runtime": runtime}


func _bind_room(runtime: RefCounted) -> void:
	runtime.advance_frame({"runtime_frame": 0})
	_suite.assert_true(_event_exists(runtime.on_room_started({"run_id": &"run-a", "run_revision": 1, "room_id": &"room-1", "room_revision": 1, "owner_character_generation": 5}), &"time_lord_room_started"), "room binds Time Lord run identity")


func _mastery(token: int, frame: int, attack: float = 24.0, position: Vector2 = Vector2(4, 5)) -> Dictionary:
	return {"weapon_id": &"sword", "mastery_family": &"sword", "generation": 1, "action_token": token, "context": {"run_id": &"run-a", "run_revision": 1, "owner_character_generation": 5, "runtime_frame": frame, "attack": attack, "position": position, "approved_echo": true}}


func _skill_intent(held_frames: int) -> Dictionary:
	return {"id": &"character_skill", "edge": &"released", "held_frames": held_frames}


func _skill_context(frame: int, energy: float, abilities: Array = [&"stop", &"rewind"]) -> Dictionary:
	return {"runtime_frame": frame, "run_id": &"run-a", "run_revision": 1, "owner_character_generation": 5, "alive": true, "time_energy": energy, "equipped_time_abilities": abilities}


func _commit_time(runtime: RefCounted, ability_id: StringName, frame: int, token: int, generation: int, abilities: Array, extra: Dictionary = {}) -> Array:
	var context := {"ability_id": ability_id, "runtime_frame": frame, "token": token, "generation": generation, "run_id": &"run-a", "run_revision": 1, "owner_character_generation": 5, "equipped_time_abilities": abilities}
	for key: Variant in extra.keys():
		context[key] = extra[key]
	var prepared: Dictionary = runtime.before_time_skill(context)
	if not bool(prepared.get("ok", false)):
		return []
	context["character_decision"] = prepared.decision
	return runtime.after_time_skill(context)


func _time_extra(ability_id: StringName) -> Dictionary:
	match ability_id:
		&"stop":
			return {"stop_until_frame": 180}
		&"rewind":
			return {"pre_return_position": Vector2(12, 16), "attack": 24.0}
		&"rift":
			return {"rift_until_frame": 180, "rift_generation": 7, "rift_radius": 160.0, "attack": 24.0}
	return {}


func _event_exists(events: Array, event_id: StringName) -> bool:
	for event: Dictionary in events:
		if StringName(str(event.get("event_id", ""))) == event_id:
			return true
	return false


func _event_context(events: Array, event_id: StringName) -> Dictionary:
	for event: Dictionary in events:
		if StringName(str(event.get("event_id", ""))) == event_id:
			return (event.get("context", {}) as Dictionary).duplicate(true)
	return {}


func _load_definition(profile_id: String) -> Dictionary:
	var file := FileAccess.open(PROFILE_CATALOG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		return {}
	for value: Variant in parsed:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == profile_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _talent_definitions(ids: PackedStringArray) -> Array[Dictionary]:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(TALENT_CATALOG_PATH)
	)
	var requested: Dictionary = {}
	for talent_id: String in ids:
		requested[talent_id] = true
	var result: Array[Dictionary] = []
	if parsed is Array:
		for value: Variant in parsed:
			if value is Dictionary and requested.has(str((value as Dictionary).get("id", ""))):
				result.append((value as Dictionary).duplicate(true))
	return result
