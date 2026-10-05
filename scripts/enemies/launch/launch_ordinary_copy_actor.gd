class_name LaunchOrdinaryCopyActor
extends "res://scripts/enemies/launch/launch_summon_actor.gd"

const CopyRuntime := preload("res://scripts/enemies/launch/launch_ordinary_copy_runtime.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")


static func instantiate_copy(parent_id: String) -> Node2D:
	if not Ids.ENEMY_FLOORS.has(parent_id):
		return null
	var scene := load("res://data/content_packs/base/assets/enemies/launch/enemy_%s.tscn" % parent_id) as PackedScene
	if scene == null:
		return null
	var actor := scene.instantiate() as Node2D
	actor.set_script(load("res://scripts/enemies/launch/launch_ordinary_copy_actor.gd"))
	actor.name = "Copy_" + parent_id
	actor.set_meta("summoned", true)
	actor.set_meta("reward_eligible", false)
	return actor


func _create_launch_runtime() -> RefCounted:
	return CopyRuntime.new()
