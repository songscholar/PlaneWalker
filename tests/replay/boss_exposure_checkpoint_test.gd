extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunRuntimeHostScript := preload("res://scripts/application/run_runtime_host.gd")
const RoomControllerScript := preload("res://scripts/dungeon/room_controller.gd")
const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")


class FaultingBossParticipant:
	extends Node

	var source_id: StringName = &""
	var next_generation_floor: int = 1
	var state: Dictionary = {}
	var replay_authority: RefCounted
	var fail_next_restore: bool = false

	func hostile_identity_snapshot() -> Dictionary:
		return {
			"hostile_source_id": source_id,
			"next_generation_floor": next_generation_floor,
			"active": true,
		}

	func restore_hostile_identity_snapshot(value: Dictionary) -> bool:
		if (
			value.size() != 3
			or str(value.get("hostile_source_id", "")).strip_edges().is_empty()
			or int(value.get("next_generation_floor", 0)) <= 0
			or not bool(value.get("active", false))
		):
			return false
		source_id = StringName(str(value["hostile_source_id"]))
		next_generation_floor = int(value["next_generation_floor"])
		return true

	func character_boss_exposure_snapshot() -> Dictionary:
		return state.duplicate(true)

	func character_boss_exposure_identity() -> Dictionary:
		return (state.get("identity", {}) as Dictionary).duplicate(true)

	func configure_character_boss_exposure_replay_authority(authority: RefCounted) -> bool:
		if authority == null:
			return false
		if replay_authority != null:
			return replay_authority == authority
		replay_authority = authority
		return true

	func can_restore_character_boss_exposure_replay_snapshot(
		value: Dictionary,
		authority: RefCounted
	) -> bool:
		return authority != null and authority == replay_authority and not value.is_empty()

	func restore_character_boss_exposure_replay_snapshot(
		value: Dictionary,
		authority: RefCounted
	) -> bool:
		if not can_restore_character_boss_exposure_replay_snapshot(value, authority):
			return false
		if fail_next_restore:
			fail_next_restore = false
			return false
		state = value.duplicate(true)
		return true


var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_host_checkpoint_supports_fresh_reconstruction_and_backward_seek()
	await _test_checkpoint_fault_rolls_back_already_restored_participants()
	_suite.finish(get_tree())


func _test_host_checkpoint_supports_fresh_reconstruction_and_backward_seek() -> void:
	var fixture: Dictionary = await _spawn_host_fixture()
	var host: Node = fixture["host"]
	var room: Node = fixture["room"]
	var authority: RefCounted = host.get("_boss_exposure_replay_authority")
	var boss: Node = await _spawn_boss(room, &"hostile:boss-seek", authority)

	_activate_claim(boss, 61)
	var checkpoint_61: Dictionary = host.call("capture_boss_exposure_replay_checkpoint")
	_suite.assert_equal(checkpoint_61.get("run_id"), "run-boss-replay", "production checkpoint binds the active authoritative run")
	_suite.assert_equal(
		((checkpoint_61.get("boss_exposure_state", {}) as Dictionary).get("participants", []) as Array).size(),
		1,
		"production checkpoint captures the live Boss exposure participant"
	)

	_suite.assert_true(boss.extend_character_boss_exposure(62, 30), "seek fixture advances the live monotonic ledger to generation 62")
	var generation_62: Dictionary = boss.character_boss_exposure_snapshot()
	_suite.assert_true(
		not boss.restore_character_boss_exposure_snapshot(
			((checkpoint_61["boss_exposure_state"] as Dictionary)["participants"] as Array)[0]["snapshot"]
		),
		"ordinary runtime restore cannot seek from generation 62 back to 61"
	)
	_suite.assert_true(
		host.call("restore_boss_exposure_replay_checkpoint", checkpoint_61),
		"protected production Replay restore seeks from generation 62 back to checkpoint generation 61"
	)
	_suite.assert_equal(boss.character_boss_exposure_snapshot().get("claimed_stop_generation_floor"), 61, "protected seek restores the exact older generation floor")
	_suite.assert_true(boss.extend_character_boss_exposure(62, 30), "Replay branch may deterministically consume generation 62 again after seek")
	var before_foreign_binding: Dictionary = boss.character_boss_exposure_snapshot()
	var foreign_room_checkpoint := checkpoint_61.duplicate(true)
	var foreign_room_participant := ((foreign_room_checkpoint["boss_exposure_state"] as Dictionary)["participants"] as Array)[0] as Dictionary
	(foreign_room_participant["snapshot"] as Dictionary)["identity"]["room_id"] = "foreign-room"
	_suite.assert_true(
		not host.call("restore_boss_exposure_replay_checkpoint", foreign_room_checkpoint),
		"checkpoint bound to a foreign room cannot restore onto the live Boss"
	)
	var foreign_generation_checkpoint := checkpoint_61.duplicate(true)
	var foreign_generation_participant := ((foreign_generation_checkpoint["boss_exposure_state"] as Dictionary)["participants"] as Array)[0] as Dictionary
	(foreign_generation_participant["snapshot"] as Dictionary)["identity"]["hostile_next_generation_floor"] = 99
	_suite.assert_true(
		not host.call("restore_boss_exposure_replay_checkpoint", foreign_generation_checkpoint),
		"checkpoint with a foreign hostile generation binding fails closed"
	)
	_suite.assert_equal(boss.character_boss_exposure_snapshot(), before_foreign_binding, "foreign room/generation checkpoint rejection is atomic")
	_suite.assert_true(
		not host.call("restore_boss_exposure_replay_checkpoint", checkpoint_61.merged({"run_id": "forged-run"}, true)),
		"cross-run checkpoint restore fails closed"
	)
	_suite.assert_equal(boss.character_boss_exposure_snapshot().get("claimed_stop_generation_floor"), 62, "cross-run rejection leaves the live branch unchanged")

	var source_id := StringName(str(boss.hostile_identity_snapshot().get("hostile_source_id", "")))
	boss.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var reconstructed: Node = await _spawn_boss(room, source_id, authority)
	_suite.assert_equal(reconstructed.character_boss_exposure_snapshot().get("claimed_stop_generation_floor"), 0, "fresh Boss begins with an empty exposure ledger")
	_suite.assert_true(
		host.call("restore_boss_exposure_replay_checkpoint", checkpoint_61),
		"fresh Boss reconstruction accepts the protected data-only checkpoint"
	)
	var reconstructed_checkpoint: Dictionary = host.call("capture_boss_exposure_replay_checkpoint")
	_suite.assert_equal(
		reconstructed_checkpoint.get("boss_exposure_state"),
		checkpoint_61.get("boss_exposure_state"),
		"fresh reconstruction is byte-equivalent at the production checkpoint boundary"
	)
	await _cleanup_fixture(fixture)


func _test_checkpoint_fault_rolls_back_already_restored_participants() -> void:
	var fixture: Dictionary = await _spawn_host_fixture()
	var host: Node = fixture["host"]
	var room: Node = fixture["room"]
	var authority: RefCounted = host.get("_boss_exposure_replay_authority")
	var boss: Node = await _spawn_boss(room, &"hostile:a-real-boss", authority)
	_activate_claim(boss, 71)

	var fault := FaultingBossParticipant.new()
	fault.name = "FaultingBossParticipant"
	fault.source_id = &"hostile:z-fault"
	fault.state = _idle_snapshot(7)
	_suite.assert_true(fault.configure_character_boss_exposure_replay_authority(authority), "fault fixture receives the protected Replay capability")
	(room.get_node("Enemies") as Node).add_child(fault)
	var checkpoint: Dictionary = host.call("capture_boss_exposure_replay_checkpoint")

	_suite.assert_true(boss.extend_character_boss_exposure(72, 30), "fault fixture diverges the first participant after capture")
	var boss_before_fault: Dictionary = boss.character_boss_exposure_snapshot()
	fault.state = _idle_snapshot(8)
	var fault_before: Dictionary = fault.character_boss_exposure_snapshot()
	fault.fail_next_restore = true
	_suite.assert_true(
		not host.call("restore_boss_exposure_replay_checkpoint", checkpoint),
		"a participant apply fault rejects the complete checkpoint transaction"
	)
	_suite.assert_equal(boss.character_boss_exposure_snapshot(), boss_before_fault, "transaction fault rolls the already-restored Boss back exactly")
	_suite.assert_equal(fault.character_boss_exposure_snapshot(), fault_before, "transaction fault preserves the failing participant state")

	var missing_participant := checkpoint.duplicate(true)
	((missing_participant["boss_exposure_state"] as Dictionary)["participants"] as Array).pop_back()
	_suite.assert_true(
		not host.call("restore_boss_exposure_replay_checkpoint", missing_participant),
		"checkpoint with an incomplete participant set fails preflight"
	)
	_suite.assert_equal(boss.character_boss_exposure_snapshot(), boss_before_fault, "preflight fault has zero Boss side effects")
	await _cleanup_fixture(fixture)


func _spawn_host_fixture() -> Dictionary:
	var room := RoomControllerScript.new()
	room.name = "RoomController"
	room.auto_start = false
	var spawn_points := Node2D.new()
	spawn_points.name = "SpawnPoints"
	room.add_child(spawn_points)
	var boss_spawn := Marker2D.new()
	boss_spawn.name = "BossSpawnPoint"
	room.add_child(boss_spawn)
	var enemies := Node2D.new()
	enemies.name = "Enemies"
	room.add_child(enemies)
	add_child(room)
	await get_tree().process_frame

	var host := RunRuntimeHostScript.new()
	host.set("_room_controller", room)
	host.set("_active_run_id", "run-boss-replay")
	host.set("_published_run_id", "run-boss-replay")
	var authority: RefCounted = host.get("_boss_exposure_replay_authority")
	_suite.assert_true(room.call("configure_character_boss_exposure_replay_authority", authority), "RoomController accepts the Host-owned protected Replay authority")
	return {"host": host, "room": room}


func _spawn_boss(room: Node, source_id: StringName, authority: RefCounted) -> Node:
	var boss := BossScene.instantiate()
	boss.set_physics_process(false)
	_suite.assert_true(boss.configure_hostile_identity(source_id, 1), "Boss fixture installs its stable hostile identity")
	boss.set_meta("run_id", &"run-boss-replay")
	boss.set_meta("room_id", &"room-boss-replay")
	boss.set_meta("encounter_id", &"encounter-boss-replay")
	boss.set_meta("encounter_spawn_id", StringName("spawn-%s" % str(source_id)))
	boss.set_meta("encounter_enemy_id", &"chrono_warden")
	_suite.assert_true(
		boss.configure_character_boss_exposure_replay_authority(authority),
		"Boss fixture installs the Host-owned protected Replay capability"
	)
	(room.get_node("Enemies") as Node).add_child(boss)
	boss.set_physics_process(false)
	await get_tree().process_frame
	return boss


func _activate_claim(boss: Node, generation: int) -> void:
	var source_id := StringName("checkpoint-window-%d" % generation)
	boss.apply_time_stop_source(source_id, 0.5)
	_suite.assert_true(boss.extend_character_boss_exposure(generation, 30), "checkpoint fixture reserves generation %d" % generation)
	boss.clear_time_stop_source(source_id)
	_suite.assert_equal(boss.character_boss_exposure_snapshot().get("tail_state"), "active", "checkpoint fixture activates generation %d" % generation)


func _idle_snapshot(generation_floor: int) -> Dictionary:
	return {
		"schema_version": 1,
		"identity": {
			"run_id": "run-boss-replay",
			"room_id": "room-boss-replay",
			"encounter_id": "encounter-boss-replay",
			"encounter_spawn_id": "spawn-fault",
			"encounter_enemy_id": "chrono_warden",
			"hostile_source_id": "hostile:z-fault",
			"hostile_next_generation_floor": 1,
			"committed_attack_generation": 0,
		},
		"claimed_stop_generation_floor": generation_floor,
		"tail_state": "idle",
		"remaining_tail_frames": 0,
		"claims": [],
	}


func _cleanup_fixture(fixture: Dictionary) -> void:
	var host: Node = fixture["host"]
	var room: Node = fixture["room"]
	if is_instance_valid(host):
		host.free()
	if is_instance_valid(room):
		room.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
