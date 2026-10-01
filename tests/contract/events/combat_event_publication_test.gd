extends Node

const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const CharacterActionCoordinatorScript := preload(
	"res://scripts/player/characters/character_action_coordinator.gd"
)

const PRODUCER_PATHS: Array[String] = [
	"res://scripts/combat/health_component.gd",
	"res://scripts/combat/sword_weapon.gd",
	"res://scripts/combat/bow_weapon.gd",
	"res://scripts/combat/weapons/weapon_runtime.gd",
	"res://scripts/combat/weapons/sword_weapon_runtime.gd",
	"res://scripts/combat/weapons/bow_weapon_runtime.gd",
	"res://scripts/combat/weapons/gun_weapon_runtime.gd",
	"res://scripts/combat/weapons/staff_weapon_runtime.gd",
	"res://scripts/combat/weapons/gauntlets_weapon_runtime.gd",
	"res://scripts/player/player_controller.gd",
	"res://scripts/player/characters/character_action_coordinator.gd",
	"res://scripts/time_system/time_manager.gd",
	"res://scripts/time_system/time_rift.gd",
	"res://scripts/dungeon/room_controller.gd",
	"res://scripts/enemies/boss_chrono_warden.gd",
	"res://scripts/dungeon/encounter_runner.gd",
	"res://scripts/ui/floating_text_layer.gd",
]

class RewindRecorderStub:
	extends Node

	var _snapshot_available := true
	var commit_succeeds := true
	var commit_calls: int = 0
	var rollback_calls: int = 0
	var legacy_restore_calls: int = 0

	func has_snapshot() -> bool:
		return _snapshot_available

	func prepare_rewind_transaction() -> Dictionary:
		return {
			"schema_version": 1,
			"ticket_id": 1,
			"target_snapshot": {"position": Vector2.ZERO},
		} if _snapshot_available else {}

	func commit_rewind_transaction(_ticket: Dictionary) -> bool:
		commit_calls += 1
		if not _snapshot_available or not commit_succeeds:
			return false
		_snapshot_available = false
		EventBus.time_skill_started.emit(&"time_rewind", {})
		EventBus.time_skill_ended.emit(&"time_rewind", {})
		return true

	func rollback_rewind_transaction(_ticket: Dictionary) -> Dictionary:
		rollback_calls += 1
		return {"ok": true, "code": &"ROLLED_BACK"}

	func restore_player_state(_snapshot: Dictionary) -> bool:
		legacy_restore_calls += 1
		return _snapshot_available

	func consume_oldest_snapshot() -> Dictionary:
		if not _snapshot_available:
			return {}
		_snapshot_available = false
		return {"position": Vector2.ZERO}

	func clear_snapshots() -> void:
		_snapshot_available = false


class EventRecorder:
	extends RefCounted

	var damage_about_count: int = 0
	var damage_applied_count: int = 0
	var hit_confirmed_count: int = 0
	var entity_died_count: int = 0
	var weapon_cues: Array[Dictionary] = []
	var dash_contexts: Array[Dictionary] = []
	var spawned_instance_ids: Array[int] = []
	var spawn_contexts: Array[Dictionary] = []
	var time_started: Dictionary = {}
	var time_ended: Dictionary = {}
	var time_start_contexts: Dictionary = {}
	var rejected_skill_events: int = 0
	var weapon_mastery_facts: Array[Dictionary] = []

	func on_damage_about(_damage_info: Variant, _target: Node) -> void:
		damage_about_count += 1

	func on_damage_applied(_damage_info: Variant, _target: Node, _final_amount: float) -> void:
		damage_applied_count += 1

	func on_hit_confirmed(_damage_info: Variant, _target: Node, _final_amount: float) -> void:
		hit_confirmed_count += 1

	func on_entity_died(_entity: Node, _killer: Variant) -> void:
		entity_died_count += 1

	func on_weapon_cue_requested(
		weapon_id: StringName,
		action_id: StringName,
		token: int,
		cue: Dictionary
	) -> void:
		weapon_cues.append({
			"weapon_id": weapon_id,
			"action_id": action_id,
			"token": token,
			"cue": cue.duplicate(true),
		})

	func on_player_dashed(context: Dictionary) -> void:
		dash_contexts.append(context.duplicate(true))

	func on_enemy_spawned(enemy: Node, context: Dictionary) -> void:
		if enemy == null or not is_instance_valid(enemy):
			return
		spawned_instance_ids.append(enemy.get_instance_id())
		spawn_contexts.append(context.duplicate(true))

	func on_time_started(skill_id: StringName, context: Dictionary) -> void:
		time_started[skill_id] = int(time_started.get(skill_id, 0)) + 1
		var contexts: Array = time_start_contexts.get(skill_id, [])
		contexts.append(context.duplicate(true))
		time_start_contexts[skill_id] = contexts

	func on_time_ended(skill_id: StringName, _context: Dictionary) -> void:
		time_ended[skill_id] = int(time_ended.get(skill_id, 0)) + 1

	func on_weapon_mastery_confirmed(
		weapon_id: StringName,
		mastery_family: StringName,
		mastery_id: StringName,
		action_id: StringName,
		token: int,
		generation: int,
		target_id: int,
		context: Dictionary
	) -> void:
		weapon_mastery_facts.append({
			"weapon_id": weapon_id,
			"mastery_family": mastery_family,
			"mastery_id": mastery_id,
			"action_id": action_id,
			"token": token,
			"generation": generation,
			"target_id": target_id,
			"context": context.duplicate(true),
		})

	func time_started_total() -> int:
		var total := 0
		for count: Variant in time_started.values():
			total += int(count)
		return total


class MasteryRuntimeStub extends RefCounted:
	var revision: int = 0

	func advance_frame(_context: Dictionary) -> Array[Dictionary]:
		return []

	func snapshot() -> Dictionary:
		return {"revision": revision}

	func can_restore_snapshot(value: Dictionary) -> bool:
		return value.size() == 1 and typeof(value.get("revision")) == TYPE_INT

	func restore_snapshot(value: Dictionary) -> bool:
		if not can_restore_snapshot(value):
			return false
		revision = int(value["revision"])
		return true

	func reset_runtime_state(_reason: StringName) -> void:
		revision += 1

	func on_weapon_mastery_confirmed(_context: Dictionary) -> Array[Dictionary]:
		revision += 1
		return []


var _suite
var _recorder := EventRecorder.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_connect_recorder()
	_test_producers_have_no_generic_publication()
	await _test_damage_and_death_publish_once()
	await _test_committed_player_actions_publish_once()
	_test_weapon_mastery_fact_publishes_once()
	await _test_time_skill_lifecycle_and_rejections()
	await _test_summoned_instances_publish_once()
	_disconnect_recorder()
	_suite.finish(get_tree())


func _test_producers_have_no_generic_publication() -> void:
	for path: String in PRODUCER_PATHS:
		var file := FileAccess.open(path, FileAccess.READ)
		_suite.assert_true(file != null, "%s is readable" % path)
		if file == null:
			continue
		var source := file.get_as_text()
		_suite.assert_true(
			not source.contains("EventBus.publish("),
			"%s has no paired generic publication" % path
		)


func _test_damage_and_death_publish_once() -> void:
	var entity := Node2D.new()
	var health := HealthComponentScript.new()
	health.name = "HealthComponent"
	health.max_hp = 20.0
	entity.add_child(health)
	add_child(entity)
	await get_tree().process_frame

	var damage_info := DamageInfoScript.from_plan({
		"run_id": "combat-event-test",
		"target_id": "event-test-target",
		"hostile_source_id": "event-test-source",
		"attack_generation": 1,
		"hit_index": 0,
		"action_token": 1,
		"amount": 25.0,
		"damage_type": DamageInfoScript.DamageType.PHYSICAL,
		"source": self,
		"attacker": self,
		"can_crit": false,
		"crit_chance": 0.0,
		"crit_multiplier": 1.5,
		"knockback": Vector2.ZERO,
		"tags": ["test:lethal"],
		"source_generation": 1,
		"control_effect": {},
	})
	_suite.assert_close(health.take_damage(damage_info), 25.0, "lethal hit commits its calculated damage")
	_suite.assert_close(health.take_damage(damage_info), 0.0, "dead target rejects duplicate damage")
	_suite.assert_equal(_recorder.damage_about_count, 1, "one hit announces one pending damage")
	_suite.assert_equal(_recorder.damage_applied_count, 1, "one hit applies damage once")
	_suite.assert_equal(_recorder.hit_confirmed_count, 1, "one hit confirms once")
	_suite.assert_equal(_recorder.entity_died_count, 1, "lethal hit publishes one death")
	entity.queue_free()
	await get_tree().process_frame


func _test_committed_player_actions_publish_once() -> void:
	var player := PlayerScene.instantiate()
	add_child(player)
	await get_tree().process_frame
	var bow: Node = player.get_node("BowWeapon")

	_suite.assert_true(player.try_action(&"attack"), "sword attack begins through the coordinator")
	for _frame: int in range(6):
		player.advance_action_frame()
	var sword_snapshot: Dictionary = player.weapon_action_coordinator.snapshot()
	_suite.assert_equal(sword_snapshot.get("phase"), "ACTIVE", "sword attack publishes at active commit")
	_suite.assert_true(
		player.weapon_runtime.on_phase_enter(
			sword_snapshot.get("plan", {}),
			&"ACTIVE",
			int(sword_snapshot.get("token", 0))
		).is_empty(),
		"duplicate active transition is rejected"
	)
	player.cancel_transient_actions()

	_suite.assert_true(
		player.configure_loadout({
			"schema_version": 1,
			"milestone": "NEXT",
			"character_id": "wanderer",
			"weapon_id": "bow",
			"enabled_time_skills": ["stop", "rewind"],
			"difficulty": "normal",
			"seed": 20260930,
		}),
		"bow publication fixture uses the profile-backed player path"
	)
	for legacy_method: StringName in [
		&"start_charge",
		&"release_charge",
		&"cancel_charge",
		&"is_charging",
		&"get_charge_ratio",
		&"get_cooldown_remaining",
	]:
		_suite.assert_true(
			not bow.has_method(legacy_method),
			"Bow adapter retires legacy action clock method %s" % legacy_method
		)
	var bow_source := FileAccess.get_file_as_string("res://scripts/combat/bow_weapon.gd")
	var player_source := FileAccess.get_file_as_string("res://scripts/player/player_controller.gd")
	var event_bus_source := FileAccess.get_file_as_string("res://autoload/event_bus.gd")
	_suite.assert_true(not bow_source.contains("func _process("), "Bow adapter owns no frame clock")
	_suite.assert_true(
		not bow_source.contains("EventBus.player_attacked.emit"),
		"Bow adapter cannot bypass Player event publication"
	)
	_suite.assert_true(
		not player_source.contains("player_attacked"),
		"PlayerController retires the legacy player_attacked publication"
	)
	_suite.assert_true(
		not event_bus_source.contains("player_attacked"),
		"EventBus retires the legacy player_attacked signal"
	)

	_suite.assert_true(player.try_action(&"ranged_attack"), "bow press commits through Player and Coordinator")
	var hold_snapshot: Dictionary = player.weapon_presentation_snapshot()
	var bow_token := int(hold_snapshot.get("token", 0))
	_suite.assert_equal(hold_snapshot.get("phase"), "HOLD", "bow press enters coordinator HOLD")
	for _frame: int in range(9):
		player.advance_action_frame()
	_suite.assert_true(player.try_action(&"ranged_release"), "charged bow release resolves the same HOLD token")
	_suite.assert_equal(
		int(player.weapon_presentation_snapshot().get("token", 0)),
		bow_token,
		"bow release preserves the committed action token"
	)
	player.advance_action_frame()
	var bow_active: Dictionary = player.weapon_action_coordinator.snapshot()
	_suite.assert_equal(bow_active.get("phase"), "ACTIVE", "bow release publishes only when ACTIVE begins")
	_suite.assert_true(
		player.weapon_runtime.on_phase_enter(
			bow_active.get("plan", {}),
			&"ACTIVE",
			int(bow_active.get("token", 0))
		).is_empty(),
		"duplicate Bow ACTIVE transition cannot publish a second payload or cue"
	)
	player.cancel_transient_actions()

	var cues_before_undercharge := _recorder.weapon_cues.size()
	_suite.assert_true(
		not player.try_action(&"ranged_attack"),
		"cancelling the active arrow cannot bypass the committed Bow cooldown"
	)
	for _frame: int in range(20):
		player.advance_action_frame()
	_suite.assert_true(player.try_action(&"ranged_attack"), "second bow press begins a fresh HOLD")
	_suite.assert_true(not player.try_action(&"ranged_release"), "undercharged bow release is rejected")
	_suite.assert_equal(
		_recorder.weapon_cues.size(),
		cues_before_undercharge,
		"undercharged release publishes no weapon cue"
	)

	_suite.assert_true(player.try_action(&"dash"), "dash commits from free state")
	_suite.assert_true(not player.try_action(&"dash"), "active dash rejects a duplicate commit")

	_suite.assert_equal(_recorder.weapon_cues.size(), 2, "sword and bow publish one typed release cue each")
	if _recorder.weapon_cues.size() == 2:
		_suite.assert_equal(_recorder.weapon_cues[0]["weapon_id"], &"sword", "sword cue identifies the weapon")
		_suite.assert_equal(
			str(_recorder.weapon_cues[0].get("action_id", "")),
			"light_1",
			"sword release cue identifies the profile action"
		)
		_suite.assert_true(
			int(_recorder.weapon_cues[0].get("token", 0)) > 0,
			"sword release cue carries its coordinator token"
		)
		_suite.assert_equal(_recorder.weapon_cues[1]["weapon_id"], &"bow", "bow cue identifies the weapon")
		_suite.assert_equal(
			str(_recorder.weapon_cues[1].get("action_id", "")),
			"candidate_draw",
			"bow release cue identifies the profile action"
		)
		_suite.assert_equal(
			int(_recorder.weapon_cues[1].get("token", 0)),
			bow_token,
			"bow release cue carries the shared coordinator token"
		)
		_suite.assert_true(
			not _recorder.weapon_cues[1]["cue"].has("charge"),
			"bow release cue no longer exposes legacy adapter charge state"
		)
	_suite.assert_equal(_recorder.dash_contexts, [{}], "one committed dash publishes an empty context")

	# Let committed projectile and dash timers finish so the contract exits leak-free.
	await get_tree().create_timer(1.55).timeout
	player.queue_free()
	await get_tree().process_frame


func _test_weapon_mastery_fact_publishes_once() -> void:
	var coordinator: RefCounted = CharacterActionCoordinatorScript.new()
	_suite.assert_true(coordinator.call("configure", MasteryRuntimeStub.new()), "mastery producer configures")
	var generation := int(coordinator.call("generation"))
	var context := {"pellet": 0, "nested": {"value": 7}}
	var fact := {
		"weapon_id": &"gun",
		"mastery_family": &"gun",
		"mastery_id": &"gun_magazine_finisher",
		"action_id": &"normal_shot",
		"generation": generation,
		"action_token": 77,
		"target_id": 9001,
		"context": context,
	}
	var before_count := _recorder.weapon_mastery_facts.size()
	_suite.assert_true(coordinator.call("confirm_weapon_mastery", fact), "accepted mastery publishes")
	_suite.assert_true(not coordinator.call("confirm_weapon_mastery", fact), "duplicate mastery rejects")
	var echo_fact := fact.duplicate(true)
	echo_fact.action_token = 78
	(echo_fact.context as Dictionary).is_echo = true
	_suite.assert_true(not coordinator.call("confirm_weapon_mastery", echo_fact), "echo mastery rejects")
	_suite.assert_equal(
		_recorder.weapon_mastery_facts.size(),
		before_count + 1,
		"accepted mastery publishes exactly one typed fact"
	)
	if _recorder.weapon_mastery_facts.size() == before_count + 1:
		var published: Dictionary = _recorder.weapon_mastery_facts[before_count]
		_suite.assert_equal(published, {
			"weapon_id": &"gun",
			"mastery_family": &"gun",
			"mastery_id": &"gun_magazine_finisher",
			"action_id": &"normal_shot",
			"token": 77,
			"generation": generation,
			"target_id": 9001,
			"context": {"pellet": 0, "nested": {"value": 7}},
		}, "typed mastery payload is exact")
	context.nested.value = 99
	_suite.assert_equal(
		(_recorder.weapon_mastery_facts[before_count] as Dictionary).context.nested.value,
		7,
		"caller mutation cannot rewrite the published mastery fact"
	)


func _test_time_skill_lifecycle_and_rejections() -> void:
	var player := PlayerScene.instantiate()
	add_child(player)
	await get_tree().process_frame
	var manager: Node = player.get_node("TimeManager")
	manager.time_stop_duration = 0.02
	manager.time_rift_duration = 0.02

	_suite.assert_true(manager.try_time_stop(), "Time Stop commits")
	var starts_before_rejection := _recorder.time_started_total()
	_suite.assert_true(not manager.try_time_stop(), "cooldown rejects duplicate Time Stop")
	_recorder.rejected_skill_events += _recorder.time_started_total() - starts_before_rejection
	await get_tree().create_timer(0.05).timeout

	var rift_position := Vector2(48.0, 72.0)
	_suite.assert_true(manager.try_time_rift(rift_position), "Time Rift commits")
	await get_tree().create_timer(0.08).timeout

	manager.reset_runtime_state()
	var rewind_recorder := RewindRecorderStub.new()
	player.add_child(rewind_recorder)
	_suite.assert_true(manager.try_rewind(rewind_recorder), "Time Rewind commits")

	manager.reset_runtime_state()
	manager.time_accelerate_duration = 0.02
	_suite.assert_true(manager.try_time_accelerate(), "Time Accelerate commits")
	await get_tree().create_timer(0.05).timeout

	_suite.assert_equal(_recorder.time_started.get(&"time_stop", 0), 1, "successful Time Stop starts once")
	_suite.assert_equal(_recorder.time_ended.get(&"time_stop", 0), 1, "successful Time Stop ends once")
	_suite.assert_equal(_recorder.time_started.get(&"time_rewind", 0), 1, "successful Time Rewind starts once")
	_suite.assert_equal(_recorder.time_ended.get(&"time_rewind", 0), 1, "successful Time Rewind ends once")
	_suite.assert_equal(_recorder.time_started.get(&"time_rift", 0), 1, "successful Time Rift starts once")
	_suite.assert_equal(_recorder.time_ended.get(&"time_rift", 0), 1, "successful Time Rift ends once")
	_suite.assert_equal(_recorder.time_started.get(&"time_accelerate", 0), 1, "successful Time Accelerate starts once")
	_suite.assert_equal(_recorder.time_ended.get(&"time_accelerate", 0), 1, "successful Time Accelerate ends once")
	_suite.assert_equal(_recorder.rejected_skill_events, 0, "rejected skills publish nothing")
	_suite.assert_equal(rewind_recorder.commit_calls, 1, "Time Rewind delegates one atomic commit to its recorder")
	_suite.assert_equal(rewind_recorder.rollback_calls, 0, "successful Time Rewind needs no explicit rollback")
	_suite.assert_equal(rewind_recorder.legacy_restore_calls, 0, "Time Rewind retires the legacy direct restore path")

	manager.reset_runtime_state()
	var rejected_rewind := RewindRecorderStub.new()
	rejected_rewind.commit_succeeds = false
	player.add_child(rejected_rewind)
	var rewind_starts_before_rejection := int(_recorder.time_started.get(&"time_rewind", 0))
	var rewind_ends_before_rejection := int(_recorder.time_ended.get(&"time_rewind", 0))
	_suite.assert_true(not manager.try_rewind(rejected_rewind), "failed atomic Rewind commit is rejected")
	_suite.assert_equal(rejected_rewind.commit_calls, 1, "failed Time Rewind attempts one recorder commit")
	_suite.assert_equal(
		int(_recorder.time_started.get(&"time_rewind", 0)),
		rewind_starts_before_rejection,
		"failed Rewind commit publishes no start event"
	)
	_suite.assert_equal(
		int(_recorder.time_ended.get(&"time_rewind", 0)),
		rewind_ends_before_rejection,
		"failed Rewind commit publishes no end event"
	)
	var rift_contexts: Array = _recorder.time_start_contexts.get(&"time_rift", [])
	_suite.assert_equal(rift_contexts.size(), 1, "Time Rift has one start context")
	if rift_contexts.size() == 1:
		_suite.assert_equal(rift_contexts[0], {"position": rift_position}, "Time Rift fact records its committed position")

	player.queue_free()
	await get_tree().process_frame


func _test_summoned_instances_publish_once() -> void:
	var player := PlayerScene.instantiate()
	add_child(player)
	var enemies := Node2D.new()
	add_child(enemies)
	var boss := BossScene.instantiate()
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	enemies.add_child(boss)
	boss.enemy_summoned.connect(_acknowledge_summon_for_test)
	await get_tree().process_frame

	var before := _recorder.spawned_instance_ids.size()
	boss.force_summon_fragments_for_test()
	await get_tree().process_frame
	var published_ids := _recorder.spawned_instance_ids.slice(before)
	var published_contexts := _recorder.spawn_contexts.slice(before)
	_suite.assert_equal(published_ids.size(), int(boss.fragment_count), "boss publishes every committed summon")
	_suite.assert_equal(
		published_ids.size(),
		_unique_count(published_ids),
		"each entity spawns once"
	)
	for context: Dictionary in published_contexts:
		_suite.assert_equal(context, {"boss": false, "summoned": true}, "summon fact has frozen spawn context")

	enemies.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _acknowledge_summon_for_test(enemy: Node) -> void:
	enemy.set_meta("encounter_counted", true)


func _unique_count(values: Array[int]) -> int:
	var seen: Dictionary = {}
	for value: int in values:
		seen[value] = true
	return seen.size()


func _connect_recorder() -> void:
	EventBus.damage_about_to_apply.connect(_recorder.on_damage_about)
	EventBus.damage_applied.connect(_recorder.on_damage_applied)
	EventBus.hit_confirmed.connect(_recorder.on_hit_confirmed)
	EventBus.entity_died.connect(_recorder.on_entity_died)
	EventBus.weapon_cue_requested.connect(_recorder.on_weapon_cue_requested)
	EventBus.player_dashed.connect(_recorder.on_player_dashed)
	EventBus.enemy_spawned.connect(_recorder.on_enemy_spawned)
	EventBus.time_skill_started.connect(_recorder.on_time_started)
	EventBus.time_skill_ended.connect(_recorder.on_time_ended)
	EventBus.weapon_mastery_confirmed.connect(_recorder.on_weapon_mastery_confirmed)


func _disconnect_recorder() -> void:
	EventBus.damage_about_to_apply.disconnect(_recorder.on_damage_about)
	EventBus.damage_applied.disconnect(_recorder.on_damage_applied)
	EventBus.hit_confirmed.disconnect(_recorder.on_hit_confirmed)
	EventBus.entity_died.disconnect(_recorder.on_entity_died)
	EventBus.weapon_cue_requested.disconnect(_recorder.on_weapon_cue_requested)
	EventBus.player_dashed.disconnect(_recorder.on_player_dashed)
	EventBus.enemy_spawned.disconnect(_recorder.on_enemy_spawned)
	EventBus.time_skill_started.disconnect(_recorder.on_time_started)
	EventBus.time_skill_ended.disconnect(_recorder.on_time_ended)
	EventBus.weapon_mastery_confirmed.disconnect(_recorder.on_weapon_mastery_confirmed)
