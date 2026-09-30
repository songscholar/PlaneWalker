class_name HealthComponent
extends Node

const DamageCalculatorScript := preload("res://scripts/combat/damage_calculator.gd")
const DamageResolutionScript := preload("res://scripts/combat/damage_resolution.gd")

const DEFENSE_DECISION_KEYS := {
	"prevented": true,
	"multiplier": true,
	"prevent_reason": true,
	"guard_kind": true,
	"commit_context": true,
}
const DEFENSE_BYPASS_TAGS := {
	"self_cost": true,
	"corruption": true,
	"terminal": true,
	"unguardable": true,
	"irreversible": true,
}

signal damaged(amount: float, current_hp: float)
signal healed(amount: float, current_hp: float)
signal died(killer: Variant)

@export var max_hp: float = 100.0
@export var defense: float = 0.0
@export var starts_full: bool = true
@export_range(0.0, 1.0, 0.05) var damage_received_multiplier: float = 1.0

var current_hp: float = 0.0
var invulnerable: bool = false
var dead: bool = false
var healing_multiplier: float = 1.0
var _invulnerability_token: int = 0
var _active_invulnerability_tokens: Dictionary = {}
var _active_invulnerability_sources: Dictionary = {}


func _ready() -> void:
	if starts_full:
		current_hp = max_hp
	else:
		current_hp = clampf(current_hp, 0.0, max_hp)


func configure_from_stats(stats: Resource) -> void:
	clear_invulnerability_sources()
	max_hp = stats.max_hp
	defense = stats.defense
	current_hp = max_hp
	dead = false


func apply_stat_totals(stats: Resource) -> void:
	var previous_max_hp := max_hp
	max_hp = stats.max_hp
	defense = stats.defense
	if max_hp > previous_max_hp:
		current_hp += max_hp - previous_max_hp
	current_hp = clampf(current_hp, 0.0, max_hp)


func configure_accessibility_assists(assists: Dictionary) -> void:
	var multiplier: Variant = assists.get("damage_received_multiplier", 1.0)
	if typeof(multiplier) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(multiplier)):
		damage_received_multiplier = 1.0
		return
	damage_received_multiplier = clampf(float(multiplier), 0.0, 1.0)


func take_damage(damage_info: RefCounted) -> float:
	return _resolution_finalized_damage(resolve_and_apply_damage(damage_info))


func resolve_and_apply_damage(
	damage_info: RefCounted,
	weapon_decision: Dictionary = {},
	character_decision: Dictionary = {}
) -> RefCounted:
	if damage_info == null:
		return null
	var planned_amount := float(damage_info.amount)
	if (
		not is_finite(planned_amount)
		or planned_amount <= 0.0
		or dead
		or invulnerable
		or _damage_bypasses_defense(damage_info.tags)
	):
		return _apply_damage_resolution(
			damage_info,
			_resolve_damage(damage_info, weapon_decision, character_decision)
		)

	var owner_entity := get_parent()
	if weapon_decision.is_empty() and character_decision.is_empty():
		var planned_decisions := _owner_defense_decisions(owner_entity, damage_info)
		if not bool(planned_decisions.get("ok", false)):
			return _prevented_resolution(damage_info, &"invalid_decision")
		weapon_decision = planned_decisions["weapon"]
		character_decision = planned_decisions["character"]

	var parsed_weapon := _parse_defense_decision(weapon_decision)
	var parsed_character := _parse_defense_decision(character_decision)
	var resolution: RefCounted = _resolve_damage(
		damage_info,
		weapon_decision,
		character_decision
	)
	if resolution == null:
		return null
	var resolution_snapshot: Dictionary = resolution.snapshot()
	if (
		not bool(parsed_weapon.get("ok", false))
		or not bool(parsed_character.get("ok", false))
		or resolution_snapshot.get("prevent_reason", &"") == &"invalid_decision"
	):
		return resolution

	var has_defense_decision := (
		not weapon_decision.is_empty() or not character_decision.is_empty()
	)
	if has_defense_decision:
		if owner_entity == null or not owner_entity.has_method("commit_damage_defense"):
			return _prevented_resolution(damage_info, &"defense_commit_failed")
		var commit_result: Variant = owner_entity.call(
			"commit_damage_defense",
			{
				"weapon": (
					{}
					if weapon_decision.is_empty()
					else _canonical_defense_decision(parsed_weapon)
				),
				"character": (
					{}
					if character_decision.is_empty()
					else _canonical_defense_decision(parsed_character)
				),
			},
			resolution
		)
		if typeof(commit_result) != TYPE_BOOL or not bool(commit_result):
			return _prevented_resolution(damage_info, &"defense_commit_failed")
	return _apply_damage_resolution(damage_info, resolution)


func _resolve_damage(
	damage_info: RefCounted,
	weapon_decision: Dictionary = {},
	character_decision: Dictionary = {}
) -> RefCounted:
	if damage_info == null:
		return null
	var planned_amount := float(damage_info.amount)
	if not is_finite(planned_amount) or planned_amount <= 0.0:
		return _prevented_resolution(damage_info, &"invalid_damage")
	var original_amount := planned_amount
	if dead:
		return _prevented_resolution(damage_info, &"target_dead")
	if invulnerable:
		return _prevented_resolution(damage_info, &"target_invulnerable")

	var parsed_weapon := _parse_defense_decision(weapon_decision)
	var parsed_character := _parse_defense_decision(character_decision)
	if not bool(parsed_weapon.get("ok", false)) or not bool(parsed_character.get("ok", false)):
		return _prevented_resolution(damage_info, &"invalid_decision")

	var post_weapon := original_amount
	var post_character := original_amount
	var post_accessibility := original_amount
	var post_defense := original_amount
	var guard_kind := &""
	var bypasses_defense := _damage_bypasses_defense(damage_info.tags)
	if not bypasses_defense:
		if bool(parsed_weapon["prevented"]):
			post_weapon = 0.0
			post_character = 0.0
			post_accessibility = 0.0
			post_defense = 0.0
			guard_kind = parsed_weapon["guard_kind"]
			var weapon_resolution := DamageResolutionScript.prevented(
				_prevention_reason(parsed_weapon, &"weapon_prevented"),
				_resolution_context(
					damage_info,
					original_amount,
					post_weapon,
					post_character,
					post_accessibility,
					post_defense,
					guard_kind
				)
			)
			return weapon_resolution
		post_weapon *= float(parsed_weapon["multiplier"])
		if parsed_weapon["guard_kind"] != &"":
			guard_kind = parsed_weapon["guard_kind"]

		post_character = post_weapon
		if bool(parsed_character["prevented"]):
			post_character = 0.0
			post_accessibility = 0.0
			post_defense = 0.0
			guard_kind = parsed_character["guard_kind"]
			var character_resolution := DamageResolutionScript.prevented(
				_prevention_reason(parsed_character, &"character_prevented"),
				_resolution_context(
					damage_info,
					original_amount,
					post_weapon,
					post_character,
					post_accessibility,
					post_defense,
					guard_kind
				)
			)
			return character_resolution
		post_character *= float(parsed_character["multiplier"])
		if parsed_character["guard_kind"] != &"":
			guard_kind = parsed_character["guard_kind"]

	post_accessibility = _apply_target_damage_modifiers(damage_info, post_character)
	post_defense = DamageCalculatorScript.apply_flat_defense(post_accessibility, defense)
	var resolution := DamageResolutionScript.applied(
		post_defense,
		_resolution_context(
			damage_info,
			original_amount,
			post_weapon,
			post_character,
			post_accessibility,
			post_defense,
			guard_kind
		)
	)
	if resolution == null:
		return null
	return resolution


func _apply_damage_resolution(damage_info: RefCounted, resolution: RefCounted) -> RefCounted:
	if damage_info == null or resolution == null:
		return resolution
	var snapshot: Dictionary = resolution.snapshot()
	var prevent_reason := StringName(str(snapshot.get("prevent_reason", "")))
	if resolution.is_prevented():
		if prevent_reason not in [
			&"invalid_damage",
			&"target_dead",
			&"target_invulnerable",
			&"invalid_decision",
			&"defense_commit_failed",
		]:
			_emit_damage_observation(damage_info)
		return resolution

	var final_amount := float(resolution.finalized_damage())
	if not is_finite(final_amount) or final_amount <= 0.0:
		return _prevented_resolution(damage_info, &"invalid_resolution")
	_emit_damage_observation(damage_info)
	current_hp = maxf(0.0, current_hp - final_amount)
	damaged.emit(final_amount, current_hp)
	_apply_hit_reaction(damage_info, final_amount)
	EventBus.damage_applied.emit(damage_info, get_parent(), final_amount)
	if current_hp <= 0.0:
		_die(damage_info.attacker)
	return resolution


func _apply_hit_reaction(damage_info: RefCounted, final_amount: float) -> void:
	var owner_entity := get_parent()
	EventBus.hit_confirmed.emit(damage_info, owner_entity, final_amount)
	if damage_info.knockback.length_squared() > 0.0 and owner_entity.has_method("apply_knockback"):
		owner_entity.apply_knockback(damage_info.knockback)
	if owner_entity.has_method("apply_weapon_hit_control"):
		owner_entity.call("apply_weapon_hit_control", damage_info, final_amount)


func _owner_defense_decisions(owner_entity: Node, damage_info: RefCounted) -> Dictionary:
	if not owner_entity.has_method("damage_defense_decisions"):
		return {"ok": true, "weapon": {}, "character": {}}
	var value: Variant = owner_entity.call("damage_defense_decisions", damage_info)
	if not value is Dictionary:
		return {"ok": false}
	var envelope: Dictionary = value
	if envelope.is_empty():
		return {"ok": true, "weapon": {}, "character": {}}
	if envelope.size() != 2 or not envelope.has("weapon") or not envelope.has("character"):
		return {"ok": false}
	if not envelope["weapon"] is Dictionary or not envelope["character"] is Dictionary:
		return {"ok": false}
	return {
		"ok": true,
		"weapon": (envelope["weapon"] as Dictionary).duplicate(true),
		"character": (envelope["character"] as Dictionary).duplicate(true),
	}


func _parse_defense_decision(decision: Dictionary) -> Dictionary:
	if decision.is_empty():
		return {
			"ok": true,
			"prevented": false,
			"multiplier": 1.0,
			"prevent_reason": &"",
			"guard_kind": &"",
			"commit_context": {},
		}

	var canonical: Dictionary = {}
	for key_value: Variant in decision.keys():
		if typeof(key_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return {"ok": false}
		var key := str(key_value)
		if not DEFENSE_DECISION_KEYS.has(key) or canonical.has(key):
			return {"ok": false}
		canonical[key] = decision[key_value]

	var prevented_value: Variant = canonical.get("prevented", false)
	if typeof(prevented_value) != TYPE_BOOL:
		return {"ok": false}
	var prevented := bool(prevented_value)
	var multiplier_value: Variant = canonical.get("multiplier", 1.0)
	if (
		typeof(multiplier_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(multiplier_value))
	):
		return {"ok": false}
	var multiplier := float(multiplier_value)
	if multiplier < 0.0 or multiplier > 1.0 or (prevented and not is_equal_approx(multiplier, 1.0)):
		return {"ok": false}

	var prevent_reason_value: Variant = canonical.get("prevent_reason", &"")
	var guard_kind_value: Variant = canonical.get("guard_kind", &"")
	if typeof(prevent_reason_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return {"ok": false}
	if typeof(guard_kind_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return {"ok": false}
	var prevent_reason := StringName(str(prevent_reason_value))
	var guard_kind := StringName(str(guard_kind_value))
	if prevented and prevent_reason == &"" and guard_kind == &"":
		return {"ok": false}
	if not prevented and prevent_reason != &"":
		return {"ok": false}

	var commit_context_value: Variant = canonical.get("commit_context", {})
	if not commit_context_value is Dictionary:
		return {"ok": false}
	return {
		"ok": true,
		"prevented": prevented,
		"multiplier": multiplier,
		"prevent_reason": prevent_reason,
		"guard_kind": guard_kind,
		"commit_context": (commit_context_value as Dictionary).duplicate(true),
	}


func _canonical_defense_decision(parsed: Dictionary) -> Dictionary:
	return {
		"prevented": bool(parsed["prevented"]),
		"multiplier": float(parsed["multiplier"]),
		"prevent_reason": StringName(parsed["prevent_reason"]),
		"guard_kind": StringName(parsed["guard_kind"]),
		"commit_context": (parsed["commit_context"] as Dictionary).duplicate(true),
	}


func _prevention_reason(decision: Dictionary, fallback: StringName) -> StringName:
	var prevent_reason: StringName = decision["prevent_reason"]
	if prevent_reason != &"":
		return prevent_reason
	var guard_kind: StringName = decision["guard_kind"]
	return guard_kind if guard_kind != &"" else fallback


func _prevented_resolution(
	damage_info: RefCounted,
	reason: StringName,
	guard_kind: StringName = &""
) -> RefCounted:
	if damage_info == null:
		return null
	var amount := float(damage_info.amount)
	if not is_finite(amount) or amount < 0.0:
		amount = 0.0
	return DamageResolutionScript.prevented(
		reason,
		_resolution_context(
			damage_info,
			amount,
			amount,
			amount,
			amount,
			amount,
			guard_kind
		)
	)


func _resolution_context(
	damage_info: RefCounted,
	original_amount: float,
	post_weapon: float,
	post_character: float,
	post_accessibility: float,
	post_defense: float,
	guard_kind: StringName
) -> Dictionary:
	var run_id := StringName(str(damage_info.run_id))
	if run_id == &"":
		run_id = &"legacy"
	var target_id := StringName(str(damage_info.target_id))
	if target_id == &"pending_target":
		target_id = _authoritative_target_id(target_id)
	if target_id == &"":
		target_id = StringName(get_parent().name if get_parent() != null else "legacy_target")
	var hostile_source_id := StringName(str(damage_info.hostile_source_id))
	if hostile_source_id == &"":
		hostile_source_id = &"legacy_source"
	var attack_generation := maxi(1, int(damage_info.attack_generation))
	var action_token := maxi(1, int(damage_info.action_token))
	var tags: Array = damage_info.tags.duplicate()
	return {
		"run_id": run_id,
		"target_id": target_id,
		"hostile_source_id": hostile_source_id,
		"attack_generation": attack_generation,
		"hit_index": int(damage_info.hit_index),
		"action_token": action_token,
		"source_generation": int(damage_info.source_generation),
		"original_amount": original_amount,
		"post_weapon_defense_amount": post_weapon,
		"post_character_defense_amount": post_character,
		"post_accessibility_amount": post_accessibility,
		"post_defense_amount": post_defense,
		"guard_kind": guard_kind,
		"irreversible": _damage_is_irreversible(tags),
		"tags": tags,
	}


func _authoritative_target_id(fallback: StringName) -> StringName:
	var owner_entity := get_parent()
	if owner_entity == null:
		return fallback
	for key: StringName in [&"stable_target_id", &"stable_target_key", &"encounter_spawn_id"]:
		if owner_entity.has_meta(key):
			var value := str(owner_entity.get_meta(key)).strip_edges()
			if not value.is_empty():
				return StringName(value)
	return fallback


func _damage_bypasses_defense(tags: Array) -> bool:
	for tag_value: Variant in tags:
		var semantic := _tag_semantic(tag_value)
		if DEFENSE_BYPASS_TAGS.has(semantic):
			return true
	return false


func _damage_is_irreversible(tags: Array) -> bool:
	for tag_value: Variant in tags:
		if _tag_semantic(tag_value) == "irreversible":
			return true
	return false


func _tag_semantic(tag_value: Variant) -> String:
	var tag := str(tag_value).strip_edges().to_lower().replace("-", "_")
	var separator := tag.rfind(":")
	return tag.substr(separator + 1) if separator >= 0 else tag


func _emit_damage_observation(damage_info: RefCounted) -> void:
	EventBus.damage_about_to_apply.emit(damage_info, get_parent())


func _resolution_finalized_damage(resolution: RefCounted) -> float:
	if resolution == null:
		return 0.0
	return float(resolution.finalized_damage())


func heal(amount: float) -> float:
	if dead:
		return 0.0
	var previous_hp := current_hp
	current_hp = minf(max_hp, current_hp + amount * healing_multiplier)
	var healed_amount := current_hp - previous_hp
	if healed_amount > 0.0:
		healed.emit(healed_amount, current_hp)
	return healed_amount


func lose_health(amount: float, source: Variant = null) -> float:
	if dead or amount <= 0.0:
		return 0.0
	var final_amount := minf(current_hp, amount)
	current_hp = maxf(0.0, current_hp - final_amount)
	damaged.emit(final_amount, current_hp)
	if current_hp <= 0.0:
		_die(source)
	return final_amount


func _apply_target_damage_modifiers(damage_info: RefCounted, starting_amount: float) -> float:
	var amount := starting_amount
	var owner_entity := get_parent()
	if owner_entity.is_in_group("player"):
		amount *= damage_received_multiplier
	if owner_entity.has_method("get_damage_taken_multiplier_for"):
		var contextual_multiplier_value: Variant = owner_entity.call(
			"get_damage_taken_multiplier_for",
			damage_info
		)
		if typeof(contextual_multiplier_value) in [TYPE_INT, TYPE_FLOAT]:
			var contextual_multiplier := float(contextual_multiplier_value)
			if is_finite(contextual_multiplier) and contextual_multiplier > 0.0:
				amount *= contextual_multiplier
	elif owner_entity.has_method("get_damage_taken_multiplier"):
		var target_multiplier_value: Variant = owner_entity.get_damage_taken_multiplier()
		if typeof(target_multiplier_value) in [TYPE_INT, TYPE_FLOAT]:
			var target_multiplier := float(target_multiplier_value)
			if is_finite(target_multiplier) and target_multiplier > 0.0:
				amount *= target_multiplier
	if owner_entity.has_method("get_weakpoint_damage_bonus"):
		var weakpoint_bonus: float = owner_entity.get_weakpoint_damage_bonus(damage_info)
		if weakpoint_bonus > 0.0:
			amount *= 1.0 + weakpoint_bonus
	if damage_info.tags.has("talent:ruin_execute") and _hp_ratio() <= _heavy_execute_threshold(damage_info):
		amount *= 1.0 + _heavy_execute_bonus(damage_info)
	return DamageCalculatorScript.critical_amount(damage_info, amount)


func _hp_ratio() -> float:
	return current_hp / maxf(1.0, max_hp)


func _heavy_execute_bonus(damage_info: RefCounted) -> float:
	if damage_info.source != null:
		return float(damage_info.source.get("heavy_execute_multiplier_bonus"))
	return 0.0


func _heavy_execute_threshold(damage_info: RefCounted) -> float:
	if damage_info.source != null:
		return float(damage_info.source.get("heavy_execute_threshold"))
	return 0.3


func apply_invulnerability(duration: float) -> void:
	if duration <= 0.0:
		return
	_invulnerability_token += 1
	var token := _invulnerability_token
	_active_invulnerability_tokens[token] = true
	_refresh_invulnerability_state()
	_expire_invulnerability(token, duration)


func _expire_invulnerability(token: int, duration: float) -> void:
	await get_tree().create_timer(duration, false).timeout
	_active_invulnerability_tokens.erase(token)
	_refresh_invulnerability_state()


func acquire_invulnerability_source(source_id: StringName) -> bool:
	if source_id == &"" or _active_invulnerability_sources.has(source_id):
		return false
	_active_invulnerability_sources[source_id] = true
	_refresh_invulnerability_state()
	return true


func release_invulnerability_source(source_id: StringName) -> bool:
	if source_id == &"" or not _active_invulnerability_sources.has(source_id):
		return false
	_active_invulnerability_sources.erase(source_id)
	_refresh_invulnerability_state()
	return true


func clear_invulnerability_sources() -> void:
	_active_invulnerability_sources.clear()
	_refresh_invulnerability_state()


func _refresh_invulnerability_state() -> void:
	invulnerable = (
		not _active_invulnerability_tokens.is_empty()
		or not _active_invulnerability_sources.is_empty()
	)


func is_alive() -> bool:
	return not dead


func _die(killer: Variant) -> void:
	if dead:
		return
	dead = true
	clear_invulnerability_sources()
	EventBus.entity_died.emit(get_parent(), killer)
	died.emit(killer)
