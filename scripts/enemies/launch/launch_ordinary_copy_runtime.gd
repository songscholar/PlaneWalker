class_name LaunchOrdinaryCopyRuntime
extends "res://scripts/enemies/launch/launch_enemy_runtime.gd"

const CopyProjection := preload("res://scripts/enemies/launch/launch_ordinary_copy_projection.gd")


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	_definition.clear()
	_state.clear()
	if not CopyProjection.validate(definition):
		return _failure("ordinary_copy_projection")
	var ordinary := definition.duplicate(true)
	ordinary.erase("copy_contract")
	ordinary.actor_kind = "enemy"
	var accepted := super.configure(ordinary, identity)
	if not accepted.ok:
		return accepted
	_state.definition_digest = JSON.stringify(definition, "", true, true).sha256_text()
	return {"ok": true, "snapshot": snapshot()}
