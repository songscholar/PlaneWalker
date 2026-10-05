extends Node

const Registry := preload("res://scripts/content/content_registry.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Boss := preload("res://scripts/enemies/launch/boss_definition.gd")
const Runtime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
const Responses := preload("res://scripts/enemies/launch/time_sovereign_response_runtime.gd")
const CharacterProfile := preload("res://scripts/player/characters/character_runtime_profile.gd")
const WeaponProfile := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")
const Catalog := preload("res://scripts/dungeon/launch_encounter_catalog.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Payload := preload("res://scripts/enemies/launch/launch_hostile_payload_runtime.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const CHARACTERS := ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord"]
const WEAPONS := ["sword", "bow", "gun", "staff", "gauntlets"]
const TIME_PAIRS := [["stop", "rewind"], ["stop", "rift"], ["stop", "accelerate"], ["rewind", "rift"], ["rewind", "accelerate"], ["rift", "accelerate"]]
const CASE_COUNT := 22500
const BOUNDS := {"x": 0.0, "y": 0.0, "width": 640.0, "height": 360.0}
var _registry: RefCounted
var _catalog: RefCounted
var _bosses := {}
var _characters := {}
var _weapons := {}
var _errors: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_registry = Registry.new()
	var loaded: RefCounted = _registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	_check(not loaded.has_blocking_errors(), "authoritative Base load")
	_catalog = Catalog.new()
	_check(_catalog.configure(_registry).ok, "authoritative encounter/affix catalog")
	for row: Dictionary in _registry.get_catalog_entries(&"boss_definition", &"LAUNCH"):
		var parser := Boss.new()
		if _check(parser.configure(row).ok, "canonical Boss " + str(row.id)):
			_bosses[row.id] = parser.runtime_projection()
	for character_id: String in CHARACTERS:
		var profile: Dictionary = _registry.resolve_character_runtime_profile(StringName(character_id), &"LAUNCH")
		var parser: RefCounted = CharacterProfile.from_definition(profile)
		if _check(parser != null, "canonical character profile " + character_id):
			_characters[character_id] = parser.snapshot()
	for weapon_id: String in WEAPONS:
		var profile: Dictionary = _registry.resolve_weapon_runtime_profile(StringName(weapon_id), &"LAUNCH")
		var parser := WeaponProfile.new()
		if _check(parser.configure(profile).ok, "canonical weapon profile " + weapon_id):
			_weapons[weapon_id] = parser.snapshot()
	_check(_bosses.size() == 5 and _characters.size() == 5 and _weapons.size() == 5, "exact parsed Launch profile closure")
	var start := int(OS.get_environment("PLANEWALKER_SYNTHETIC_START"))
	var count := int(OS.get_environment("PLANEWALKER_SYNTHETIC_COUNT")) if not OS.get_environment("PLANEWALKER_SYNTHETIC_COUNT").is_empty() else 5
	_check(start >= 0 and count > 0 and start + count <= CASE_COUNT, "canonical synthetic range")
	var rows: Array[Dictionary] = []
	if _errors.is_empty():
		for index: int in range(start, start + count):
			var identity := case_identity(index)
			var first := _simulate(identity)
			var second := _simulate(identity)
			var repeated: bool = first.bytes == second.bytes
			var row: Dictionary = first.row
			row["repeat_sha256"] = str(second.bytes).sha256_text()
			if not repeated:
				row.errors.append("full trace byte divergence")
			row.errors.append_array(second.row.errors)
			rows.append(row)
			if not row.errors.is_empty():
				_errors.append("case %d: %s" % [index, row.errors])
				break
			if (index + 1) % 100 == 0:
				print("P15_SYNTHETIC_CASE ", index + 1, "/22500")
	var budgets := _budget_probe() if _errors.is_empty() else {}
	var counterplay := _counterplay_probe() if _errors.is_empty() else {}
	var output := OS.get_environment("PLANEWALKER_SYNTHETIC_OUTPUT")
	if output.is_empty():
		output = "res://build/p15-synthetic-probe.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"schema_version": 1, "synthetic": true, "production_case_count": 0, "human_playtests": 0, "range_start": start, "requested_case_count": count, "content_snapshot": Content.snapshot(_registry), "cases": rows, "budgets": budgets, "counterplay": counterplay, "errors": _errors}, "\t", true, true) + "\n")
		file.close()
	else:
		_errors.append("report write failed")
	if not _errors.is_empty():
		push_error(str(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)


static func case_identity(index: int) -> Dictionary:
	var seed_index := index / 750
	var local := index % 750
	var loadout := local / 5
	var boss_index := local % 5
	var character_index := loadout / 30
	var weapon_index := (loadout % 30) / 6
	var pair: Array = TIME_PAIRS[loadout % 6].duplicate()
	var seed := 2026100500 + seed_index
	return {"index": index, "seed_index": seed_index, "seed": seed, "loadout_index": loadout, "character_id": CHARACTERS[character_index], "weapon_id": WEAPONS[weapon_index], "time_abilities": pair, "boss_id": Ids.BOSS_IDS[boss_index], "boss_index": boss_index, "key": "%d|%s|%s|%s+%s|%s" % [seed, CHARACTERS[character_index], WEAPONS[weapon_index], pair[0], pair[1], Ids.BOSS_IDS[boss_index]]}


func _simulate(identity: Dictionary) -> Dictionary:
	var definition: Dictionary = _bosses[identity.boss_id]
	var character: Dictionary = _characters[identity.character_id]
	var weapon: Dictionary = _weapons[identity.weapon_id]
	var native_identity := {"run_id": "synthetic-%d-%s" % [identity.seed, identity.boss_id], "hostile_source_id": "domain-" + str(identity.boss_id), "next_generation_floor": 7, "runtime_frame": 0, "seed": int(identity.seed)}
	var runtime := Runtime.new()
	var errors: Array[String] = []
	var traces: Array = []
	var row := {"identity": identity.duplicate(true), "action_id": "", "frames": 0, "time_inputs": identity.time_abilities.duplicate(), "time_input_count": 0, "profile_inputs_consumed": false, "accepted_damage": 0.0, "typed_cold_next_frame_equal": false, "malformed_snapshot_refused": false, "phase_monotonic": false, "terminal_cleanup": false, "hit_count": 0, "effect_count": 0, "unwarned_hits": 0, "checkpoint_sha256": "", "profile_inputs_sha256": "", "recipe_affix_sha256": "", "recipe_id": "", "affix_ids": [], "profile_inputs": {}, "time_observations": [], "enrage_threshold_observed": false, "errors": errors}
	if not runtime.configure(definition, native_identity).ok or not runtime.configure_arena_origin({"x": 0.0, "y": 0.0}):
		errors.append("Boss runtime configure")
		return {"row": row, "bytes": ""}
	var weapon_action: Dictionary = weapon.actions.filter(func(action: Dictionary): return action.semantic_action == "weapon_primary")[0]
	var payload: Dictionary = weapon.payloads.filter(func(value: Dictionary): return value.payload_id == weapon_action.payload_id)[0]
	var amount := float(character.base_stats.attack) * float(payload.parameters.get("damage_multiplier", 1.0))
	var inputs := {"character_profile": character.id, "weapon_profile": weapon.id, "attack": float(character.base_stats.attack), "attack_speed": float(character.base_stats.attack_speed), "move_speed": float(character.base_stats.move_speed), "weapon_action": weapon_action.duplicate(true), "payload": payload.duplicate(true), "time_interactions": {}, "synthetic_damage_amount": amount}
	for ability: String in identity.time_abilities:
		inputs.time_interactions[ability] = {"character": character.time_interactions[ability].duplicate(true), "weapon": weapon.time_interactions[ability].duplicate(true)}
	row.profile_inputs_sha256 = _json(inputs).sha256_text()
	row.profile_inputs = inputs.duplicate(true)
	row.profile_inputs_consumed = amount > 0.0
	traces.append({"inputs": inputs})
	var recipe: Dictionary = _catalog.resolve_for_revision(Ids.PROFILE_IDS[int(identity.boss_index)], int(identity.seed), "domain-repeat", "elite", "", 2)
	if recipe.is_empty():
		errors.append("seeded recipe resolution")
	else:
		row.recipe_id = recipe.id
		for wave: Dictionary in recipe.waves:
			for spawn: Dictionary in wave.spawns:
				for affix_id: String in spawn.affix_ids:
					if not row.affix_ids.has(affix_id):
						row.affix_ids.append(affix_id)
					if _catalog.affix_definition(affix_id).is_empty():
						errors.append("seeded authored affix")
		row.affix_ids.sort()
	row.recipe_affix_sha256 = _json(recipe).sha256_text()
	traces.append({"recipe_affixes": recipe})
	var action := _selected_action(definition, identity)
	row.action_id = action.id
	var phase := _action_phase(definition, action.id, identity)
	var context := _context(identity, action, 0, character, weapon_action)
	if phase > 0:
		var hp := float(definition.max_hp) * float(definition.phases[phase].hp_threshold)
		var changed: Dictionary = runtime.accept_damage_fact({"fact_id": "synthetic-phase", "runtime_frame": 0, "target_source_id": native_identity.hostile_source_id, "amount": float(definition.max_hp) - hp, "hp_after": hp})
		if not changed.ok:
			errors.append("phase admission")
		traces.append({"phase": changed})
		for frame: int in range(1, 61):
			context.runtime_frame = frame
			var result := runtime.advance_frame(frame, context, false)
			if not result.ok:
				errors.append("phase frame")
				break
	if action.id == definition.enrage.action_id:
		var preparation := HashingContext.new()
		preparation.start(HashingContext.HASH_SHA256)
		for frame: int in range(int(runtime.snapshot().runtime_frame) + 1, int(definition.enrage.threshold_frames) + 1):
			context.runtime_frame = frame
			var result := runtime.advance_frame(frame, context, false)
			preparation.update((_json(result) + "\n").to_utf8_buffer())
			if not result.ok:
				errors.append("full enrage preparation")
				break
		row.enrage_threshold_observed = int(runtime.snapshot().runtime_frame) == int(definition.enrage.threshold_frames) and runtime.snapshot().mechanism_state.enraged
		traces.append({"enrage_preparation_sha256": preparation.finish().hex_encode(), "accepted_threshold": runtime.snapshot().runtime_frame, "enraged": runtime.snapshot().mechanism_state.enraged})
	var frame := int(runtime.snapshot().runtime_frame)
	context.runtime_frame = frame
	if identity.boss_id == "time_sovereign":
		var ordered: Array = identity.time_abilities.duplicate()
		if str(action.id).begins_with("traitor.counter_"):
			var ability := str(action.id).trim_prefix("traitor.counter_")
			ordered.erase(ability)
			ordered.push_front(ability)
		for index: int in range(ordered.size()):
			var receipt := _receipt(native_identity.run_id, frame, index + 1, ordered[index], context.target_position)
			var admitted: Dictionary = runtime.accept_time_ability_receipt(receipt)
			if not admitted.ok:
				errors.append("equipped paid receipt")
			traces.append({"receipt": receipt, "admitted": admitted})
		if action.id == "traitor.counter_stop":
			for _offset: int in range(int(definition.mechanisms.counter_stop_delay_frames)):
				frame += 1
				context.runtime_frame = frame
				if not runtime.advance_frame(frame, context, false).ok:
					errors.append("paid Stop counter delay")
	var request := runtime.request_action(action.id, context)
	if not request.ok:
		errors.append("authored move request: " + str(request))
		row.frames = frame
		return {"row": row, "bytes": _json(traces)}
	traces.append({"request": request})
	var commit_frame := frame
	for ability: String in identity.time_abilities:
		row.time_input_count += 1
		if ability == "stop":
			var duration := 180 + int(character.time_interactions.stop.parameters.get("window_bonus_frames", 0))
			var accepted := runtime.add_control_source("synthetic-stop", "stop", duration, 1.0)
			var observation := {"ability": ability, "kind": "actual_boss_control", "duration": duration, "accepted": accepted, "conversion": runtime.snapshot().mechanism_state.delay_remaining_frames}
			row.time_observations.append(observation)
			traces.append(observation)
			if not accepted:
				errors.append("positive Stop conversion")
		elif ability == "rift":
			var accepted := runtime.add_control_source("synthetic-rift", "rift", 120, 0.4)
			var observation := {"ability": ability, "kind": "actual_boss_control", "accepted": accepted, "actual_multiplier": runtime.control_modifiers().movement_multiplier}
			row.time_observations.append(observation)
			traces.append(observation)
			if not accepted or float(runtime.control_modifiers().movement_multiplier) < 0.70:
				errors.append("bounded Rift conversion")
		else:
			var observation := {"ability": ability, "kind": "synthetic_profile_damage", "synthetic_profile_observation": inputs.time_interactions[ability]}
			row.time_observations.append(observation)
			traces.append(observation)
	var checkpoint_offset := maxi(1, int(action.warning_frames) / 2)
	var cold_done := false
	var initial_phase := int(runtime.snapshot().mechanism_state.phase_index)
	for offset: int in range(1, 1000):
		frame += 1
		context.runtime_frame = frame
		var checkpoint := runtime.snapshot() if not cold_done and offset == checkpoint_offset else {}
		var before_position: Dictionary = context.source_position.duplicate(true)
		var motion: Dictionary = runtime.motion_for_frame(frame, context)
		if not motion.get("ok", false):
			errors.append("authored motion")
			break
		context.source_position = {"x": float(context.source_position.x) + float(motion.displacement.x), "y": float(context.source_position.y) + float(motion.displacement.y)}
		var result := runtime.advance_frame(frame, context, false)
		if not result.ok:
			errors.append("authored frame: " + str(result))
			break
		traces.append({"frame": frame, "motion": motion, "batch": result})
		row.hit_count += result.hit_facts.size()
		row.effect_count += result.effect_requests.size()
		var state := runtime.snapshot() if not checkpoint.is_empty() or result.phase == "IDLE" else {}
		for hit: Dictionary in result.hit_facts:
			if hit.runtime_frame < commit_frame + int(action.warning_frames):
				row.unwarned_hits += 1
		if not cold_done and offset == checkpoint_offset:
			var encoded := Replay.encode_replay_json(checkpoint)
			var decoded := Replay.decode_replay_json(encoded.get("json", ""))
			var fresh := Runtime.new()
			var restored: bool = fresh.configure(definition, native_identity).ok and fresh.configure_arena_origin({"x": 0.0, "y": 0.0}) and encoded.ok and decoded.ok and fresh.restore_snapshot(decoded.replay)
			row.checkpoint_sha256 = str(encoded.get("json", "")).sha256_text()
			if restored:
				var cold_context := context.duplicate(true)
				cold_context.source_position = before_position
				var cold_motion := fresh.motion_for_frame(frame, cold_context)
				cold_context.source_position = {"x": float(before_position.x) + float(cold_motion.displacement.x), "y": float(before_position.y) + float(cold_motion.displacement.y)}
				row.typed_cold_next_frame_equal = checkpoint.action.phase == "WARNING" and cold_motion == motion and fresh.advance_frame(frame, cold_context, false) == result and fresh.snapshot() == state
				var forged := fresh.snapshot()
				forged.mechanism_state.hp_current = float(definition.max_hp) + 1.0
				row.malformed_snapshot_refused = not fresh.restore_snapshot(forged) and fresh.snapshot() == state
			cold_done = true
		if offset > int(action.warning_frames) + int(action.active_frames) + int(action.recovery_frames) and result.phase == "IDLE" and int(state.mechanism_state.delay_remaining_frames) == 0:
			break
	if row.effect_count == 0 or row.hit_count < action.hit_schedule.size():
		errors.append("authored schedule did not execute")
	var current_hp := float(runtime.snapshot().mechanism_state.hp_current)
	var damage_observations: Array[Dictionary] = [{"kind": "profile_primary", "amount": amount}]
	for ability: String in identity.time_abilities:
		if ability in ["rewind", "accelerate"]:
			var multiplier: float = float(weapon.time_interactions[ability].parameters.get("damage_multiplier", 1.0))
			damage_observations.append({"kind": "synthetic_" + ability + "_profile", "amount": amount * multiplier})
	for index: int in range(damage_observations.size()):
		var fact := {"fact_id": "synthetic-profile-hit-%d" % index, "runtime_frame": frame, "target_source_id": native_identity.hostile_source_id, "amount": float(damage_observations[index].amount), "hp_after": maxf(0.0, current_hp - float(damage_observations[index].amount))}
		var accepted := runtime.accept_damage_fact(fact)
		if not accepted.ok or runtime.accept_damage_fact(fact).ok:
			errors.append("profile damage admission/dedup")
		row.accepted_damage += current_hp - float(fact.hp_after)
		current_hp = float(fact.hp_after)
		traces.append({"synthetic_profile_damage": damage_observations[index], "fact": fact, "accepted": accepted})
	row.phase_monotonic = int(runtime.snapshot().mechanism_state.phase_index) >= initial_phase
	var terminal: Dictionary = runtime.cancel(&"synthetic_terminal")
	var final := runtime.snapshot()
	row.terminal_cleanup = terminal.ok and final.terminal and final.action.phase == "IDLE" and final.control.terminal and final.conversion.claims.is_empty() and final.conversion.weapon_sources.is_empty() and (not final.has("time_response") or final.time_response.terminal and final.time_response.pending.is_empty())
	traces.append({"terminal": terminal, "final": final})
	row.frames = frame
	var bytes := _json(traces)
	row["trace_sha256"] = bytes.sha256_text()
	return {"row": row, "bytes": bytes}


func _selected_action(definition: Dictionary, identity: Dictionary) -> Dictionary:
	if identity.loadout_index == 149:
		return definition.actions.filter(func(value: Dictionary): return value.id == definition.enrage.action_id)[0]
	var candidates: Array = (definition.actions + definition.time_responses).filter(func(value: Dictionary): return value.id != definition.enrage.action_id and (not str(value.id).begins_with("traitor.counter_") or identity.time_abilities.has(str(value.id).trim_prefix("traitor.counter_"))))
	return candidates[(int(identity.seed_index) + int(identity.loadout_index)) % candidates.size()].duplicate(true)


static func _action_phase(definition: Dictionary, action_id: String, identity: Dictionary) -> int:
	for index: int in range(definition.phases.size()):
		if definition.phases[index].action_ids.has(action_id):
			return index
	return (int(identity.seed_index) + int(identity.loadout_index)) % definition.phases.size()


static func _context(identity: Dictionary, action: Dictionary, frame: int, character: Dictionary, weapon_action: Dictionary) -> Dictionary:
	var source := {"x": 320.0 + float(identity.seed_index % 7), "y": 180.0}
	var distance := clampf(40.0 + float(weapon_action.windup_frames) + float(character.base_stats.move_speed) / 60.0, float(action.distance_min_px), float(action.distance_max_px))
	return {"runtime_frame": frame, "source_position": source, "target_position": {"x": float(source.x) + distance, "y": float(source.y)}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "synthetic-player"}


static func _receipt(run_id: String, frame: int, token: int, ability: String, target: Dictionary) -> Dictionary:
	var receipt := {"id": "", "run_id": run_id, "owner_generation": 1, "action_generation": 1, "action_token": token, "ability_id": ability, "runtime_frame": frame, "endpoint": target.duplicate(true), "facing": {"x": 1.0, "y": 0.0}}
	receipt.id = Responses.receipt_id(receipt)
	return receipt


func _budget_probe() -> Dictionary:
	var errors: Array[String] = []
	var enemy := Enemy.new()
	var rows: Array = _registry.get_catalog_entries(&"enemy_definition", &"LAUNCH")
	var moth: Dictionary = rows.filter(func(value: Dictionary): return value.id == "corrosive_moth")[0]
	if not enemy.configure(moth).ok:
		return {"errors": ["budget source"]}
	var projection: Dictionary = enemy.runtime_projection()
	var coordinator := Actions.new()
	coordinator.configure({"id": projection.id, "actor_kind": "enemy", "actions": projection.actions}, {"run_id": "synthetic-budget", "hostile_source_id": "budget-source", "next_generation_floor": 7, "runtime_frame": 0})
	var context := {"runtime_frame": 0, "source_position": {"x": 100.0, "y": 100.0}, "target_position": {"x": 120.0, "y": 100.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "synthetic-player"}
	coordinator.request_action("corrosive_moth.corrosive_spit", context)
	var batch := {}
	for frame: int in range(1, 31):
		context.runtime_frame = frame
		batch = coordinator.advance_frame(frame, context)
	var hit: Dictionary = batch.hit_facts[0]
	var runtime := Payload.new()
	runtime.configure("synthetic-budget", 30)
	for index: int in range(256):
		var candidate := hit.duplicate(true)
		candidate.hostile_source_id = "budget-source-%d" % index
		for lane: Dictionary in candidate.geometry:
			lane.hostile_source_id = candidate.hostile_source_id
		if not runtime.reserve_projectile(candidate, BOUNDS, {}).ok:
			errors.append("256 reservation budget")
	var state := runtime.snapshot()
	var before := runtime.snapshot()
	var overflow := hit.duplicate(true)
	overflow.hostile_source_id = "overflow-source"
	for lane: Dictionary in overflow.geometry:
		lane.hostile_source_id = overflow.hostile_source_id
	var refused: bool = not runtime.reserve_projectile(overflow, BOUNDS, {}).ok and before == runtime.snapshot()
	var fresh := Payload.new()
	fresh.configure("synthetic-budget", 30)
	var encoded := Replay.encode_replay_json(state)
	var decoded := Replay.decode_replay_json(encoded.json)
	var cold_equal: bool = encoded.ok and decoded.ok and fresh.restore_snapshot(decoded.replay) and fresh.snapshot() == state
	var next: Dictionary = runtime.advance_frame(31, {"projectile_contacts": {}, "targets": {}})
	cold_equal = cold_equal and fresh.advance_frame(31, {"projectile_contacts": {}, "targets": {}}) == next and fresh.snapshot() == runtime.snapshot()
	var zones := Payload.new()
	zones.configure("synthetic-budget", 30)
	for index: int in range(13):
		if not zones.reserve_death_pool({"kind": "death_pool", "run_id": "synthetic-budget", "hostile_source_id": "zone-%d" % index, "runtime_frame": 30, "attack_generation": index + 1, "position": {"x": 100.0, "y": 100.0}, "bounds": BOUNDS.duplicate(true), "parameters": {"warning_frames": 30, "radius": 16.0, "damage": 5.0}}).ok:
			errors.append("zone pending reservation")
	var zone_state := zones.snapshot()
	var zone_peak: int = zone_state.zones.filter(func(value: Dictionary): return value.phase != "PENDING").size()
	var zone_pulse_peak := 0
	var lifetime := Payload.new()
	lifetime.configure("synthetic-budget", 30)
	lifetime.reserve_projectile(hit, BOUNDS, {})
	for frame: int in range(31, 631):
		var pulse := zones.advance_frame(frame, {"projectile_contacts": {}, "targets": {"budget-player": {"position": {"x": 100.0, "y": 100.0}, "collision_radius_px": 8.0}}})
		if not lifetime.advance_frame(frame, {"projectile_contacts": {}, "targets": {}}).ok or not pulse.ok:
			errors.append("finite payload frame")
			break
		zone_peak = maxi(zone_peak, zones.snapshot().zones.filter(func(value: Dictionary): return value.phase != "PENDING").size())
		zone_pulse_peak = maxi(zone_pulse_peak, pulse.damage_requests.size())
	var response := Responses.new()
	response.configure({"run_id": "synthetic-budget", "hostile_source_id": "time-budget", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}, _bosses.time_sovereign.mechanisms)
	var bounded := true
	for index: int in range(10):
		var admitted: Dictionary = response.accept_receipt(_receipt("synthetic-budget", 0, index + 1, ["stop", "rewind", "accelerate", "rift"][index % 4], {"x": 100.0, "y": 100.0}))
		bounded = admitted.ok and admitted.queued == (index < 4) and response.snapshot().pending.size() <= 4 and bounded
	var pending_peak: int = response.snapshot().pending.size()
	response.retire()
	return {"projectile_peak": state.projectiles.filter(func(value: Dictionary): return value.phase == "ACTIVE").size(), "zone_peak": zone_peak, "zone_pulse_peak": zone_pulse_peak, "reservation_count": state.projectiles.size(), "projectile_overflow_pending": state.projectiles.filter(func(value: Dictionary): return value.phase == "PENDING").size() == 224, "zone_overflow_pending": zone_state.zones.filter(func(value: Dictionary): return value.phase == "PENDING").size() == 1, "reservation_overflow_refused": refused, "typed_cold_equal": cold_equal, "finite_lifetime_cleanup": lifetime.snapshot().projectiles.is_empty() and zones.snapshot().zones.is_empty(), "response_pending_peak": pending_peak, "response_overflow_bounded": bounded, "terminal_response_cleanup": response.snapshot().terminal and response.snapshot().pending.is_empty(), "errors": errors}


func _counterplay_probe() -> Dictionary:
	var rows: Array[Dictionary] = []
	for phase: int in [0, 1]:
		for ability: String in ["stop", "rewind", "accelerate", "rift"]:
			var first := _positive_response(phase, ability)
			var second := _positive_response(phase, ability)
			var row: Dictionary = first.row
			row["trace_sha256"] = str(first.bytes).sha256_text()
			row["repeat_sha256"] = str(second.bytes).sha256_text()
			row["repeat_equal"] = first.bytes == second.bytes
			row.errors.append_array(second.row.errors)
			rows.append(row)
	return {"case_count": rows.size(), "cases": rows}


func _positive_response(phase: int, ability: String) -> Dictionary:
	var definition: Dictionary = _bosses.time_sovereign
	var identity := {"run_id": "synthetic-positive-response", "hostile_source_id": "domain-time-positive", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
	var runtime := Runtime.new()
	var errors: Array[String] = []
	var row := {"phase": phase, "ability": ability, "positive_response": false, "typed_cold_equal": false, "duplicate_refused": false, "terminal_cleanup": false, "errors": errors}
	var traces: Array = []
	if not runtime.configure(definition, identity).ok or not runtime.configure_arena_origin({"x": 0.0, "y": 0.0}):
		errors.append("positive response configure")
		return {"row": row, "bytes": ""}
	var frame := 0
	if phase == 1:
		var changed := runtime.accept_damage_fact({"fact_id": "positive-phase", "runtime_frame": 0, "target_source_id": identity.hostile_source_id, "amount": 800.0, "hp_after": 1200.0})
		traces.append({"phase": changed})
		for next: int in range(1, 61):
			traces.append(runtime.advance_frame(next, _response_context(next), false))
		frame = 60
	var receipt := _receipt(identity.run_id, frame, 1, ability, {"x": 370.0, "y": 180.0})
	var admitted := runtime.accept_time_ability_receipt(receipt)
	var before := runtime.snapshot()
	row.duplicate_refused = admitted.ok and not runtime.accept_time_ability_receipt(receipt).ok and before == runtime.snapshot()
	traces.append({"receipt": receipt, "admitted": admitted})
	if ability == "stop":
		for _offset: int in range(int(definition.mechanisms.counter_stop_delay_frames)):
			frame += 1
			traces.append(runtime.advance_frame(frame, _response_context(frame), false))
	var request := runtime.request_action("traitor.counter_" + ability, _response_context(frame))
	traces.append({"request": request})
	if not request.ok:
		errors.append("positive response paid request")
		return {"row": row, "bytes": _json(traces)}
	var start := frame
	for offset: int in range(1, 23):
		frame = start + offset
		var checkpoint := runtime.snapshot()
		var motion := runtime.motion_for_frame(frame, _response_context(frame))
		var result := runtime.advance_frame(frame, _response_context(frame), false)
		traces.append({"motion": motion, "batch": result})
		if offset == 22:
			var encoded := Replay.encode_replay_json(checkpoint)
			var decoded := Replay.decode_replay_json(encoded.json)
			var fresh := Runtime.new()
			row.typed_cold_equal = fresh.configure(definition, identity).ok and fresh.configure_arena_origin({"x": 0.0, "y": 0.0}) and encoded.ok and decoded.ok and fresh.restore_snapshot(decoded.replay) and fresh.motion_for_frame(frame, _response_context(frame)) == motion and fresh.advance_frame(frame, _response_context(frame), false) == result and fresh.snapshot() == runtime.snapshot()
	if ability == "stop":
		var half: float = float(definition.mechanisms.counter_stop_cancel_damage) / 2.0
		var first := runtime.accept_time_response_watch_hit(_watch(frame, "stop-watch-1", half))
		var duplicate := runtime.accept_time_response_watch_hit(_watch(frame, "stop-watch-1", half))
		var second := runtime.accept_time_response_watch_hit(_watch(frame, "stop-watch-2", half))
		traces.append({"first": first, "duplicate": duplicate, "second": second})
		row.positive_response = first.ok and not first.cancel_action and not duplicate.cancel_action and second.cancel_action and second.exposure_frames == definition.mechanisms.counter_stop_exposure_frames and runtime.snapshot().action.phase == "IDLE"
	elif ability == "rewind":
		var first := runtime.accept_time_response_watch_hit(_watch(frame, "rewind-watch-1", 1.0, false, true))
		var duplicate := runtime.accept_time_response_watch_hit(_watch(frame, "rewind-watch-2", 1.0, false, true))
		traces.append({"first": first, "duplicate": duplicate})
		row.positive_response = first.exposure_frames == definition.mechanisms.counter_rewind_echo_exposure_frames and duplicate.exposure_frames == 0 and runtime.is_exposed()
	else:
		var activation := start + 45
		for next: int in range(frame + 1, activation + 1):
			frame = next
			traces.append(runtime.advance_frame(frame, _response_context(frame), false))
		if ability == "accelerate":
			var shatters := 0
			for index: int in range(int(definition.mechanisms.counter_accelerate_shatter_hits)):
				var hit := runtime.accept_time_response_watch_hit(_watch(frame, "accelerate-watch-%d" % index, 1.0, true))
				traces.append(hit)
				shatters += int(hit.shatter_zone)
			var generation: int = runtime.snapshot().time_response.active.attack_generation
			row.positive_response = shatters == 1 and not runtime.time_response_zone_alive(generation) and runtime.is_exposed()
		else:
			for next: int in range(frame + 1, activation + int(definition.mechanisms.counter_rift_delay_frames) + 1):
				frame = next
				traces.append(runtime.advance_frame(frame, _response_context(frame), false))
			row.positive_response = runtime.snapshot().mechanism_state.delay_remaining_frames == definition.mechanisms.counter_rift_recovery_extension_frames and runtime.snapshot().time_response.active.recovery_granted
	var terminal := runtime.cancel(&"synthetic_positive_terminal")
	var final := runtime.snapshot()
	row.terminal_cleanup = terminal.ok and final.terminal and final.time_response.terminal and final.time_response.pending.is_empty() and final.time_response.active.cancelled
	traces.append({"terminal": terminal, "final": final})
	if not row.positive_response or not row.typed_cold_equal or not row.duplicate_refused or not row.terminal_cleanup:
		errors.append("positive response invariant")
	return {"row": row, "bytes": _json(traces)}


static func _response_context(frame: int) -> Dictionary:
	return {"runtime_frame": frame, "source_position": {"x": 320.0, "y": 180.0}, "target_position": {"x": 370.0, "y": 180.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "synthetic-player"}


static func _watch(frame: int, id: String, amount: float, accelerated: bool = false, echo: bool = false) -> Dictionary:
	return {"fact_id": id, "runtime_frame": frame, "amount": amount, "accelerated": accelerated, "rewind_echo": echo}


func _check(value: bool, label: String) -> bool:
	if not value:
		_errors.append(label)
	return value


static func _json(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)
