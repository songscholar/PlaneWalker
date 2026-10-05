extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Encounter := preload("res://scripts/dungeon/launch_encounter_runtime.gd")
const Driver := preload("res://scripts/dungeon/native_launch_encounter_driver.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Semantics := preload("res://scripts/enemies/launch/launch_semantic_effect_authority.gd")
const RUN := "run-validation-projection"
const ROOM := "room-validation-projection"
const FRAME := 180
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var effects := Effects.new()
	var semantics := Semantics.new()
	suite.assert_true(effects.configure(RUN, FRAME) and semantics.configure(RUN, FRAME), "real effect and semantic authorities configure")
	var source: Dictionary = effects.snapshot()
	var frames: Array[Dictionary] = []
	for frame: int in range(1, FRAME + 1):
		frames.append({"frame": frame, "hp": 100.0 - float(frame % 10)})
	source.semantics.histories["hostile:history"] = {"max_hp": 100.0, "frames": frames}
	suite.assert_true(effects.can_restore_launch_transaction_snapshot(source) and semantics.can_restore_transaction_snapshot(source.semantics), "complete historical source validates before optimization")
	var definitions := Content.read_catalog("launch_encounters.json")
	var encounter := Encounter.new()
	var profile: Dictionary = definitions[0]
	var recipe: Dictionary = profile.recipes[0]
	var definition := {"id": str(profile.id) + "." + str(recipe.id), "floor_id": profile.floor_id, "recipe_id": recipe.id, "room_type": recipe.room_type, "waves": recipe.waves}
	suite.assert_true(encounter.configure(definition, {"run_id": RUN, "room_id": ROOM, "runtime_frame": FRAME, "encounter_generation": 1}).ok, "complete cold fixture uses an authored encounter")
	var cold := {"schema_version": 2, "definition": encounter.get("_encounter").duplicate(true), "encounter": encounter.snapshot(), "effects": source, "actors": {}, "summon_actors": {}, "threats": [], "run_seed": 4, "last_flushed_frame": FRAME}
	suite.assert_true(Driver.validate_cold_snapshot(cold, RUN, ROOM, FRAME), "full authored cold boundary and semantic history validate")
	var driver := Driver.new()
	var available := true
	for authority: Object in [semantics, effects, driver]:
		var present := authority.has_method("_validation_snapshot")
		suite.assert_true(present, "complete validation exposes an internal migration-only projection")
		available = available and present
	if available:
		_test_current(semantics, effects, driver, cold)
		_test_migrations(effects, driver, cold)
		_test_refusals(semantics, effects, cold)
	driver.free()
	suite.finish(get_tree())


func _test_current(semantics: RefCounted, effects: RefCounted, driver: Node, cold: Dictionary) -> void:
	var before := var_to_bytes(cold)
	for _repeat: int in range(16):
		suite.assert_true(is_same(semantics.call("_validation_snapshot", cold.effects.semantics), cold.effects.semantics), "current semantic validation retains its exact 180-frame history source")
		suite.assert_true(is_same(effects.call("_validation_snapshot", cold.effects), cold.effects), "current effect validation avoids copying complete histories")
		suite.assert_true(is_same(driver.call("_validation_snapshot", cold), cold), "current cold validation avoids copying the complete aggregate")
		suite.assert_true(semantics.can_restore_transaction_snapshot(cold.effects.semantics) and effects.can_restore_launch_transaction_snapshot(cold.effects) and Driver.validate_cold_snapshot(cold, RUN, ROOM, FRAME), "complete validation remains executable on every current source")
	suite.assert_equal(var_to_bytes(cold), before, "repeated complete validation leaves every typed source byte unchanged")
	var public: Dictionary = Driver.normalize_cold_snapshot(cold)
	suite.assert_equal(var_to_bytes(public), before, "public normalization retains exact previous typed bytes")
	suite.assert_true(not is_same(public, cold) and not is_same(public.effects.semantics.histories, cold.effects.semantics.histories), "public cold normalization remains deeply detached")
	public.effects.semantics.histories["hostile:history"].frames[0].hp = 0.0
	suite.assert_equal(var_to_bytes(cold), before, "external normalized history edits remain isolated")
	var normalized_effects: Dictionary = Effects.normalize_transaction_snapshot(cold.effects)
	var normalized_semantics: Dictionary = Semantics.normalize_transaction_snapshot(cold.effects.semantics)
	suite.assert_true(not is_same(normalized_effects.semantics.histories, cold.effects.semantics.histories) and not is_same(normalized_semantics.histories, cold.effects.semantics.histories), "both public child normalizers remain deeply detached")


func _test_migrations(effects: RefCounted, driver: Node, cold: Dictionary) -> void:
	for root_version: int in [1, 2]:
		for effect_version: int in [1, 2]:
			for semantic_version: int in [1, 2]:
				var legacy := cold.duplicate(true)
				legacy.schema_version = root_version
				if root_version == 1:
					legacy.erase("summon_actors")
				legacy.effects.schema_version = effect_version
				if effect_version == 1:
					legacy.effects.erase("summons")
				legacy.effects.semantics.schema_version = semantic_version
				if semantic_version == 1:
					legacy.effects.semantics.erase("spatial")
				var before := var_to_bytes(legacy)
				var expected := Driver.normalize_cold_snapshot(legacy)
				var projected: Dictionary = driver.call("_validation_snapshot", legacy)
				suite.assert_equal(var_to_bytes(projected), var_to_bytes(expected), "every current/legacy schema combination retains exact complete normalization")
				suite.assert_true(Driver.validate_cold_snapshot(legacy, RUN, ROOM, FRAME), "complete validation retains supported historical combinations")
				suite.assert_equal(var_to_bytes(legacy), before, "complete historical validation never mutates its caller")
				var projected_effects: Dictionary = effects.call("_validation_snapshot", legacy.effects)
				suite.assert_equal(var_to_bytes(projected_effects), var_to_bytes(Effects.normalize_transaction_snapshot(legacy.effects)), "effect projection retains exact supported migration bytes")
				if root_version == 2 and (effect_version == 1 or semantic_version == 1):
					suite.assert_true(not is_same(projected, legacy) and is_same(projected.encounter, legacy.encounter), "mixed-schema cold migration copies only its changed envelope")


func _test_refusals(semantics: RefCounted, effects: RefCounted, cold: Dictionary) -> void:
	var before := var_to_bytes(cold)
	var invalid := cold.duplicate(true)
	invalid.effects.semantics.histories["hostile:history"].frames[0].hp = INF
	suite.assert_true(not semantics.can_restore_transaction_snapshot(invalid.effects.semantics) and not effects.can_restore_launch_transaction_snapshot(invalid.effects) and not Driver.validate_cold_snapshot(invalid, RUN, ROOM, FRAME), "current full history checks reject nonfinite values after valid observations")
	invalid = cold.duplicate(true)
	invalid.effects.semantics.histories["hostile:history"].frames[0].frame = FRAME + 1
	suite.assert_true(not semantics.can_restore_transaction_snapshot(invalid.effects.semantics) and not effects.can_restore_launch_transaction_snapshot(invalid.effects) and not Driver.validate_cold_snapshot(invalid, RUN, ROOM, FRAME), "current full history checks reject impossible historical clocks")
	invalid = cold.duplicate(true)
	invalid.effects.semantics.unowned = true
	suite.assert_true(not semantics.can_restore_transaction_snapshot(invalid.effects.semantics) and not effects.can_restore_launch_transaction_snapshot(invalid.effects) and not Driver.validate_cold_snapshot(invalid, RUN, ROOM, FRAME), "current schema does not bypass exact child fields")
	invalid = cold.duplicate(true)
	invalid.effects.schema_version = 2.0
	suite.assert_true(not effects.can_restore_launch_transaction_snapshot(invalid.effects) and not Driver.validate_cold_snapshot(invalid, RUN, ROOM, FRAME), "typed effect version guard remains exact")
	invalid = cold.duplicate(true)
	invalid.schema_version = 2.0
	suite.assert_true(not Driver.validate_cold_snapshot(invalid, RUN, ROOM, FRAME), "typed cold version guard remains exact")
	invalid = cold.duplicate(true)
	invalid.effects.semantics.schema_version = 3
	suite.assert_true(not semantics.can_restore_transaction_snapshot(invalid.effects.semantics) and not effects.can_restore_launch_transaction_snapshot(invalid.effects) and not Driver.validate_cold_snapshot(invalid, RUN, ROOM, FRAME), "unknown integer semantic version rejects through all current parents")
	invalid = cold.duplicate(true)
	invalid.effects.schema_version = 3
	suite.assert_true(not effects.can_restore_launch_transaction_snapshot(invalid.effects) and not Driver.validate_cold_snapshot(invalid, RUN, ROOM, FRAME), "unknown integer effect version rejects through current cold parent")
	invalid = cold.duplicate(true)
	invalid.schema_version = 3
	suite.assert_true(not Driver.validate_cold_snapshot(invalid, RUN, ROOM, FRAME), "unknown integer cold version retains original refusal")
	suite.assert_true(not Driver.validate_cold_snapshot(cold, "wrong-run", ROOM, FRAME) and not Driver.validate_cold_snapshot(cold, RUN, ROOM, FRAME + 1), "whole native identity and clock checks remain mandatory")
	suite.assert_equal(var_to_bytes(cold), before, "refused observations preserve caller source and live authority")
