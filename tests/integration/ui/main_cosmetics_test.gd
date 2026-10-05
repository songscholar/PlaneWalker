extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Registry := preload("res://scripts/content/content_registry.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Progress := preload("res://tests/support/p16_progression_fixtures.gd")
const Route := preload("res://tests/support/native_launch_route_fixture.gd")
const Catalog := preload("res://scripts/progression/cosmetic_catalog.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(GameState.activate_profile_content(registry).ok, "cosmetic UI activates actual authored Profile content")
	var service: RefCounted = GameState.profile_runtime_service()
	var save: RefCounted = GameState.get("_save_service")
	var meta: RefCounted = Factory.from_registry(registry).context.catalog
	var fixture := Progress.profile(meta)
	fixture.statistics.finished_runs = 1
	fixture.statistics.victories = 1
	fixture.discovered_items = ["absolute_zero_device"]
	suite.assert_true(save.save_profile("slot_1", "base", {"meta_profile_state": fixture}).ok and service.configure(meta, save, "slot_1", "base").ok, "eligible progress fixture is physically promoted then reloaded")
	GameState.refresh_profile_state()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	Route.freeze(main)
	var hub: Node = main.get_node("HubFlowCoordinator")
	suite.assert_true(hub.travel("hub_rift").ok and hub.open_function("gallery").ok, "actual native Hub opens authored gallery")
	suite.assert_equal(hub.view_state().cosmetics.size(), 15, "actual gallery projects all fifteen free appearances")
	var known := false
	for row: Dictionary in hub.view_state().collections.gallery:
		known = known or row.id == "absolute_zero_device" and row.owned
	suite.assert_true(known, "cosmetic collection preserves the discovered-item gallery")
	var claim := _action(hub, "cosmetic:wanderer.return")
	suite.assert_true(claim != null and not claim.disabled, "eligible free appearance has an actual native claim control")
	if claim == null:
		await _dispose(main)
		suite.finish(get_tree())
		return
	var before: Dictionary = service.payload()
	save.set_fault_injector(func(point: StringName): return point == &"before_primary_promote")
	await _key_accept(claim)
	suite.assert_equal(service.payload(), before, "native keyboard claim failure preserves exact live collection")
	suite.assert_true(hub.panel_view().error_label.visible, "failed physical claim exposes an actionable native retry state")
	save.set_fault_injector(Callable())
	var retired: Callable = claim.pressed.get_connections()[0].callable
	await _joy_accept(claim)
	suite.assert_true(service.payload().get("cosmetic_collection", {}).get("claimed_ids", []).has("wanderer.return"), "native controller retry physically claims the appearance")
	before = service.payload()
	retired.call()
	suite.assert_equal(service.payload(), before, "retired claim callback cannot replay after native projection replacement")
	var equip := _action(hub, "cosmetic:wanderer.return")
	await _joy_accept(equip)
	suite.assert_equal(service.equipped_cosmetic("wanderer"), "wanderer.return", "actual native controller equips the claimed appearance")
	suite.assert_equal(service.snapshot().statistics, fixture.statistics, "native appearance controls grant no progression")
	suite.assert_equal(service.snapshot().chronos_shards, fixture.chronos_shards, "free appearance controls spend no currency")
	for locale: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		await get_tree().process_frame
		await get_tree().process_frame
		_assert_previews(hub)
		await _capture("gallery-" + locale, hub.panel_view())
	await _joy_cancel()
	suite.assert_true(not hub.panel_view().visible and hub.is_hub_visible(), "controller Back returns from gallery to the native Hub")
	await _dispose(main)
	GameState.set("_profile_runtime", null)
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	Route.freeze(main)
	service = GameState.profile_runtime_service()
	hub = main.get_node("HubFlowCoordinator")
	suite.assert_equal(service.equipped_cosmetic("wanderer"), "wanderer.return", "fresh actual Main reloads the physical equipped appearance")
	suite.assert_true(hub.travel("hub_rift").ok and hub.open_function("gallery").ok, "cold Main restores native gallery access")
	await _joy_accept(_action(hub, "cosmetic:time_guardian.victory"))
	await _joy_accept(_action(hub, "cosmetic:time_guardian.victory"))
	suite.assert_equal(service.equipped_cosmetic("time_guardian"), "time_guardian.victory", "another owned character can claim and equip its victory route")
	await _joy_cancel()
	suite.assert_true(hub.travel("hub_council").ok and hub.open_function("gateway").ok, "native gateway remains reachable after cosmetic collection")
	var selector: OptionButton = hub.panel_view().find_child("character_id", true, false)
	for index: int in range(selector.item_count):
		if selector.get_item_metadata(index).id == "time_guardian":
			selector.select(index)
			selector.item_selected.emit(index)
			break
	var launch := _action(hub, "launch")
	suite.assert_true(launch != null and not launch.disabled, "native gateway admits the equipped character")
	await _joy_accept(launch)
	Route.freeze(main)
	var player: Node = main.get_node("CombatRoom01/Player")
	var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
	var atlas: Sprite2D = proxy.get_node("ProductionActorAtlas")
	suite.assert_equal(atlas.snapshot().cosmetic_id, "time_guardian.victory", "actual Main launch applies equipped appearance after native character configuration")
	suite.assert_equal(atlas.texture, load(Catalog.load_base().definition("time_guardian.victory").atlas_path), "actual launched Player uses the collection's exact raster texture")
	suite.assert_true(main.checkpoint_current_run().ok, "actual native checkpoint retains the equipped launch")
	var replay_before: Dictionary = player.full_player_replay_snapshot()
	await _dispose(main)
	GameState.set("_profile_runtime", null)
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	Route.freeze(main)
	hub = main.get_node("HubFlowCoordinator")
	suite.assert_true(hub.open_function("gateway").ok, "fresh actual Main exposes authenticated native resume")
	await _joy_accept(_action(hub, "resume"))
	Route.freeze(main)
	player = main.get_node("CombatRoom01/Player")
	proxy = CombatFeedback.ensure_actor_proxy_for_test(player)
	atlas = proxy.get_node("ProductionActorAtlas")
	suite.assert_equal(atlas.snapshot().cosmetic_id, "time_guardian.victory", "actual native resume restores durable equipped appearance")
	suite.assert_equal(player.full_player_replay_snapshot(), replay_before, "native cosmetic reapplication preserves exact checkpointed Player and combat domains")
	await _capture("resumed-cosmetic-player", main)
	await _dispose(main)
	CombatFeedback.reset_feedback_for_test()
	suite.finish(get_tree())


func _assert_previews(hub: Node) -> void:
	var collection: Node = hub.panel_view().find_child("CosmeticCollection", true, false)
	suite.assert_true(collection != null, "actual native gallery contains bitmap preview component")
	if collection == null:
		return
	var count := 0
	for row: Node in collection.get_children():
		var preview := row.get_node_or_null("RasterPreview") as TextureRect
		if preview == null:
			continue
		count += 1
		suite.assert_true(preview.texture is AtlasTexture and preview.texture.atlas != null and preview.texture.region == Rect2(0, 0, 48, 48), "native preview uses the actual first frame of the full gameplay raster")
		suite.assert_true(preview.get_global_rect().size == Vector2(48, 48), "appearance previews retain stable native pixel dimensions")
		for child: Node in row.get_children():
			if child is Control:
				suite.assert_true(child.position.x >= 0 and child.position.x + child.size.x <= row.size.x + 1.0, "translated preview row fits its native container without overlap")
	suite.assert_equal(count, 15, "every authored appearance has a real native raster preview")


func _capture(name: String, target: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var directory := "res://build/visual-evidence/p23-cosmetics"
	DirAccess.make_dir_recursive_absolute(directory)
	var size := "%dx%d" % [image.get_width(), image.get_height()]
	image.save_png(directory + "/" + name + "-" + size + ".png")
	if name.begins_with("gallery"):
		var preview := target.find_child("RasterPreview", true, false) as TextureRect
		if preview == null:
			return
		var scale: Vector2 = Vector2(image.get_size()) / get_viewport().get_visible_rect().size
		var rect := preview.get_global_rect()
		var colors: Dictionary = {}
		for y: int in range(int(rect.position.y * scale.y), int(rect.end.y * scale.y)):
			for x: int in range(int(rect.position.x * scale.x), int(rect.end.x * scale.x)):
				colors[image.get_pixel(x, y).to_rgba32()] = true
		suite.assert_true(colors.size() >= 8, "actual graphical preview contains raster pixels rather than a blank surface")


func _action(hub: Node, id: String) -> Button:
	for control: Control in hub.panel_view().action_controls():
		if str(control.get_meta("action_id", "")) == id:
			return control as Button
	return null


func _key_accept(button: Button) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_true(button != null and not button.disabled, "keyboard command targets an available native control")
	if button == null or button.disabled:
		return
	button.grab_focus()
	await get_tree().process_frame
	suite.assert_equal(get_viewport().gui_get_focus_owner(), button, "keyboard command owns settled native focus")
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _joy_accept(button: Button) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_true(button != null and not button.disabled, "controller command targets an available native control")
	if button == null or button.disabled:
		return
	button.grab_focus()
	await get_tree().process_frame
	suite.assert_equal(get_viewport().gui_get_focus_owner(), button, "controller command owns settled native focus")
	await _joy_button(JOY_BUTTON_A)


func _joy_cancel() -> void:
	await _joy_button(JOY_BUTTON_B)


func _joy_button(index: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _dispose(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
