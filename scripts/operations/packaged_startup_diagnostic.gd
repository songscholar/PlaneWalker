extends Node

const Snapshot := preload("res://scripts/content/content_snapshot_provider.gd")

var _checks: Array[String] = []
var _failure := ""


func verify(main: Node) -> void:
	var output := OS.get_environment("PLANEWALKER_STARTUP_REPORT")
	var isolated := OS.get_environment("PLANEWALKER_USER_DATA_DIR")
	if not output.is_absolute_path() or not isolated.is_absolute_path() or not GameState.save_path.begins_with(isolated.simplify_path() + "/"):
		push_error("Packaged startup requires isolated user data and an absolute report path")
		get_tree().quit(2)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var hub: Node = main.get_node_or_null("HubFlowCoordinator")
	var host: Node = main.get_node_or_null("RunRuntimeHost")
	var service: RefCounted = GameState.profile_runtime_service()
	var content := Snapshot.snapshot(host.content_registry()) if host != null else {}
	if _check(hub != null and host != null and service != null and main.get("_profile_error") == "" and not content.is_empty(), "production_boot"):
		_check(hub.is_hub_visible() and not main.get_node("StartMenu").visible, "native_hub_first_screen")
		var initial: Dictionary = service.snapshot()
		for district: String in ["hub_craft", "hub_rift", "hub_council"]:
			_check(hub.travel(district).ok and hub.scene_host().get_child_count() == 1 and hub.view_state().district_id == district, district)
		_check(service.snapshot() == initial, "navigation_preserves_profile")
		if _check(hub.open_function("gateway").ok, "gateway_panel"):
			var launch: Button
			for control: Control in hub.panel_view().action_controls():
				if str(control.get_meta("action_id", "")) == "launch":
					launch = control as Button
			if _check(launch != null and not launch.disabled, "gateway_launch_control"):
				var view: Dictionary = hub.view_state()
				hub.submit_command({"epoch": view.epoch, "function_id": "gateway", "operation": "launch", "payload": {"seed": 20261005}}, int(view.revision))
				await get_tree().process_frame
				if _check(not hub.is_hub_visible() and service.snapshot().launch_sequence == 1 and not service.snapshot().active_launch_receipt.is_empty(), "durable_native_launch"):
					var selected := false
					for route: Dictionary in host.route_choices():
						if route.room_type in ["combat", "elite"]:
							var result = host.select_route(StringName(route.edge_id), int(host.runtime_snapshot().revision))
							selected = result.ok
							if not selected:
								print("Startup route refused: ", result.code, " ", result.context)
							break
					if _check(selected, "production_combat_route"):
						main.get_node("DungeonFlow").refresh(true)
						var controller: Node = main.get_node("CombatRoom01")
						for _frame: int in range(240):
							await get_tree().physics_frame
							await get_tree().process_frame
							if controller.encounter_runner().is_active() and controller.get_node("Enemies").get_child_count() > 0:
								break
						_check(controller.encounter_runner().is_active() and controller.get_node("Enemies").get_child_count() > 0, "native_combat_actors")
						_check(main.checkpoint_current_run().ok, "durable_combat_checkpoint")
	var report := {"schema_id": "planewalker.packaged_startup", "schema_version": 1, "status": "pass" if _failure.is_empty() else "failed", "engine_version": Engine.get_version_info().string, "checks": _checks.duplicate(), "failure": _failure, "content_snapshot": content}
	var tree := get_tree()
	main.queue_free()
	await tree.process_frame
	await tree.process_frame
	await tree.create_timer(0.15, true, false, true).timeout
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Packaged startup report could not be written")
		tree.quit(2)
		return
	file.store_string(JSON.stringify(report) + "\n")
	file.close()
	if _failure.is_empty():
		print("PASS: packaged native startup")
		tree.quit(0)
	else:
		push_error("Packaged startup failed: " + _failure)
		tree.quit(1)


func _check(value: bool, id: String) -> bool:
	if value:
		_checks.append(id)
	elif _failure.is_empty():
		_failure = id
	return value
