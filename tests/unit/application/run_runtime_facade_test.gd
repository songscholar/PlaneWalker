extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunRuntimeFacadeScript := preload("res://scripts/application/run_runtime_facade.gd")

const FIXED_SEED := 20260929


class EmptyContentRegistry:
	extends RefCounted

	func get_by_category(_category: StringName, _milestone: StringName) -> Array[Dictionary]:
		return []


class FailingCloseDraft:
	extends RefCounted

	var base: RefCounted

	func _init(source: RefCounted = null) -> void:
		base = source

	func resolve_option(offer: Dictionary, option_id: StringName):
		if base == null:
			return null
		return base.call("resolve_option", offer.duplicate(true), option_id)

	func close_offer(_offer_id: String) -> bool:
		return false


class FailingRestoreOrchestrator:
	extends RefCounted

	var base: RefCounted

	func _init(source: RefCounted) -> void:
		base = source

	func revision() -> int:
		return int(base.call("revision"))

	func snapshot() -> Dictionary:
		return base.call("snapshot").duplicate(true)

	func selection_transaction_snapshot() -> Dictionary:
		return base.call("selection_transaction_snapshot").duplicate(true)

	func commit_selection_and_transition(definition: Dictionary):
		return base.call("commit_selection_and_transition", definition.duplicate(true))

	func restore_selection_transaction_snapshot(_value: Dictionary) -> bool:
		return false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_active_loadout_authority(suite)
	_test_boot_and_room_flow(suite)
	_test_loadout_failure_is_atomic(suite)
	_test_offer_creation_failure_is_atomic(suite)
	_test_selection_reservation_is_atomic(suite)
	_test_selection_restore_failure_is_integrity_failure(suite)
	_test_contract_acceptance_is_idempotent(suite)
	_test_terminal_and_pause_guards(suite)
	_test_authoritative_clock_forwarding(suite)
	_test_launch_gold_income_is_atomic(suite)
	_test_boot_failure(suite)
	suite.finish(get_tree())


func _test_active_loadout_authority(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "active loadout facade boots")
	suite.assert_true(facade.has_method("active_loadout"), "facade exposes the accepted loadout boundary")
	if not facade.has_method("active_loadout"):
		return
	suite.assert_true((facade.call("active_loadout") as Dictionary).is_empty(), "boot starts without a stale accepted loadout")
	suite.assert_true(facade.start_run({"seed": FIXED_SEED}, "active-loadout-run").ok, "active loadout run starts")
	var loadout: Dictionary = facade.call("active_loadout")
	suite.assert_equal(str(loadout.get("weapon", {}).get("id", "")), "sword", "accepted loadout retains the canonical weapon")
	suite.assert_equal(str(loadout.get("weapon_profile", {}).get("id", "")), "sword_m1_v1", "accepted loadout retains the canonical weapon profile")
	loadout["weapon_profile"]["id"] = "forged_profile"
	suite.assert_equal(
		str((facade.call("active_loadout") as Dictionary).get("weapon_profile", {}).get("id", "")),
		"sword_m1_v1",
		"accepted loadout query returns a deep copy"
	)
	suite.assert_true(facade.boot().ok, "reboot succeeds after active loadout fixture")
	suite.assert_true((facade.call("active_loadout") as Dictionary).is_empty(), "reboot clears the prior accepted loadout")


func _test_loadout_failure_is_atomic(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "loadout failure facade boots")
	var before: Dictionary = facade.snapshot()
	var room_plan_before: Array[Dictionary] = facade.room_plan()
	var invalid_m1_bow := {
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "bow",
		"enabled_time_skills": ["stop", "rewind"],
		"seed": FIXED_SEED,
	}

	var rejected = facade.start_run(invalid_m1_bow, "invalid-m1-bow")
	var after: Dictionary = facade.snapshot()
	suite.assert_equal(rejected.code, &"CONTENT_NOT_AVAILABLE", "M1 Bow is rejected before run start")
	suite.assert_equal(after["phase"], before["phase"], "loadout rejection preserves phase")
	suite.assert_equal(after["revision"], before["revision"], "loadout rejection preserves revision")
	suite.assert_equal(after, before, "loadout rejection preserves the complete run snapshot")
	suite.assert_equal(facade.room_plan(), room_plan_before, "loadout rejection preserves the prepared room plan")
	if facade.has_method("active_loadout"):
		suite.assert_true((facade.call("active_loadout") as Dictionary).is_empty(), "rejected start does not publish an accepted loadout")


func _test_boot_and_room_flow(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	var booted = facade.boot()
	suite.assert_true(booted.ok, "manifest boots")
	var started = facade.start_run({"seed": FIXED_SEED}, "wave3a-run")
	suite.assert_true(started.ok, "run starts")
	suite.assert_equal(facade.snapshot()["phase"], RunPhaseScript.Value.ROOM_ENTERING, "start prepares room one")
	suite.assert_equal(facade.room_plan().size(), 5, "facade exposes the shared five-room plan")
	suite.assert_true(facade.encounter_catalog() != null, "facade exposes the shared encounter catalog")

	var room_one: Dictionary = facade.current_room_definition()
	suite.assert_equal(room_one["reward_kind"], "starter", "room one uses starter reward")
	suite.assert_equal(room_one["encounter_id"], "m1_room_01", "room one references its authored encounter")
	var encounter_one: Dictionary = facade.current_encounter_definition()
	suite.assert_equal(encounter_one["id"], "m1_room_01", "facade resolves the current encounter from the shared catalog")
	suite.assert_equal(encounter_one["waves"][0]["spawns"][0]["enemy_id"], "chaser", "room one resolves the authored enemy")
	encounter_one["waves"][0]["spawns"][0]["enemy_id"] = "changed"
	suite.assert_equal(facade.current_encounter_definition()["waves"][0]["spawns"][0]["enemy_id"], "chaser", "encounter definition is a deep copy")
	room_one["reward_kind"] = "changed"
	suite.assert_equal(facade.current_room_definition()["reward_kind"], "starter", "room definition is a deep copy")

	suite.assert_true(facade.enter_current_room().ok, "room one enters")
	var phase_before_pause: int = facade.snapshot()["phase"]
	var revision_before_pause: int = facade.snapshot()["revision"]
	suite.assert_true(facade.pause_run().ok, "active room pauses")
	suite.assert_true(facade.snapshot()["suspended"], "pause sets suspended")
	suite.assert_equal(facade.snapshot()["phase"], phase_before_pause, "pause preserves phase")
	suite.assert_equal(facade.snapshot()["revision"], revision_before_pause + 1, "pause advances revision")
	suite.assert_true(facade.resume_run().ok, "active room resumes")
	suite.assert_true(not facade.snapshot()["suspended"], "resume clears suspended")
	suite.assert_equal(facade.snapshot()["phase"], phase_before_pause, "resume preserves phase")

	var completion = facade.complete_current_room()
	suite.assert_true(completion.ok, "room one completes")
	var offer_one: Dictionary = completion.context["offer"]
	suite.assert_equal(offer_one["category"], "item", "room one opens starter item offer")
	suite.assert_equal(offer_one["options"].size(), 3, "room one has three starter options")

	var canonical_open_offer: Dictionary = facade.snapshot()["open_offer"]
	completion.context["offer"]["title_key"] = "MUTATED"
	suite.assert_equal(facade.snapshot()["open_offer"], canonical_open_offer, "completion context is a deep copy")
	var rejected_restart = facade.start_run({"seed": FIXED_SEED + 1}, "forged-restart")
	suite.assert_equal(rejected_restart.code, &"INVALID_PHASE", "active run rejects a second start")
	suite.assert_equal(facade.snapshot()["open_offer"], canonical_open_offer, "rejected restart preserves the open offer")

	var frozen_option := _option_id_for_content(offer_one, "frozen_burst")
	suite.assert_true(not frozen_option.is_empty(), "starter offer contains frozen burst")
	var forged_id = facade.submit_selection("forged-offer", frozen_option, int(offer_one["revision"]))
	suite.assert_equal(forged_id.code, &"OFFER_CLOSED", "forged offer id is rejected")
	var forged_revision = facade.submit_selection(str(offer_one["offer_id"]), frozen_option, int(offer_one["revision"]) + 1)
	suite.assert_equal(forged_revision.code, &"STALE_REVISION", "forged revision is rejected")
	var forged_option = facade.submit_selection(str(offer_one["offer_id"]), "missing-option", int(offer_one["revision"]))
	suite.assert_equal(forged_option.code, &"OPTION_NOT_FOUND", "forged option is rejected")
	suite.assert_true(facade.snapshot()["build"]["items"].is_empty(), "forged submissions do not change build")

	var selected = facade.submit_selection(str(offer_one["offer_id"]), frozen_option, int(offer_one["revision"]))
	suite.assert_true(selected.ok, "canonical starter selection succeeds")
	suite.assert_true(facade.snapshot()["build"]["items"].has("frozen_burst"), "starter writes authoritative build")
	suite.assert_equal(facade.snapshot()["build"]["dominant_archetype"], "freeze_burst", "starter establishes dominant route")
	selected.context["definition"]["archetype"] = "MUTATED"
	suite.assert_equal(facade.snapshot()["build"]["dominant_archetype"], "freeze_burst", "selection context is a deep copy")
	var duplicate = facade.submit_selection(str(offer_one["offer_id"]), frozen_option, int(offer_one["revision"]))
	suite.assert_equal(duplicate.code, &"ALREADY_CONSUMED", "committed offer cannot submit twice")
	suite.assert_equal(facade.snapshot()["build"]["reward_history"].size(), 1, "duplicate submit does not duplicate history")

	var snapshot_copy: Dictionary = facade.snapshot()
	snapshot_copy["build"]["items"].append("forged-item")
	suite.assert_true(not facade.snapshot()["build"]["items"].has("forged-item"), "snapshot is a deep copy")

	suite.assert_true(facade.complete_transition().ok, "room one transition completes")
	suite.assert_equal(facade.current_room_definition()["reward_kind"], "reinforcement", "room two uses reinforcement")
	suite.assert_true(facade.enter_current_room().ok, "room two enters")
	var room_two_completion = facade.complete_current_room()
	suite.assert_true(room_two_completion.ok, "room two completes")
	var offer_two: Dictionary = room_two_completion.context["offer"]
	suite.assert_true(not _option_content_ids(offer_two).has("frozen_burst"), "room two excludes owned starter")
	suite.assert_true(_option_content_ids(offer_two).has("bls_stop_weakpoint"), "room two includes dominant-route payoff")
	_select_first_and_finish_transition(suite, facade, offer_two, "room two")

	suite.assert_equal(facade.current_room_definition()["reward_kind"], "talent", "room three uses talent reward")
	suite.assert_true(facade.enter_current_room().ok, "room three enters")
	var room_three_completion = facade.complete_current_room()
	suite.assert_true(room_three_completion.ok, "room three completes")
	var offer_three: Dictionary = room_three_completion.context["offer"]
	suite.assert_equal(offer_three["category"], "talent", "room three opens talent offer")
	_select_first_and_finish_transition(suite, facade, offer_three, "room three")

	suite.assert_equal(facade.current_room_definition()["reward_kind"], "contract", "room four uses contract reward")
	suite.assert_true(facade.enter_current_room().ok, "room four enters")
	var room_four_completion = facade.complete_current_room()
	suite.assert_true(room_four_completion.ok, "room four completes")
	var offer_four: Dictionary = room_four_completion.context["offer"]
	suite.assert_equal(offer_four["category"], "contract", "room four opens contract offer")
	var decline_option := _option_id_for_content(offer_four, "decline_contract")
	var declined = facade.submit_selection(str(offer_four["offer_id"]), decline_option, int(offer_four["revision"]))
	suite.assert_true(declined.ok, "decline contract succeeds")
	suite.assert_true(facade.snapshot()["build"]["curses"].is_empty(), "decline records no curse")
	suite.assert_true(facade.complete_transition().ok, "room four transition completes")

	var boss_room: Dictionary = facade.current_room_definition()
	suite.assert_equal(boss_room["type"], "boss", "room five is boss")
	suite.assert_equal(boss_room["reward_kind"], "none", "boss has no reward")
	suite.assert_equal(boss_room["encounter_id"], "m1_room_05_boss", "room five references the boss encounter")
	suite.assert_equal(facade.current_encounter_definition()["waves"][0]["spawns"][0]["enemy_id"], "chrono_warden", "boss encounter resolves Chrono Warden")
	suite.assert_true(facade.enter_current_room().ok, "boss room enters")
	suite.assert_equal(facade.snapshot()["phase"], RunPhaseScript.Value.BOSS_ACTIVE, "room five uses boss phase")
	var invalid_boss_completion = facade.complete_current_room()
	suite.assert_equal(invalid_boss_completion.code, &"INVALID_PHASE", "boss cannot open a normal reward")
	var victory = facade.boss_defeated({"result": "victory"})
	suite.assert_true(victory.ok, "boss defeat succeeds")
	suite.assert_equal(facade.snapshot()["phase"], RunPhaseScript.Value.VICTORY, "boss defeat enters victory")
	suite.assert_true(facade.snapshot()["open_offer"].is_empty(), "victory has no open offer")


func _test_contract_acceptance_is_idempotent(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "contract acceptance manifest boots")
	suite.assert_true(facade.start_run({"seed": FIXED_SEED}, "wave3a-contract").ok, "contract acceptance run starts")
	for room_number: int in range(1, 4):
		suite.assert_true(facade.enter_current_room().ok, "contract setup room %d enters" % room_number)
		var completion = facade.complete_current_room()
		suite.assert_true(completion.ok, "contract setup room %d completes" % room_number)
		_select_first_and_finish_transition(suite, facade, completion.context["offer"], "contract setup room %d" % room_number)

	suite.assert_true(facade.enter_current_room().ok, "contract acceptance room enters")
	var contract_completion = facade.complete_current_room()
	suite.assert_true(contract_completion.ok, "contract acceptance offer opens")
	var contract_offer: Dictionary = contract_completion.context["offer"]
	var curse_option := _first_option_except(contract_offer, "decline_contract")
	var accepted = facade.submit_selection(str(contract_offer["offer_id"]), curse_option, int(contract_offer["revision"]))
	suite.assert_true(accepted.ok, "curse contract succeeds")
	suite.assert_equal(facade.snapshot()["build"]["curses"].size(), 1, "accepted contract records one curse")
	var duplicate = facade.submit_selection(str(contract_offer["offer_id"]), curse_option, int(contract_offer["revision"]))
	suite.assert_equal(duplicate.code, &"ALREADY_CONSUMED", "accepted contract cannot submit twice")
	suite.assert_equal(facade.snapshot()["build"]["curses"].size(), 1, "duplicate contract records no second curse")


func _test_offer_creation_failure_is_atomic(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "atomic failure manifest boots")
	suite.assert_true(facade.start_run({"seed": FIXED_SEED}, "wave3a-atomic-failure").ok, "atomic failure run starts")
	suite.assert_true(facade.enter_current_room().ok, "atomic failure room enters")
	var before: Dictionary = facade.snapshot()
	facade._registry = EmptyContentRegistry.new()
	var failed = facade.complete_current_room()
	var after: Dictionary = facade.snapshot()
	suite.assert_equal(failed.code, &"CONTENT_NOT_AVAILABLE", "missing draft content rejects room completion")
	suite.assert_equal(after["phase"], before["phase"], "draft failure preserves combat phase")
	suite.assert_equal(after["revision"], before["revision"], "draft failure preserves revision")
	suite.assert_true(after["open_offer"].is_empty(), "draft failure opens no offer")
	suite.assert_true(after["consumed_offer_ids"].is_empty(), "draft failure consumes no offer")


func _test_selection_reservation_is_atomic(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "reservation facade boots")
	suite.assert_true(facade.start_run({"seed": FIXED_SEED}, "reservation-run").ok, "reservation run starts")
	suite.assert_true(facade.enter_current_room().ok, "reservation room enters")
	var completion = facade.complete_current_room()
	suite.assert_true(completion.ok, "reservation offer opens")
	var offer: Dictionary = completion.context["offer"]
	var option_id := str(offer["options"][0]["option_id"])
	var before: Dictionary = facade.snapshot()
	suite.assert_true(facade.has_method("reserve_selection"), "facade exposes selection reservation")
	suite.assert_true(facade.has_method("commit_reserved_selection"), "facade exposes reserved commit")
	suite.assert_true(facade.has_method("cancel_reserved_selection"), "facade exposes reservation cancellation")
	if not facade.has_method("reserve_selection"):
		return
	var reserved = facade.call(
		"reserve_selection",
		str(offer["offer_id"]),
		option_id,
		int(offer["revision"])
	)
	suite.assert_true(reserved.ok, "valid option reserves without mutation")
	suite.assert_equal(facade.snapshot(), before, "reservation leaves authoritative state unchanged")
	var reservation_id := str(reserved.context.get("reservation_id", ""))
	suite.assert_true(not reservation_id.is_empty(), "reservation returns a stable identity")
	reserved.context["definition"]["id"] = "forged"
	suite.assert_equal(facade.snapshot(), before, "reservation context is isolated from authority")
	var duplicate_reservation = facade.call(
		"reserve_selection",
		str(offer["offer_id"]),
		option_id,
		int(offer["revision"])
	)
	suite.assert_equal(duplicate_reservation.code, &"SELECTION_RESERVED", "one offer cannot own two in-flight reservations")
	suite.assert_true(bool(facade.call("cancel_reserved_selection", reservation_id).ok), "reservation cancellation succeeds")
	suite.assert_equal(facade.snapshot(), before, "cancellation leaves the offer and build unchanged")

	reserved = facade.call(
		"reserve_selection",
		str(offer["offer_id"]),
		option_id,
		int(offer["revision"])
	)
	reservation_id = str(reserved.context.get("reservation_id", ""))
	suite.assert_true(facade.pause_run().ok, "a concurrent authority command advances the revision")
	var stale_commit = facade.call("commit_reserved_selection", reservation_id)
	suite.assert_equal(stale_commit.code, &"STALE_REVISION", "reservation commit rejects authority revision drift")
	var stale_snapshot: Dictionary = facade.snapshot()
	suite.assert_equal(stale_snapshot.get("open_offer"), before.get("open_offer"), "stale commit keeps the offer open")
	suite.assert_equal(stale_snapshot.get("consumed_offer_ids"), before.get("consumed_offer_ids"), "stale commit consumes no offer")
	suite.assert_equal(stale_snapshot.get("build"), before.get("build"), "stale commit writes no build state")
	suite.assert_true(bool(facade.call("cancel_reserved_selection", reservation_id).ok), "stale reservation remains explicitly cancellable")
	suite.assert_true(facade.resume_run().ok, "reservation test restores the running suspension state")

	reserved = facade.call(
		"reserve_selection",
		str(offer["offer_id"]),
		option_id,
		int(offer["revision"])
	)
	reservation_id = str(reserved.context.get("reservation_id", ""))
	var before_close: Dictionary = facade.snapshot()
	var original_draft: RefCounted = facade.get("_draft")
	facade.set("_draft", FailingCloseDraft.new(original_draft))
	var failed_commit = facade.call("commit_reserved_selection", reservation_id)
	suite.assert_equal(failed_commit.code, &"COMMIT_FAILED", "draft close failure rejects the authoritative commit")
	suite.assert_equal(facade.snapshot(), before_close, "failed close restores phase, revision, offer, consumption, and build")
	facade.set("_draft", original_draft)
	suite.assert_true(bool(facade.call("cancel_reserved_selection", reservation_id).ok), "failed reservation remains cancellable")

	facade.set("_draft", FailingCloseDraft.new(original_draft))
	var wrapped_failure = facade.submit_selection(
		str(offer["offer_id"]),
		option_id,
		int(offer["revision"])
	)
	suite.assert_equal(wrapped_failure.code, &"COMMIT_FAILED", "compatibility selection reports Draft close failure")
	facade.set("_draft", original_draft)
	var retry_after_wrapped_failure = facade.reserve_selection(
		str(offer["offer_id"]),
		option_id,
		int(offer["revision"])
	)
	suite.assert_true(retry_after_wrapped_failure.ok, "compatibility selection cancels its failed reservation")
	suite.assert_true(facade.cancel_reserved_selection(str(retry_after_wrapped_failure.context.get("reservation_id", ""))).ok, "compatibility retry fixture cancels cleanly")

	reserved = facade.call(
		"reserve_selection",
		str(offer["offer_id"]),
		option_id,
		int(offer["revision"])
	)
	reservation_id = str(reserved.context.get("reservation_id", ""))
	var committed = facade.call("commit_reserved_selection", reservation_id)
	suite.assert_true(committed.ok, "reserved selection commits atomically")
	var after: Dictionary = facade.snapshot()
	suite.assert_equal(after.get("phase"), RunPhaseScript.Value.ROOM_ENTERING, "atomic commit includes room transition")
	suite.assert_equal(after.get("current_room"), 2, "atomic commit advances to the next room")
	suite.assert_equal(after.get("open_offer"), {}, "atomic commit clears the offer")
	suite.assert_true(after.get("consumed_offer_ids", []).has(str(offer["offer_id"])), "atomic commit consumes the offer")
	suite.assert_equal(after.get("build", {}).get("reward_history", []).size(), 1, "atomic commit writes the build once")
	var repeated = facade.call("commit_reserved_selection", reservation_id)
	suite.assert_equal(repeated.code, &"RESERVATION_NOT_FOUND", "committed reservation cannot execute twice")
	var replayed = facade.submit_selection(
		str(offer["offer_id"]),
		option_id,
		int(offer["revision"])
	)
	suite.assert_equal(replayed.code, &"ALREADY_CONSUMED", "replayed selection cannot commit or publish twice")
	suite.assert_equal(facade.snapshot().get("build", {}).get("reward_history", []).size(), 1, "selection replay keeps one authoritative build write")
	suite.assert_true(facade.complete_transition().ok, "legacy transition call is an idempotent compatibility no-op")


func _test_selection_restore_failure_is_integrity_failure(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "integrity facade boots")
	suite.assert_true(facade.start_run({"seed": FIXED_SEED}, "integrity-run").ok, "integrity run starts")
	suite.assert_true(facade.enter_current_room().ok, "integrity room enters")
	var completion = facade.complete_current_room()
	var offer: Dictionary = completion.context["offer"]
	var reserved = facade.reserve_selection(
		str(offer["offer_id"]),
		str(offer["options"][0]["option_id"]),
		int(offer["revision"])
	)
	var original_orchestrator: RefCounted = facade.get("_orchestrator")
	facade.set("_orchestrator", FailingRestoreOrchestrator.new(original_orchestrator))
	facade.set("_draft", FailingCloseDraft.new())
	var response := {}
	suite.assert_true(not suite.expect_engine_error(func() -> bool:
		response.value = facade.commit_reserved_selection(str(reserved.context.get("reservation_id", "")))
		return response.value.ok,
		"Selection authority rollback failed after DraftService close rejection",
		"RunRuntimeFacade.commit_reserved_selection injected Draft close and rollback refusal"), "failed authority rollback reports command refusal")
	var result = response.value
	suite.assert_equal(result.code, &"INTEGRITY_FAILURE", "Draft close plus authority rollback failure is fail-closed")
	suite.assert_equal(facade.snapshot().get("phase"), RunPhaseScript.Value.ROOM_ENTERING, "failed rollback is never reported as the pre-commit phase")


func _test_terminal_and_pause_guards(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "defeat manifest boots")
	suite.assert_true(facade.start_run({"seed": FIXED_SEED}, "wave3a-defeat").ok, "defeat run starts")
	suite.assert_true(facade.enter_current_room().ok, "defeat room enters")
	var defeat = facade.player_died({"result": "death"})
	suite.assert_true(defeat.ok, "player death succeeds")
	suite.assert_equal(facade.snapshot()["phase"], RunPhaseScript.Value.DEFEAT, "player death enters defeat")
	suite.assert_equal(facade.complete_current_room().code, &"TERMINAL_STATE", "defeat rejects late room completion")
	suite.assert_equal(facade.submit_selection("late-offer", "late-option", 0).code, &"TERMINAL_STATE", "defeat rejects late selection")
	suite.assert_equal(facade.enter_current_room().code, &"TERMINAL_STATE", "defeat rejects late room entry")


func _test_authoritative_clock_forwarding(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "clock facade boots")
	suite.assert_true(facade.start_run({"seed": FIXED_SEED}, "wave3a-clock").ok, "clock run starts")
	suite.assert_true(facade.enter_current_room().ok, "clock room enters")
	var revision_before: int = facade.snapshot()["revision"]
	suite.assert_true(facade.advance_time(0.25).ok, "facade forwards active clock time")
	suite.assert_equal(facade.snapshot()["run_time_ms"], 250, "facade snapshot exposes authoritative elapsed time")
	suite.assert_equal(facade.snapshot()["revision"], revision_before, "elapsed time does not churn command revision")
	suite.assert_true(facade.pause_run().ok, "clock run pauses")
	suite.assert_true(facade.advance_time(1.0).ok, "facade accepts paused clock no-op")
	suite.assert_equal(facade.snapshot()["run_time_ms"], 250, "facade clock freezes while suspended")


func _test_launch_gold_income_is_atomic(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "gold income facade boots")
	suite.assert_true(
		facade.start_run(_launch_config(), "launch-gold-income").ok,
		"gold income Launch run starts"
	)
	suite.assert_true(facade.has_method("grant_run_gold"), "facade exposes controlled gold income")
	if not facade.has_method("grant_run_gold"):
		return
	var before: Dictionary = facade.snapshot()
	var granted = facade.call("grant_run_gold", "tx_room_reward_001", 75, "room_reward")
	suite.assert_true(granted.ok, "positive room reward gold commits")
	var after: Dictionary = facade.snapshot()
	suite.assert_equal(after.get("run_economy", {}).get("balance"), 75, "gold income updates balance")
	suite.assert_equal(
		after.get("run_economy", {}).get("ledger", []),
		[{
			"transaction_id": "tx_room_reward_001",
			"operation": "gold_delta",
			"amount": 75,
			"revision": 1,
		}],
		"gold income records one canonical ledger fact"
	)
	suite.assert_equal(after.get("merchant_state"), before.get("merchant_state"), "gold income preserves merchant state")
	suite.assert_equal(int(after.get("revision", 0)), int(before.get("revision", 0)) + 1, "gold income consumes one command revision")

	var duplicate = facade.call("grant_run_gold", "tx_room_reward_001", 75, "room_reward")
	suite.assert_equal(
		duplicate.code,
		&"DUPLICATE_TRANSACTION",
		"duplicate income rejects: %s" % str(duplicate.context)
	)
	suite.assert_equal(facade.snapshot(), after, "duplicate income mutates nothing")
	var invalid = facade.call("grant_run_gold", "tx_invalid_reward", -1, "room_reward")
	suite.assert_equal(invalid.code, &"INVALID_ARGUMENT", "negative income rejects")
	suite.assert_equal(facade.snapshot(), after, "invalid income mutates nothing")


func _test_boot_failure(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	var booted = facade.boot("res://tests/fixtures/content/missing-runtime-manifest.json")
	suite.assert_equal(booted.code, &"CONTENT_NOT_AVAILABLE", "missing manifest blocks facade boot")
	suite.assert_true(not booted.context.get("errors", []).is_empty(), "boot failure includes validation errors")
	suite.assert_equal(facade.start_run({"seed": FIXED_SEED}, "blocked-run").code, &"INVALID_PHASE", "blocked facade cannot start")


func _launch_config() -> Dictionary:
	return {
		"schema_version": 1,
		"seed": FIXED_SEED,
		"difficulty": "normal",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"milestone": "LAUNCH",
	}


func _select_first_and_finish_transition(suite, facade, offer: Dictionary, label: String) -> void:
	var option_id := str(offer["options"][0]["option_id"])
	var selected = facade.submit_selection(str(offer["offer_id"]), option_id, int(offer["revision"]))
	suite.assert_true(selected.ok, "%s selection succeeds" % label)
	suite.assert_true(facade.complete_transition().ok, "%s transition succeeds" % label)


func _option_id_for_content(offer: Dictionary, content_id: String) -> String:
	for option: Dictionary in offer.get("options", []):
		if str(option.get("content_id", "")) == content_id:
			return str(option.get("option_id", ""))
	return ""


func _option_content_ids(offer: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for option: Dictionary in offer.get("options", []):
		ids.append(str(option.get("content_id", "")))
	return ids


func _first_option_except(offer: Dictionary, excluded_content_id: String) -> String:
	for option: Dictionary in offer.get("options", []):
		if str(option.get("content_id", "")) != excluded_content_id:
			return str(option.get("option_id", ""))
	return ""
