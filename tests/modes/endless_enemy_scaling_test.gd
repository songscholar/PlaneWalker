extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Runtime := preload("res://scripts/enemies/launch/launch_enemy_runtime.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const DAMAGE_FIELDS := ["impact_pool_damage", "death_pool_damage", "residual_tick_damage", "explosion_damage", "corpse_pool_damage", "elite_burn_damage", "death_collapse_damage"]
const Payload := preload("res://scripts/enemies/launch/launch_hostile_payload_runtime.gd")


func _ready() -> void:
	var suite := Suite.new()
	var parser := Enemy.new()
	suite.assert_true(parser.has_method("difficulty_projection"), "endless scales enemy auxiliary damage through a validated shared projection")
	if not parser.has_method("difficulty_projection"):
		suite.finish(get_tree())
		return
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	for id: String in Ids.enemy_ids():
		for kind: String in ["enemy", "elite"]:
			var content := registry.get_content(StringName(id))
			var source: Dictionary = {}
			for field: String in Enemy.FIELDS:
				source[field] = content.get(field)
			var accepted := parser.configure(source)
			suite.assert_true(accepted.ok, "canonical authored enemy parses " + id + ": " + str(accepted.get("context", {})))
			var original := parser.runtime_projection(kind)
			var projected: Dictionary = parser.call("difficulty_projection", original, 3.0, 2.0)
			suite.assert_true(projected.ok, "bounded native enemy projection " + id + " " + kind + ": " + str(projected.get("context", {})))
			if not projected.ok:
				continue
			var native := Runtime.new()
			var identity := {"run_id": "endless-scaling", "hostile_source_id": "scaled-" + id, "next_generation_floor": 1, "runtime_frame": 0, "seed": 41}
			suite.assert_true(native.configure(projected.definition, identity).ok, "scaled auxiliary values pass authenticated native parser " + id)
			for field: String in DAMAGE_FIELDS:
				if original.mechanisms.has(field):
					suite.assert_equal(projected.definition.mechanisms[field], float(original.mechanisms[field]) * 2.0, "outgoing auxiliary damage scales " + id + "/" + field)
			var restored := Runtime.new()
			suite.assert_true(restored.configure(projected.definition, identity).ok and restored.restore_snapshot(native.snapshot()), "scaled native enemy supports identical cold reconstruction " + id)
			if projected.definition.mechanisms.has("impact_pool_damage"):
				var forged: Dictionary = projected.definition.duplicate(true)
				forged.mechanisms.impact_pool_damage += 1.0
				suite.assert_true(not Runtime.new().configure(forged, identity).ok, "scaled mechanism proof refuses invented auxiliary damage")
				_moth_payload(suite, native, projected.definition)
	suite.finish(get_tree())


func _moth_payload(suite: RefCounted, native: RefCounted, definition: Dictionary) -> void:
	var context := {"runtime_frame": 0, "source_position": {"x": 300.0, "y": 150.0}, "target_position": {"x": 350.0, "y": 150.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player-scaling"}
	for frame: int in range(1, 101):
		context.runtime_frame = frame
		native.advance_frame(frame, context, false)
	var action: Dictionary = definition.actions[0]
	suite.assert_true(native.request_action(action.id, context).ok, "scaled moth commits actual native projectile action")
	var payload := Payload.new()
	payload.configure("endless-scaling", 100)
	for frame: int in range(101, 100 + int(action.warning_frames) + 2):
		context.runtime_frame = frame
		var result: Dictionary = native.advance_frame(frame, context, false)
		payload.advance_frame(frame, {"projectile_contacts": {}, "targets": {}})
		for hit: Dictionary in result.get("hit_facts", []):
			var parameters: Dictionary = definition.mechanisms.duplicate(true)
			parameters["mechanism_scaling"] = definition.mechanism_scaling.duplicate(true)
			suite.assert_true(payload.reserve_projectile(hit, {"x": 0.0, "y": 0.0, "width": 640.0, "height": 360.0}, parameters).ok, "actual scaled acid projectile retains verified impact-pool values")
	suite.assert_true(not payload.snapshot().projectiles.is_empty(), "scaled moth creates physical projectile domain reservation")
	if not payload.snapshot().projectiles.is_empty():
		suite.assert_equal(payload.snapshot().projectiles[0].definition.impact_pool.damage, definition.mechanisms.impact_pool_damage, "reserved native acid pool owns scaled outgoing damage")
