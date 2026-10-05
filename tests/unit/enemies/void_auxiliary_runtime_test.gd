extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
var suite: RefCounted
var definition: Dictionary
var identity := {"run_id": "run-void", "hostile_source_id": "void-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}


func _ready() -> void:
	suite = Suite.new()
	var path := "res://scripts/enemies/launch/void_auxiliary_runtime.gd"
	suite.assert_true(FileAccess.file_exists(path), "Void auxiliary effects have a finite authoritative domain")
	if FileAccess.file_exists(path):
		var parser := Definition.new()
		parser.configure(Content.boss("void_throne"))
		definition = parser.runtime_projection()
		_statuses(path)
		_tear_and_step(path)
		_pickups_and_restore(path)
		_staged_boundaries(path)
	suite.finish(get_tree())


func _runtime(path: String) -> RefCounted:
	var runtime: RefCounted = load(path).new()
	suite.assert_true(runtime.configure(definition, identity).ok, "Void auxiliary binds canonical authored content")
	suite.assert_true(runtime.bind_origin({"x": 0.0, "y": 0.0}), "Void auxiliary binds native arena origin")
	return runtime


func _cast(action_id: String, generation: int, frame: int) -> Dictionary:
	var geometry: Array = []
	var action: Dictionary = {}
	for row: Dictionary in definition.actions:
		if row.id == action_id:
			action = row
	for index: int in range(action.geometry.size()):
		var row: Dictionary = action.geometry[index]
		geometry.append({"hostile_source_id": "void-owner", "attack_generation": generation + index, "shape": row.shape, "origin": {"x": 320.0, "y": 180.0}, "aim_direction": {"x": 1.0, "y": 0.0}, "target_point": {"x": 360.0, "y": 180.0}, "summon_slots": [], "radius": row.radius, "length": row.length, "active_from_frame": frame, "active_through_frame": frame + int(action.active_frames) - 1})
	return {"run_id": "run-void", "owner_source_id": "void-owner", "action_id": action_id, "attack_generation": generation, "runtime_frame": frame, "geometry": geometry, "damage_multiplier": 1.0}


func _damage(generation: int, frame: int, id: String, amount: float = 1.0) -> Dictionary:
	return {"fact_id": id, "run_id": "run-void", "owner_source_id": "void-owner", "attack_generation": generation, "hit_index": 0, "target_id": "player", "runtime_frame": frame, "actual_loss": amount}


func _clock(runtime: RefCounted, through: int) -> void:
	for frame: int in range(int(runtime.snapshot().runtime_frame) + 1, through + 1):
		suite.assert_true(runtime.advance_frame(frame), "Void auxiliary advances a contiguous finite clock")


func _statuses(path: String) -> void:
	var runtime := _runtime(path)
	suite.assert_true(runtime.reserve_cast(_cast("voidking_scepter_strike", 7, 0)).ok, "real scepter generation reserves burn authority")
	var damage := _damage(7, 0, "scepter-health")
	suite.assert_true(runtime.accept_damage_receipt(damage).ok and not runtime.accept_damage_receipt(damage).ok, "accepted scepter Health loss installs burn once")
	var ticks := 0
	for frame: int in range(1, 182):
		runtime.advance_frame(frame)
		var requests: Array = runtime.burn_damage_requests(frame)
		ticks += requests.size()
		if not requests.is_empty():
			suite.assert_equal(requests[0].damage, 2.0, "scepter burn deals authored2damage")
	suite.assert_true(ticks == 6 and runtime.snapshot().burns.is_empty(), "scepter burn ticks every30frames through180 then retires")
	suite.assert_true(runtime.reserve_cast(_cast("voidking_void_bolt", 8, 181)).ok, "bolt owns a visible projectile generation")
	suite.assert_true(runtime.accept_damage_receipt(_damage(8, 181, "bolt-health")).ok, "accepted bolt Health loss owns finite slow")
	suite.assert_equal(runtime.target_modifiers("player").get("movement_multiplier"), 0.65, "bolt slow is0.65")
	_clock(runtime, 301)
	suite.assert_true(runtime.target_modifiers("player").is_empty(), "bolt slow expires exactly120frames after receipt")
	runtime.reserve_cast(_cast("voidking_void_grasp", 9, 301))
	runtime.accept_damage_receipt(_damage(9, 301, "grasp-health"))
	suite.assert_equal(runtime.target_modifiers("player").get("movement_multiplier"), 0.4, "grasp slow is0.4")
	runtime.reserve_cast(_cast("voidking_devour", 10, 301))
	runtime.accept_damage_receipt(_damage(10, 301, "devour-health"))
	suite.assert_equal(runtime.target_modifiers("player").get("attack_multiplier"), 0.85, "devour output is0.85 without touching inventory")
	_clock(runtime, 391)
	suite.assert_true(not runtime.target_modifiers("player").has("movement_multiplier"), "grasp retires after90frames")
	_clock(runtime, 481)
	suite.assert_true(runtime.target_modifiers("player").is_empty(), "devour output retires after180frames")
	var foreign := _damage(10, 481, "foreign")
	foreign.owner_source_id = "foreign"
	suite.assert_true(not runtime.accept_damage_receipt(foreign).ok, "foreign owner cannot install Void statuses")
	runtime.reserve_cast(_cast("voidking_void_bolt", 11, 481))
	runtime.accept_damage_receipt(_damage(11, 481, "zero-health", 0.0))
	suite.assert_true(runtime.target_modifiers("player").is_empty(), "zero actual Health loss cannot install a slow")


func _tear_and_step(path: String) -> void:
	var runtime := _runtime(path)
	runtime.reserve_cast(_cast("voidking_plane_tear", 7, 0))
	_clock(runtime, 89)
	suite.assert_true(runtime.mechanism_requests(89).is_empty(), "tear final warning waits for its90frame zone")
	runtime.advance_frame(90)
	var requests: Array = runtime.mechanism_requests(90)
	suite.assert_true(requests.size() == 1 and requests[0].kind == "void_tear_final" and requests[0].parameters.warning_frames == 40 and requests[0].parameters.damage == 25.0 and requests[0].parameters.radius == 32.0, "tear final burst starts its own40frame warning with25/r32")
	suite.assert_equal(requests[0].position, {"x": 480.0, "y": 180.0}, "tear final warning owns its frozen line endpoint")
	runtime.reserve_cast(_cast("voidking_void_step", 8, 90))
	var landing := {"run_id": "run-void", "owner_source_id": "void-owner", "attack_generation": 8, "runtime_frame": 90, "position": {"x": 320.0, "y": 180.0}, "landed": true}
	suite.assert_true(runtime.accept_landing_receipt(landing).ok and not runtime.accept_landing_receipt(landing).ok, "actual Step landing settles once")
	var followup: Dictionary = runtime.step_followup_request(90)
	suite.assert_true(followup.action_id == "voidking_scepter_strike" and followup.warning_frames == 28, "Step follow-up requests a real independently warned action")
	suite.assert_true(runtime.accept_followup_receipt(8, 9, 90).ok and runtime.step_followup_request(90).is_empty(), "follow-up generation is claimed only once")
	var forged := landing.duplicate(true)
	forged.attack_generation = 10
	suite.assert_true(not runtime.accept_landing_receipt(forged).ok, "unreserved Step cannot relocate")
	suite.assert_true(runtime.accept_phase(1, 90).ok and runtime.mechanism_requests(90).is_empty(), "phase transition cancels pending finite auxiliary work")


func _pickups_and_restore(path: String) -> void:
	var runtime := _runtime(path)
	runtime.reserve_cast(_cast("voidking_shard_projection", 7, 0))
	suite.assert_true(runtime.active_pickups().size() == 4, "eight shards create at mostfour finite native pickups")
	runtime.reserve_cast(_cast("voidking_shard_projection", 15, 0))
	suite.assert_equal(runtime.active_pickups().size(), 4, "concurrent shard casts respect the fourpickup cap")
	var pickup: Dictionary = runtime.active_pickups()[0]
	var receipt := {"fact_id": "pickup-energy", "run_id": "run-void", "owner_source_id": "void-owner", "pickup_id": pickup.id, "target_id": "player", "runtime_frame": 0, "energy_before": 98.0, "energy_after": 100.0, "maximum": 100.0, "revision_before": 1, "revision_after": 2}
	suite.assert_true(runtime.consume_pickup(receipt).ok and not runtime.consume_pickup(receipt).ok, "real capped2energy receipt consumes one +5pickup once")
	suite.assert_equal(runtime.active_pickups().size(), 3, "used pickup leaves native projection immediately")
	var current: Dictionary = runtime.snapshot()
	var cold := _runtime(path)
	suite.assert_true(cold.restore_snapshot(current) and cold.snapshot() == current, "fresh auxiliary reconstructs cast and resource receipt exactly")
	for kind: String in ["energy", "clock", "position", "cast", "unknown"]:
		var forged := current.duplicate(true)
		match kind:
			"energy": forged.pickups[0].energy_amount = 5.0
			"clock": forged.pickups[0].through_frame += 1
			"position": forged.pickups[0].position.x += 1.0
			"cast": forged.casts[0].action_id = "voidking_void_bolt"
			"unknown": forged.extra = true
		suite.assert_true(not cold.can_restore_snapshot(forged), "cold auxiliary rejects forged " + kind)
	_clock(runtime, 180)
	suite.assert_true(runtime.active_pickups().is_empty(), "unclaimed pickups expire after180frames")
	suite.assert_true(runtime.can_restore_snapshot(runtime.snapshot(), true), "expired receipts preserve strict event provenance")
	runtime.retire()
	suite.assert_true(runtime.target_modifiers("player").is_empty() and runtime.active_pickups().is_empty() and runtime.can_restore_snapshot(runtime.snapshot(), true), "Boss death retires finite work and remains recoverable")


func _staged_boundaries(path: String) -> void:
	var runtime := _runtime(path)
	var cast := _cast("voidking_tentacle_lash", 7, 1)
	suite.assert_true(runtime.reserve_cast(cast).ok and runtime.can_restore_snapshot(runtime.snapshot()) and not runtime.can_restore_snapshot(runtime.snapshot(), true), "nextframe cast is reversible but not an accepted cold boundary")
	suite.assert_true(runtime.advance_frame(1) and runtime.snapshot().exposure_through_frame == 30, "tentacle opens exactly30accepted frames of exposure")
	suite.assert_true(runtime.accept_phase(1, 2).ok and runtime.advance_frame(2) and runtime.can_restore_snapshot(runtime.snapshot(), true), "staged phase retirement rebuilds using its event frame")
	var corrupt := _cast("voidking_void_bolt", 8, 2)
	corrupt.geometry[0].radius = 12.0
	var before: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.reserve_cast(corrupt).ok and runtime.snapshot() == before, "unapproved geometry cannot reserve a cast or mutate state")
	var fresh := _runtime(path)
	suite.assert_true(fresh.restore_snapshot(runtime.snapshot()), "fresh domain restores phase retirement and tentacle receipt")
