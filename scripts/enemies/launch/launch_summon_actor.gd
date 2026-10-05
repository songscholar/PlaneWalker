class_name LaunchSummonActor
extends "res://scripts/enemies/launch/launch_hostile_actor.gd"

const SummonRuntime := preload("res://scripts/enemies/launch/launch_summon_runtime.gd")
const Template := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
var _summon_authority: RefCounted
var _summon_lease: Dictionary = {}


static func instantiate_summon(id: String) -> Node2D:
	var texture := load("res://assets/production/summons/%s.png" % id) as Texture2D
	if texture == null:
		return null
	var actor := Template.instantiate() as Node2D
	actor.set_script(load("res://scripts/enemies/launch/launch_summon_actor.gd"))
	actor.name = "Summon_" + id
	actor.set_meta("summoned", true)
	actor.set_meta("reward_eligible", false)
	actor.get_node("Sprite2D").texture = texture
	return actor


func _create_launch_runtime() -> RefCounted:
	return SummonRuntime.new()


func configure_summon_lease(authority: RefCounted, lease: Dictionary) -> bool:
	if _summon_authority != null or authority == null or not authority.has_method("owns_child_lease") or not authority.owns_child_lease(self, lease):
		return false
	_summon_authority = authority
	_summon_lease = lease.duplicate(true)
	return true


func prepare_launch_frame(frame: int, observations: Dictionary) -> Dictionary:
	if _summon_authority == null or not _summon_authority.owns_child_lease(self, _summon_lease):
		return _launch_failure("summon_lease")
	if health.is_alive() and _summon_authority.child_retirement_required(self, frame):
		var loss := float(health.lose_health(float(health.current_hp), self))
		if loss <= 0.0 or not _launch_runtime.accept_damage_fact({"fact_id": "summon-retirement:" + str(hostile_source_id), "runtime_frame": frame, "target_source_id": str(hostile_source_id), "amount": loss, "hp_after": 0.0}).ok:
			return _launch_failure("summon_retirement")
	return super.prepare_launch_frame(frame, observations)


func prepared_launch_arena_payloads_retired() -> bool:
	return not _prepared_launch_frame.is_empty() and bool(_prepared_launch_frame.after.runtime.terminal)


func _on_died(_killer: Variant) -> void:
	if not is_instance_valid(health) or not health.dead or health.current_hp > 0.0 or not _death_receipt.is_empty():
		return
	cancel_active_attack()
	_launch_runtime.cancel(&"death")
	clear_weapon_hit_control_state(&"death")
	reset_elemental_statuses()
	_hostile_identity_active = false
	remove_from_group("enemies")
	remove_from_group("time_stoppable")
	_death_receipt = "hostile_defeat:%s" % (str(_launch_identity.run_id) + "|" + str(hostile_source_id)).sha256_text().substr(0, 40)
	_refresh_control_visual()
	hostile_final_death.emit(hostile_source_id, _death_receipt)
