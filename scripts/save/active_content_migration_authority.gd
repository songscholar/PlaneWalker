class_name ActiveContentMigrationAuthority
extends RefCounted

const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Host := preload("res://scripts/application/run_runtime_host.gd")
const Room := preload("res://scenes/rooms/combat_room_01.tscn")
const SceneHost := preload("res://scripts/dungeon/room_scene_host.gd")
const FloorEffects := preload("res://scripts/dungeon/floor_rule_effect_authority.gd")
const Snapshot := preload("res://scripts/content/content_snapshot_provider.gd")
const Checkpoint := preload("res://scripts/save/native_run_checkpoint_authority.gd")


static func verify(save: RefCounted, catalog: RefCounted, profile_id: String, domain: String, target: Dictionary, parent: Node) -> Dictionary:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return _failure("probe_parent")
	var service := Service.new()
	if not service.configure(catalog, save, profile_id, domain).ok:
		return _failure("profile")
	var payload := service.payload()
	var authenticated := service.authenticated_active_run(int(service.snapshot().revision))
	if not authenticated.ok:
		return _failure("run_lineage")
	# Production owners run synchronously without a gameplay frame or presentation.
	var root := Node2D.new()
	root.name = "ContentMigrationProbe"
	root.visible = false
	root.process_mode = Node.PROCESS_MODE_DISABLED
	var controller := Room.instantiate()
	controller.name = "CombatRoom01"
	controller.auto_start = false
	root.add_child(controller)
	var scene_host := SceneHost.new()
	root.add_child(scene_host)
	var host := Host.new()
	host.room_controller_path = NodePath("../CombatRoom01")
	root.add_child(host)
	parent.add_child(root)
	host.set_process(false)
	host.set_run_presentation_visible(false)
	var player: Node = controller.get_node("Player")
	player.set_weapon_resource_publication_enabled(false)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var effects := FloorEffects.new()
	var participants: Dictionary = host.native_checkpoint_participants()
	var valid: bool = effects.configure(player, scene_host) and host.configure_route_scene_adapter(scene_host) and host.configure_floor_rule_effect_authority(effects) and Snapshot.snapshot(host.content_registry()) == target
	var stage := "probe_configuration"
	if valid:
		if payload.get("native_run_checkpoint", {}).is_empty():
			var facade: RefCounted = participants.facade
			valid = facade.restore_launch_run(authenticated.context.run, effects).ok and Checkpoint.json_equal(facade.snapshot(), authenticated.context.run)
			stage = "current_domain"
		else:
			var restored: Variant = host.restore_profile_checkpoint(service, int(service.snapshot().revision))
			valid = restored.ok and Checkpoint.json_equal(host.runtime_snapshot(), authenticated.context.run) and service.payload() == payload
			stage = "native_reconstruction"
	root.free()
	return {"ok": true, "code": &"OK", "context": {}} if valid else _failure(stage)


static func _failure(stage: String) -> Dictionary:
	return {"ok": false, "code": &"NATIVE_CONTENT_MIGRATION_REQUIRED", "context": {"stage": stage}}
