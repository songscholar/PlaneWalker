extends "res://scripts/replay/player_replay_world.gd"

const Recorder := preload("res://scripts/replay/replay_recorder.gd")
const Driver := preload("res://scripts/dungeon/native_launch_encounter_driver.gd")
const Atlas := preload("res://scripts/presentation/actor_atlas_projection.gd")
const Geometry := preload("res://scripts/replay/run_replay_geometry_view.gd")
const Actions := preload("res://scripts/player/player_action_state.gd")
const SemanticZone := preload("res://scripts/enemies/launch/launch_semantic_zone_projection.gd")

var _observation: Dictionary = {}
var _presentation: Node2D
var _atlas: Sprite2D
var _count := 0


func observation() -> Dictionary:
	return _observation.duplicate(true)


func hostile_count() -> int:
	return _count


func present_observation(value: Dictionary, registry: RefCounted) -> Dictionary:
	if not isolation_valid() or registry == null or not _valid(value):
		return _failure()
	var player := get_node_or_null("Player") as Node2D
	if player == null:
		player = create_player()
		if player == null or not player.configure_replay_view_identity(value.player.identity):
			return _failure()
	if player.full_player_replay_identity() != value.player.identity:
		return _failure()
	var stage := Node2D.new()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(stage)
	if not _build_scene(stage, value, registry):
		stage.free()
		return _failure()
	var candidate_atlas := Atlas.new()
	if not candidate_atlas.configure(str(value.player.identity.character_id), str(value.get("cosmetic_id", ""))):
		candidate_atlas.free()
		stage.free()
		return _failure()
	var before: Dictionary = player.full_player_replay_snapshot()
	if not player.restore_full_player_replay_snapshot(value.player) or player.full_player_replay_snapshot() != value.player:
		player.restore_full_player_replay_snapshot(before)
		candidate_atlas.free()
		stage.free()
		return _failure()
	var state := &"idle"
	match player.action_state.current_state:
		Actions.State.ATTACK_WINDUP, Actions.State.ATTACK_ACTIVE, Actions.State.ATTACK_RECOVERY: state = &"attack"
		Actions.State.DASH: state = &"move"
		Actions.State.TIME_CAST: state = &"cast"
		Actions.State.HITSTUN: state = &"hurt"
		Actions.State.DEAD: state = &"death"
		_:
			if player.velocity.length_squared() > 0.01:
				state = &"move"
	candidate_atlas.present(state, player.get("_last_move_direction"), float(value.player.frame) / 60.0, false, true)
	if is_instance_valid(_atlas):
		_atlas.free()
	_atlas = candidate_atlas
	player.add_child(_atlas)
	player.get_node("Visual").visible = false
	if is_instance_valid(_presentation):
		remove_child(_presentation)
		_presentation.queue_free()
	_presentation = stage
	move_child(stage, 1)
	_observation = value.duplicate(true)
	_count = value.native.get("actors", {}).size()
	return {"ok": true, "code": &"OK", "context": {}}


static func _valid(value: Dictionary) -> bool:
	if not value.get("player") is Dictionary or not value.get("run") is Dictionary or not value.get("native") is Dictionary or not value.get("scene") is Dictionary or not value.get("room") is Dictionary or typeof(value.get("sequence")) != TYPE_INT:
		return false
	var identity: Dictionary = value.player.get("identity", {})
	if identity.is_empty() or not Recorder.validate_full_player_snapshot(value.player, identity).ok or value.run.get("run_id") != identity.get("run_id") or not Recorder.replay_value_is_safe(value):
		return false
	if not value.native.is_empty():
		var room_id := str(value.native.get("encounter", {}).get("identity", {}).get("room_id", ""))
		if not Driver.validate_cold_snapshot(value.native, str(identity.run_id), room_id, int(value.player.frame)):
			return false
		if value.scene.get("binding", {}).get("node_id") != room_id:
			return false
	return true


func _build_scene(stage: Node2D, value: Dictionary, registry: RefCounted) -> bool:
	var binding: Dictionary = value.scene.get("binding", {})
	if not binding.is_empty():
		var template: Dictionary = registry.get_content(StringName(str(binding.get("content_id", ""))))
		if template.get("category") != "room_template" or not template.get("scene_path") is String or not ResourceLoader.exists(template.scene_path, "PackedScene"):
			return false
		var room: Node2D = (load(template.scene_path) as PackedScene).instantiate()
		var bound: Dictionary = room.bind_room({"id": str(binding.get("node_id", "")), "template_id": template.id, "room_type": template.room_type}, template, binding)
		if not bound.ok:
			room.free()
			return false
		room.process_mode = Node.PROCESS_MODE_DISABLED
		stage.add_child(room)
	var geometry := Geometry.new()
	geometry.frame = int(value.player.frame)
	geometry.facts = value.native.get("threats", []).duplicate(true)
	for saved: Dictionary in value.native.get("actors", {}).values():
		var definition: Dictionary = registry.get_content(StringName(saved.definition_id))
		if definition.get("category") not in ["enemy_definition", "boss_definition"]:
			return false
		var sprite: Sprite2D
		if definition.category == "boss_definition":
			sprite = Atlas.new()
			if not sprite.configure(str(saved.definition_id)):
				sprite.free()
				return false
			var phase: String = saved.actor.runtime.action.phase
			sprite.present(&"attack" if phase == "ACTIVE" else (&"cast" if phase == "WARNING" else &"idle"), Vector2.RIGHT, float(value.player.frame) / 60.0, false, true)
		else:
			sprite = Sprite2D.new()
			var path := "res://assets/production/enemies/%s.png" % str(saved.definition_id)
			if not ResourceLoader.exists(path, "Texture2D"):
				sprite.free()
				return false
			sprite.texture = load(path)
			sprite.hframes = 4
			sprite.frame = maxi(0, ["IDLE", "WARNING", "ACTIVE", "RECOVERY"].find(str(saved.actor.runtime.action.phase)))
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.scale = Vector2.ONE * (1.15 if saved.actor.has("affixes") else 1.0)
		sprite.position = Geometry._point(saved.actor.position)
		stage.add_child(sprite)
		var arena: Dictionary = saved.actor.runtime.get("arena_state", {})
		var origin := Geometry._point(arena.get("arena_origin", saved.actor.get("room_motion", {}).get("bounds", {})))
		for field: String in ["covers", "roots", "walls"]:
			for construct: Dictionary in arena.get(field, []):
				var visual := Sprite2D.new()
				var asset := "forest_root" if field == "roots" else ("ruins_wall" if field == "walls" else "ruins_cover")
				visual.texture = load("res://assets/production/constructs/%s.png" % asset)
				visual.hframes = 3
				visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				visual.frame = 2 if construct.broken or construct.get("retired", false) or construct.get("expired", false) else (1 if float(construct.current_hp) <= float(construct.max_hp) * 0.5 else 0)
				visual.position = origin + Geometry._point(construct.position) + (Vector2(0, -8) if field == "covers" else Vector2.ZERO)
				visual.rotation = Geometry._point(construct.direction).angle() if field == "walls" else 0.0
				visual.visible = not arena.get("terminal", false)
				stage.add_child(visual)
	for payload: Dictionary in value.native.get("effects", {}).get("payloads", {}).get("projectiles", []) + value.native.get("effects", {}).get("payloads", {}).get("zones", []):
		if payload.phase in ["PENDING", "DORMANT"]:
			continue
		var definition: Dictionary = payload.definition
		var kind := "projectile" if definition.kind == "projectile" else "pool"
		var path := "res://data/content_packs/base/assets/enemies/launch/acid_%s.png" % kind if definition.visual_kind == "acid" else "res://assets/production/hostile_effects/%s_%s.png" % [definition.visual_kind, kind]
		if not ResourceLoader.exists(path, "Texture2D"):
			return false
		var sprite := Sprite2D.new()
		sprite.texture = load(path)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.hframes = 4
		sprite.frame = (int(value.player.frame) / 6) % 4
		sprite.position = Geometry._point(payload.position if kind == "projectile" else definition.position)
		if kind == "projectile":
			sprite.rotation = Geometry._point(definition.direction).angle()
		else:
			sprite.scale = Vector2.ONE * float(definition.radius) / (13.0 if definition.visual_kind == "acid" else 14.0)
		stage.add_child(sprite)
	for record: Dictionary in value.native.get("effects", {}).get("semantics", {}).get("zones", []):
		if record.phase == "PENDING":
			continue
		var zone := SemanticZone.new()
		stage.add_child(zone)
		if not zone.project_record(record, int(value.player.frame)):
			return false
	stage.add_child(geometry)
	return true


static func _failure() -> Dictionary:
	return {"ok": false, "code": &"RUN_REPLAY_VIEW_INVALID", "context": {}}
