class_name ModeCombatHudProjector
extends RefCounted

const Contract := preload("res://scripts/ui/contracts/mode_combat_hud_view_state.gd")
const RunProjector := preload("res://scripts/application/run_view_state_projector.gd")
const META_FIELDS := ["run_id", "revision", "stage_index", "stage_total", "elapsed_frames", "suspended"]
var _resources := RunProjector.new()


func project(mode_id: String, metadata: Dictionary, player_snapshot: Dictionary, boss_snapshot: Dictionary) -> Dictionary:
	if metadata.size() != META_FIELDS.size():
		return _failure("metadata")
	for field: String in META_FIELDS:
		if not metadata.has(field):
			return _failure("metadata." + field)
	var player := player_snapshot.duplicate(true)
	var weapon := _resources._weapon_view(player.get("weapon"))
	var character := _resources._character_view(player.get("character"))
	var active := _resources._active_item_view(player.get("active_item"))
	for projection: Dictionary in [weapon, character, active]:
		if not projection.ok:
			return _failure(str(projection.get("field", "player")))
	for field: String in ["weapon", "character", "active_item"]:
		player.erase(field)
	var view := metadata.duplicate(true)
	view.merge({"schema_version": 1, "mode_id": mode_id, "player": player, "weapon_state": weapon.weapon_state.duplicate(true), "character_state": character.character_state, "active_item_state": active.active_item_state, "boss": boss_snapshot.duplicate(true) if not boss_snapshot.is_empty() else null})
	var validation = Contract.validate(view)
	if not validation.ok:
		return {"ok": false, "code": validation.code, "context": validation.context.duplicate(true)}
	return {"ok": true, "code": &"OK", "context": {"view_state": view.duplicate(true)}}


static func _failure(field: String) -> Dictionary:
	return {"ok": false, "code": &"INVALID_ARGUMENT", "context": {"field": field}}
