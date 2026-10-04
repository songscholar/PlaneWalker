extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Snapshots := preload("res://scripts/content/content_snapshot_provider.gd")
const Accessibility := preload("res://scripts/accessibility/accessibility_runtime.gd")

var _fault := false
var _closed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	get_window().size = Vector2i(640, 360)
	get_window().content_scale_size = Vector2i(640, 360)
	var implementation := load("res://scripts/training/training_flow_coordinator.gd") as Script
	suite.assert_true(implementation != null, "native training requires independent arena, camera and usable coordinator")
	if implementation != null:
		var coordinator: Node = implementation.new()
		add_child(coordinator)
		for method: String in ["configure", "open", "close", "is_training_active", "training_player", "training_panel", "training_arena"]:
			suite.assert_true(coordinator.has_method(method), "training coordinator publishes narrow native integration API: " + method)
		suite.assert_true(coordinator.has_signal("closed"), "training owns an explicit closed handoff")
		var registry := Registry.new()
		var loaded: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
		suite.assert_true(not loaded.has_blocking_errors(), "arena uses activated real Launch content")
		var save := Save.new()
		suite.assert_true(save.configure(Paths.resolve_default("user://p16r-training", "p16r-training"), "test-training-arena", Snapshots.snapshot(registry), Callable(), Callable(self, "_inject_fault")).ok, "arena uses physical Profile persistence")
		var service := Service.new()
		suite.assert_true(service.configure(Factory.from_registry(registry).context.catalog, save, "arena_slot", "base").ok, "arena owns actual fresh Profile service")
		suite.assert_true(coordinator.configure(registry, service).ok, "coordinator configures real arena foundation")
		coordinator.closed.connect(func(): _closed += 1)
		suite.assert_true(coordinator.open().ok and coordinator.is_training_active(), "training opens an independent actual scene")
		coordinator.get("_flow").set_process(false)
		await get_tree().process_frame
		await get_tree().process_frame
		var player: Node2D = coordinator.training_player()
		var panel: Control = coordinator.training_panel()
		var arena: Node2D = coordinator.training_arena()
		suite.assert_equal(player.global_position, Vector2(204, 204), "actual Player enters within 640x360 practice floor")
		suite.assert_true(not player.is_physics_processing() and not get_tree().paused, "configuration pauses only the owned Player")
		suite.assert_true(arena.native_target() != null and arena.native_target().target == player and arena.native_target().get_node("Hurtbox") != null, "practice target owns actual combat Health and Hurtbox")
		suite.assert_true(coordinator.get_node("TrainingCamera").is_current(), "training takes its independent native camera")
		for field: String in ["task_id", "character_id", "weapon_id", "time_abilities"]:
			var option: OptionButton = panel.selector(field)
			suite.assert_equal(option.item_count, 6 if field in ["task_id", "time_abilities"] else 5, "real selector exposes authored options: " + field)
			suite.assert_true(Rect2(Vector2.ZERO, Vector2(640, 360)).encloses(option.get_global_rect()), "selector fits native safe area: " + field + str(option.get_global_rect()))
		panel.play_button().pressed.emit()
		suite.assert_true(player.is_physics_processing(), "symbolic practice control enables actual Player")
		panel.play_button().pressed.emit()
		suite.assert_true(not player.is_physics_processing(), "symbolic configure control stops actual Player")
		var before: Dictionary = service.snapshot()
		suite.assert_true(player.advance_action_frame(_intents(1, Vector2.RIGHT)), "native arena movement produces actual task objective")
		_fault = true
		var refused: Dictionary = coordinator.close()
		suite.assert_true(not refused.ok and coordinator.is_training_active() and coordinator.training_player() == player and _closed == 0 and service.snapshot() == before, "failed physical save keeps Back and native attempt recoverable")
		panel.reset_button().pressed.emit()
		suite.assert_true(coordinator.training_player() == player and service.snapshot() == before, "failed physical save keeps Reset on original attempt")
		var character: OptionButton = panel.selector("character_id")
		character.select(1)
		character.item_selected.emit(1)
		suite.assert_true(coordinator.training_player() == player and character.get_selected_metadata() == "wanderer", "failed physical save restores actual selector without native drift")
		_fault = false
		coordinator.get("_flow")._process(0.0)
		coordinator._process(0.0)
		suite.assert_true(coordinator.get("_flow").training_adapter().pending_observations().is_empty() and coordinator.get("_rejection") == &"", "automatic physical retry clears the actual saved error state")
		suite.assert_true(coordinator.close().ok and not coordinator.is_training_active() and _closed == 1, "Back retries physical objective then closes once")
		await get_tree().process_frame
		suite.assert_true(coordinator.open().ok, "training reopens after exact native retirement")
		player = coordinator.training_player()
		player.set_physics_process(false)
		var dash := _intents(1, Vector2.ZERO)
		dash.dash = [{"id": &"dash", "edge": &"pressed", "held_frames": 0, "mode": &"press"}]
		suite.assert_true(player.advance_action_frame(dash), "actual reopened dash complements persisted objective")
		suite.assert_true(coordinator.get("_flow").process_pending_observations().ok, "arena drains real saved task completion")
		await get_tree().process_frame
		suite.assert_true(service.snapshot().chronos_shards == before.chronos_shards + 3 and panel.progress_label().text.contains("1/1"), "durable objective UI follows physically saved completion")
		character.select(1)
		character.item_selected.emit(1)
		var next: Node2D = coordinator.training_player()
		suite.assert_true(next != player and next.full_player_replay_identity().character_id == character.get_selected_metadata(), "actual selector recreates selected native character")
		panel.reset_button().pressed.emit()
		suite.assert_true(coordinator.training_player() != next and service.snapshot().chronos_shards == before.chronos_shards + 3, "native Reset recreates resources and preserves first-completion claim")
		var weapon: OptionButton = panel.selector("weapon_id")
		weapon.grab_focus()
		var prior_weapon: String = weapon.get_selected_metadata()
		var controller := InputEventJoypadButton.new()
		controller.button_index = JOY_BUTTON_DPAD_RIGHT
		controller.pressed = true
		Input.parse_input_event(controller)
		await get_tree().process_frame
		controller.pressed = false
		Input.parse_input_event(controller)
		await get_tree().process_frame
		suite.assert_true(weapon.get_selected_metadata() != prior_weapon and coordinator.training_player().full_player_replay_identity().weapon_id == weapon.get_selected_metadata(), "actual controller direction selects and configures native weapon")
		await _verify_visuals(suite, coordinator, panel)
		player = coordinator.training_player()
		suite.assert_true(player.advance_action_frame(_intents(1, Vector2.RIGHT)), "paused API fixture retains one actual pending frame")
		var paused_profile: Dictionary = service.snapshot()
		var pending: Array = coordinator.get("_flow").training_adapter().pending_observations()
		get_tree().paused = true
		var paused_close: Dictionary = coordinator.close()
		panel.reset_button().pressed.emit()
		suite.assert_true(not paused_close.ok and coordinator.is_training_active() and coordinator.training_player() == player and coordinator.get("_flow").training_adapter().pending_observations() == pending and service.snapshot() == paused_profile, "paused public Back/Reset cannot discard an unsaved actual frame")
		get_tree().paused = false
		await _test_boss_drill(suite, coordinator, service)
		await _test_boss_retirement(suite, coordinator, service)
		await _test_second_slot(suite, coordinator, service)
		_test_failed_restart(suite, coordinator)
		suite.assert_true(service.snapshot().statistics == before.statistics and service.snapshot().launch_sequence == before.launch_sequence, "arena does not mutate formal run accounting")
		suite.assert_true(coordinator.close().ok, "final arena retirement drains native attempt")
		if coordinator.get("_flow").training_player() != null:
			coordinator.get("_flow").close()
		coordinator.queue_free()
		await get_tree().process_frame
	suite.finish(get_tree())


func _test_boss_drill(suite: RefCounted, coordinator: Node, service: RefCounted) -> void:
	suite.assert_true(coordinator.close().ok, "previous drill drains before real Boss attempt")
	var before: Dictionary = service.snapshot()
	var opened: Dictionary = coordinator.open("T-05")
	suite.assert_true(opened.ok, "task five requires an actual Chrono Warden conversion drill")
	if not opened.ok:
		return
	var player: Node2D = coordinator.training_player()
	var boss: Node2D = coordinator.training_arena().native_target()
	suite.assert_true(boss != null and boss.has_method("training_conversion_fact"), "T05 binds the actual Boss action engine and native conversion proof")
	if boss == null or not boss.has_method("training_conversion_fact"):
		return
	player.set_physics_process(false)
	boss.set_physics_process(false)
	var idle_stop := _intents(1, Vector2.ZERO)
	idle_stop.time = [{"id": &"time_slot_1", "edge": &"pressed", "held_frames": 0, "mode": &"press"}]
	suite.assert_true(player.advance_action_frame(idle_stop), "real Stop can contact an idle practice Boss")
	suite.assert_true(coordinator.get("_flow").training_adapter().pending_observations().is_empty() and service.snapshot() == before, "idle Boss exposure grants no conversion objective")
	coordinator.training_panel().reset_button().pressed.emit()
	player = coordinator.training_player()
	boss = coordinator.training_arena().native_target()
	player.set_physics_process(false)
	boss.set_physics_process(false)
	for index: int in range(240):
		boss._physics_process(1.0 / 60.0)
		if boss.get_boss_ui_snapshot().phase == "WINDUP":
			break
	suite.assert_equal(boss.get_boss_ui_snapshot().phase, "WINDUP", "actual Boss AI commits its authored warning without test force helpers")
	suite.assert_true(player.advance_action_frame(_intents(1, Vector2.ZERO)), "actual Player samples native Boss warning in its first frame")
	var stopped := _intents(2, Vector2.ZERO)
	stopped.time = idle_stop.time.duplicate(true)
	suite.assert_true(player.advance_action_frame(stopped), "actual Stop contacts and converts the committed Boss window")
	var source: String = player.time_manager.replay_snapshot().stop_source_id
	var fact: Dictionary = boss.training_conversion_fact(StringName(source))
	suite.assert_true(not fact.is_empty() and fact.after.exposed and fact.after.remaining > fact.before.remaining, "actual Boss stores exact native source, exposure and positive action extension")
	var flow: Node = coordinator.get("_flow")
	suite.assert_equal(flow.training_adapter().pending_observations().size(), 1, "committed actual Boss conversion issues one sealed native objective")
	var pending: Array = flow.training_adapter().pending_observations()
	var exact_parent: Node = boss.get_parent()
	exact_parent.remove_child(boss)
	coordinator.add_child(boss)
	suite.assert_true(not coordinator.close().ok and flow.training_adapter().pending_observations() == pending and coordinator.training_player() == player, "invalid Boss with an unsaved actual objective cannot retire or discard progress")
	coordinator.remove_child(boss)
	exact_parent.add_child(boss)
	_fault = true
	suite.assert_true(not flow.process_pending_observations().ok and service.snapshot() == before and flow.training_adapter().pending_observations().size() == 1, "failed physical Boss reward promotion keeps exact native objective")
	_fault = false
	var saved: Dictionary = flow.process_pending_observations()
	suite.assert_true(saved.ok and saved.context.get("completed_tasks", []) == ["T-05"] and service.snapshot().chronos_shards == before.chronos_shards + 15, "real Boss conversion grants exactly fifteen physically saved shards")
	player.authoritative_frame_committed.emit(2)
	suite.assert_true(flow.training_adapter().pending_observations().is_empty(), "duplicate public Boss frame cannot issue another conversion")
	var restarted := Service.new()
	suite.assert_true(restarted.configure(Factory.from_registry(coordinator.get("_registry")).context.catalog, service.get("_save"), "arena_slot", "base").ok, "fresh Profile service reloads actual Boss reward from physical save")
	suite.assert_true(restarted.snapshot().chronos_shards == service.snapshot().chronos_shards and restarted.enable_tutorial(coordinator.get("_registry").get_catalog_entries(&"tutorial_definition", &"LAUNCH")).ok and restarted.tutorial_progress_view().context.training_claims.has("T-05"), "Boss completion claim survives physical restart")
	coordinator.training_panel().reset_button().pressed.emit()
	player = coordinator.training_player()
	boss = coordinator.training_arena().native_target()
	player.set_physics_process(false)
	boss.set_physics_process(false)
	suite.assert_true(_native_warning(boss), "real Boss warning repeats through actual action engine")
	var repeat_stop := _intents(1, Vector2.ZERO)
	repeat_stop.time = idle_stop.time.duplicate(true)
	suite.assert_true(player.advance_action_frame(repeat_stop) and flow.process_pending_observations().ok, "reset Boss attempt receives another authentic conversion")
	suite.assert_equal(service.snapshot().chronos_shards, before.chronos_shards + 15, "actual repeated Boss conversion never rewards twice")
	var adapter: RefCounted = flow.training_adapter()
	var exact_health: Node = boss.health
	boss.health = Node.new()
	suite.assert_true(not adapter.is_live_binding(), "replacement native Boss Health refuses issued binding")
	var replacement: Node = boss.health
	boss.health = exact_health
	replacement.free()
	var parent: Node = boss.get_parent()
	parent.remove_child(boss)
	coordinator.add_child(boss)
	suite.assert_true(not adapter.is_live_binding(), "foreign native Boss parent refuses issued binding")
	coordinator.remove_child(boss)
	parent.add_child(boss)
	suite.assert_true(adapter.is_live_binding(), "exact restored Boss participants revalidate without fabricated proof")
	coordinator.training_panel().reset_button().pressed.emit()
	player = coordinator.training_player()
	boss = coordinator.training_arena().native_target()
	player.set_physics_process(false)
	boss.set_physics_process(false)
	suite.assert_true(_native_warning(boss), "native refusal fixture uses actual warning")
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not player.advance_action_frame(repeat_stop), "real late World refusal rejects the Stop conversion frame")
	suite.assert_true(flow.training_adapter().pending_observations().is_empty() and service.snapshot().chronos_shards == before.chronos_shards + 15, "uncommitted Boss source publishes no objective or reward")
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	coordinator.training_panel().reset_button().pressed.emit()
	player = coordinator.training_player()
	boss = coordinator.training_arena().native_target()
	player.set_physics_process(false)
	boss.set_physics_process(false)
	suite.assert_true(_native_warning(boss), "foreign source fixture uses actual warning")
	boss.remove_from_group("time_stoppable")
	boss.apply_time_stop_source(&"foreign-native-source", 3.0)
	suite.assert_true(player.advance_action_frame(repeat_stop) and flow.training_adapter().pending_observations().is_empty(), "foreign Boss source without actual TimeManager target contact cannot complete training")
	boss.add_to_group("time_stoppable")
	coordinator.training_panel().reset_button().pressed.emit()
	var pair_selector: OptionButton = coordinator.training_panel().selector("time_abilities")
	pair_selector.select(0)
	pair_selector.item_selected.emit(0)
	player = coordinator.training_player()
	boss = coordinator.training_arena().native_target()
	player.set_physics_process(false)
	boss.set_physics_process(false)
	suite.assert_true(_native_warning(boss), "wrong ability fixture uses actual warning")
	suite.assert_true(player.advance_action_frame(repeat_stop) and flow.training_adapter().pending_observations().is_empty(), "actual Accelerate cannot fabricate Stop conversion")
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://build/visual-evidence/p16r-training-arena/actual-boss.png")


func _test_boss_retirement(suite: RefCounted, coordinator: Node, service: RefCounted) -> void:
	var before: Dictionary = service.snapshot()
	var player: Node = coordinator.training_player()
	var boss: Node = coordinator.training_arena().native_target()
	boss.health.lose_health(boss.health.current_hp, "training-boss-death")
	suite.assert_true(boss.health.dead and not coordinator.get("_flow").training_adapter().is_live_binding(), "actual Boss death retires the exact native binding")
	coordinator.training_panel().reset_button().pressed.emit()
	suite.assert_true(coordinator.training_player() != player and coordinator.training_arena().native_target() != boss and service.snapshot() == before, "Reset safely replaces a dead Boss when every issued observation is already saved")
	boss = coordinator.training_arena().native_target()
	boss.health.lose_health(boss.health.current_hp, "training-boss-death")
	await get_tree().create_timer(0.25).timeout
	suite.assert_true(coordinator.training_arena().native_target() == null, "actual Boss retirement frees the practice actor")
	suite.assert_true(coordinator.close().ok and service.snapshot() == before, "Back safely retires an absent Boss without discarding pending progress")
	suite.assert_true(coordinator.open().ok, "training remains usable after dead Boss retirement")


func _test_second_slot(suite: RefCounted, coordinator: Node, service: RefCounted) -> void:
	suite.assert_true(coordinator.close().ok, "arena closes before independent native second-slot proof")
	var before: Dictionary = service.snapshot()
	var flow: Node = coordinator.get("_flow")
	var started: Dictionary = flow.start({"task_id": "T-05", "seed": 42, "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["rewind", "stop"]})
	suite.assert_true(started.ok, "native API binds the actual Boss with Stop in the second time slot")
	if started.ok:
		var player: Node = flow.training_player()
		var boss: Node = coordinator.training_arena().native_target()
		player.set_physics_process(false)
		boss.set_physics_process(false)
		suite.assert_true(_native_warning(boss), "second-slot proof uses the actual authored Boss warning")
		var stopped := _intents(1, Vector2.ZERO)
		stopped.time = [{"id": &"time_slot_2", "edge": &"pressed", "held_frames": 0, "mode": &"press"}]
		suite.assert_true(player.advance_action_frame(stopped) and flow.training_adapter().pending_observations().size() == 1 and flow.process_pending_observations().ok, "accepted second-slot Stop seals and physically saves the actual Boss conversion")
		suite.assert_equal(service.snapshot().chronos_shards, before.chronos_shards, "second-slot conversion preserves the earlier durable one-time claim")
	flow.close()
	coordinator.training_arena().retire_attempt()
	await get_tree().process_frame
	suite.assert_true(coordinator.open().ok, "native second-slot proof leaves the player-facing arena reusable")


func _native_warning(boss: Node) -> bool:
	for index: int in range(240):
		boss._physics_process(1.0 / 60.0)
		if boss.get_boss_ui_snapshot().phase == "WINDUP":
			return true
	return false


func _test_failed_restart(suite: RefCounted, coordinator: Node) -> void:
	suite.assert_true(coordinator.close().ok and coordinator.open("T-05").ok, "restart refusal fixture opens the actual Boss drill")
	var flow: Node = coordinator.get("_flow")
	var provider: Callable = flow.get("_boss_provider")
	flow.set("_boss_provider", Callable())
	var option: OptionButton = coordinator.training_panel().selector("character_id")
	option.select(1)
	option.item_selected.emit(1)
	suite.assert_true(not coordinator.is_training_active() and coordinator.training_player() == null and not coordinator.training_panel().visible, "unavailable requested and prior Boss restart closes the retired arena cleanly")
	flow.set("_boss_provider", provider)
	if not coordinator.is_training_active():
		suite.assert_true(coordinator.open().ok, "restored native provider can reopen after failed restart")


func _intents(frame: int, movement: Vector2) -> Dictionary:
	return {"movement": movement, "aim": Vector2.RIGHT, "dash": [], "weapon": [], "time": [], "character": [], "meta": {"source": "training-arena-test", "target_frame": frame, "frame": frame}}


func _inject_fault(stage: StringName) -> bool:
	return _fault and stage == &"before_primary_promote"


func _verify_visuals(suite: RefCounted, coordinator: Node, panel: Control) -> void:
	var locale := TranslationServer.get_locale()
	var old_scale: Variant = GameState.persistent.settings.get("text_scale", 1.0)
	var accessibility := Accessibility.new()
	add_child(accessibility)
	for language: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(language)
		for text_scale: float in [1.0, 1.5]:
			GameState.persistent.settings.text_scale = text_scale
			GameState.setting_changed.emit(&"text_scale", text_scale)
			accessibility.apply_to_tree(panel)
			for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
				get_window().size = resolution
				await get_tree().process_frame
				await get_tree().process_frame
				for control: Control in panel.focus_controls():
					suite.assert_true(Rect2(Vector2.ZERO, panel.size).encloses(control.get_global_rect()), "controller control fits actual locale/scale/viewport " + str([language, text_scale, resolution]))
					if control is OptionButton:
						var font: Font = control.get_theme_font("font")
						var text_size := font.get_string_size(control.text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size"))
						suite.assert_true(text_size.x <= control.size.x - 24, "selected native option text fits at " + str([language, text_scale, resolution]) + ": " + control.text)
				var label: Label = panel.progress_label()
				suite.assert_true(label.get_minimum_size().y <= label.size.y, "durable localized progress fits accessible status band")
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					var pixels := get_viewport().get_texture().get_image()
					var colors: Dictionary = {}
					for y: int in range(80, 296, 3):
						for x: int in range(16, 624, 3):
							var point := Vector2i(Vector2(x, y) * Vector2(pixels.get_size()) / Vector2(640, 360))
							colors[pixels.get_pixelv(point).to_rgba32()] = true
					suite.assert_true(colors.size() > 12, "actual native floor, Player and target produce nonblank pixels")
					var output := "res://build/visual-evidence/p16r-training-arena/%s-%s-%dx%d.png" % [language, str(text_scale), resolution.x, resolution.y]
					DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
					suite.assert_equal(pixels.save_png(output), OK, "actual native training screenshot retained")
	TranslationServer.set_locale(locale)
	GameState.persistent.settings.text_scale = old_scale
	GameState.setting_changed.emit(&"text_scale", old_scale)
	accessibility.queue_free()
	await get_tree().process_frame
