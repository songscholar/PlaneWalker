extends "res://tests/integration/ui/main_daily_boss_test.gd"

const HUD_PATH := "res://scenes/ui/modes/mode_combat_hud.tscn"
const PROJECTOR_PATH := "res://scripts/ui/style/mode_combat_hud_projector.gd"
const MODE_ROWS := [
	["boss_rush", "BossRushCoordinator", "boss_rush", 5],
	["daily_boss", "DailyBossCoordinator", "daily", 1],
	["authored_challenges", "AuthoredChallengeCoordinator", "authored", 3],
	["endless", "EndlessCoordinator", "endless", 5],
]


func _run() -> void:
	_suite = Suite.new()
	_suite.assert_true(ResourceLoader.exists(HUD_PATH), "all challenge modes have a shared graphical combat HUD")
	_suite.assert_true(ResourceLoader.exists(PROJECTOR_PATH), "mode HUD has a read-only typed projection adapter")
	if not ResourceLoader.exists(HUD_PATH) or not ResourceLoader.exists(PROJECTOR_PATH):
		_suite.finish(get_tree())
		return
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	for row: Array in MODE_ROWS:
		_seed_main_profile("mode-finish-" + str(row[0]))
		var main := Main.instantiate()
		add_child(main)
		await _frames(2)
		var hub: Node = main.get_node("HubFlowCoordinator")
		_suite.assert_true(hub.travel("hub_council").ok and hub.open_function("gateway").ok, "real gateway opens for " + str(row[0]))
		_daily_action(hub.panel_view(), str(row[0])).pressed.emit()
		var coordinator: Node = main.get_node(str(row[1]))
		var panel: Control = coordinator.panel()
		await _frames(2)
		_suite.assert_true(panel.find_child("ModeLoadout", true, false) != null, "mode menu exposes authentic graphical loadout " + str(row[0]))
		_suite.assert_true(panel.find_child("ModeArtwork", true, false) != null, "mode identity uses production artwork " + str(row[0]))
		var track: Node = panel.find_child("BossTrack", true, false)
		_suite.assert_true(track != null and track.get_child_count() == int(row[3]), "mode menu exposes authored boss track " + str(row[0]))
		var state: Dictionary = panel.view_state()
		_suite.assert_equal(panel.view_state(), state, "visual composition leaves exact menu projection intact")
		await _capture_mode(coordinator, str(row[0]) + "-menu")
		var start := _daily_action(panel, "start")
		_suite.assert_true(start != null and not start.disabled, "earned profile can start " + str(row[0]))
		if start == null or start.disabled:
			main.queue_free()
			await _frames(2)
			continue
		start.pressed.emit()
		await _frames(6)
		if row[0] == "endless":
			var host: Node = coordinator.runtime().runtime_host()
			var entered_combat := false
			for route: Dictionary in host.route_choices():
				if route.room_type in ["combat", "elite"]:
					entered_combat = host.select_route(StringName(route.edge_id), int(host.runtime_snapshot().revision)).ok
					break
			_suite.assert_true(entered_combat, "Endless HUD is exercised inside an actual native combat route")
			await _frames(4)
		await get_tree().process_frame
		await get_tree().process_frame
		var hud: Control = coordinator.get("_hud")
		if row[0] == "endless":
			_suite.assert_equal((hud.get_parent() as CanvasLayer).layer, 10, "Endless resource HUD remains below focused dungeon overlays")
		_suite.assert_true(hud.visible and hud.has_method("latest_state"), "actual combat uses the graphical HUD " + str(row[0]))
		if hud.has_method("latest_state"):
			var view: Dictionary = hud.latest_state()
			_suite.assert_true(not view.is_empty() and view.mode_id == row[2], "actual source is accepted for " + str(row[0]))
			for node_name: String in ["ModeHpGauge", "ModeEnergyGauge", "WeaponSlot", "CharacterSlot", "TimeSlot1", "TimeSlot2", "PauseButton"]:
				_suite.assert_true(hud.find_child(node_name, true, false) != null, "graphical resource exists: " + str(row[0]) + "/" + node_name)
			if not view.is_empty():
				var copy := view.duplicate(true)
				_suite.assert_equal(hud.render(view).code, &"STALE_REVISION", "same revision cannot repaint accepted combat")
				var malformed := view.duplicate(true)
				malformed.revision += 1
				malformed.player.hp = -1
				_suite.assert_true(not hud.render(malformed).ok, "invalid resource refuses without changing display")
				_suite.assert_equal(hud.latest_state(), copy, "refusals preserve last accepted mode state")
				view.player.time_slots[0].cooldown = 500
				_suite.assert_equal(hud.latest_state(), copy, "public HUD copies cannot change retained display")
				if row[0] == "boss_rush":
					await _projection_isolation(coordinator, copy)
					var isolated: Control = load(HUD_PATH).instantiate()
					add_child(isolated)
					_suite.assert_true(isolated.render(copy).ok, "independent HUD accepts first run identity")
					var next_run := copy.duplicate(true)
					next_run.run_id += "-next"
					next_run.revision = 0
					_suite.assert_true(isolated.render(next_run).ok, "new run may begin with its first revision")
					copy.revision += 100
					var retired = isolated.render(copy)
					_suite.assert_true(retired.code == &"STALE_REVISION" and retired.context.get("field") == "run_id", "retired run cannot repaint new active run")
					isolated.queue_free()
		await _capture_mode(coordinator, str(row[0]) + "-combat")
		var pause := InputEventAction.new()
		pause.action = &"pause"
		pause.pressed = true
		_suite.assert_true(coordinator.handle_input(pause) and panel.visible, "mapped pause retains mode commands " + str(row[0]))
		var frozen: Dictionary = coordinator.runtime().snapshot()
		await _frames(3)
		_suite.assert_equal(coordinator.runtime().snapshot(), frozen, "graphical pause never advances mode state")
		await _capture_mode(coordinator, str(row[0]) + "-pause")
		_suite.assert_true(coordinator.return_to_hub().ok, "mode returns through production save policy " + str(row[0]))
		main.queue_free()
		await _frames(2)
	# Rapid four-Main teardown needs one mixer retirement interval before exit.
	await get_tree().create_timer(0.3, true, false, true).timeout
	_suite.finish(get_tree())


func _projection_isolation(coordinator: Node, accepted: Dictionary) -> void:
	var player: Dictionary = coordinator.runtime().current_player().get_player_ui_snapshot()
	var original := player.duplicate(true)
	var metadata := {}
	for key: String in ["run_id", "revision", "stage_index", "stage_total", "elapsed_frames", "suspended"]:
		metadata[key] = accepted[key]
	var boss: Dictionary = accepted.boss.duplicate(true) if accepted.boss is Dictionary else {}
	var projector: RefCounted = load(PROJECTOR_PATH).new()
	var projected: Dictionary = projector.project("boss_rush", metadata, player, boss)
	_suite.assert_true(projected.ok, "pure adapter accepts actual player/native boss facts")
	_suite.assert_equal(player, original, "mode projection never normalizes source player state")
	if projected.ok:
		projected.context.view_state.player.time_slots[0].cooldown = 900
		_suite.assert_equal(player, original, "projected nested arrays remain detached from authoritative source")
	metadata.stage_total = 0
	_suite.assert_true(not projector.project("boss_rush", metadata, player, boss).ok, "invalid mode metadata fails closed")


func _capture_mode(coordinator: Node, id: String) -> void:
	if not OS.get_cmdline_user_args().has("--mode-finish-screenshots"):
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var pixels := get_viewport().get_texture().get_image()
	_suite.assert_true(pixels != null and not pixels.is_empty(), "mode screenshot has native pixels " + id)
	if pixels == null or pixels.is_empty():
		return
	var output := "res://build/ui-mode-finish-screenshots/" + id + ".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	_suite.assert_equal(pixels.save_png(output), OK, "mode screenshot retained " + id)
	_suite.assert_true(coordinator.find_child("ModeArtwork", true, false) != null, "captured mode retains production identity art")
