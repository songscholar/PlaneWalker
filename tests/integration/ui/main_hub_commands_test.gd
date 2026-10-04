extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Registry := preload("res://scripts/content/content_registry.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(GameState.activate_profile_content(registry).ok, "native commands require actual-content Profile")
	var service: RefCounted = GameState.profile_runtime_service()
	var save: RefCounted = GameState.get("_save_service")
	var catalog: RefCounted = Factory.from_registry(registry).context.catalog
	var fixture: Dictionary = service.snapshot()
	fixture.chronos_shards = 4000
	fixture.existential_imprints = 500
	fixture.unlocked_nodes = ["F-01", "F-02", "F-03", "F-04"]
	suite.assert_true(save.save_profile("slot_1", "base", {"meta_profile_state": fixture}).ok, "rich Profile fixture is physically saved")
	suite.assert_true(service.configure(catalog, save, "slot_1", "base").ok, "actual service reloads the physical fixture")
	GameState.refresh_profile_state()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var hub: Node = main.get_node_or_null("HubFlowCoordinator")
	suite.assert_true(hub != null, "production Hub exists for native commands")
	if hub == null:
		main.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	suite.assert_true(hub.open_function("council").ok, "native council opens")
	var node_id := ""
	var cost := 0
	for row: Dictionary in hub.view_state().nodes:
		if row.available:
			node_id = str(row.id)
			cost = int(row.cost.chronos_shards)
			break
	var purchase := _action(hub, node_id)
	suite.assert_true(purchase != null and not purchase.disabled, "eligible authored node has a native purchase control")
	var before: Dictionary = service.snapshot()
	save.set_fault_injector(func(point: StringName): return point == &"before_primary_promote")
	if purchase != null:
		purchase.pressed.emit()
	suite.assert_equal(service.snapshot(), before, "failed native purchase leaves full Profile unchanged")
	suite.assert_true(hub.panel_view().error_label.visible, "failed purchase exposes a native retry state")
	save.set_fault_injector(Callable())
	if purchase != null:
		var retired: Callable = purchase.pressed.get_connections()[0].callable
		purchase.pressed.emit()
		retired.call()
	suite.assert_true(service.snapshot().unlocked_nodes.has(node_id), "native purchase persists exact node ownership")
	suite.assert_equal(service.snapshot().chronos_shards, 4000 - cost, "native purchase spends exact authored cost once")
	suite.assert_equal(GameState.persistent.meta_profile_state, service.snapshot(), "native purchase refreshes compatibility mirror")
	suite.assert_true(hub.travel("hub_craft").ok and hub.open_function("forge").ok, "actual forge opens after council")
	var upgrade := _action(hub, "upgrade:sword")
	suite.assert_true(upgrade != null and not upgrade.disabled, "actual sword upgrade is available")
	if upgrade != null:
		upgrade.pressed.emit()
	suite.assert_equal(service.forge_projection("sword").forge_level, 1, "native forge control persists level one")
	suite.assert_true(hub.open_function("meditation").ok, "actual build library opens")
	var input: LineEdit = hub.panel_view().find_child("BuildName", true, false)
	input.text = "Native Rift Sword"
	var add_build := _action(hub, "build_save")
	if add_build != null:
		add_build.pressed.emit()
	suite.assert_equal(service.snapshot().build_library.size(), 1, "native naming and save persist one owned build")
	if not service.snapshot().build_library.is_empty():
		var id: String = service.snapshot().build_library[0].id
		var select := _action(hub, "build_select:" + id)
		if select != null:
			select.pressed.emit()
		suite.assert_equal(hub.view_state().loadout.selected.weapon_id, "sword", "native build selection resolves the real owned loadout")
		var remove := _action(hub, "build_remove:" + id)
		if remove != null:
			remove.pressed.emit()
		suite.assert_true(service.snapshot().build_library.is_empty(), "native remove persists library deletion")
	suite.assert_true(hub.travel("hub_council").ok and hub.open_function("gateway").ok, "actual gateway opens for revision recovery")
	var updated: Dictionary = service.execute_tutorial({"command_id": "native-hub-review-suppress", "kind": "tutorial_suppress", "suppressed": true}, int(service.snapshot().revision))
	suite.assert_true(updated.ok, "actual lesson service independently saves a Profile revision")
	suite.assert_true(not hub.close_panel().ok, "stale native command cannot change the current Profile")
	suite.assert_equal(hub.panel_view().view_state().revision, service.snapshot().revision, "stale refusal refreshes the native projection")
	suite.assert_true(hub.close_panel().ok, "refreshed native back command recovers without restarting Main")
	var durable := Service.new()
	suite.assert_true(durable.configure(catalog, save, "slot_1", "base").ok and durable.snapshot() == service.snapshot(), "native command results reload from actual promoted JSON")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _action(hub: Node, id: String) -> Button:
	for control: Control in hub.panel_view().action_controls():
		if str(control.get_meta("action_id", "")) == id:
			return control as Button
	return null
