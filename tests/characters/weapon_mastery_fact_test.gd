extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const CharacterActionCoordinatorScript := preload(
	"res://scripts/player/characters/character_action_coordinator.gd"
)
const WeaponRuntimeScript := preload("res://scripts/combat/weapons/weapon_runtime.gd")
const SwordWeaponRuntimeScript := preload(
	"res://scripts/combat/weapons/sword_weapon_runtime.gd"
)
const BowWeaponRuntimeScript := preload(
	"res://scripts/combat/weapons/bow_weapon_runtime.gd"
)
const GunWeaponRuntimeScript := preload(
	"res://scripts/combat/weapons/gun_weapon_runtime.gd"
)
const StaffWeaponRuntimeScript := preload(
	"res://scripts/combat/weapons/staff_weapon_runtime.gd"
)
const GauntletsWeaponRuntimeScript := preload(
	"res://scripts/combat/weapons/gauntlets_weapon_runtime.gd"
)


class FakeCharacterRuntime extends RefCounted:
	var revision: int = 0
	var mastery_contexts: Array[Dictionary] = []
	var reject_next_mastery: bool = false
	var reject_restore: bool = false


	func advance_frame(_context: Dictionary) -> Array[Dictionary]:
		return []


	func snapshot() -> Dictionary:
		return {
			"revision": revision,
			"mastery_contexts": mastery_contexts.duplicate(true),
		}


	func can_restore_snapshot(value: Dictionary) -> bool:
		return (
			value.size() == 2
			and typeof(value.get("revision")) == TYPE_INT
			and int(value.get("revision", -1)) >= 0
			and value.get("mastery_contexts") is Array
		)


	func restore_snapshot(value: Dictionary) -> bool:
		if reject_restore or not can_restore_snapshot(value):
			return false
		revision = int(value["revision"])
		mastery_contexts = (value["mastery_contexts"] as Array).duplicate(true)
		return true


	func reset_runtime_state(_reason: StringName) -> void:
		revision += 1
		mastery_contexts.clear()


	func on_weapon_mastery_confirmed(context: Dictionary) -> Variant:
		revision += 1
		mastery_contexts.append(context.duplicate(true))
		if reject_next_mastery:
			reject_next_mastery = false
			return {"ok": false, "events": []}
		return []


class MasteryRecorder extends RefCounted:
	var facts: Array[Dictionary] = []


	func record(
		weapon_id: StringName,
		mastery_family: StringName,
		mastery_id: StringName,
		action_id: StringName,
		token: int,
		generation: int,
		target_id: int,
		context: Dictionary
	) -> void:
		facts.append({
			"weapon_id": weapon_id,
			"mastery_family": mastery_family,
			"mastery_id": mastery_id,
			"action_id": action_id,
			"token": token,
			"generation": generation,
			"target_id": target_id,
			"context": context.duplicate(true),
		})


const FAMILY_CASES: Array[Dictionary] = [
	{
		"runtime": SwordWeaponRuntimeScript,
		"family": &"sword",
		"mastery_ids": [
			&"sword_perfect_guard",
			&"sword_counter_confirmed",
			&"sword_charged_commitment",
		],
	},
	{
		"runtime": BowWeaponRuntimeScript,
		"family": &"bow",
		"mastery_ids": [
			&"bow_full_charge_weakpoint",
			&"bow_full_charge_penetration",
		],
	},
	{
		"runtime": GunWeaponRuntimeScript,
		"family": &"gun",
		"mastery_ids": [
			&"gun_perfect_reload",
			&"gun_magazine_finisher",
		],
	},
	{
		"runtime": StaffWeaponRuntimeScript,
		"family": &"staff",
		"mastery_ids": [
			&"staff_ordered_combination",
			&"staff_controlled_zone",
		],
	},
	{
		"runtime": GauntletsWeaponRuntimeScript,
		"family": &"gauntlets",
		"mastery_ids": [
			&"gauntlets_dodge_counter",
			&"gauntlets_combo_threshold",
			&"gauntlets_chain_finisher",
		],
	},
]

var _suite
var _recorder := MasteryRecorder.new()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	EventBus.weapon_mastery_confirmed.connect(_recorder.record)
	_test_multi_callback_claim_is_exactly_once()
	_test_family_key_deduplicates_different_mastery_ids()
	_test_rejected_and_malformed_facts_are_zero_mutation()
	_test_runtime_rejection_rolls_back_before_claim_and_publication()
	_test_runtime_rollback_failure_still_publishes_nothing()
	_test_generation_reset_and_stale_facts()
	_test_action_snapshot_preserves_claims_and_is_deep_isolated()
	_test_weapon_runtime_mastery_boundaries()
	EventBus.weapon_mastery_confirmed.disconnect(_recorder.record)
	_suite.finish(get_tree())


func _test_multi_callback_claim_is_exactly_once() -> void:
	var fixture := _coordinator_fixture()
	var coordinator: RefCounted = fixture.coordinator
	var runtime: FakeCharacterRuntime = fixture.runtime
	var generation := int(coordinator.call("generation"))
	var before_count := _recorder.facts.size()
	var callback_index := 0
	for callback_context: Dictionary in [
		{"hit_index": 0, "pellet": 0, "zone_tick": 0},
		{"hit_index": 1, "pellet": 1, "zone_tick": 1},
		{"hit_index": 2, "pellet": 7, "zone_tick": 12},
	]:
		for target_id: int in [11, 11, 12, 13]:
			var accepted := bool(coordinator.call("confirm_weapon_mastery", _fact(
				&"gun",
				&"gun_magazine_finisher",
				generation,
				44,
				target_id,
				callback_context
			)))
			_suite.assert_true(
				accepted == (callback_index == 0),
				"only the first pellet/target/tick callback claims mastery"
			)
			callback_index += 1
	_suite.assert_equal(_recorder.facts.size(), before_count + 1, "one action publishes one mastery fact")
	_suite.assert_equal(runtime.mastery_contexts.size(), 1, "Character Runtime hook receives one mastery fact")


func _test_family_key_deduplicates_different_mastery_ids() -> void:
	var fixture := _coordinator_fixture()
	var coordinator: RefCounted = fixture.coordinator
	var generation := int(coordinator.call("generation"))
	var before_count := _recorder.facts.size()
	_suite.assert_true(
		coordinator.call("confirm_weapon_mastery", _fact(
			&"gun", &"gun_perfect_reload", generation, 9, 0, {"reload_frame": 31}
		)),
		"first mastery ID claims the family/token"
	)
	_suite.assert_true(
		not coordinator.call("confirm_weapon_mastery", _fact(
			&"gun", &"gun_magazine_finisher", generation, 9, 21, {"rounds": 0}
		)),
		"different mastery ID cannot mint a second family/token claim"
	)
	_suite.assert_equal(_recorder.facts.size(), before_count + 1, "family dedupe publishes once")


func _test_rejected_and_malformed_facts_are_zero_mutation() -> void:
	var fixture := _coordinator_fixture()
	var coordinator: RefCounted = fixture.coordinator
	var runtime: FakeCharacterRuntime = fixture.runtime
	var generation := int(coordinator.call("generation"))
	var before_action: Dictionary = coordinator.call("action_snapshot")
	var before_runtime := runtime.snapshot()
	var before_count := _recorder.facts.size()
	var invalid_facts: Array = [
		{},
		_fact(&"axe", &"gun_perfect_reload", generation, 1, 0),
		_fact(&"gun", &"sword_perfect_guard", generation, 2, 0),
		_fact(&"gun", &"unknown_mastery", generation, 3, 0),
		_fact(&"gun", &"gun_perfect_reload", generation + 1, 4, 0),
		_fact(&"gun", &"gun_perfect_reload", generation, 0, 0),
		_fact(&"gun", &"gun_perfect_reload", generation, 5, -1),
		_fact(&"gun", &"gun_perfect_reload", generation, 6, 0, {"is_echo": true}),
		_fact(&"gun", &"gun_perfect_reload", generation, 7, 0, {"recursive_echo": true}),
		_fact(&"gun", &"gun_perfect_reload", generation, 8, 0, {"mastery_eligible": false}),
		_fact(&"gun", &"gun_perfect_reload", generation, 9, 0, {"rejected": true}),
		_fact(&"gun", &"gun_perfect_reload", generation, 10, 0, {"tags": ["no_mastery"]}),
		_fact(&"gun", &"gun_perfect_reload", generation, 14, 0, {"unsafe": RefCounted.new()}),
		_fact(&"gun", &"gun_perfect_reload", generation, 15, 0, {"nested": [{"unsafe": Resource.new()}]}),
		_fact(&"gun", &"gun_perfect_reload", generation, 16, 0, {"unsafe": Callable(self, "_ready")}),
	]
	var weapon_mismatch := _fact(&"gun", &"gun_perfect_reload", generation, 11, 0)
	weapon_mismatch["mastery_family"] = &"sword"
	invalid_facts.append(weapon_mismatch)
	var unknown_field := _fact(&"gun", &"gun_perfect_reload", generation, 12, 0)
	unknown_field["unknown"] = true
	invalid_facts.append(unknown_field)
	var wrong_context := _fact(&"gun", &"gun_perfect_reload", generation, 13, 0)
	wrong_context["context"] = []
	invalid_facts.append(wrong_context)
	for invalid_fact: Variant in invalid_facts:
		_suite.assert_true(
			not bool(coordinator.call("confirm_weapon_mastery", invalid_fact)),
			"invalid, stale, echo, recursive, or no-mastery fact rejects"
		)
	_suite.assert_equal(coordinator.call("action_snapshot"), before_action, "rejected facts do not install claims")
	_suite.assert_equal(runtime.snapshot(), before_runtime, "rejected facts do not invoke Character Runtime")
	_suite.assert_equal(_recorder.facts.size(), before_count, "rejected facts publish no EventBus signal")


func _test_runtime_rejection_rolls_back_before_claim_and_publication() -> void:
	var fixture := _coordinator_fixture()
	var coordinator: RefCounted = fixture.coordinator
	var runtime: FakeCharacterRuntime = fixture.runtime
	var generation := int(coordinator.call("generation"))
	var fact := _fact(&"sword", &"sword_counter_confirmed", generation, 17, 91)
	var before_runtime := runtime.snapshot()
	var before_action: Dictionary = coordinator.call("action_snapshot")
	var before_count := _recorder.facts.size()
	runtime.reject_next_mastery = true
	_suite.assert_true(
		not coordinator.call("confirm_weapon_mastery", fact),
		"malformed/rejected Character Runtime hook rejects the mastery transaction"
	)
	_suite.assert_equal(runtime.snapshot(), before_runtime, "partial Character Runtime mutation rolls back exactly")
	_suite.assert_equal(coordinator.call("action_snapshot"), before_action, "hook rejection installs no claim")
	_suite.assert_equal(_recorder.facts.size(), before_count, "hook rejection publishes no signal")
	_suite.assert_true(
		coordinator.call("confirm_weapon_mastery", fact),
		"rolled-back claim remains available for a later valid hook"
	)


func _test_runtime_rollback_failure_still_publishes_nothing() -> void:
	var fixture := _coordinator_fixture()
	var coordinator: RefCounted = fixture.coordinator
	var runtime: FakeCharacterRuntime = fixture.runtime
	var generation := int(coordinator.call("generation"))
	var fact := _fact(&"sword", &"sword_counter_confirmed", generation, 18, 92)
	var before_action: Dictionary = coordinator.call("action_snapshot")
	var before_count := _recorder.facts.size()
	runtime.reject_next_mastery = true
	runtime.reject_restore = true
	_suite.assert_true(
		not coordinator.call("confirm_weapon_mastery", fact),
		"failed Character Runtime rollback rejects the mastery transaction"
	)
	_suite.assert_equal(coordinator.call("action_snapshot"), before_action, "rollback failure installs no claim")
	_suite.assert_equal(_recorder.facts.size(), before_count, "rollback failure publishes no signal")


func _test_generation_reset_and_stale_facts() -> void:
	var fixture := _coordinator_fixture()
	var coordinator: RefCounted = fixture.coordinator
	var generation := int(coordinator.call("generation"))
	var first := _fact(&"bow", &"bow_full_charge_weakpoint", generation, 5, 42)
	_suite.assert_true(coordinator.call("confirm_weapon_mastery", first), "first generation claims token five")
	_suite.assert_true(coordinator.call("reset_runtime_state", &"generation_test"), "reset advances mastery generation")
	var next_generation := int(coordinator.call("generation"))
	_suite.assert_equal(next_generation, generation + 1, "reset advances exactly one generation")
	_suite.assert_true(not coordinator.call("confirm_weapon_mastery", first), "stale generation rejects")
	_suite.assert_true(
		coordinator.call("confirm_weapon_mastery", _fact(
			&"bow", &"bow_full_charge_weakpoint", next_generation, 5, 42
		)),
		"later generation may reuse the same numeric token"
	)


func _test_action_snapshot_preserves_claims_and_is_deep_isolated() -> void:
	var fixture := _coordinator_fixture()
	var coordinator: RefCounted = fixture.coordinator
	var runtime: FakeCharacterRuntime = fixture.runtime
	var generation := int(coordinator.call("generation"))
	var context := {"nested": {"value": 7}, "tags": ["mastery"]}
	var fact := _fact(&"staff", &"staff_controlled_zone", generation, 80, 101, context)
	var before_count := _recorder.facts.size()
	_suite.assert_true(coordinator.call("confirm_weapon_mastery", fact), "staff zone claim succeeds")
	var claimed_snapshot: Dictionary = coordinator.call("action_snapshot")
	context.nested.value = 99
	(fact["context"] as Dictionary).nested.value = 88
	_suite.assert_equal(
		(runtime.mastery_contexts[0] as Dictionary).context.nested.value,
		7,
		"caller mutation cannot rewrite Character Runtime fact"
	)
	_suite.assert_equal(
		(_recorder.facts[before_count] as Dictionary).context.nested.value,
		7,
		"caller mutation cannot rewrite published fact"
	)
	var exposed_snapshot: Dictionary = coordinator.call("action_snapshot")
	((exposed_snapshot.mastery_claims[0] as Dictionary).context as Dictionary).nested.value = 77
	_suite.assert_equal(
		((coordinator.call("action_snapshot") as Dictionary).mastery_claims[0] as Dictionary).context.nested.value,
		7,
		"returned action snapshot cannot rewrite stored claim"
	)
	var duplicate_claim_snapshot := claimed_snapshot.duplicate(true)
	(duplicate_claim_snapshot.mastery_claims as Array).append(
		(duplicate_claim_snapshot.mastery_claims[0] as Dictionary).duplicate(true)
	)
	var before_invalid_restore: Dictionary = coordinator.call("action_snapshot")
	_suite.assert_true(
		not coordinator.call("restore_action_snapshot", duplicate_claim_snapshot),
		"duplicate claim snapshot rejects"
	)
	_suite.assert_equal(
		coordinator.call("action_snapshot"),
		before_invalid_restore,
		"invalid claim snapshot is zero mutation"
	)

	_suite.assert_true(coordinator.call("reset_runtime_state", &"snapshot_round_trip"), "fixture mutates generation")
	_suite.assert_true(coordinator.call("restore_action_snapshot", claimed_snapshot), "claim-bearing action snapshot restores")
	_suite.assert_true(not coordinator.call("confirm_weapon_mastery", fact), "restored claim remains deduplicated")


func _test_weapon_runtime_mastery_boundaries() -> void:
	var base_runtime: RefCounted = WeaponRuntimeScript.new()
	_suite.assert_equal(base_runtime.call("mastery_family"), &"", "base runtime has no mastery family")
	_suite.assert_equal(base_runtime.call("mastery_ids"), [], "base runtime has no mastery IDs")
	for family_case: Dictionary in FAMILY_CASES:
		var runtime: RefCounted = (family_case.runtime as GDScript).new()
		var family: StringName = family_case.family
		var mastery_ids: Array = family_case.mastery_ids
		_suite.assert_equal(runtime.call("mastery_family"), family, "%s family is canonical" % family)
		_suite.assert_equal(runtime.call("mastery_ids"), mastery_ids, "%s mastery IDs are canonical" % family)
		for mastery_id: StringName in mastery_ids:
			var context := {"nested": {"value": 4}}
			var payload := {
				"confirmed": true,
				"mastery_eligible": true,
				"is_echo": false,
				"recursive_echo": false,
				"tags": ["weapon:%s" % family],
			}
			var fact: Dictionary = runtime.call(
				"build_mastery_fact",
				mastery_id,
				&"weapon_primary",
				7,
				19,
				31,
				payload,
				context
			)
			_suite.assert_equal(fact.get("weapon_id"), family, "%s fact owns canonical weapon" % mastery_id)
			_suite.assert_equal(fact.get("mastery_family"), family, "%s fact owns canonical family" % mastery_id)
			_suite.assert_equal(fact.get("mastery_id"), mastery_id, "%s fact preserves canonical ID" % mastery_id)
			_suite.assert_equal(fact.get("context"), context, "%s fact preserves semantic context" % mastery_id)
			context.nested.value = 99
			_suite.assert_equal(
				(fact.get("context", {}) as Dictionary).nested.value,
				4,
				"%s fact context is deep isolated" % mastery_id
			)
		_suite.assert_equal(
			runtime.call("build_mastery_fact", &"unknown", &"weapon_primary", 7, 20, 31, {"confirmed": true}, {}),
			{},
			"%s runtime rejects unknown mastery ID" % family
		)
		for rejected_payload: Dictionary in [
			{"confirmed": false},
			{"confirmed": true, "mastery_eligible": false},
			{"confirmed": true, "is_echo": true},
			{"confirmed": true, "recursive_echo": true},
			{"confirmed": true, "rejected": true},
			{"confirmed": true, "tags": ["no_mastery"]},
			{"confirmed": true, "nested": {"unsafe": RefCounted.new()}},
			{"confirmed": true, "nested": [{"unsafe": Resource.new()}]},
			{"confirmed": true, "unsafe": Callable(self, "_ready")},
		]:
			_suite.assert_equal(
				runtime.call(
					"build_mastery_fact",
					mastery_ids[0],
					&"weapon_primary",
					7,
					21,
					31,
					rejected_payload,
					{}
				),
				{},
				"%s rejects ineligible payload boundary" % family
			)
		for unsafe_context: Dictionary in [
			{"unsafe": RefCounted.new()},
			{"nested": [{"unsafe": Resource.new()}]},
			{"unsafe": Callable(self, "_ready")},
		]:
			_suite.assert_equal(
				runtime.call(
					"build_mastery_fact",
					mastery_ids[0],
					&"weapon_primary",
					7,
					22,
					31,
					{"confirmed": true},
					unsafe_context
				),
				{},
				"%s rejects replay-unsafe mastery context" % family
			)


func _coordinator_fixture() -> Dictionary:
	var runtime := FakeCharacterRuntime.new()
	var coordinator: RefCounted = CharacterActionCoordinatorScript.new()
	_suite.assert_true(coordinator.call("configure", runtime), "mastery fixture configures")
	return {"coordinator": coordinator, "runtime": runtime}


func _fact(
	weapon_id: StringName,
	mastery_id: StringName,
	generation: int,
	action_token: int,
	target_id: int,
	context: Dictionary = {}
) -> Dictionary:
	return {
		"weapon_id": weapon_id,
		"mastery_family": weapon_id,
		"mastery_id": mastery_id,
		"action_id": &"weapon_primary",
		"generation": generation,
		"action_token": action_token,
		"target_id": target_id,
		"context": context.duplicate(true),
	}
