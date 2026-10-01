extends Node

const ActiveItemRuntimeScript := preload("res://scripts/items/active_item_runtime.gd")
const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunRuntimeHostScript := preload("res://scripts/application/run_runtime_host.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class ActiveRegistry:
	extends RefCounted

	var definitions: Dictionary = {}

	func get_content(content_id: StringName) -> Dictionary:
		return (definitions.get(str(content_id), {}) as Dictionary).duplicate(true)


class ActiveFacade:
	extends RefCounted

	var registry: RefCounted
	var definitions: Dictionary = {}
	var fail_commit: bool = false
	var reserve_count: int = 0
	var commit_count: int = 0
	var cancel_count: int = 0
	var death_count: int = 0

	func content_registry() -> RefCounted:
		return registry

	func reserve_selection(_offer_id: String, option_id: String, _revision: int):
		reserve_count += 1
		return CommandResultScript.success(4, {
			"reservation_id": "active-reservation-%d" % reserve_count,
			"definition": (definitions.get(option_id, {}) as Dictionary).duplicate(true),
		})

	func commit_reserved_selection(_reservation_id: String):
		commit_count += 1
		if fail_commit:
			return CommandResultScript.failure(&"COMMIT_FAILED", 4)
		return CommandResultScript.success(5, {"selection_revision": 5})

	func cancel_reserved_selection(_reservation_id: String):
		cancel_count += 1
		return CommandResultScript.success(4)

	func snapshot() -> Dictionary:
		return {"run_id": "launch-active-flow", "revision": 5}

	func player_died(_context: Dictionary = {}):
		death_count += 1
		return CommandResultScript.failure(&"TERMINAL_STATE", 6)


class ActivePlayer:
	extends Node

	var runtime: RefCounted = ActiveItemRuntimeScript.new()
	var equip_count: int = 0
	var last_replace_existing: bool = false
	var fail_restore: bool = false

	func equip_active_item(definition: Dictionary, replace_existing: bool = false) -> Dictionary:
		var current: Dictionary = active_item_snapshot()
		if bool(current.get("configured", false)) and not replace_existing:
			return {"ok": false, "code": &"REPLACEMENT_REQUIRED", "context": {}}
		var candidate: RefCounted = ActiveItemRuntimeScript.new()
		if not bool(candidate.call("configure", definition.duplicate(true))):
			return {"ok": false, "code": &"INVALID_DEFINITION", "context": {}}
		runtime = candidate
		equip_count += 1
		last_replace_existing = replace_existing
		return {"ok": true, "code": &"OK", "context": {}}

	func active_item_snapshot() -> Dictionary:
		return (runtime.call("snapshot") as Dictionary).duplicate(true)

	func full_player_replay_snapshot() -> Dictionary:
		return {
			"schema_version": 5,
			"active_item_state": active_item_snapshot(),
			"sentinel": "launch-active-flow",
		}

	func restore_full_player_replay_snapshot(value: Dictionary) -> bool:
		if fail_restore or not value.get("active_item_state") is Dictionary:
			return false
		return bool(runtime.call(
			"restore_snapshot",
			(value["active_item_state"] as Dictionary).duplicate(true)
		)) and full_player_replay_snapshot() == value


class TalentPlayer:
	extends Node

	var selected_definitions: Array[Dictionary] = []
	var fail_restore: bool = false

	func character_talent_transaction_snapshot() -> Dictionary:
		return {"selected_definitions": selected_definitions.duplicate(true)}

	func install_character_talent(definition: Dictionary) -> bool:
		var talent_id := str(definition.get("id", ""))
		if talent_id.is_empty():
			return false
		for selected: Dictionary in selected_definitions:
			if str(selected.get("id", "")) == talent_id:
				return false
		selected_definitions.append(definition.duplicate(true))
		return true

	func restore_character_talent_transaction_snapshot(value: Dictionary) -> bool:
		if fail_restore or value.size() != 1 or not value.get("selected_definitions") is Array:
			return false
		selected_definitions = (value["selected_definitions"] as Array).duplicate(true)
		return character_talent_transaction_snapshot() == value


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var absolute_zero := _active_definition(
		"absolute_zero_device",
		"absolute_zero",
		"freeze_burst",
		{"radius": 180.0, "duration_frames": 180, "weakpoint_bonus": 0.5, "energy_cost": 35.0}
	)
	var paradox := _active_definition(
		"paradox_beacon",
		"paradox_beacon",
		"rewind_echo",
		{"rewind_frames": 180, "echo_damage_multiplier": 0.8, "energy_cost": 30.0}
	)
	var railshot := _active_definition(
		"railshot_module",
		"railshot",
		"piercing_barrage",
		{"pierce_bonus": 4, "damage_multiplier": 1.6, "ammo_refund": 2}
	)
	var registry := ActiveRegistry.new()
	registry.definitions = {
		"absolute_zero_device": absolute_zero,
		"paradox_beacon": paradox,
		"railshot_module": railshot,
	}
	var facade := ActiveFacade.new()
	facade.registry = registry
	facade.definitions = registry.definitions.duplicate(true)
	var player := ActivePlayer.new()
	add_child(player)
	suite.assert_true(bool(player.equip_active_item(absolute_zero).get("ok", false)), "fixture equips its original active item")

	var host = RunRuntimeHostScript.new()
	add_child(host)
	host.set("_facade", facade)
	host.set("_player", player)
	host.set("_active_run_id", "launch-active-flow")
	host.set("_published_run_id", "launch-active-flow")
	host.call("_create_choice_layer")

	var first_offer := _offer("launch-active-offer-1", 4, paradox)
	host.call("_open_offer", first_offer)
	await get_tree().process_frame
	var panel: Control = host.call("choice_panel")
	var active_button := _button(panel, "paradox_beacon")
	suite.assert_true(active_button != null, "Launch active offer renders its active item")
	if active_button != null:
		var active_meta := active_button.get_meta("active_item", {}) as Dictionary
		suite.assert_equal(active_meta.get("cooldown_frames"), 900, "Host enriches active cooldown metadata")
		suite.assert_equal(active_meta.get("replacement_required"), true, "Host detects the occupied active slot")
		active_button.pressed.emit()
	await get_tree().process_frame
	suite.assert_equal(facade.reserve_count, 0, "replacement prompt performs no reservation before confirmation")
	panel.replacement_confirm_button.pressed.emit()
	await get_tree().process_frame
	suite.assert_equal(facade.reserve_count, 1, "confirmed active selection reserves authority once")
	suite.assert_equal(facade.commit_count, 1, "confirmed active selection commits authority once")
	suite.assert_equal(player.equip_count, 2, "confirmed active selection equips once after the fixture item")
	suite.assert_true(player.last_replace_existing, "confirmed active selection uses explicit replacement")
	suite.assert_equal(
		(player.active_item_snapshot().get("definition", {}) as Dictionary).get("id"),
		"paradox_beacon",
		"successful Launch selection installs the offered active item"
	)
	suite.assert_true(not panel.visible, "successful active selection closes the ChoicePanel")

	var before_failed_commit := player.full_player_replay_snapshot()
	facade.fail_commit = true
	var failed_offer := _offer("launch-active-offer-2", 6, railshot)
	host.call("_open_offer", failed_offer)
	await get_tree().process_frame
	var failed_button := _button(panel, "railshot_module")
	if failed_button != null:
		failed_button.pressed.emit()
	await get_tree().process_frame
	panel.replacement_confirm_button.pressed.emit()
	await get_tree().process_frame
	suite.assert_equal(facade.commit_count, 2, "authority failure occurs after one staged active replacement")
	suite.assert_equal(facade.cancel_count, 1, "authority failure cancels the reservation")
	suite.assert_equal(
		player.full_player_replay_snapshot(),
		before_failed_commit,
		"authority failure restores the exact pre-selection Full Player snapshot"
	)
	suite.assert_true(panel.visible and panel.error_label.visible, "atomic rollback keeps the choice retryable")
	suite.assert_equal(facade.death_count, 0, "successful exact rollback avoids integrity termination")

	player.fail_restore = true
	var integrity_offer := _offer("launch-active-offer-3", 7, absolute_zero)
	host.call("_open_offer", integrity_offer)
	await get_tree().process_frame
	var integrity_button := _button(panel, "absolute_zero_device")
	if integrity_button != null:
		integrity_button.pressed.emit()
	await get_tree().process_frame
	panel.replacement_confirm_button.pressed.emit()
	await get_tree().process_frame
	suite.assert_equal(facade.commit_count, 3, "restore-failure fixture reaches authority commit once")
	suite.assert_equal(facade.cancel_count, 2, "restore failure still cancels the reservation")
	suite.assert_equal(
		facade.death_count,
		1,
		"failed Full Player restore enters the reward integrity fail-closed path"
	)
	suite.assert_true(
		panel.visible and panel.error_label.visible,
		"integrity termination leaves the reward surface blocked and visible"
	)

	var codex_margin := _talent_definition(
		"codex_margin",
		{"talent_pair_window_frames": 420}
	)
	var efficient_inscription := _talent_definition(
		"efficient_inscription",
		{"talent_infusion_energy_cost": 5}
	)
	var talent_registry := ActiveRegistry.new()
	talent_registry.definitions = {
		"codex_margin": codex_margin,
		"efficient_inscription": efficient_inscription,
	}
	var talent_facade := ActiveFacade.new()
	talent_facade.registry = talent_registry
	talent_facade.definitions = talent_registry.definitions.duplicate(true)
	talent_facade.fail_commit = true
	var talent_player := TalentPlayer.new()
	add_child(talent_player)
	var talent_host = RunRuntimeHostScript.new()
	add_child(talent_host)
	talent_host.set("_facade", talent_facade)
	talent_host.set("_player", talent_player)
	talent_host.set("_active_run_id", "launch-active-flow")
	talent_host.set("_published_run_id", "launch-active-flow")
	talent_host.call("_create_choice_layer")
	var talent_before := talent_player.character_talent_transaction_snapshot()
	var talent_offer := _talent_offer(
		"launch-talent-offer-1",
		8,
		codex_margin,
		efficient_inscription
	)
	talent_host.call("_open_offer", talent_offer)
	await get_tree().process_frame
	var talent_panel: Control = talent_host.call("choice_panel")
	var talent_button := _button(talent_panel, "codex_margin")
	suite.assert_true(talent_button != null, "Launch Talent offer renders its scoped option")
	if talent_button != null:
		talent_button.pressed.emit()
	await get_tree().process_frame
	suite.assert_equal(talent_facade.commit_count, 1, "Talent authority failure follows one staged install")
	suite.assert_equal(talent_facade.cancel_count, 1, "Talent authority failure cancels its reservation")
	suite.assert_equal(
		talent_player.character_talent_transaction_snapshot(),
		talent_before,
		"Talent authority failure restores the exact pre-selection snapshot"
	)
	suite.assert_true(
		talent_panel.visible and talent_panel.error_label.visible,
		"Talent rollback keeps the offer visible and retryable"
	)
	suite.assert_equal(talent_facade.death_count, 0, "exact Talent rollback avoids integrity termination")

	talent_player.fail_restore = true
	var broken_restore_offer := _talent_offer(
		"launch-talent-offer-2",
		9,
		efficient_inscription,
		codex_margin
	)
	talent_host.call("_open_offer", broken_restore_offer)
	await get_tree().process_frame
	var broken_restore_button := _button(talent_panel, "efficient_inscription")
	if broken_restore_button != null:
		broken_restore_button.pressed.emit()
	await get_tree().process_frame
	suite.assert_equal(talent_facade.commit_count, 2, "Talent restore failure reaches authority commit")
	suite.assert_equal(talent_facade.cancel_count, 2, "Talent restore failure cancels the reservation")
	suite.assert_equal(
		talent_facade.death_count,
		1,
		"Talent restore failure enters reward_transaction_integrity"
	)

	talent_host.queue_free()
	talent_player.queue_free()
	host.queue_free()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _offer(offer_id: String, revision: int, active_definition: Dictionary) -> Dictionary:
	return {
		"schema_version": 1,
		"offer_id": offer_id,
		"category": "item",
		"title_key": "UI_CHOOSE_REWARD",
		"revision": revision,
		"can_skip": false,
		"options": [
			_option(active_definition),
			_option(_passive_definition("fixture_passive_a")),
			_option(_passive_definition("fixture_passive_b")),
		],
	}


func _talent_offer(
	offer_id: String,
	revision: int,
	first: Dictionary,
	second: Dictionary
) -> Dictionary:
	return {
		"schema_version": 1,
		"offer_id": offer_id,
		"category": "talent",
		"title_key": "UI_CHOOSE_TALENT",
		"revision": revision,
		"can_skip": false,
		"options": [
			_option(first),
			_option(second),
			_option(_talent_definition(
				"dominion_cadence",
				{
					"talent_dominion_energy_cost": 45,
					"talent_dominion_cooldown_frames": 360,
				}
			)),
		],
	}


func _option(definition: Dictionary) -> Dictionary:
	var content_id := str(definition.get("id", ""))
	return {
		"option_id": content_id,
		"content_id": content_id,
		"name_key": str(definition.get("name_key", "")),
		"description_key": str(definition.get("description_key", "")),
		"archetype_key": "ARCHETYPE_%s" % str(definition.get("archetype", "GENERAL")).to_upper(),
		"role_key": "ROLE_%s" % str(definition.get("role", "utility")).to_upper(),
		"rarity": str(definition.get("rarity", "common")),
		"icon_id": str(definition.get("icon_id", "fixture_icon")),
		"effect_summary_keys": [],
	}


func _active_definition(
	content_id: String,
	handler_id: String,
	archetype: String,
	parameters: Dictionary
) -> Dictionary:
	return {
		"id": content_id,
		"category": "item",
		"availability": ["LAUNCH", "EXPANSION"],
		"name_key": "%s_NAME" % content_id.to_upper(),
		"description_key": "%s_DESC" % content_id.to_upper(),
		"tags": ["active", "risk", archetype],
		"compatibility": {"archetype_ids": [archetype]},
		"effects": {},
		"kind": "time",
		"archetype": archetype,
		"role": "risk",
		"rarity": "rare",
		"icon_id": "content_%s" % content_id,
		"item_mode": "active",
		"active_handler_id": handler_id,
		"cooldown_frames": 900,
		"active_parameters": parameters.duplicate(true),
	}


func _passive_definition(content_id: String) -> Dictionary:
	return {
		"id": content_id,
		"name_key": "%s_NAME" % content_id.to_upper(),
		"description_key": "%s_DESC" % content_id.to_upper(),
		"archetype": "freeze_burst",
		"role": "starter",
		"rarity": "common",
		"icon_id": "content_%s" % content_id,
	}


func _talent_definition(content_id: String, effects: Dictionary) -> Dictionary:
	return {
		"id": content_id,
		"category": "talent",
		"availability": ["LAUNCH", "EXPANSION"],
		"name_key": "%s_NAME" % content_id.to_upper(),
		"description_key": "%s_DESC" % content_id.to_upper(),
		"tags": ["character", "time_lord"],
		"compatibility": {"character_ids": ["time_lord"]},
		"effects": effects.duplicate(true),
		"kind": "time_lord",
		"archetype": "",
		"role": "route",
		"rarity": "common",
		"icon_id": "content_%s" % content_id,
	}


func _button(panel: Control, option_id: String) -> Button:
	var container := panel.get_node("SafeArea/Center/PanelRoot/Content/OptionsContainer")
	for child: Node in container.get_children():
		if child is Button and str((child as Button).get_meta("option_id", "")) == option_id:
			return child as Button
	return null
