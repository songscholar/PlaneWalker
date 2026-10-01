extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const SwordWeaponRuntimeScript := preload(
	"res://scripts/combat/weapons/sword_weapon_runtime.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponActionCoordinatorScript := preload(
	"res://scripts/combat/weapons/weapon_action_coordinator.gd"
)
const WeaponModifierStateScript := preload(
	"res://scripts/combat/weapons/weapon_modifier_state.gd"
)
const WeaponRuntimeProfileScript := preload(
	"res://scripts/combat/weapons/weapon_runtime_profile.gd"
)

const PROFILE_CATALOG_PATH := (
	"res://data/content_packs/base/content/weapon_runtime_profiles.json"
)
const PLAYER_CONTROLLER_PATH := "res://scripts/player/player_controller.gd"
const SWORD_RUNTIME_PATH := "res://scripts/combat/weapons/sword_weapon_runtime.gd"
const M1_EXPECTED: Array[Dictionary] = [
	{
		"id": "light_1",
		"windup": 6,
		"active": 5,
		"recovery": 11,
		"cancel": 6,
		"movement": 0.55,
		"multiplier": 0.8,
		"knockback": 120.0,
		"tags": ["weapon:sword"],
		"cue_id": "sword_light_1_active",
	},
	{
		"id": "light_2",
		"windup": 8,
		"active": 5,
		"recovery": 12,
		"cancel": 6,
		"movement": 0.55,
		"multiplier": 1.0,
		"knockback": 120.0,
		"tags": ["weapon:sword"],
		"cue_id": "sword_light_2_active",
	},
	{
		"id": "light_3",
		"windup": 10,
		"active": 6,
		"recovery": 17,
		"cancel": 6,
		"movement": 0.55,
		"multiplier": 1.3,
		"knockback": 120.0,
		"tags": ["attack:finisher", "weapon:sword"],
		"cue_id": "sword_light_3_active",
	},
	{
		"id": "heavy",
		"windup": 21,
		"active": 8,
		"recovery": 27,
		"cancel": 15,
		"movement": 0.20,
		"multiplier": 2.0,
		"knockback": 260.0,
		"tags": ["attack:heavy", "weapon:sword"],
		"cue_id": "sword_heavy_active",
	},
]


class CueRecorder:
	extends RefCounted

	var cues: Array[Dictionary] = []


	func on_weapon_cue_requested(
		weapon_id: StringName,
		action_id: StringName,
		token: int,
		cue: Dictionary
	) -> void:
		cues.append({
			"weapon_id": weapon_id,
			"action_id": action_id,
			"token": token,
			"cue": cue.duplicate(true),
		})


var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_player_controller_delegates_sword_action_authority()
	await _test_runtime_plans_freeze_all_four_m1_actions()
	await _test_recovery_cancel_boundary_is_half_open()
	await _test_combo_reset_boundary_is_exactly_47_48()
	await _test_player_hitbox_and_damage_payload_parity()
	await _test_reward_hooks_preserve_m1_damage_rules()
	await _test_release_feedback_starts_once_at_active()
	_suite.finish(get_tree())


func _test_player_controller_delegates_sword_action_authority() -> void:
	var source := FileAccess.get_file_as_string(PLAYER_CONTROLLER_PATH)
	var runtime_source := FileAccess.get_file_as_string(SWORD_RUNTIME_PATH)
	_suite.assert_true(not source.is_empty(), "PlayerController source is readable")
	_suite.assert_true(not runtime_source.is_empty(), "Sword runtime source is readable")
	var retained_authority: Array[String] = []
	for legacy_symbol: String in [
		"var _active_attack_definition",
		"var _combo_window_frames_remaining",
		"var _buffered_attack_heavy",
		"func _request_attack(",
		"func _begin_attack(",
		"func _enter_attack_active(",
		"func _enter_attack_recovery(",
	]:
		if source.contains(legacy_symbol):
			retained_authority.append(legacy_symbol)
	_suite.assert_equal(
		retained_authority,
		[],
		"PlayerController delegates Sword timing, combo, and phase authority to the coordinator"
	)
	_suite.assert_true(
		not source.contains("$SwordWeapon") and not source.contains("sword_weapon."),
		"PlayerController has no Sword-specific child lookup or adapter operations"
	)
	_suite.assert_true(
		not runtime_source.contains("get_node_or_null(\"SwordWeapon\")"),
		"Sword runtime receives its payload adapter by explicit dependency injection"
	)


func _test_runtime_plans_freeze_all_four_m1_actions() -> void:
	var fixture := await _runtime_fixture()
	var runtime: RefCounted = fixture["runtime"]

	for index: int in range(M1_EXPECTED.size()):
		var expected: Dictionary = M1_EXPECTED[index]
		var semantic_action := &"weapon_secondary" if expected["id"] == "heavy" else &"weapon_primary"
		var planned: Dictionary = runtime.plan_intent(_intent(semantic_action), {})
		_suite.assert_true(bool(planned.get("ok", false)), "%s plans" % expected["id"])
		var plan: Dictionary = planned.get("plan", {})
		_assert_exact_plan(plan, expected)
		_suite.assert_equal(
			int(plan.get("combo_reset_frames", -1)),
			48,
			"%s keeps the forty-eight-frame combo reset" % expected["id"]
		)

		var token := 100 + index
		var committed: Dictionary = runtime.commit_action(plan, token)
		_suite.assert_true(bool(committed.get("ok", false)), "%s commits" % expected["id"])
		_suite.assert_true(
			runtime.on_phase_enter(plan, &"WINDUP", token).is_empty(),
			"%s windup releases no payload or cue" % expected["id"]
		)
		var active_events: Array = runtime.on_phase_enter(plan, &"ACTIVE", token)
		_suite.assert_equal(
			active_events.size(),
			2,
			"%s active releases exactly one payload and one cue" % expected["id"]
		)
		_suite.assert_true(
			_variant_contains(active_events, expected["cue_id"]),
			"%s active releases its authoritative cue" % expected["id"]
		)
		_suite.assert_true(
			runtime.on_phase_enter(plan, &"ACTIVE", token).is_empty(),
			"%s duplicate active entry releases nothing" % expected["id"]
		)
		runtime.on_phase_enter(plan, &"RECOVERY", token)
		runtime.finish_action(token)

	await _free_player(fixture["player"])


func _test_recovery_cancel_boundary_is_half_open() -> void:
	for index: int in range(M1_EXPECTED.size()):
		var expected: Dictionary = M1_EXPECTED[index]
		var fixture := await _runtime_fixture()
		var runtime: RefCounted = fixture["runtime"]
		var coordinator: RefCounted = fixture["coordinator"]
		await _prime_combo_step(runtime, index if index < 3 else 0)

		var semantic_action := &"weapon_secondary" if expected["id"] == "heavy" else &"weapon_primary"
		var committed: Dictionary = coordinator.submit_intent(_intent(semantic_action), {})
		_suite.assert_true(bool(committed.get("ok", false)), "%s commits through coordinator" % expected["id"])
		var original_token: int = coordinator.current_token()
		_advance_coordinator(
			coordinator,
			int(expected["windup"]) + int(expected["active"])
		)
		_suite.assert_equal(
			coordinator.phase_name(),
			&"RECOVERY",
			"%s reaches recovery before cancel probe" % expected["id"]
		)

		var replacement_action := &"weapon_primary" if expected["id"] == "heavy" else &"weapon_secondary"
		var buffered: Dictionary = coordinator.submit_intent(
			_intent(replacement_action, 600),
			{}
		)
		_suite.assert_true(bool(buffered.get("ok", false)), "%s buffers replacement" % expected["id"])
		_suite.assert_equal(
			str(buffered.get("code", "")),
			"BUFFERED",
			"%s replacement is buffered before cancel frame" % expected["id"]
		)
		_advance_coordinator(coordinator, int(expected["cancel"]) - 1)
		_suite.assert_equal(
			coordinator.current_token(),
			original_token,
			"%s rejects cancel before the boundary" % expected["id"]
		)
		_suite.assert_equal(
			coordinator.phase_name(),
			&"RECOVERY",
			"%s remains in recovery before the boundary" % expected["id"]
		)
		coordinator.advance_frame()
		_suite.assert_true(
			coordinator.current_token() != original_token,
			"%s accepts cancel on the boundary frame" % expected["id"]
		)
		_suite.assert_equal(
			coordinator.phase_name(),
			&"WINDUP",
			"%s replacement starts at the boundary" % expected["id"]
		)

		await _free_player(fixture["player"])


func _test_combo_reset_boundary_is_exactly_47_48() -> void:
	var frame_47_player := await _spawn_player()
	var frame_47_sword: Node = frame_47_player.get_node("SwordWeapon")
	_suite.assert_true(frame_47_player.try_action(&"attack"), "frame-47 fixture commits light one")
	_advance_player(frame_47_player, 47)
	_suite.assert_true(
		frame_47_player.try_action(&"attack"),
		"a follow-up committed within forty-seven frames is accepted"
	)
	_advance_player(frame_47_player, int(M1_EXPECTED[1]["windup"]))
	var frame_47_damage: RefCounted = frame_47_sword.hitbox.get("_active_damage_info")
	_suite.assert_true(frame_47_damage != null, "frame-47 follow-up reaches active")
	if frame_47_damage != null:
		_suite.assert_close(
			float(frame_47_damage.amount),
			30.0 * float(M1_EXPECTED[1]["multiplier"]),
			"frame forty-seven continues with light two"
		)
	await _free_player(frame_47_player)

	var frame_48_player := await _spawn_player()
	var frame_48_sword: Node = frame_48_player.get_node("SwordWeapon")
	_suite.assert_true(frame_48_player.try_action(&"attack"), "frame-48 fixture commits light one")
	_advance_player(frame_48_player, 48)
	_suite.assert_true(
		frame_48_player.try_action(&"attack"),
		"an attack committed at the forty-eight-frame boundary is accepted"
	)
	_advance_player(frame_48_player, int(M1_EXPECTED[0]["windup"]))
	var frame_48_damage: RefCounted = frame_48_sword.hitbox.get("_active_damage_info")
	_suite.assert_true(frame_48_damage != null, "frame-48 attack reaches active")
	if frame_48_damage != null:
		_suite.assert_close(
			float(frame_48_damage.amount),
			30.0 * float(M1_EXPECTED[0]["multiplier"]),
			"frame forty-eight resets to light one"
		)
	await _free_player(frame_48_player)


func _test_player_hitbox_and_damage_payload_parity() -> void:
	var light_player := await _spawn_player()
	var light_sword: Node = light_player.get_node("SwordWeapon")
	for index: int in range(3):
		var expected: Dictionary = M1_EXPECTED[index]
		await _assert_player_attack(light_player, light_sword, &"attack", expected)
	await _free_player(light_player)

	var heavy_player := await _spawn_player()
	var heavy_sword: Node = heavy_player.get_node("SwordWeapon")
	await _assert_player_attack(heavy_player, heavy_sword, &"heavy_attack", M1_EXPECTED[3])
	await _free_player(heavy_player)


func _test_reward_hooks_preserve_m1_damage_rules() -> void:
	var player := await _spawn_player()
	var sword: Node = player.get_node("SwordWeapon")
	sword.combo_finisher_multiplier_bonus = 0.35
	sword.heavy_damage_multiplier_bonus = 0.40
	sword.heavy_execute_multiplier_bonus = 0.50
	sword.heavy_execute_threshold = 0.30
	sword.low_hp_damage_multiplier_bonus = 0.45
	sword.low_hp_threshold = 0.35
	player.health.current_hp = player.health.max_hp * 0.35

	for index: int in range(3):
		var expected: Dictionary = M1_EXPECTED[index]
		_suite.assert_true(player.try_action(&"attack"), "%s reward probe commits" % expected["id"])
		_advance_player(player, int(expected["windup"]))
		var damage_info: RefCounted = sword.hitbox.get("_active_damage_info")
		_suite.assert_true(damage_info != null, "%s reward probe reaches active" % expected["id"])
		if damage_info != null:
			var finisher_bonus := 1.35 if expected["id"] == "light_3" else 1.0
			_suite.assert_close(
				float(damage_info.amount),
				30.0 * float(expected["multiplier"]) * finisher_bonus * 1.45,
				"%s applies only its eligible finisher and low-hp hooks" % expected["id"]
			)
		_advance_player(player, int(expected["active"]) + int(expected["recovery"]))

	_suite.assert_true(player.try_action(&"heavy_attack"), "rewarded heavy commits")
	_advance_player(player, int(M1_EXPECTED[3]["windup"]))
	var heavy_damage: RefCounted = sword.hitbox.get("_active_damage_info")
	_suite.assert_true(heavy_damage != null, "rewarded heavy reaches active")
	if heavy_damage != null:
		_suite.assert_close(
			float(heavy_damage.amount),
			30.0 * 2.0 * 1.40 * 1.45,
			"heavy damage and low-hp hooks multiply without pre-applying execute"
		)
		_suite.assert_true(
			heavy_damage.tags.has("talent:ruin_execute"),
			"execute reward adds its source-aware tag"
		)
		_suite.assert_equal(heavy_damage.source, sword, "execute damage retains SwordWeapon as source")
		_suite.assert_equal(heavy_damage.attacker, player, "execute damage retains Player as attacker")
		await _assert_execute_target_modifier(heavy_damage)

	await _free_player(player)


func _test_release_feedback_starts_once_at_active() -> void:
	var player := await _spawn_player()
	var coordinator: RefCounted = player.weapon_action_coordinator
	var runtime: RefCounted = player.weapon_runtime
	var recorder := CueRecorder.new()
	EventBus.weapon_cue_requested.connect(recorder.on_weapon_cue_requested)
	CombatFeedback.reset_feedback_for_test()

	var committed_facts: Array[Dictionary] = []
	coordinator.weapon_action_committed.connect(
		func(weapon_id: StringName, action_id: StringName, token: int, context: Dictionary) -> void:
			committed_facts.append({
				"weapon_id": weapon_id,
				"action_id": action_id,
				"token": token,
				"context": context.duplicate(true),
			})
	)

	_suite.assert_true(player.try_action(&"attack"), "feedback probe commits")
	_suite.assert_equal(committed_facts.size(), 1, "transaction fact publishes once at commit")
	_suite.assert_equal(recorder.cues.size(), 0, "windup publishes no typed release cue")
	_suite.assert_equal(
		_count_audio_cue(&"sword_swing"),
		0,
		"windup plays no sword release audio"
	)

	_advance_player(player, int(M1_EXPECTED[0]["windup"]) - 1)
	_suite.assert_equal(recorder.cues.size(), 0, "pre-active frame still has no release cue")
	_suite.assert_equal(_count_audio_cue(&"sword_swing"), 0, "pre-active frame remains silent")
	player.advance_action_frame()
	_suite.assert_equal(coordinator.phase_name(), &"ACTIVE", "release probe enters active exactly")
	_suite.assert_equal(recorder.cues.size(), 1, "active publishes one typed release cue")
	if recorder.cues.size() == 1:
		_suite.assert_equal(recorder.cues[0]["weapon_id"], &"sword", "release cue identifies Sword")
		_suite.assert_equal(recorder.cues[0]["action_id"], &"light_1", "release cue identifies the profile action")
	_suite.assert_equal(_count_audio_cue(&"sword_swing"), 1, "active plays release audio once")

	var snapshot: Dictionary = coordinator.snapshot()
	var duplicate_events: Array = runtime.on_phase_enter(
		snapshot.get("plan", {}),
		&"ACTIVE",
		int(snapshot.get("token", 0))
	)
	_suite.assert_true(duplicate_events.is_empty(), "duplicate active callback releases no event")
	_suite.assert_equal(recorder.cues.size(), 1, "duplicate active callback publishes no cue")
	_suite.assert_equal(_count_audio_cue(&"sword_swing"), 1, "duplicate active callback plays no audio")
	_suite.assert_equal(committed_facts.size(), 1, "phase entry does not duplicate transaction fact")

	if EventBus.weapon_cue_requested.is_connected(recorder.on_weapon_cue_requested):
		EventBus.weapon_cue_requested.disconnect(recorder.on_weapon_cue_requested)
	CombatFeedback.reset_feedback_for_test()
	await _free_player(player)


func _runtime_fixture() -> Dictionary:
	var player := await _spawn_player()
	var profile = WeaponRuntimeProfileScript.new()
	var profile_result: Dictionary = profile.configure(_profile_definition())
	_suite.assert_true(bool(profile_result.get("ok", false)), "sword_m1_v1 profile configures")
	var modifiers = WeaponModifierStateScript.new()
	_suite.assert_true(
		modifiers.configure(
			PackedStringArray(["weapon.attack_speed", "weapon.charge_rate", "weapon.damage"]),
			{
				"weapon.attack_speed": {"minimum": 0.2, "maximum": 5.0},
				"weapon.charge_rate": {"minimum": 0.0, "maximum": 5.0},
				"weapon.damage": {"minimum": 0.0, "maximum": 10.0},
			}
		),
		"Sword M1 modifiers configure"
	)
	var runtime = SwordWeaponRuntimeScript.new()
	_suite.assert_true(
		runtime.bind_adapter(player.get_node("SwordWeapon")),
		"Sword M1 runtime accepts an explicit payload adapter"
	)
	_suite.assert_true(runtime.configure(player, profile, modifiers), "Sword M1 runtime configures")
	var coordinator = WeaponActionCoordinatorScript.new()
	_suite.assert_true(coordinator.configure(runtime), "Sword M1 coordinator configures")
	return {
		"player": player,
		"profile": profile,
		"modifiers": modifiers,
		"runtime": runtime,
		"coordinator": coordinator,
	}


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	return player


func _free_player(player: Node) -> void:
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _profile_definition() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	if not parsed is Array:
		return {}
	for definition_value: Variant in parsed as Array:
		if (
			definition_value is Dictionary
			and str((definition_value as Dictionary).get("id", "")) == "sword_m1_v1"
		):
			return (definition_value as Dictionary).duplicate(true)
	return {}


func _intent(intent_id: StringName, buffer_frames: int = 12) -> Dictionary:
	return {
		"id": str(intent_id),
		"edge": "pressed",
		"buffer_frames": buffer_frames,
	}


func _assert_exact_plan(plan: Dictionary, expected: Dictionary) -> void:
	_suite.assert_equal(plan.get("weapon_id"), "sword", "%s identifies Sword" % expected["id"])
	_suite.assert_equal(plan.get("action_id"), expected["id"], "%s action id matches" % expected["id"])
	_suite.assert_close(float(plan.get("character_attack_scale", 0.0)), 1.0, "%s freezes Wanderer attack scale" % expected["id"])
	_suite.assert_close(float(plan.get("attack_speed", 0.0)), 1.0, "%s freezes Wanderer attack speed" % expected["id"])
	_suite.assert_close(float(plan.get("crit_chance", -1.0)), 0.05, "%s freezes Wanderer critical chance" % expected["id"])
	_suite.assert_close(float(plan.get("crit_multiplier", 0.0)), 1.5, "%s freezes Wanderer critical multiplier" % expected["id"])
	var payload_parameters := ((plan.get("payloads", []) as Array)[0] as Dictionary).get("parameters", {}) as Dictionary
	_suite.assert_close(float(payload_parameters.get("character_attack_scale", 0.0)), 1.0, "%s payload freezes Wanderer attack scale" % expected["id"])
	_suite.assert_close(float(payload_parameters.get("attack_speed", 0.0)), 1.0, "%s payload freezes Wanderer attack speed" % expected["id"])
	_suite.assert_close(float(payload_parameters.get("crit_chance", -1.0)), 0.05, "%s payload freezes Wanderer critical chance" % expected["id"])
	_suite.assert_close(float(payload_parameters.get("crit_multiplier", 0.0)), 1.5, "%s payload freezes Wanderer critical multiplier" % expected["id"])
	_suite.assert_equal(_phase(plan, 0).get("phase"), "WINDUP", "%s begins in windup" % expected["id"])
	_suite.assert_equal(
		_phase(plan, 0).get("duration_frames"),
		expected["windup"],
		"%s windup frames match" % expected["id"]
	)
	_suite.assert_equal(_phase(plan, 1).get("phase"), "ACTIVE", "%s has active phase" % expected["id"])
	_suite.assert_equal(
		_phase(plan, 1).get("duration_frames"),
		expected["active"],
		"%s active frames match" % expected["id"]
	)
	_suite.assert_equal(_phase(plan, 2).get("phase"), "RECOVERY", "%s has recovery" % expected["id"])
	_suite.assert_equal(
		_phase(plan, 2).get("duration_frames"),
		expected["recovery"],
		"%s recovery frames match" % expected["id"]
	)
	_suite.assert_equal(
		_phase(plan, 2).get("cancel_from_frame"),
		expected["cancel"],
		"%s cancel frame matches" % expected["id"]
	)
	for phase_index: int in range(3):
		_suite.assert_close(
			float(_phase(plan, phase_index).get("movement_multiplier", -1.0)),
			float(expected["movement"]),
			"%s phase %d movement multiplier matches" % [expected["id"], phase_index]
		)
	var payload := _payload(plan)
	_suite.assert_close(
		float(payload.get("parameters", {}).get("damage_multiplier", -1.0)),
		float(expected["multiplier"]),
		"%s damage multiplier matches" % expected["id"]
	)
	_suite.assert_close(
		float(payload.get("parameters", {}).get("knockback", -1.0)),
		float(expected["knockback"]),
		"%s knockback matches" % expected["id"]
	)
	_suite.assert_equal(
		_sorted_strings(payload.get("parameters", {}).get("tags", [])),
		_sorted_strings(expected["tags"]),
		"%s tags match" % expected["id"]
	)


func _assert_player_attack(
	player: Node,
	sword: Node,
	action_id: StringName,
	expected: Dictionary
) -> void:
	var hitbox: Area2D = sword.get_node("Hitbox")
	_suite.assert_true(player.try_action(action_id), "%s commits through Player" % expected["id"])
	_suite.assert_true(not hitbox.is_active(), "%s hitbox is closed in windup" % expected["id"])
	_suite.assert_close(
		player.get_action_movement_multiplier(),
		float(expected["movement"]),
		"%s movement multiplier matches" % expected["id"]
	)
	_advance_player(player, int(expected["windup"]) - 1)
	_suite.assert_true(not hitbox.is_active(), "%s hitbox stays closed before active" % expected["id"])
	player.advance_action_frame()
	_suite.assert_true(hitbox.is_active(), "%s hitbox opens on the first active frame" % expected["id"])
	var damage_info: RefCounted = hitbox.get("_active_damage_info")
	_suite.assert_true(damage_info != null, "%s active phase owns DamageInfo" % expected["id"])
	if damage_info != null:
		var action_identity: Dictionary = player.weapon_damage_action_identity()
		_suite.assert_true(
			not action_identity.is_empty(),
			"%s exposes its committed coordinator identity" % expected["id"]
		)
		_suite.assert_equal(
			damage_info.action_token,
			int(action_identity.get("action_token", 0)),
			"%s damage uses the committed coordinator token" % expected["id"]
		)
		_suite.assert_equal(
			damage_info.attack_generation,
			int(action_identity.get("attack_generation", 0)),
			"%s damage uses the committed action generation" % expected["id"]
		)
		_suite.assert_close(
			float(damage_info.amount),
			30.0 * float(expected["multiplier"]),
			"%s base damage remains unchanged" % expected["id"]
		)
		_suite.assert_close(
			damage_info.knockback.length(),
			float(expected["knockback"]),
			"%s knockback remains unchanged" % expected["id"]
		)
		_suite.assert_equal(
			_sorted_strings(damage_info.tags),
			_sorted_strings(expected["tags"]),
			"%s damage tags remain unchanged" % expected["id"]
		)
		_suite.assert_equal(damage_info.source, sword, "%s keeps SwordWeapon source" % expected["id"])
		_suite.assert_equal(damage_info.attacker, player, "%s keeps Player attacker" % expected["id"])
	_advance_player(player, int(expected["active"]))
	_suite.assert_true(not hitbox.is_active(), "%s hitbox closes before recovery" % expected["id"])
	_advance_player(player, int(expected["recovery"]))


func _assert_execute_target_modifier(damage_info: RefCounted) -> void:
	var target := Node2D.new()
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_hp = 200.0
	health.starts_full = false
	health.current_hp = 50.0
	target.add_child(health)
	add_child(target)
	await get_tree().process_frame
	health.current_hp = 50.0
	var base_amount := float(damage_info.amount)
	_suite.assert_close(
		health.take_damage(damage_info),
		base_amount * 1.50,
		"execute reward multiplies Heavy only at or below its target threshold"
	)
	target.queue_free()
	await get_tree().process_frame


func _prime_combo_step(runtime: RefCounted, step: int) -> void:
	for index: int in range(step):
		var plan: Dictionary = runtime.plan_intent(_intent(&"weapon_primary"), {}).get("plan", {})
		var token := 700 + index
		runtime.commit_action(plan, token)
		runtime.on_phase_enter(plan, &"ACTIVE", token)
		runtime.on_phase_enter(plan, &"RECOVERY", token)
		runtime.finish_action(token)


func _advance_player(player: Node, frames: int) -> void:
	for _frame: int in range(maxi(0, frames)):
		player.advance_action_frame()


func _advance_coordinator(coordinator: RefCounted, frames: int) -> void:
	for _frame: int in range(maxi(0, frames)):
		coordinator.advance_frame()


func _phase(plan: Dictionary, index: int) -> Dictionary:
	var phases_value: Variant = plan.get("phases", [])
	if not phases_value is Array or index < 0 or index >= (phases_value as Array).size():
		return {}
	var phase_value: Variant = (phases_value as Array)[index]
	return (phase_value as Dictionary).duplicate(true) if phase_value is Dictionary else {}


func _payload(plan: Dictionary) -> Dictionary:
	var payloads_value: Variant = plan.get("payloads", [])
	if not payloads_value is Array or (payloads_value as Array).is_empty():
		return {}
	var payload_value: Variant = (payloads_value as Array)[0]
	return (payload_value as Dictionary).duplicate(true) if payload_value is Dictionary else {}


func _variant_contains(value: Variant, expected: Variant) -> bool:
	if typeof(value) == typeof(expected) and value == expected:
		return true
	if value is Array:
		for child: Variant in value as Array:
			if _variant_contains(child, expected):
				return true
	elif value is Dictionary:
		for child: Variant in (value as Dictionary).values():
			if _variant_contains(child, expected):
				return true
	return false


func _sorted_strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value: Variant in values as Array:
			result.append(str(value))
	result.sort()
	return result


func _count_audio_cue(cue_id: StringName) -> int:
	var history_value: Variant = CombatFeedback.get_audio_contract_for_test().get("history", [])
	if not history_value is Array:
		return 0
	var count := 0
	for history_cue: Variant in history_value as Array:
		if StringName(str(history_cue)) == cue_id:
			count += 1
	return count
