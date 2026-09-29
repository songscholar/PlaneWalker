extends Node

const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PRODUCER_PATHS: Array[String] = [
	"res://scripts/combat/health_component.gd",
	"res://scripts/combat/sword_weapon.gd",
	"res://scripts/combat/bow_weapon.gd",
	"res://scripts/player/player_controller.gd",
	"res://scripts/time_system/time_manager.gd",
	"res://scripts/time_system/time_rift.gd",
	"res://scripts/dungeon/room_controller.gd",
	"res://scripts/enemies/boss_chrono_warden.gd",
	"res://scripts/dungeon/encounter_runner.gd",
	"res://scripts/ui/floating_text_layer.gd",
]

class EventRecorder:
	extends RefCounted

	var damage_about_count: int = 0
	var damage_applied_count: int = 0
	var hit_confirmed_count: int = 0
	var entity_died_count: int = 0
	var attacked: Array[Dictionary] = []
	var dash_contexts: Array[Dictionary] = []
	var spawned_instance_ids: Array[int] = []
	var spawn_contexts: Array[Dictionary] = []
	var time_started: Dictionary = {}
	var time_ended: Dictionary = {}
	var time_start_contexts: Dictionary = {}
	var rejected_skill_events: int = 0

	func on_damage_about(_damage_info: Variant, _target: Node) -> void:
		damage_about_count += 1

	func on_damage_applied(_damage_info: Variant, _target: Node, _final_amount: float) -> void:
		damage_applied_count += 1

	func on_hit_confirmed(_damage_info: Variant, _target: Node, _final_amount: float) -> void:
		hit_confirmed_count += 1

	func on_entity_died(_entity: Node, _killer: Variant) -> void:
		entity_died_count += 1

	func on_player_attacked(weapon_id: StringName, context: Dictionary) -> void:
		attacked.append({"weapon_id": weapon_id, "context": context.duplicate(true)})

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

	func time_started_total() -> int:
		var total := 0
		for count: Variant in time_started.values():
			total += int(count)
		return total


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

	var damage_info := DamageInfoScript.new(
		25.0,
		DamageInfoScript.DamageType.PHYSICAL,
		self,
		self
	)
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
	var sword: Node = player.get_node("SwordWeapon")
	var bow: Node = player.get_node("BowWeapon")

	_suite.assert_true(not sword.begin_attack(false).is_empty(), "sword attack begins")
	_suite.assert_true(sword.enter_active_phase(), "sword attack publishes at active commit")
	_suite.assert_true(not sword.enter_active_phase(), "duplicate active transition is rejected")

	_suite.assert_true(bow.start_charge(), "bow charge begins")
	bow.set("_charge_time", float(bow.full_charge_time))
	_suite.assert_true(bow.release_charge(Vector2.RIGHT), "charged bow shot commits")
	bow.set("_cooldown_remaining", 0.0)
	_suite.assert_true(bow.start_charge(), "second bow charge begins")
	_suite.assert_true(not bow.release_charge(Vector2.RIGHT), "undercharged bow release is rejected")

	_suite.assert_true(player.try_action(&"dash"), "dash commits from free state")
	_suite.assert_true(not player.try_action(&"dash"), "active dash rejects a duplicate commit")

	_suite.assert_equal(_recorder.attacked.size(), 2, "sword and bow publish one committed attack each")
	if _recorder.attacked.size() == 2:
		_suite.assert_equal(_recorder.attacked[0]["weapon_id"], &"sword", "sword fact identifies the weapon")
		_suite.assert_equal(_recorder.attacked[0]["context"], {}, "sword fact has no invented context")
		_suite.assert_equal(_recorder.attacked[1]["weapon_id"], &"bow", "bow fact identifies the weapon")
		_suite.assert_close(
			float(_recorder.attacked[1]["context"].get("charge", -1.0)),
			1.0,
			"bow fact records committed charge"
		)
	_suite.assert_equal(_recorder.dash_contexts, [{}], "one committed dash publishes an empty context")

	# Let committed projectile and dash timers finish so the contract exits leak-free.
	await get_tree().create_timer(1.55).timeout
	player.queue_free()
	await get_tree().process_frame


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

	_suite.assert_equal(_recorder.time_started.get(&"time_stop", 0), 1, "successful Time Stop starts once")
	_suite.assert_equal(_recorder.time_ended.get(&"time_stop", 0), 1, "successful Time Stop ends once")
	_suite.assert_equal(_recorder.time_started.get(&"time_rift", 0), 1, "successful Time Rift starts once")
	_suite.assert_equal(_recorder.time_ended.get(&"time_rift", 0), 1, "successful Time Rift ends once")
	_suite.assert_equal(_recorder.rejected_skill_events, 0, "rejected skills publish nothing")
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
	EventBus.player_attacked.connect(_recorder.on_player_attacked)
	EventBus.player_dashed.connect(_recorder.on_player_dashed)
	EventBus.enemy_spawned.connect(_recorder.on_enemy_spawned)
	EventBus.time_skill_started.connect(_recorder.on_time_started)
	EventBus.time_skill_ended.connect(_recorder.on_time_ended)


func _disconnect_recorder() -> void:
	EventBus.damage_about_to_apply.disconnect(_recorder.on_damage_about)
	EventBus.damage_applied.disconnect(_recorder.on_damage_applied)
	EventBus.hit_confirmed.disconnect(_recorder.on_hit_confirmed)
	EventBus.entity_died.disconnect(_recorder.on_entity_died)
	EventBus.player_attacked.disconnect(_recorder.on_player_attacked)
	EventBus.player_dashed.disconnect(_recorder.on_player_dashed)
	EventBus.enemy_spawned.disconnect(_recorder.on_enemy_spawned)
	EventBus.time_skill_started.disconnect(_recorder.on_time_started)
	EventBus.time_skill_ended.disconnect(_recorder.on_time_ended)
