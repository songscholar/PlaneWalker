extends Node

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const ReplayPlayerScript := preload("res://scripts/replay/replay_player.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const LAUNCH_SCHEMA_VERSION := 7
const CHARACTER_IDS: Array[StringName] = [
	&"wanderer",
	&"time_guardian",
	&"void_walker",
	&"primordial_knight",
	&"time_lord",
]

class FailOnceActiveItemRuntime:
	extends RefCounted

	var _snapshot: Dictionary
	var _fail_next_restore: bool = true

	func _init(snapshot: Dictionary) -> void:
		_snapshot = snapshot.duplicate(true)

	func snapshot() -> Dictionary:
		return _snapshot.duplicate(true)

	func can_restore_snapshot(value: Dictionary) -> bool:
		return value.size() == _snapshot.size()

	func restore_snapshot(value: Dictionary) -> bool:
		if _fail_next_restore:
			_fail_next_restore = false
			return false
		_snapshot = value.duplicate(true)
		return true


var _suite
var _registry: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_registry = ContentRegistryScript.new()
	var report: RefCounted = _registry.call("load_packs", [
		{"path": "res://data/content_packs/base/pack.json", "required": true},
	], "0.4.0-dev", &"M1")
	_suite.assert_true(not report.call("has_blocking_errors"), "Replay matrix loads the Base Pack")
	if not report.call("has_blocking_errors"):
		await _test_five_character_round_trips()
		await _test_passive_and_live_talent_round_trip_and_drift_rejection()
		await _test_active_item_round_trip_and_tamper_rejection()
		await _test_dash_and_reward_invulnerability_round_trip_and_rollback()
		await _test_legacy_launch_v4_and_v5_fail_closed_after_authentication()
		await _test_event_modifier_replay_and_legacy_v6()
	_suite.finish(get_tree())


func _test_five_character_round_trips() -> void:
	for character_index: int in range(CHARACTER_IDS.size()):
		var character_id := CHARACTER_IDS[character_index]
		var source := await _spawn_launch_player(character_id, 4100 + character_index)
		var identity: Dictionary = source.full_player_replay_identity()
		var initial: Dictionary = source.full_player_replay_snapshot()
		var label := str(character_id)
		_suite.assert_equal(
			int(initial.get("schema_version", 0)),
			LAUNCH_SCHEMA_VERSION,
			"%s Launch snapshot uses Player Replay schema 7" % label
		)
		_suite.assert_true(
			initial.get("active_item_state") is Dictionary,
			"%s Launch snapshot includes authoritative active-item state" % label
		)
		_suite.assert_true(
			initial.get("reward_effect_state") is Dictionary,
			"%s Launch snapshot seals passive reward-effect state" % label
		)
		_suite.assert_true(
			initial.get("live_talent_state") is Dictionary,
			"%s Launch snapshot seals live talent definitions and modifiers" % label
		)
		_suite.assert_true(
			(initial.get("player_state", {}) as Dictionary).get(
				"invulnerability_state"
			) is Dictionary,
			"%s Launch schema 7 seals non-reward invulnerability state" % label
		)

		var recorder = ReplayRecorderScript.new()
		_suite.assert_true(
			bool(recorder.start_full_player_recording(identity, 4100 + character_index).get("ok", false)),
			"%s Launch Replay recording starts" % label
		)
		_suite.assert_true(
			bool(recorder.record_full_player_frame(
				initial,
				_frame_intents(int(initial.get("frame", 0))),
				[]
			).get("ok", false)),
			"%s records the initial Launch checkpoint" % label
		)
		_suite.assert_true(source.advance_action_frame({}), "%s advances one fixed frame" % label)
		var terminal: Dictionary = source.full_player_replay_snapshot()
		_suite.assert_true(
			bool(recorder.record_full_player_frame(
				terminal,
				_frame_intents(int(terminal.get("frame", 0))),
				[]
			).get("ok", false)),
			"%s records the terminal Launch checkpoint" % label
		)
		var finished: Dictionary = recorder.finish_full_player_recording()
		_suite.assert_true(bool(finished.get("ok", false)), "%s Launch Replay finishes" % label)
		var replay := finished.get("replay", {}) as Dictionary
		_suite.assert_equal(
			int(replay.get("schema_version", 0)),
			LAUNCH_SCHEMA_VERSION,
			"%s Launch Replay root uses schema 7" % label
		)
		for frame_value: Variant in replay.get("frames", []) as Array:
			var frame := frame_value as Dictionary
			_suite.assert_equal(
				int(frame.get("schema_version", 0)),
				LAUNCH_SCHEMA_VERSION,
				"%s Launch Replay frame uses schema 7" % label
			)
			_suite.assert_equal(
				int((frame.get("snapshot", {}) as Dictionary).get("schema_version", 0)),
				LAUNCH_SCHEMA_VERSION,
				"%s embedded Launch snapshot uses schema 7" % label
			)

		var target := await _spawn_launch_player(character_id, 4100 + character_index)
		var replay_player = ReplayPlayerScript.new()
		_suite.assert_true(
			bool(replay_player.load_full_player_replay(
				replay,
				target.full_player_replay_identity()
			).get("ok", false)),
			"%s Launch Replay loads against the same character identity" % label
		)
		var replayed: Dictionary = replay_player.replay_full_player_to_terminal(target, 0)
		_suite.assert_true(
			bool(replayed.get("ok", false)),
			"%s Launch Replay reaches the terminal checkpoint" % label
		)
		_suite.assert_equal(
			target.full_player_replay_snapshot(),
			terminal,
			"%s Launch Replay restores the exact terminal state" % label
		)

		var mismatched_id := CHARACTER_IDS[(character_index + 1) % CHARACTER_IDS.size()]
		var mismatched := await _spawn_launch_player(mismatched_id, 4100 + character_index)
		var rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
			replay,
			mismatched.full_player_replay_identity()
		)
		_suite.assert_equal(
			rejected.get("code"),
			&"FULL_PLAYER_REPLAY_IDENTITY_MISMATCH",
			"%s Replay rejects a different Launch character profile" % label
		)

		await _free_player(mismatched)
		await _free_player(target)
		await _free_player(source)


func _test_event_modifier_replay_and_legacy_v6() -> void:
	var source := await _spawn_launch_player(&"wanderer", 5401)
	var projection := [
		{"modifier_id": "heroic_guard", "magnitude": 1.2, "source_transaction_id": "tx_replay_guard"},
		{"modifier_id": "tranquility", "magnitude": 1.25, "source_transaction_id": "tx_replay_regen"},
		{"modifier_id": "weapon_temper", "magnitude": 1.1, "source_transaction_id": "tx_replay_temper"},
	]
	_suite.assert_true(source.sync_event_temporary_modifiers(projection), "Replay source installs independent authored event effects")
	var active: Dictionary = source.full_player_replay_snapshot()
	_suite.assert_true(active.get("event_temporary_modifiers") is Array, "full Player checkpoint seals event modifier projection")
	if not active.get("event_temporary_modifiers") is Array:
		await _free_player(source)
		return
	_suite.assert_equal(active["schema_version"], 7, "Launch event projection has an explicit Player Replay schema 7")
	_suite.assert_equal(active["event_temporary_modifiers"], projection, "checkpoint seals magnitude and stable source identity")
	var identity: Dictionary = source.full_player_replay_identity()
	var recorder = ReplayRecorderScript.new()
	_suite.assert_true(recorder.start_full_player_recording(identity, 5401).get("ok", false), "event Replay recording starts")
	_suite.assert_true(recorder.record_full_player_frame(active, _frame_intents(0), []).get("ok", false), "active event checkpoint records")
	_suite.assert_true(source.advance_action_frame({}), "active event advances through the authoritative frame clock")
	var active_later: Dictionary = source.full_player_replay_snapshot()
	_suite.assert_true(recorder.record_full_player_frame(active_later, _frame_intents(1), []).get("ok", false), "active event later checkpoint records")
	_suite.assert_true(source.sync_event_temporary_modifiers([]), "domain expiry removes event effects before the next frame")
	_suite.assert_true(source.advance_action_frame({}), "expired event advances the next authoritative frame")
	var expired: Dictionary = source.full_player_replay_snapshot()
	_suite.assert_true(recorder.record_full_player_frame(expired, _frame_intents(2), []).get("ok", false), "expired event checkpoint records")
	var finished: Dictionary = recorder.finish_full_player_recording()
	_suite.assert_true(finished.get("ok", false), "event Replay recording seals")
	var replay: Dictionary = finished.get("replay", {})
	var target := await _spawn_launch_player(&"wanderer", 5401)
	var replay_player = ReplayPlayerScript.new()
	_suite.assert_true(replay_player.load_full_player_replay(replay, target.full_player_replay_identity()).get("ok", false), "event Replay loads into a fresh matching Player")
	_suite.assert_true(replay_player.restore_full_player_frame(target, 1).get("ok", false), "event Replay restores an active checkpoint independently from Dungeon")
	_suite.assert_equal(target.event_temporary_modifier_snapshot(), projection, "independent Replay restores all three real event sources")
	_suite.assert_close(target.get_effective_attack(), float(target.stats.attack) * 1.1, "independent Replay restores actual attack")
	_suite.assert_close(target.get_node("SwordWeapon").base_attack, target.get_effective_attack(), "independent Replay rebinds the real weapon adapter attack")
	_suite.assert_close(target.get_damage_taken_multiplier(), 1.0 / 1.2, "independent Replay restores actual incoming damage")
	_suite.assert_close(target.get_node("TimeManager").event_energy_regen_multiplier(), 1.25, "independent Replay restores actual regeneration")
	_suite.assert_true(replay_player.restore_full_player_frame(target, 1).get("ok", false), "same active checkpoint restores idempotently")
	_suite.assert_equal(target.full_player_replay_snapshot(), active_later, "same checkpoint cannot stack event magnitude")
	_suite.assert_true(replay_player.restore_full_player_frame(target, 2).get("ok", false), "independent Replay restores expiry")
	_suite.assert_equal(target.full_player_replay_snapshot(), expired, "independent Replay reproduces the exact expired checkpoint")
	_suite.assert_equal(target.event_temporary_modifier_snapshot(), [], "expired checkpoint clears the physical layer")
	_suite.assert_close(target.get_damage_taken_multiplier(), 1.0, "expired checkpoint restores unmodified mitigation")
	_suite.assert_close(target.get_node("TimeManager").event_energy_regen_multiplier(), 1.0, "expired checkpoint restores unmodified regeneration")
	var unauthenticated := replay.duplicate(true)
	unauthenticated["frames"][0]["snapshot"]["event_temporary_modifiers"][0]["magnitude"] = 1.3
	_suite.assert_equal(ReplayPlayerScript.new().load_full_player_replay(unauthenticated, identity).get("code"), &"FULL_PLAYER_FRAME_DIGEST_MISMATCH", "event projection is authenticated before restore")
	for candidate: Array in [
		[{"modifier_id": "unknown", "magnitude": 1.1, "source_transaction_id": "tx_unknown"}],
		[{"modifier_id": "weapon_temper", "magnitude": 11.0, "source_transaction_id": "tx_large"}],
		[projection[0], projection[0]],
	]:
		var forged := replay.duplicate(true)
		forged["frames"][0]["snapshot"]["event_temporary_modifiers"] = candidate
		_rehash_full_player_replay(forged)
		_suite.assert_equal(ReplayPlayerScript.new().load_full_player_replay(forged, identity).get("code"), &"FULL_PLAYER_EVENT_MODIFIER_STATE_INVALID", "rehashing cannot legalize an invalid event projection")
	var atomic_target := await _spawn_launch_player(&"wanderer", 5401)
	atomic_target.sync_event_temporary_modifiers([{"modifier_id": "past_strength", "magnitude": 1.15, "source_transaction_id": "tx_atomic_before"}])
	atomic_target.set("active_item_runtime", FailOnceActiveItemRuntime.new(atomic_target.active_item_snapshot()))
	var before: Dictionary = atomic_target.full_player_replay_snapshot()
	_suite.assert_true(not atomic_target.restore_full_player_replay_snapshot(active_later), "downstream participant failure rejects event Replay installation")
	_suite.assert_equal(atomic_target.full_player_replay_snapshot(), before, "failed Replay restore compensates the previous event layer and all participants")
	await _free_player(atomic_target)
	await _free_player(target)
	await _free_player(source)
	var legacy_source := await _spawn_launch_player(&"wanderer", 5402)
	var legacy_recorder = ReplayRecorderScript.new()
	legacy_recorder.start_full_player_recording(legacy_source.full_player_replay_identity(), 5402)
	legacy_recorder.record_full_player_frame(legacy_source.full_player_replay_snapshot(), _frame_intents(0), [])
	var legacy_current: Dictionary = legacy_recorder.finish_full_player_recording().get("replay", {})
	var legacy := _legacy_launch_replay(legacy_current, 6)
	var legacy_copy := legacy.duplicate(true)
	var legacy_target := await _spawn_launch_player(&"wanderer", 5402)
	legacy_target.sync_event_temporary_modifiers([{"modifier_id": "weapon_temper", "magnitude": 1.1, "source_transaction_id": "tx_legacy_target"}])
	var legacy_player = ReplayPlayerScript.new()
	_suite.assert_true(legacy_player.load_full_player_replay(legacy, legacy_target.full_player_replay_identity()).get("ok", false), "authenticated legacy schema 6 migrates with an empty event layer")
	_suite.assert_true(legacy_player.restore_full_player_frame(legacy_target, 0).get("ok", false), "legacy schema 6 restores into the current Player")
	_suite.assert_equal(legacy_target.event_temporary_modifier_snapshot(), [], "legacy migration cannot preserve unrelated currently installed event effects")
	_suite.assert_equal(legacy, legacy_copy, "legacy Replay migration preserves caller bytes and digests")
	var legacy_tampered := legacy.duplicate(true)
	legacy_tampered["frames"][0]["snapshot"]["player_state"]["position"] += Vector2.ONE
	_suite.assert_equal(ReplayPlayerScript.new().load_full_player_replay(legacy_tampered, legacy_source.full_player_replay_identity()).get("code"), &"FULL_PLAYER_FRAME_DIGEST_MISMATCH", "legacy schema 6 is authenticated before migration refreshes digests")
	await _free_player(legacy_target)
	await _free_player(legacy_source)


func _test_passive_and_live_talent_round_trip_and_drift_rejection() -> void:
	var source := await _spawn_launch_player(&"wanderer", 5151)
	var talent_definition: Dictionary = _registry.call("get_content", &"tal_eternity_reserve")
	var passive_definition := {
		"id": "replay_passive_fixture",
		"category": "item",
		"effects": {
			"max_hp_bonus": 12.0,
			"time_stop_duration_bonus": 0.75,
			"invulnerable_duration": 1.0,
		},
	}
	var active_definition: Dictionary = _registry.call(
		"get_content",
		&"absolute_zero_device"
	)
	var identity: Dictionary = source.full_player_replay_identity()
	var identity_digest := ReplayRecorderScript.value_digest(identity)
	var recorder = ReplayRecorderScript.new()
	_suite.assert_true(
		bool(recorder.start_full_player_recording(identity, 5151).get("ok", false)),
		"sealed Launch Replay recording starts before live rewards"
	)
	var initial: Dictionary = source.full_player_replay_snapshot()
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			initial,
			_frame_intents(int(initial.get("frame", 0))),
			[]
		).get("ok", false)),
		"sealed Launch Replay records the reward-free initial checkpoint"
	)
	_suite.assert_true(
		bool(source.apply_reward(passive_definition).get("ok", false)),
		"Launch Replay fixture applies a passive reward after recording starts"
	)
	var reward_before_rejected_frame: Dictionary = source.reward_effect_snapshot()
	source.get("weapon_action_coordinator").set("_frame_event_commit_fault_for_test", true)
	_suite.assert_true(
		not source.advance_action_frame({}),
		"rejected fixed frame reaches post-decrement rollback"
	)
	source.get("weapon_action_coordinator").set("_frame_event_commit_fault_for_test", false)
	_suite.assert_equal(
		source.reward_effect_snapshot(),
		reward_before_rejected_frame,
		"rejected fixed frame preserves reward invulnerability remaining frames"
	)
	_suite.assert_equal(
		ReplayRecorderScript.value_digest(source.full_player_replay_identity()),
		identity_digest,
		"passive rewards do not mutate the frozen Launch Replay identity"
	)
	_suite.assert_true(
		source.install_character_talent(talent_definition),
		"Launch Replay fixture installs a live talent after the passive reward"
	)
	_suite.assert_equal(
		ReplayRecorderScript.value_digest(source.full_player_replay_identity()),
		identity_digest,
		"live talents do not mutate the frozen Launch Replay identity"
	)
	_suite.assert_true(
		bool(source.equip_active_item(active_definition).get("ok", false)),
		"Launch Replay fixture equips an active item after the live talent"
	)
	var source_time_manager: Node = source.get_node("TimeManager")
	source_time_manager.set("energy", float(source_time_manager.get("max_energy")))
	_suite.assert_true(
		bool(source.activate_equipped_active_item({"is_boss_target": true}).get("ok", false)),
		"Launch Replay fixture activates the equipped active item"
	)
	_suite.assert_equal(
		ReplayRecorderScript.value_digest(source.full_player_replay_identity()),
		identity_digest,
		"active-item changes do not mutate the frozen Launch Replay identity"
	)
	_suite.assert_true(source.advance_action_frame({}), "sealed Launch fixture advances one frame")
	var snapshot: Dictionary = source.full_player_replay_snapshot()
	var live_talent := snapshot.get("live_talent_state", {}) as Dictionary
	_suite.assert_equal(
		live_talent.get("selected_talent_ids"),
		["tal_eternity_reserve"],
		"Launch Replay seals the selected live talent IDs"
	)
	_suite.assert_equal(
		live_talent.get("definitions_digest"),
		ReplayRecorderScript.value_digest(live_talent.get("talent_definitions", [])),
		"Launch Replay seals the exact live talent definitions"
	)
	_suite.assert_equal(
		live_talent.get("modifier_digest"),
		ReplayRecorderScript.value_digest(live_talent.get("modifiers", {})),
		"Launch Replay seals the exact live talent modifiers"
	)
	_suite.assert_equal(
		(live_talent.get("talent_definitions", []) as Array)[0],
		talent_definition,
		"live Replay keeps the authoritative registry talent definition"
	)
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			snapshot,
			_frame_intents(int(snapshot.get("frame", 0))),
			[]
		).get("ok", false)),
		"sealed Launch Replay keeps recording after passive, talent, and active-item changes"
	)
	var finished: Dictionary = recorder.finish_full_player_recording()
	_suite.assert_true(bool(finished.get("ok", false)), "sealed Launch Replay finishes")
	var replay := (finished.get("replay", {}) as Dictionary).duplicate(true)
	for legacy_version: int in [4, 5]:
		var reward_bearing_legacy := _legacy_launch_replay(replay, legacy_version)
		var reward_bearing_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
			reward_bearing_legacy,
			identity
		)
		_suite.assert_equal(
			reward_bearing_rejected.get("code"),
			&"FULL_PLAYER_REPLAY_MIGRATION_INVALID",
			"reward-bearing legacy Launch v%d Replay fails closed" % legacy_version
		)
	var target := await _spawn_launch_player(&"wanderer", 5151)
	var replay_player = ReplayPlayerScript.new()
	_suite.assert_true(
		bool(replay_player.load_full_player_replay(
			replay,
			target.full_player_replay_identity()
		).get("ok", false)),
		"sealed Launch Replay loads against matching content"
	)
	_suite.assert_true(
		bool(target.call(
			"_full_player_talent_definitions_match_authority",
			snapshot.get("live_talent_state", {}),
			snapshot.get("identity", {})
		)),
		"post-start talent definitions match local Base Pack authority"
	)
	_suite.assert_true(
		bool(target.get("active_item_runtime").call(
			"can_restore_snapshot",
			(snapshot.get("active_item_state", {}) as Dictionary).duplicate(true)
		)),
		"post-start active-item state passes pure target validation"
	)
	_suite.assert_true(
		not (target.call(
			"_validated_full_player_replay_snapshot",
			snapshot.duplicate(true)
		) as Dictionary).is_empty(),
		"post-start Launch checkpoint passes target-side authority validation"
	)
	_suite.assert_true(
		bool(replay_player.restore_full_player_frame(target, 1).get("ok", false)),
		"sealed Launch Replay restores passive, live-talent, and active-item state"
	)
	_suite.assert_equal(
		target.reward_effect_snapshot(),
		snapshot.get("reward_effect_state"),
		"passive reward-effect state round-trips exactly"
	)
	_suite.assert_equal(
		target.active_item_snapshot(),
		snapshot.get("active_item_state"),
		"active-item state round-trips from the post-start checkpoint"
	)
	_suite.assert_true(
		bool(target.get_node("HealthComponent").get("invulnerable")),
		"fresh Replay target reconstructs active reward invulnerability"
	)
	for offset: int in range(3):
		_suite.assert_true(source.advance_action_frame({}), "source advances reward frame %d" % offset)
		_suite.assert_true(target.advance_action_frame({}), "target advances reward frame %d" % offset)
		_suite.assert_equal(
			target.reward_effect_snapshot(),
			source.reward_effect_snapshot(),
			"reward invulnerability remaining frames stay deterministic at offset %d" % offset
		)
	await _free_player(source)
	await _free_player(target)

	var unknown_reward := replay.duplicate(true)
	var unknown_reward_state := (
		((unknown_reward["frames"] as Array)[1] as Dictionary)["snapshot"] as Dictionary
	)["reward_effect_state"] as Dictionary
	unknown_reward_state["unknown"] = true
	_rehash_full_player_replay(unknown_reward)
	var unknown_reward_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		unknown_reward,
		identity
	)
	_suite.assert_equal(
		unknown_reward_rejected.get("code"),
		&"FULL_PLAYER_REWARD_EFFECT_STATE_INVALID",
		"unknown passive-state fields fail closed after outer rehash"
	)

	var forged_modifier := replay.duplicate(true)
	var forged_live := (
		((forged_modifier["frames"] as Array)[1] as Dictionary)["snapshot"] as Dictionary
	)["live_talent_state"] as Dictionary
	(forged_live["modifiers"] as Dictionary)["low_energy_threshold"] = 29
	forged_live["modifier_digest"] = ReplayRecorderScript.value_digest(forged_live["modifiers"])
	_rehash_full_player_replay(forged_modifier)
	var forged_modifier_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		forged_modifier,
		identity
	)
	_suite.assert_equal(
		forged_modifier_rejected.get("code"),
		&"FULL_PLAYER_LIVE_TALENT_STATE_INVALID",
		"forged live modifier state fails closed after digest recomputation"
	)

	var changed_bounds := replay.duplicate(true)
	var changed_bounds_live := (
		((changed_bounds["frames"] as Array)[1] as Dictionary)["snapshot"] as Dictionary
	)["live_talent_state"] as Dictionary
	var changed_definition := (changed_bounds_live["talent_definitions"] as Array)[0] as Dictionary
	(changed_definition["effects"] as Dictionary)["low_energy_regen_multiplier"] = -1.0
	changed_bounds_live["definitions_digest"] = ReplayRecorderScript.value_digest(
		changed_bounds_live["talent_definitions"]
	)
	_rehash_full_player_replay(changed_bounds)
	var changed_bounds_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		changed_bounds,
		identity
	)
	_suite.assert_equal(
		changed_bounds_rejected.get("code"),
		&"FULL_PLAYER_LIVE_TALENT_STATE_INVALID",
		"changed talent effect bounds fail closed after outer rehash"
	)

	var content_drift := replay.duplicate(true)
	var drift_snapshot := (
		((content_drift["frames"] as Array)[1] as Dictionary)["snapshot"] as Dictionary
	)
	var drift_live := drift_snapshot["live_talent_state"] as Dictionary
	((drift_live["talent_definitions"] as Array)[0] as Dictionary)["name_key"] = "content.drift"
	drift_live["definitions_digest"] = ReplayRecorderScript.value_digest(
		drift_live["talent_definitions"]
	)
	var drift_character_runtime := (
		(drift_snapshot["character_state"] as Dictionary)["runtime"] as Dictionary
	)
	((drift_character_runtime["talent_definitions"] as Array)[0] as Dictionary)["name_key"] = "content.drift"
	_rehash_full_player_replay(content_drift)
	var drift_target := await _spawn_launch_player(&"wanderer", 5151)
	var drift_before: Dictionary = drift_target.full_player_replay_snapshot()
	var drift_player = ReplayPlayerScript.new()
	_suite.assert_true(
		bool(drift_player.load_full_player_replay(
			content_drift,
			drift_target.full_player_replay_identity()
		).get("ok", false)),
		"semantically valid but drifted content reaches target validation"
	)
	_suite.assert_equal(
		drift_player.restore_full_player_frame(drift_target, 1).get("code"),
		&"FULL_PLAYER_REPLAY_RESTORE_REJECTED",
		"target authority rejects synchronized drift in both talent-definition copies"
	)
	_suite.assert_equal(
		drift_target.full_player_replay_snapshot(),
		drift_before,
		"content drift rejection leaves the target atomically unchanged"
	)
	await _free_player(drift_target)


func _test_active_item_round_trip_and_tamper_rejection() -> void:
	var source := await _spawn_launch_player(&"wanderer", 5201)
	var active_definition: Dictionary = _registry.call(
		"get_content",
		&"absolute_zero_device"
	)
	_suite.assert_true(
		bool(source.equip_active_item(active_definition).get("ok", false)),
		"Launch Replay fixture equips Absolute Zero Device"
	)
	var time_manager: Node = source.get_node("TimeManager")
	time_manager.set("energy", float(time_manager.get("max_energy")))
	var activated: Dictionary = source.activate_equipped_active_item({"is_boss_target": true})
	_suite.assert_true(bool(activated.get("ok", false)), "Launch Replay fixture activates its item")

	var identity: Dictionary = source.full_player_replay_identity()
	var recorder = ReplayRecorderScript.new()
	_suite.assert_true(
		bool(recorder.start_full_player_recording(identity, 5201).get("ok", false)),
		"active-item Launch Replay recording starts"
	)
	var initial: Dictionary = source.full_player_replay_snapshot()
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			initial,
			_frame_intents(int(initial.get("frame", 0))),
			[]
		).get("ok", false)),
		"active-item Launch Replay records the activated checkpoint"
	)
	_suite.assert_true(source.advance_action_frame({}), "active-item fixture advances one frame")
	var terminal: Dictionary = source.full_player_replay_snapshot()
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			terminal,
			_frame_intents(int(terminal.get("frame", 0))),
			[]
		).get("ok", false)),
		"active-item Launch Replay records its terminal checkpoint"
	)
	var finished: Dictionary = recorder.finish_full_player_recording()
	_suite.assert_true(bool(finished.get("ok", false)), "active-item Launch Replay finishes")
	var replay := (finished.get("replay", {}) as Dictionary).duplicate(true)
	var terminal_active := terminal.get("active_item_state", {}) as Dictionary
	_suite.assert_true(
		int(terminal_active.get("cooldown_end_frame", -1)) > int(terminal_active.get("current_frame", -1)),
		"recorded active item retains a non-zero cooldown"
	)
	_suite.assert_equal(terminal_active.get("next_token"), 2, "recorded active item retains token progress")
	_suite.assert_equal(terminal_active.get("generation"), 1, "recorded active item retains generation")
	_suite.assert_true(
		not (terminal_active.get("handler_state", {}) as Dictionary).is_empty(),
		"recorded active item retains handler state"
	)
	await _free_player(source)

	var target := await _spawn_launch_player(&"wanderer", 5201)
	var replay_player = ReplayPlayerScript.new()
	_suite.assert_true(
		bool(replay_player.load_full_player_replay(
			replay,
			target.full_player_replay_identity()
		).get("ok", false)),
		"active-item Launch Replay loads"
	)
	var replayed: Dictionary = replay_player.replay_full_player_to_terminal(target, 0)
	_suite.assert_true(
		bool(replayed.get("ok", false)),
		"active-item Launch Replay reaches terminal: %s" % str(replayed)
	)
	_suite.assert_equal(
		target.active_item_snapshot(),
		terminal_active,
		"active-item runtime restores cooldown, token, generation, handler, and receipts exactly"
	)
	await _free_player(target)

	for tamper: Dictionary in [
		{"field": "cooldown", "value": 1},
		{"field": "handler", "value": "forged_handler"},
		{"field": "token", "value": 1},
		{"field": "generation", "value": 99},
	]:
		var forged := replay.duplicate(true)
		var forged_active := (
			((forged["frames"] as Array)[0] as Dictionary)["snapshot"] as Dictionary
		)["active_item_state"] as Dictionary
		match str(tamper["field"]):
			"cooldown":
				forged_active["cooldown_end_frame"] = int(
					forged_active["cooldown_end_frame"]
				) + 1
			"handler":
				(forged_active["definition"] as Dictionary)["active_handler_id"] = tamper["value"]
			"token":
				forged_active["next_token"] = tamper["value"]
			"generation":
				forged_active["generation"] = tamper["value"]
		_rehash_full_player_replay(forged)
		var rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
			forged,
			identity
		)
		_suite.assert_equal(
			rejected.get("code"),
			&"FULL_PLAYER_ACTIVE_ITEM_STATE_INVALID",
			"forged active-item %s is rejected after authenticated Replay validation" % tamper["field"]
		)

	var atomic_target := await _spawn_launch_player(&"wanderer", 5201)
	var before: Dictionary = atomic_target.full_player_replay_snapshot()
	var forged_snapshot := initial.duplicate(true)
	var forged_snapshot_active := forged_snapshot["active_item_state"] as Dictionary
	(forged_snapshot_active["definition"] as Dictionary)["active_handler_id"] = "forged_handler"
	_suite.assert_true(
		not atomic_target.restore_full_player_replay_snapshot(forged_snapshot),
		"direct full-player restore rejects forged active-item state"
	)
	_suite.assert_equal(
		atomic_target.full_player_replay_snapshot(),
		before,
		"forged active-item restore leaves the target unchanged"
	)
	await _free_player(atomic_target)

	var rollback_replay := replay.duplicate(true)
	var rollback_target := await _spawn_launch_player(&"wanderer", 5201)
	_suite.assert_true(
		bool(rollback_target.equip_active_item(
			_registry.call("get_content", &"paradox_beacon")
		).get("ok", false)),
		"rollback fixture equips a distinct active item"
	)
	var rollback_manager: Node = rollback_target.get_node("TimeManager")
	rollback_manager.set("time_rift_cost", 0.0)
	rollback_manager.set("time_rift_cooldown", 0.0)
	_suite.assert_true(
		bool(rollback_manager.call("try_time_rift", Vector2(96.0, 64.0))),
		"rollback fixture commits a world payload before the late failure"
	)
	var rollback_authority: Node = rollback_target.get_node("WorldPayloadAuthority")
	var rollback_descriptors := (
		(rollback_authority.call("replay_snapshot") as Dictionary).get("descriptors", [])
		as Array
	)
	var rollback_payload_id := StringName(str(
		(rollback_descriptors[-1] as Dictionary).get("payload_id", "")
	))
	var rollback_payload_node: Node = rollback_authority.call(
		"payload_node",
		rollback_payload_id
	)
	var rollback_before: Dictionary = rollback_target.full_player_replay_snapshot()
	rollback_target.set(
		"active_item_runtime",
		FailOnceActiveItemRuntime.new(rollback_target.active_item_snapshot())
	)
	var failed_restore_signals := {
		"energy": 0,
		"healed": 0,
		"weapon_resource": 0,
	}
	var energy_listener := func(_current: float, _maximum: float) -> void:
		failed_restore_signals["energy"] = int(failed_restore_signals["energy"]) + 1
	var healed_listener := func(_amount: float, _current_hp: float) -> void:
		failed_restore_signals["healed"] = int(failed_restore_signals["healed"]) + 1
	var weapon_listener := func(
		_weapon_id: StringName,
		_resource_id: StringName,
		_current: float,
		_maximum: float,
		_reason: StringName
	) -> void:
		failed_restore_signals["weapon_resource"] = (
			int(failed_restore_signals["weapon_resource"]) + 1
		)
	rollback_target.get_node("TimeManager").energy_changed.connect(energy_listener)
	rollback_target.get_node("HealthComponent").healed.connect(healed_listener)
	EventBus.weapon_resource_changed.connect(weapon_listener)
	var rollback_player = ReplayPlayerScript.new()
	_suite.assert_true(
		bool(rollback_player.load_full_player_replay(
			rollback_replay,
			rollback_target.full_player_replay_identity()
		).get("ok", false)),
		"active-item rollback fixture loads before participant restore"
	)
	var failed_restore: Dictionary = rollback_player.restore_full_player_frame(rollback_target, 1)
	_suite.assert_equal(
		failed_restore.get("code"),
		&"FULL_PLAYER_REPLAY_RESTORE_REJECTED",
		"later participant rejection keeps the stable restore refusal code"
	)
	_suite.assert_equal(
		rollback_target.full_player_replay_snapshot(),
		rollback_before,
		"later participant rejection rolls active-item installation back atomically"
	)
	_suite.assert_true(
		rollback_authority.call("payload_node", rollback_payload_id) == rollback_payload_node,
		"late participant failure reattaches the exact staged world payload node"
	)
	_suite.assert_equal(
		failed_restore_signals,
		{"energy": 0, "healed": 0, "weapon_resource": 0},
		"failed full-player restore publishes no transient health, time, or weapon notifications"
	)
	if EventBus.weapon_resource_changed.is_connected(weapon_listener):
		EventBus.weapon_resource_changed.disconnect(weapon_listener)
	await _free_player(rollback_target)


func _test_legacy_launch_v4_and_v5_fail_closed_after_authentication() -> void:
	var source := await _spawn_launch_player(&"time_guardian", 5301)
	var identity: Dictionary = source.full_player_replay_identity()
	var recorder = ReplayRecorderScript.new()
	_suite.assert_true(
		bool(recorder.start_full_player_recording(identity, 5301).get("ok", false)),
		"legacy Launch fixture starts current recording"
	)
	var initial: Dictionary = source.full_player_replay_snapshot()
	_suite.assert_true(
		bool(recorder.record_full_player_frame(
			initial,
			_frame_intents(int(initial.get("frame", 0))),
			[]
		).get("ok", false)),
		"legacy Launch fixture records an empty active slot"
	)
	var finished: Dictionary = recorder.finish_full_player_recording()
	_suite.assert_true(bool(finished.get("ok", false)), "legacy Launch fixture finishes")
	var current := (finished.get("replay", {}) as Dictionary).duplicate(true)
	var legacy_v4 := _legacy_launch_replay(current, 4)
	var legacy_v5 := _legacy_launch_replay(current, 5)
	var caller_copy_v4 := legacy_v4.duplicate(true)
	var caller_copy_v5 := legacy_v5.duplicate(true)
	var unauthenticated := legacy_v5.duplicate(true)
	var unauthenticated_player_state := (
		((unauthenticated["frames"] as Array)[0] as Dictionary)["snapshot"] as Dictionary
	)["player_state"] as Dictionary
	unauthenticated_player_state["position"] = (
		unauthenticated_player_state.get("position", Vector2.ZERO) as Vector2
	) + Vector2.ONE
	var unauthenticated_rejected: Dictionary = ReplayPlayerScript.new().load_full_player_replay(
		unauthenticated,
		identity
	)
	_suite.assert_equal(
		unauthenticated_rejected.get("code"),
		&"FULL_PLAYER_FRAME_DIGEST_MISMATCH",
		"legacy Launch v5 content is authenticated before migration can refresh digests"
	)
	await _free_player(source)

	for legacy_case: Dictionary in [
		{"version": 4, "replay": legacy_v4, "copy": caller_copy_v4},
		{"version": 5, "replay": legacy_v5, "copy": caller_copy_v5},
	]:
		var target := await _spawn_launch_player(&"time_guardian", 5301)
		var replay_player = ReplayPlayerScript.new()
		var loaded: Dictionary = replay_player.load_full_player_replay(
			legacy_case["replay"],
			target.full_player_replay_identity()
		)
		_suite.assert_equal(
			loaded.get("code"),
			&"FULL_PLAYER_REPLAY_MIGRATION_INVALID",
			"legacy Launch v%d Replay fails closed because passive state cannot be proven" % int(legacy_case["version"])
		)
		_suite.assert_equal(
			legacy_case["replay"],
			legacy_case["copy"],
			"legacy Launch v%d rejection preserves caller-owned Replay" % int(legacy_case["version"])
		)
		await _free_player(target)


func _test_dash_and_reward_invulnerability_round_trip_and_rollback() -> void:
	var dash_source := await _spawn_launch_player(&"wanderer", 5401)
	_suite.assert_true(bool(dash_source.call("_begin_dash")), "dash Replay fixture starts")
	var dash_snapshot: Dictionary = dash_source.full_player_replay_snapshot()
	var dash_target := await _spawn_launch_player(&"wanderer", 5401)
	_suite.assert_true(
		dash_target.restore_full_player_replay_snapshot(dash_snapshot),
		"fresh target restores a dash invulnerability checkpoint"
	)
	_suite.assert_equal(
		dash_target.full_player_replay_snapshot(),
		dash_snapshot,
		"fresh dash restore is byte exact"
	)
	await _free_player(dash_source)
	await _free_player(dash_target)

	var overlap_source := await _spawn_launch_player(&"wanderer", 5402)
	_suite.assert_true(
		bool(overlap_source.apply_reward({
			"id": "invulnerability_overlap_fixture",
			"category": "blessing",
			"effects": {"invulnerable_duration": 1.0},
		}).get("ok", false)),
		"overlap fixture applies reward invulnerability"
	)
	_suite.assert_true(bool(overlap_source.call("_begin_dash")), "overlap fixture starts dash")
	var overlap_snapshot: Dictionary = overlap_source.full_player_replay_snapshot()
	var overlap_target := await _spawn_launch_player(&"wanderer", 5402)
	_suite.assert_true(
		overlap_target.restore_full_player_replay_snapshot(overlap_snapshot),
		"fresh target restores overlapping reward and dash invulnerability"
	)
	_suite.assert_equal(
		overlap_target.full_player_replay_snapshot(),
		overlap_snapshot,
		"overlapping invulnerability domains restore exactly"
	)
	await _free_player(overlap_source)
	await _free_player(overlap_target)

	var rollback_target := await _spawn_launch_player(&"wanderer", 5403)
	var rollback_before: Dictionary = rollback_target.full_player_replay_snapshot()
	rollback_target.get("weapon_action_coordinator").set(
		"_frame_event_commit_fault_for_test",
		true
	)
	var dash_intents := _frame_intents(1)
	dash_intents["dash"] = [{
		"id": "dash",
		"edge": "pressed",
		"held_frames": 1,
		"mode": "press",
	}]
	_suite.assert_true(
		not rollback_target.advance_action_frame(dash_intents),
		"late frame rejection occurs after dash invulnerability creation"
	)
	rollback_target.get("weapon_action_coordinator").set(
		"_frame_event_commit_fault_for_test",
		false
	)
	_suite.assert_equal(
		rollback_target.full_player_replay_snapshot(),
		rollback_before,
		"late dash rejection removes the transaction-created token exactly"
	)
	await _free_player(rollback_target)


func _spawn_launch_player(character_id: StringName, seed_value: int) -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	_suite.assert_true(
		player.configure_loadout({
			"schema_version": 1,
			"milestone": "LAUNCH",
			"character_id": str(character_id),
			"character_profile": _registry.call(
				"resolve_character_runtime_profile", character_id, &"LAUNCH"
			),
			"character_talents": [],
			"weapon_id": "sword",
			"weapon_profile": _registry.call(
				"resolve_weapon_runtime_profile", &"sword", &"LAUNCH"
			),
			"enabled_time_skills": [&"rift", &"rewind"],
			"difficulty": "normal",
			"seed": seed_value,
		}),
		"%s Launch Replay fixture configures" % str(character_id)
	)
	return player


func _frame_intents(frame: int) -> Dictionary:
	return {
		"dash": [],
		"time": [],
		"weapon": [],
		"character": [],
		"movement": Vector2.ZERO,
		"aim": Vector2.RIGHT,
		"meta": {
			"source": "character_runtime_replay_test",
			"target_frame": frame,
			"frame": frame,
		},
	}


func _empty_active_item_state() -> Dictionary:
	return {
		"schema_version": 1,
		"configured": false,
		"definition": {},
		"generation": 0,
		"next_token": 1,
		"current_frame": -1,
		"cooldown_end_frame": -1,
		"handler_state": {},
		"committed_receipts": {},
	}


func _legacy_launch_replay(current: Dictionary, version: int) -> Dictionary:
	var legacy := current.duplicate(true)
	legacy["schema_version"] = version
	for frame_value: Variant in legacy.get("frames", []) as Array:
		var frame := frame_value as Dictionary
		frame["schema_version"] = version
		var snapshot := frame.get("snapshot", {}) as Dictionary
		snapshot["schema_version"] = version
		snapshot.erase("event_temporary_modifiers")
		if version == 6:
			continue
		(snapshot.get("player_state", {}) as Dictionary).erase("invulnerability_state")
		snapshot.erase("reward_effect_state")
		snapshot.erase("live_talent_state")
		if version == 4:
			snapshot.erase("active_item_state")
	_rehash_full_player_replay(legacy)
	return legacy


func _rehash_full_player_replay(replay: Dictionary) -> void:
	for frame_value: Variant in replay.get("frames", []) as Array:
		var frame := frame_value as Dictionary
		frame["digest"] = ReplayRecorderScript.full_player_frame_digest(frame)
	var frames := replay.get("frames", []) as Array
	if not frames.is_empty():
		replay["terminal_snapshot_digest"] = ReplayRecorderScript.value_digest(
			(frames[-1] as Dictionary).get("snapshot", {})
		)
	replay["terminal_digest"] = ReplayRecorderScript.full_player_terminal_digest(replay)


func _free_player(player: Node) -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
