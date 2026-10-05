class_name HealthComponent
extends Node

const SceneScope := preload("res://scripts/player/player_scene_scope.gd")

const DamageCalculatorScript := preload("res://scripts/combat/damage_calculator.gd")
const DamageResolutionScript := preload("res://scripts/combat/damage_resolution.gd")
const IrreversibleCharacterLedgerScript := preload("res://scripts/player/characters/irreversible_character_ledger.gd")

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
const REPLAY_SNAPSHOT_FIELDS: Array[String] = [
	"run_id",
	"current_hp",
	"max_hp",
	"healing_multiplier",
	"dead",
	"ledger",
]
const FRAME_SIGNAL_TRANSACTION_SCHEMA_VERSION := 1
const FRAME_SIGNAL_PUBLICATION_SCHEMA_VERSION := 1

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
var _invulnerability_expiry_timers: Dictionary = {}
var _reward_invulnerability_tokens: Dictionary = {}
var _reward_invulnerability_remaining_frames: Dictionary = {}
var _non_reward_invulnerability_remaining_frames: Dictionary = {}
var _irreversible_ledger: RefCounted = IrreversibleCharacterLedgerScript.new()
var _next_frame_signal_transaction_ticket_id: int = 1
var _active_frame_signal_transaction: Dictionary = {}
var _next_frame_signal_publication_id: int = 1
var _prepared_frame_signal_publication: Dictionary = {}
var _finalized_frame_signal_publication: Dictionary = {}
var _frame_signal_publication_in_progress: bool = false
var _post_publication_frame_signal_events: Array[Dictionary] = []
var _published_damage_info: RefCounted
var _published_damage_context: Dictionary = {}
var _hostile_lethal_commit_context: Dictionary = {}
var _hostile_lethal_application_in_progress := false
var _post_defense_absorption_context: Dictionary = {}


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


func configure_run(run_id: StringName) -> bool:
	var normalized := StringName(str(run_id).strip_edges())
	if normalized == &"" or str(normalized).contains(":"):
		return false
	var current_run := irreversible_run_id()
	if current_run == &"":
		return bool(_irreversible_ledger.call("configure_run", normalized))
	if current_run == normalized:
		return true
	_irreversible_ledger.call("reset_for_run", normalized)
	return irreversible_run_id() == normalized


func irreversible_run_id() -> StringName:
	var value: Dictionary = _irreversible_ledger.call("snapshot")
	return StringName(str(value.get("run_id", "")))


func hp_loss_state() -> Dictionary:
	return (_irreversible_ledger.call("hp_loss_state") as Dictionary).duplicate(true)


func irreversible_ledger_snapshot() -> Dictionary:
	return (_irreversible_ledger.call("snapshot") as Dictionary).duplicate(true)


func runtime_state_snapshot() -> Dictionary:
	return {
		"run_id": irreversible_run_id(),
		"current_hp": current_hp,
		"max_hp": max_hp,
		"healing_multiplier": healing_multiplier,
		"dead": dead,
		"ledger": irreversible_ledger_snapshot(),
	}


func begin_frame_signal_transaction(runtime_frame: int) -> Dictionary:
	if (
		not _active_frame_signal_transaction.is_empty()
		or not _prepared_frame_signal_publication.is_empty()
		or not _finalized_frame_signal_publication.is_empty()
		or _frame_signal_publication_in_progress
		or runtime_frame <= 0
	):
		return {}
	var ticket := {
		"schema_version": FRAME_SIGNAL_TRANSACTION_SCHEMA_VERSION,
		"ticket_id": _next_frame_signal_transaction_ticket_id,
		"owner_instance_id": get_instance_id(),
		"runtime_frame": runtime_frame,
	}
	_next_frame_signal_transaction_ticket_id += 1
	ticket["fingerprint"] = _frame_signal_transaction_ticket_fingerprint(ticket)
	_active_frame_signal_transaction = {
		"ticket": ticket.duplicate(true),
		"events": [],
	}
	return ticket.duplicate(true)


func can_commit_frame_signal_transaction(ticket: Dictionary) -> bool:
	return (
		_frame_signal_transaction_ticket_matches(ticket)
		and _finalized_frame_signal_publication.is_empty()
		and not _frame_signal_publication_in_progress
	)


func prepare_frame_signal_publication(ticket: Dictionary) -> Dictionary:
	if not can_commit_frame_signal_transaction(ticket):
		return {}
	if not _prepared_frame_signal_publication.is_empty():
		if ticket == _prepared_frame_signal_publication.get("transaction_ticket", {}):
			return _prepared_frame_signal_publication.duplicate(true)
		return {}
	var publication := {
		"schema_version": FRAME_SIGNAL_PUBLICATION_SCHEMA_VERSION,
		"publication_id": _next_frame_signal_publication_id,
		"owner_instance_id": get_instance_id(),
		"runtime_frame": int(ticket.get("runtime_frame", -1)),
		"transaction_ticket": ticket.duplicate(true),
		"events": (
			_active_frame_signal_transaction.get("events", []) as Array
		).duplicate(true),
	}
	_next_frame_signal_publication_id += 1
	publication["fingerprint"] = _frame_signal_publication_fingerprint(publication)
	_prepared_frame_signal_publication = publication.duplicate(true)
	return publication.duplicate(true)


func finalize_frame_signal_publication(publication: Dictionary) -> bool:
	var transaction_ticket_value: Variant = publication.get("transaction_ticket")
	if not transaction_ticket_value is Dictionary:
		return false
	var transaction_ticket := transaction_ticket_value as Dictionary
	if (
		not _frame_signal_publication_matches(publication)
		or not _frame_signal_transaction_ticket_matches(transaction_ticket)
		or not _finalized_frame_signal_publication.is_empty()
		or _frame_signal_publication_in_progress
		or _active_frame_signal_transaction.get("events", [])
		!= publication.get("events", [])
	):
		return false
	_active_frame_signal_transaction.clear()
	_finalized_frame_signal_publication = _prepared_frame_signal_publication.duplicate(true)
	_prepared_frame_signal_publication.clear()
	return true


func discard_finalized_frame_signal_publication(publication: Dictionary) -> bool:
	if (
		_frame_signal_publication_in_progress
		or not _finalized_frame_signal_publication_matches(publication)
	):
		return false
	_finalized_frame_signal_publication.clear()
	_post_publication_frame_signal_events.clear()
	return true


func publish_prepared_frame_signals() -> void:
	if _finalized_frame_signal_publication.is_empty() or _frame_signal_publication_in_progress:
		return
	var events: Array = (
		_finalized_frame_signal_publication.get("events", []) as Array
	).duplicate(true)
	_finalized_frame_signal_publication.clear()
	_frame_signal_publication_in_progress = true
	_flush_frame_signal_events(events)
	while not _post_publication_frame_signal_events.is_empty():
		var deferred: Array = _post_publication_frame_signal_events.duplicate(true)
		_post_publication_frame_signal_events.clear()
		_flush_frame_signal_events(deferred)
	_frame_signal_publication_in_progress = false


func rollback_frame_signal_transaction(ticket: Dictionary) -> bool:
	if not _frame_signal_transaction_ticket_matches(ticket):
		return false
	_active_frame_signal_transaction.clear()
	_prepared_frame_signal_publication.clear()
	return true


func frame_signal_transaction_is_active() -> bool:
	return not _active_frame_signal_transaction.is_empty()


func frame_signal_transaction_runtime_frame() -> int:
	return int((_active_frame_signal_transaction.get("ticket", {}) as Dictionary).get("runtime_frame", -1))


func _frame_signal_publication_matches(publication: Dictionary) -> bool:
	if (
		_prepared_frame_signal_publication.is_empty()
		or publication.size() != 7
		or typeof(publication.get("schema_version")) != TYPE_INT
		or int(publication.get("schema_version", -1))
		!= FRAME_SIGNAL_PUBLICATION_SCHEMA_VERSION
		or typeof(publication.get("publication_id")) != TYPE_INT
		or int(publication.get("publication_id", 0)) <= 0
		or typeof(publication.get("owner_instance_id")) != TYPE_INT
		or int(publication.get("owner_instance_id", 0)) != get_instance_id()
		or typeof(publication.get("runtime_frame")) != TYPE_INT
		or int(publication.get("runtime_frame", -1)) <= 0
		or not publication.get("transaction_ticket") is Dictionary
		or not publication.get("events") is Array
		or typeof(publication.get("fingerprint")) != TYPE_STRING
		or str(publication.get("fingerprint", ""))
		!= _frame_signal_publication_fingerprint(publication)
	):
		return false
	return publication == _prepared_frame_signal_publication


func _finalized_frame_signal_publication_matches(publication: Dictionary) -> bool:
	if (
		_finalized_frame_signal_publication.is_empty()
		or publication.size() != 7
		or typeof(publication.get("schema_version")) != TYPE_INT
		or int(publication.get("schema_version", -1))
		!= FRAME_SIGNAL_PUBLICATION_SCHEMA_VERSION
		or typeof(publication.get("publication_id")) != TYPE_INT
		or int(publication.get("publication_id", 0)) <= 0
		or typeof(publication.get("owner_instance_id")) != TYPE_INT
		or int(publication.get("owner_instance_id", 0)) != get_instance_id()
		or typeof(publication.get("runtime_frame")) != TYPE_INT
		or int(publication.get("runtime_frame", -1)) <= 0
		or not publication.get("transaction_ticket") is Dictionary
		or not publication.get("events") is Array
		or typeof(publication.get("fingerprint")) != TYPE_STRING
		or str(publication.get("fingerprint", ""))
		!= _frame_signal_publication_fingerprint(publication)
	):
		return false
	var ticket := publication.get("transaction_ticket") as Dictionary
	if not _frame_signal_transaction_ticket_is_authentic(
		ticket,
		int(publication.get("runtime_frame", -1))
	):
		return false
	return publication == _finalized_frame_signal_publication


func _frame_signal_transaction_ticket_matches(ticket: Dictionary) -> bool:
	if (
		_active_frame_signal_transaction.is_empty()
		or not _active_frame_signal_transaction.get("ticket") is Dictionary
	):
		return false
	var active_ticket := _active_frame_signal_transaction.get("ticket") as Dictionary
	return (
		_frame_signal_transaction_ticket_is_authentic(
			ticket,
			int(active_ticket.get("runtime_frame", -1))
		)
		and ticket == active_ticket
	)


func _frame_signal_transaction_ticket_is_authentic(
	ticket: Dictionary,
	expected_runtime_frame: int
) -> bool:
	return (
		ticket.size() == 5
		and typeof(ticket.get("schema_version")) == TYPE_INT
		and int(ticket.get("schema_version", -1))
		== FRAME_SIGNAL_TRANSACTION_SCHEMA_VERSION
		and typeof(ticket.get("ticket_id")) == TYPE_INT
		and int(ticket.get("ticket_id", 0)) > 0
		and typeof(ticket.get("owner_instance_id")) == TYPE_INT
		and int(ticket.get("owner_instance_id", 0)) == get_instance_id()
		and typeof(ticket.get("runtime_frame")) == TYPE_INT
		and int(ticket.get("runtime_frame", -1)) == expected_runtime_frame
		and expected_runtime_frame > 0
		and typeof(ticket.get("fingerprint")) == TYPE_STRING
		and str(ticket.get("fingerprint", ""))
		== _frame_signal_transaction_ticket_fingerprint(ticket)
	)


func _frame_signal_transaction_ticket_fingerprint(ticket: Dictionary) -> String:
	var signed := ticket.duplicate(true)
	signed.erase("fingerprint")
	return var_to_bytes(signed).hex_encode().sha256_text()


func _frame_signal_publication_fingerprint(publication: Dictionary) -> String:
	var signed := publication.duplicate(true)
	signed.erase("fingerprint")
	return var_to_bytes(signed).hex_encode().sha256_text()


func _queue_or_flush_frame_signal_event(kind: StringName, arguments: Array) -> void:
	var event := {
		"kind": kind,
		"arguments": arguments.duplicate(true),
	}
	if _active_frame_signal_transaction.is_empty():
		if not _finalized_frame_signal_publication.is_empty() or _frame_signal_publication_in_progress:
			_post_publication_frame_signal_events.append(event)
			return
		_flush_frame_signal_event(event)
		return
	var events := _active_frame_signal_transaction.get("events", []) as Array
	events.append(event)
	_active_frame_signal_transaction["events"] = events


func _flush_frame_signal_events(events: Array) -> void:
	for event_value: Variant in events:
		if event_value is Dictionary:
			_flush_frame_signal_event(event_value as Dictionary)


func _flush_frame_signal_event(event: Dictionary) -> void:
	var kind := StringName(str(event.get("kind", "")))
	var arguments := event.get("arguments", []) as Array
	match kind:
		&"damage_about_to_apply":
			SceneScope.event_bus(self).damage_about_to_apply.emit(arguments[0], arguments[1])
		&"hit_confirmed":
			var previous_info := _published_damage_info
			var previous_context := _published_damage_context
			_published_damage_info = arguments[0]
			_published_damage_context = (arguments[3] as Dictionary).duplicate(true)
			SceneScope.event_bus(self).hit_confirmed.emit(arguments[0], arguments[1], float(arguments[2]))
			_published_damage_info = previous_info
			_published_damage_context = previous_context
		&"damage_applied":
			SceneScope.event_bus(self).damage_applied.emit(arguments[0], arguments[1], float(arguments[2]))
		&"damaged":
			damaged.emit(float(arguments[0]), float(arguments[1]))
		&"healed":
			healed.emit(float(arguments[0]), float(arguments[1]))
		&"died":
			var killer: Variant = arguments[0] if not arguments.is_empty() else null
			clear_invulnerability_sources()
			SceneScope.event_bus(self).entity_died.emit(get_parent(), killer)
			died.emit(killer)


func published_damage_observation_context(damage_info: RefCounted) -> Dictionary:
	return _published_damage_context.duplicate(true) if damage_info != null and damage_info == _published_damage_info else {}


func can_restore_replay_snapshot(value: Dictionary) -> bool:
	return not _validated_health_replay_snapshot(value).is_empty()


func restore_replay_snapshot(value: Dictionary) -> bool:
	var validated := _validated_health_replay_snapshot(value)
	if validated.is_empty():
		return false
	var before := runtime_state_snapshot()
	if before == validated:
		return true
	if _install_health_replay_snapshot(validated):
		return true
	if not _install_health_replay_snapshot(before):
		push_error("Health Replay restore rollback failed")
	return false


func restore_irreversible_replay_snapshot(value: Dictionary) -> bool:
	return bool(_irreversible_ledger.call("restore_replay_snapshot", value.duplicate(true)))


func transaction_snapshot() -> Dictionary:
	return {
		"run_id": irreversible_run_id(),
		"current_hp": current_hp,
		"dead": dead,
		"ledger": (_irreversible_ledger.call("freeze_transaction_snapshot") as Dictionary).duplicate(true),
	}


func restore_transaction_snapshot(value: Dictionary) -> bool:
	if not _valid_health_transaction_snapshot(value):
		return false
	var ledger_snapshot := (value["ledger"] as Dictionary).duplicate(true)
	if not bool(_irreversible_ledger.call("restore_transaction_snapshot", ledger_snapshot)):
		return false
	current_hp = float(value["current_hp"])
	dead = bool(value["dead"])
	return true


func discard_transaction_snapshot(value: Dictionary) -> bool:
	if not _valid_health_transaction_snapshot(value):
		return false
	return bool(_irreversible_ledger.call(
		"discard_transaction_snapshot",
		(value["ledger"] as Dictionary).duplicate(true)
	))


func install_rewind_transaction_state(
	target_hp: float,
	self_damage: float,
	reason: StringName,
	source_token: int,
	source_generation: int,
	heal_amount: float,
	claim_run_id: StringName
) -> Dictionary:
	if (
		dead
		or claim_run_id != irreversible_run_id()
		or not is_finite(target_hp)
		or target_hp < 0.0
		or target_hp > max_hp
		or not is_finite(self_damage)
		or self_damage < 0.0
		or not is_finite(heal_amount)
		or heal_amount < 0.0
	):
		return {"ok": false, "code": &"INVALID_REWIND_HEALTH_PLAN"}

	current_hp = target_hp
	var publication := {
		"ok": true,
		"damaged_amount": 0.0,
		"hp_after_damage": current_hp,
		"healed_amount": 0.0,
		"hp_after_heal": current_hp,
		"died": false,
		"killer": reason,
		"final_hp": current_hp,
	}
	if current_hp <= 0.0:
		dead = true
		publication["died"] = true
		return publication

	if self_damage > 0.0:
		var actual_loss := minf(current_hp, self_damage)
		var claim_result := _record_irreversible_loss(
			actual_loss,
			reason,
			source_token,
			source_generation,
			claim_run_id
		)
		if not bool(claim_result.get("ok", false)):
			return {
				"ok": false,
				"code": claim_result.get("code", &"IRREVERSIBLE_CLAIM_REJECTED"),
			}
		current_hp = maxf(0.0, current_hp - actual_loss)
		publication["damaged_amount"] = actual_loss
		publication["hp_after_damage"] = current_hp
		if current_hp <= 0.0:
			dead = true
			publication["died"] = true

	if not dead and heal_amount > 0.0:
		var previous_hp := current_hp
		current_hp = minf(max_hp, current_hp + heal_amount * healing_multiplier)
		publication["healed_amount"] = current_hp - previous_hp
	publication["hp_after_heal"] = current_hp
	publication["final_hp"] = current_hp
	return publication


func publish_rewind_transaction_state(publication: Dictionary) -> bool:
	if not bool(publication.get("ok", false)):
		return false
	var damaged_amount := float(publication.get("damaged_amount", 0.0))
	var healed_amount := float(publication.get("healed_amount", 0.0))
	if damaged_amount > 0.0:
		_queue_or_flush_frame_signal_event(
			&"damaged",
			[damaged_amount, float(publication.get("hp_after_damage", current_hp))]
		)
	if healed_amount > 0.0:
		_queue_or_flush_frame_signal_event(
			&"healed",
			[healed_amount, float(publication.get("hp_after_heal", current_hp))]
		)
	if bool(publication.get("died", false)):
		_queue_or_flush_frame_signal_event(&"died", [publication.get("killer")])
	return true


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
	if _hostile_lethal_application_in_progress:
		return _prevented_resolution(damage_info, &"hostile_lethal_reentrant")
	if invulnerable:
		return _prevented_resolution(damage_info, &"target_invulnerable")
	var hostile_owner := get_parent()
	if hostile_owner != null and hostile_owner.has_method("blocks_hostile_body_damage") and hostile_owner.call("blocks_hostile_body_damage"):
		return _prevented_resolution(damage_info, &"hostile_dormant_body")

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
	if damage_info == null or resolution == null or resolution.is_prevented() or _damage_bypasses_defense(damage_info.tags):
		return _apply_damage_resolution_without_absorption(damage_info, resolution)
	var owner_entity := get_parent()
	if owner_entity == null or not owner_entity.has_method("prepare_post_defense_absorption"):
		return _apply_damage_resolution_without_absorption(damage_info, resolution)
	var prepared: Variant = owner_entity.call("prepare_post_defense_absorption", damage_info, resolution)
	if prepared is Dictionary and prepared.is_empty():
		return _apply_damage_resolution_without_absorption(damage_info, resolution)
	if not prepared is Dictionary or not _valid_absorption_decision(prepared, resolution) or not owner_entity.has_method("commit_post_defense_absorption") or not owner_entity.has_method("rollback_post_defense_absorption"):
		return _prevented_resolution(damage_info, &"invalid_absorption")
	var decision: Dictionary = prepared.duplicate(true)
	var snapshot: Dictionary = resolution.snapshot()
	var context := _resolution_context(damage_info, snapshot.original_amount, snapshot.post_weapon_defense_amount, snapshot.post_character_defense_amount, snapshot.post_accessibility_amount, decision.amount_after, &"hostile_shield")
	var absorbed_resolution: RefCounted = DamageResolutionScript.prevented(&"hostile_shield", context) if float(decision.amount_after) == 0.0 else DamageResolutionScript.applied(float(decision.amount_after), context)
	if absorbed_resolution == null or not _commit_absorption(owner_entity, damage_info, resolution, decision, false):
		return _prevented_resolution(damage_info, &"absorption_commit_failed")
	var applied := _apply_damage_resolution_without_absorption(damage_info, absorbed_resolution)
	if float(decision.amount_after) > 0.0 and (applied == null or applied.is_prevented()):
		if not _commit_absorption(owner_entity, damage_info, resolution, decision, true):
			push_error("Post-defense absorption rollback failed closed")
	return applied


func _valid_absorption_decision(decision: Dictionary, resolution: RefCounted) -> bool:
	if decision.size() != 4 or typeof(decision.get("ok")) != TYPE_BOOL or decision.get("ok") != true or not decision.get("receipt") is Dictionary:
		return false
	for field: String in ["amount_after", "absorbed"]:
		if typeof(decision.get(field)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(decision[field])) or float(decision[field]) < 0.0:
			return false
	return is_equal_approx(float(decision.amount_after) + float(decision.absorbed), float(resolution.finalized_damage()))


func _commit_absorption(owner_entity: Node, damage_info: RefCounted, resolution: RefCounted, decision: Dictionary, rollback: bool) -> bool:
	if not _post_defense_absorption_context.is_empty():
		return false
	_post_defense_absorption_context = {"damage_info": damage_info, "resolution": resolution, "decision": decision.duplicate(true), "rollback": rollback}
	var result: Variant = owner_entity.call("rollback_post_defense_absorption" if rollback else "commit_post_defense_absorption", damage_info, resolution, decision.duplicate(true))
	_post_defense_absorption_context.clear()
	return typeof(result) == TYPE_BOOL and result


func owns_post_defense_absorption_commit(damage_info: RefCounted, resolution: RefCounted, decision: Dictionary, rollback: bool = false) -> bool:
	return not _post_defense_absorption_context.is_empty() and _post_defense_absorption_context.damage_info == damage_info and _post_defense_absorption_context.resolution == resolution and _post_defense_absorption_context.decision == decision and _post_defense_absorption_context.rollback == rollback


func _apply_damage_resolution_without_absorption(damage_info: RefCounted, resolution: RefCounted) -> RefCounted:
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
			&"hostile_lethal_reentrant",
		]:
			_emit_damage_observation(damage_info)
		return resolution

	var final_amount := float(resolution.finalized_damage())
	if not is_finite(final_amount) or final_amount <= 0.0:
		return _prevented_resolution(damage_info, &"invalid_resolution")
	var lethal_owner := get_parent()
	var lethal_decision: Dictionary = {}
	if final_amount >= current_hp and lethal_owner != null and lethal_owner.has_method("prepare_hostile_lethal_transition"):
		var prepared: Variant = lethal_owner.call("prepare_hostile_lethal_transition", damage_info, final_amount)
		if not prepared is Dictionary:
			return _prevented_resolution(damage_info, &"hostile_lethal_invalid")
		lethal_decision = prepared
		if not lethal_decision.is_empty() and (lethal_decision.get("ok") != true or typeof(lethal_decision.get("hp_after")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(lethal_decision.hp_after)) or float(lethal_decision.hp_after) < 0.0 or float(lethal_decision.hp_after) > max_hp or not lethal_owner.has_method("commit_hostile_lethal_transition")):
			return _prevented_resolution(damage_info, &"hostile_lethal_invalid")
	if bool(snapshot.get("irreversible", false)):
		var actual_loss := minf(current_hp, final_amount)
		var claim_result := _record_irreversible_loss(
			actual_loss,
			_irreversible_reason_from_tags(snapshot.get("tags", [])),
			int(snapshot.get("action_token", 0)),
			maxi(
				1,
				int(snapshot.get("source_generation", snapshot.get("attack_generation", 0)))
			),
			StringName(str(snapshot.get("run_id", "")))
		)
		if not bool(claim_result.get("ok", false)):
			return _prevented_resolution(
				damage_info,
				StringName(str(claim_result.get("code", "irreversible_claim_rejected")).to_lower())
			)
	var hp_before := current_hp
	if not lethal_decision.is_empty():
		_hostile_lethal_commit_context = {"damage_info": damage_info, "amount": final_amount, "decision": lethal_decision.duplicate(true)}
		var committed: bool = lethal_owner.call("commit_hostile_lethal_transition", damage_info, final_amount, lethal_decision)
		_hostile_lethal_commit_context.clear()
		if not committed:
			return _prevented_resolution(damage_info, &"hostile_lethal_commit_failed")
		current_hp = float(lethal_decision.hp_after)
		_hostile_lethal_application_in_progress = true
		_emit_damage_observation(damage_info)
	else:
		_emit_damage_observation(damage_info)
		current_hp = maxf(0.0, current_hp - final_amount)
	_queue_or_flush_frame_signal_event(&"damaged", [final_amount, current_hp])
	_apply_hit_reaction(damage_info, final_amount, hp_before)
	_queue_or_flush_frame_signal_event(&"damage_applied", [damage_info, get_parent(), final_amount])
	if current_hp <= 0.0:
		_die(damage_info.attacker)
	_hostile_lethal_application_in_progress = false
	return resolution


func owns_hostile_lethal_commit(damage_info: RefCounted, amount: float, decision: Dictionary) -> bool:
	return not _hostile_lethal_commit_context.is_empty() and _hostile_lethal_commit_context.damage_info == damage_info and _hostile_lethal_commit_context.amount == amount and _hostile_lethal_commit_context.decision == decision


func _apply_hit_reaction(damage_info: RefCounted, final_amount: float, hp_before: float) -> void:
	var owner_entity := get_parent()
	var context: Dictionary = {}
	if not _active_frame_signal_transaction.is_empty() or not _finalized_frame_signal_publication.is_empty() or _frame_signal_publication_in_progress:
		var weakpoint_active := bool(owner_entity.get_meta("weakpoint_active", false))
		if owner_entity.has_method("get_weakpoint_damage_bonus"):
			weakpoint_active = weakpoint_active or float(owner_entity.get_weakpoint_damage_bonus(damage_info)) > 0.0
		context = {"runtime_frame": int((_active_frame_signal_transaction.get("ticket", {}) as Dictionary).get("runtime_frame", 0)), "hp_before": hp_before, "hp_after": current_hp, "target_dead_after": current_hp <= 0.0, "weakpoint_active": weakpoint_active, "internal_observation_recorded": false}
		var attacker: Node = damage_info.attacker
		if not _active_frame_signal_transaction.is_empty() and attacker != null and is_instance_valid(attacker) and attacker.has_method("stage_frame_damage_observation"):
			# Internal Player facts retain their original settlement state while the
			# public observation waits for the entire frame to become irreversible.
			var previous_info := _published_damage_info
			var previous_context := _published_damage_context
			_published_damage_info = damage_info
			_published_damage_context = context.duplicate(true)
			context.internal_observation_recorded = bool(attacker.call("stage_frame_damage_observation", damage_info, owner_entity, final_amount))
			_published_damage_info = previous_info
			_published_damage_context = previous_context
	_queue_or_flush_frame_signal_event(&"hit_confirmed", [damage_info, owner_entity, final_amount, context])
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
	_queue_or_flush_frame_signal_event(&"damage_about_to_apply", [damage_info, get_parent()])


func _resolution_finalized_damage(resolution: RefCounted) -> float:
	if resolution == null:
		return 0.0
	return float(resolution.finalized_damage())


func heal(amount: float, publish_signal: bool = true) -> float:
	if dead:
		return 0.0
	var previous_hp := current_hp
	current_hp = minf(max_hp, current_hp + amount * healing_multiplier)
	var healed_amount := current_hp - previous_hp
	if healed_amount > 0.0 and publish_signal:
		_queue_or_flush_frame_signal_event(&"healed", [healed_amount, current_hp])
	return healed_amount


func publish_reward_healed(healed_amount: float, resulting_hp: float) -> bool:
	if (
		not is_finite(healed_amount)
		or healed_amount <= 0.0
		or not is_finite(resulting_hp)
		or resulting_hp < 0.0
	):
		return false
	_queue_or_flush_frame_signal_event(&"healed", [healed_amount, resulting_hp])
	return true


func lose_health(amount: float, source: Variant = null) -> float:
	if dead or amount <= 0.0:
		return 0.0
	var final_amount := minf(current_hp, amount)
	current_hp = maxf(0.0, current_hp - final_amount)
	_queue_or_flush_frame_signal_event(&"damaged", [final_amount, current_hp])
	if current_hp <= 0.0:
		_die(source)
	return final_amount


func lose_health_irreversible(
	amount: float,
	reason: StringName,
	source_token: int,
	source_generation: int,
	claim_run_id: StringName = &""
) -> RefCounted:
	if not is_finite(amount) or amount <= 0.0:
		return null
	var effective_run_id := irreversible_run_id() if claim_run_id == &"" else claim_run_id
	var actual_loss := minf(current_hp, amount)
	var context := _irreversible_resolution_context(
		amount,
		actual_loss,
		reason,
		source_token,
		source_generation,
		effective_run_id
	)
	if context.is_empty():
		return null
	if dead or actual_loss <= 0.0:
		return DamageResolutionScript.prevented(&"target_dead", context)
	var planned_resolution: RefCounted = DamageResolutionScript.applied(actual_loss, context)
	if planned_resolution == null:
		return null
	var claim_result := _record_irreversible_loss(
		actual_loss,
		reason,
		source_token,
		source_generation,
		effective_run_id
	)
	if not bool(claim_result.get("ok", false)):
		return DamageResolutionScript.prevented(
			StringName(str(claim_result.get("code", "irreversible_claim_rejected")).to_lower()),
			context
		)
	current_hp = maxf(0.0, current_hp - actual_loss)
	_queue_or_flush_frame_signal_event(&"damaged", [actual_loss, current_hp])
	if current_hp <= 0.0:
		_die(reason)
	return planned_resolution


func _record_irreversible_loss(
	actual_loss: float,
	reason: StringName,
	source_token: int,
	source_generation: int,
	claim_run_id: StringName
) -> Dictionary:
	if irreversible_run_id() == &"":
		return {"ok": false, "code": &"RUN_NOT_CONFIGURED"}
	return _irreversible_ledger.call(
		"record_hp_loss",
		actual_loss,
		reason,
		source_token,
		source_generation,
		claim_run_id
	)


func _irreversible_resolution_context(
	requested_amount: float,
	actual_loss: float,
	reason: StringName,
	source_token: int,
	source_generation: int,
	run_id: StringName
) -> Dictionary:
	if (
		run_id == &""
		or str(reason).strip_edges().is_empty()
		or source_token <= 0
		or source_generation <= 0
		or not is_finite(requested_amount)
		or requested_amount <= 0.0
		or not is_finite(actual_loss)
		or actual_loss < 0.0
	):
		return {}
	return {
		"run_id": run_id,
		"target_id": _authoritative_target_id(
			StringName(get_parent().name if get_parent() != null else "player")
		),
		"hostile_source_id": StringName(str(reason).substr(0, 64)),
		"attack_generation": source_generation,
		"hit_index": 0,
		"action_token": source_token,
		"source_generation": source_generation,
		"original_amount": requested_amount,
		"post_weapon_defense_amount": actual_loss,
		"post_character_defense_amount": actual_loss,
		"post_accessibility_amount": actual_loss,
		"post_defense_amount": actual_loss,
		"guard_kind": &"",
		"irreversible": true,
		"tags": ["damage:irreversible", str(reason)],
	}


func _irreversible_reason_from_tags(tags: Variant) -> StringName:
	if tags is Array or tags is PackedStringArray:
		for tag_value: Variant in tags:
			var tag := str(tag_value).strip_edges()
			var semantic := _tag_semantic(tag)
			if semantic in ["self_cost", "corruption", "terminal"] or tag.begins_with("curse:"):
				return StringName(tag)
	return &"damage:irreversible"


func _valid_health_transaction_snapshot(value: Dictionary) -> bool:
	if value.size() != 4:
		return false
	for field: String in ["run_id", "current_hp", "dead", "ledger"]:
		if not value.has(field):
			return false
	if StringName(str(value["run_id"])) != irreversible_run_id():
		return false
	if typeof(value["current_hp"]) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var restored_hp := float(value["current_hp"])
	if not is_finite(restored_hp) or restored_hp < 0.0 or restored_hp > max_hp:
		return false
	if typeof(value["dead"]) != TYPE_BOOL or not value["ledger"] is Dictionary:
		return false
	if bool(value["dead"]) and restored_hp > 0.0:
		return false
	return StringName(str((value["ledger"] as Dictionary).get("run_id", ""))) == irreversible_run_id()


func _validated_health_replay_snapshot(value: Dictionary) -> Dictionary:
	if value.size() != REPLAY_SNAPSHOT_FIELDS.size():
		return {}
	for field: String in REPLAY_SNAPSHOT_FIELDS:
		if not value.has(field):
			return {}
	for key_value: Variant in value.keys():
		if (
			typeof(key_value) not in [TYPE_STRING, TYPE_STRING_NAME]
			or str(key_value) not in REPLAY_SNAPSHOT_FIELDS
		):
			return {}
	if typeof(value["run_id"]) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return {}
	var run_id := StringName(str(value["run_id"]))
	if run_id == &"" or run_id != irreversible_run_id():
		return {}
	for field: String in ["current_hp", "max_hp", "healing_multiplier"]:
		if typeof(value[field]) not in [TYPE_INT, TYPE_FLOAT]:
			return {}
	var restored_hp := float(value["current_hp"])
	var restored_max_hp := float(value["max_hp"])
	var restored_healing_multiplier := float(value["healing_multiplier"])
	if (
		not is_finite(restored_hp)
		or not is_finite(restored_max_hp)
		or restored_max_hp <= 0.0
		or restored_hp < 0.0
		or restored_hp > restored_max_hp
		or not is_finite(restored_healing_multiplier)
		or restored_healing_multiplier < 0.0
		or typeof(value["dead"]) != TYPE_BOOL
		or bool(value["dead"]) != is_zero_approx(restored_hp)
		or not value["ledger"] is Dictionary
	):
		return {}
	var ledger := (value["ledger"] as Dictionary).duplicate(true)
	if (
		StringName(str(ledger.get("run_id", ""))) != run_id
		or not _irreversible_ledger.has_method("can_restore_replay_snapshot")
		or not bool(_irreversible_ledger.call("can_restore_replay_snapshot", ledger))
	):
		return {}
	return {
		"run_id": run_id,
		"current_hp": restored_hp,
		"max_hp": restored_max_hp,
		"healing_multiplier": restored_healing_multiplier,
		"dead": bool(value["dead"]),
		"ledger": ledger,
	}


func _install_health_replay_snapshot(value: Dictionary) -> bool:
	var ledger_target := (value["ledger"] as Dictionary).duplicate(true)
	if irreversible_ledger_snapshot() != ledger_target:
		if not bool(_irreversible_ledger.call("restore_replay_snapshot", ledger_target)):
			return false
	max_hp = float(value["max_hp"])
	current_hp = float(value["current_hp"])
	healing_multiplier = float(value["healing_multiplier"])
	dead = bool(value["dead"])
	return runtime_state_snapshot() == value


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


func reward_effect_snapshot() -> Dictionary:
	var reward_tokens: Array[int] = []
	var reward_remaining: Dictionary = {}
	for token_value: Variant in _reward_invulnerability_tokens.keys():
		var token := int(token_value)
		var remaining := int(_reward_invulnerability_remaining_frames.get(token, 0))
		if remaining <= 0:
			return {}
		reward_tokens.append(token)
		reward_remaining[str(token)] = remaining
	reward_tokens.sort()
	return {
		"current_hp": current_hp,
		"max_hp": max_hp,
		"defense": defense,
		"healing_multiplier": healing_multiplier,
		"dead": dead,
		"invulnerable": not _reward_invulnerability_tokens.is_empty(),
		"invulnerability_token": _invulnerability_token,
		"reward_invulnerability_tokens": reward_tokens,
		"reward_invulnerability_remaining": reward_remaining,
	}


func invulnerability_replay_snapshot() -> Dictionary:
	var tokens: Array[int] = []
	var remaining: Dictionary = {}
	for token_value: Variant in _non_reward_invulnerability_remaining_frames.keys():
		var token := int(token_value)
		var frames := int(_non_reward_invulnerability_remaining_frames[token])
		if frames <= 0:
			return {}
		tokens.append(token)
		remaining[str(token)] = frames
	tokens.sort()
	var sources: Array[String] = []
	for source_value: Variant in _active_invulnerability_sources.keys():
		sources.append(str(source_value))
	sources.sort()
	return {
		"invulnerability_token": _invulnerability_token,
		"non_reward_tokens": tokens,
		"non_reward_remaining_frames": remaining,
		"active_sources": sources,
	}


func can_restore_invulnerability_replay_snapshot(value: Dictionary) -> bool:
	return _valid_invulnerability_replay_snapshot(value, _reward_invulnerability_tokens.keys())


func _valid_invulnerability_replay_snapshot(value: Dictionary, reward_tokens: Array) -> bool:
	if (
		value.size() != 4
		or typeof(value.get("invulnerability_token")) != TYPE_INT
		or int(value.get("invulnerability_token", -1)) < 0
		or not value.get("non_reward_tokens") is Array
		or not value.get("non_reward_remaining_frames") is Dictionary
		or not value.get("active_sources") is Array
	):
		return false
	var tokens := value["non_reward_tokens"] as Array
	var remaining := value["non_reward_remaining_frames"] as Dictionary
	if tokens.size() != remaining.size():
		return false
	var prior := 0
	for token_value: Variant in tokens:
		if typeof(token_value) != TYPE_INT:
			return false
		var token := int(token_value)
		if (
			token <= prior
			or token > int(value["invulnerability_token"])
			or typeof(remaining.get(str(token))) != TYPE_INT
			or int(remaining[str(token)]) <= 0
			or reward_tokens.has(token)
		):
			return false
		prior = token
	var previous_source := ""
	for source_value: Variant in value["active_sources"] as Array:
		if typeof(source_value) != TYPE_STRING or str(source_value).is_empty():
			return false
		var source := str(source_value)
		if not previous_source.is_empty() and source <= previous_source:
			return false
		previous_source = source
	return true


func restore_invulnerability_replay_snapshot(value: Dictionary) -> bool:
	if not can_restore_invulnerability_replay_snapshot(value):
		return false
	var current_tokens: Array[int] = []
	for token_value: Variant in _non_reward_invulnerability_remaining_frames.keys():
		current_tokens.append(int(token_value))
	for token: int in current_tokens:
		_cancel_invulnerability_token(token)
	_active_invulnerability_sources.clear()
	for source_value: Variant in value["active_sources"] as Array:
		_active_invulnerability_sources[StringName(str(source_value))] = true
	_invulnerability_token = int(value["invulnerability_token"])
	var remaining := value["non_reward_remaining_frames"] as Dictionary
	for token_value: Variant in value["non_reward_tokens"] as Array:
		var token := int(token_value)
		if not _install_non_reward_invulnerability_frames(
			token,
			int(remaining[str(token)])
		):
			return false
	_refresh_invulnerability_state()
	return invulnerability_replay_snapshot() == value


func _install_non_reward_invulnerability_frames(token: int, remaining_frames: int) -> bool:
	if (
		token <= 0
		or remaining_frames <= 0
		or _active_invulnerability_tokens.has(token)
		or _invulnerability_expiry_timers.has(token)
	):
		return false
	_active_invulnerability_tokens[token] = true
	_non_reward_invulnerability_remaining_frames[token] = remaining_frames
	var timer := Timer.new()
	timer.one_shot = true
	timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	timer.wait_time = (
		float(remaining_frames) / float(Engine.physics_ticks_per_second)
	)
	add_child(timer)
	_invulnerability_expiry_timers[token] = timer
	timer.timeout.connect(
		_expire_invulnerability.bind(token, timer),
		CONNECT_ONE_SHOT
	)
	timer.start()
	return true


func can_restore_reward_effect_snapshot(value: Dictionary) -> bool:
	var non_reward_tokens: Array = []
	for token: Variant in _active_invulnerability_tokens:
		if not _reward_invulnerability_tokens.has(token):
			non_reward_tokens.append(token)
	return _valid_reward_effect_snapshot(value, non_reward_tokens)


func _valid_reward_effect_snapshot(value: Dictionary, non_reward_tokens: Array) -> bool:
	const FIELDS: Array[String] = [
		"current_hp", "max_hp", "defense", "healing_multiplier", "dead",
		"invulnerable", "invulnerability_token", "reward_invulnerability_tokens",
		"reward_invulnerability_remaining",
	]
	if value.size() != FIELDS.size():
		return false
	for field: String in FIELDS:
		if not value.has(field):
			return false
	for field: String in ["current_hp", "max_hp", "defense", "healing_multiplier"]:
		if typeof(value[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[field])):
			return false
	var restored_hp := float(value["current_hp"])
	var restored_max_hp := float(value["max_hp"])
	if (
		restored_max_hp <= 0.0
		or restored_hp < 0.0
		or restored_hp > restored_max_hp
		or float(value["healing_multiplier"]) < 0.0
		or typeof(value["dead"]) != TYPE_BOOL
		or bool(value["dead"]) != is_zero_approx(restored_hp)
		or typeof(value["invulnerable"]) != TYPE_BOOL
		or typeof(value["invulnerability_token"]) != TYPE_INT
		or int(value["invulnerability_token"]) < 0
		or not value["reward_invulnerability_tokens"] is Array
		or not value["reward_invulnerability_remaining"] is Dictionary
	):
		return false
	var target_tokens: Dictionary = {}
	var remaining := value["reward_invulnerability_remaining"] as Dictionary
	if remaining.size() != (value["reward_invulnerability_tokens"] as Array).size():
		return false
	var prior_token := 0
	for token_value: Variant in value["reward_invulnerability_tokens"] as Array:
		if typeof(token_value) != TYPE_INT:
			return false
		var token := int(token_value)
		if (
			token <= prior_token
			or token > int(value["invulnerability_token"])
			or not remaining.has(str(token))
			or typeof(remaining[str(token)]) != TYPE_INT
			or int(remaining[str(token)]) <= 0
		):
			return false
		target_tokens[token] = true
		prior_token = token
	for key_value: Variant in remaining.keys():
		if typeof(key_value) != TYPE_STRING or not target_tokens.has(int(str(key_value))):
			return false
	for token_value: Variant in non_reward_tokens:
		var token := int(token_value)
		if token > int(value["invulnerability_token"]) or target_tokens.has(token):
			return false
	return (not target_tokens.is_empty()) == bool(value["invulnerable"])


func can_restore_full_replay_reward_snapshot(value: Dictionary, invulnerability: Dictionary) -> bool:
	return (
		value.get("reward_invulnerability_tokens") is Array
		and invulnerability.get("non_reward_tokens") is Array
		and value.get("invulnerability_token") == invulnerability.get("invulnerability_token")
		and _valid_reward_effect_snapshot(value, invulnerability.non_reward_tokens)
		and _valid_invulnerability_replay_snapshot(invulnerability, value.reward_invulnerability_tokens)
	)


func restore_full_replay_reward_snapshot(value: Dictionary, invulnerability: Dictionary) -> bool:
	if not can_restore_full_replay_reward_snapshot(value, invulnerability):
		return false
	var before := reward_effect_snapshot()
	var before_invulnerability := invulnerability_replay_snapshot()
	if _install_full_replay_reward_snapshot(value, invulnerability):
		return true
	if not _install_full_replay_reward_snapshot(before, before_invulnerability):
		push_error("Full Replay Health restore rollback failed")
	return false


func _install_full_replay_reward_snapshot(value: Dictionary, invulnerability: Dictionary) -> bool:
	for token_value: Variant in _active_invulnerability_tokens.keys():
		_cancel_invulnerability_token(int(token_value))
	_active_invulnerability_sources.clear()
	return restore_reward_effect_snapshot(value) and restore_invulnerability_replay_snapshot(invulnerability)


func restore_reward_effect_snapshot(value: Dictionary) -> bool:
	if not can_restore_reward_effect_snapshot(value):
		return false
	var restored_hp := float(value["current_hp"])
	var restored_max_hp := float(value["max_hp"])
	var restored_healing_multiplier := float(value["healing_multiplier"])
	var target_tokens: Array[int] = []
	for token_value: Variant in value["reward_invulnerability_tokens"] as Array:
		target_tokens.append(int(token_value))
	var current_reward_tokens: Array[int] = []
	for token_value: Variant in _reward_invulnerability_tokens.keys():
		current_reward_tokens.append(int(token_value))
	for token: int in current_reward_tokens:
		_cancel_invulnerability_token(token)
	current_hp = restored_hp
	max_hp = restored_max_hp
	defense = float(value["defense"])
	healing_multiplier = restored_healing_multiplier
	dead = bool(value["dead"])
	_invulnerability_token = int(value["invulnerability_token"])
	var remaining := value["reward_invulnerability_remaining"] as Dictionary
	for token: int in target_tokens:
		if not _install_reward_invulnerability_frames(token, int(remaining[str(token)])):
			return false
	_refresh_invulnerability_state()
	return reward_effect_snapshot() == value


func _install_reward_invulnerability_frames(token: int, remaining_frames: int) -> bool:
	if (
		token <= 0
		or remaining_frames <= 0
		or _active_invulnerability_tokens.has(token)
		or _reward_invulnerability_remaining_frames.has(token)
	):
		return false
	_active_invulnerability_tokens[token] = true
	_reward_invulnerability_tokens[token] = true
	_reward_invulnerability_remaining_frames[token] = remaining_frames
	return true


func apply_invulnerability(duration: float) -> void:
	_start_invulnerability(duration, false)


func apply_reward_invulnerability(duration: float) -> bool:
	if not is_finite(duration) or duration < 0.0:
		return false
	if is_zero_approx(duration):
		return true
	return _start_invulnerability(duration, true) > 0


func advance_reward_invulnerability_frame() -> bool:
	var expired_tokens: Array[int] = []
	for token_value: Variant in _reward_invulnerability_tokens.keys():
		var token := int(token_value)
		var remaining := int(_reward_invulnerability_remaining_frames.get(token, 0))
		if remaining <= 0:
			return false
		remaining -= 1
		if remaining == 0:
			expired_tokens.append(token)
		else:
			_reward_invulnerability_remaining_frames[token] = remaining
	for token: int in expired_tokens:
		_cancel_invulnerability_token(token)
	expired_tokens.clear()
	for token_value: Variant in _non_reward_invulnerability_remaining_frames.keys():
		var token := int(token_value)
		var remaining := int(_non_reward_invulnerability_remaining_frames[token])
		if remaining <= 0:
			return false
		remaining -= 1
		if remaining == 0:
			expired_tokens.append(token)
		else:
			_non_reward_invulnerability_remaining_frames[token] = remaining
	for token: int in expired_tokens:
		_cancel_invulnerability_token(token)
	return true


func _start_invulnerability(duration: float, reward_owned: bool) -> int:
	if not is_finite(duration) or duration <= 0.0:
		return 0
	_invulnerability_token += 1
	var token := _invulnerability_token
	_active_invulnerability_tokens[token] = true
	if reward_owned:
		_reward_invulnerability_tokens[token] = true
		_reward_invulnerability_remaining_frames[token] = maxi(
			1,
			ceili(duration * float(Engine.physics_ticks_per_second))
		)
	else:
		var remaining_frames := maxi(
			1,
			ceili(duration * float(Engine.physics_ticks_per_second))
		)
		_non_reward_invulnerability_remaining_frames[token] = remaining_frames
		var expiry_timer := Timer.new()
		expiry_timer.one_shot = true
		expiry_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
		expiry_timer.wait_time = duration
		add_child(expiry_timer)
		_invulnerability_expiry_timers[token] = expiry_timer
		expiry_timer.timeout.connect(
			_expire_invulnerability.bind(token, expiry_timer),
			CONNECT_ONE_SHOT
		)
		expiry_timer.start()
	_refresh_invulnerability_state()
	return token


func _expire_invulnerability(token: int, expiry_timer: Timer) -> void:
	_active_invulnerability_tokens.erase(token)
	_reward_invulnerability_tokens.erase(token)
	_reward_invulnerability_remaining_frames.erase(token)
	_non_reward_invulnerability_remaining_frames.erase(token)
	_invulnerability_expiry_timers.erase(token)
	_refresh_invulnerability_state()
	if is_instance_valid(expiry_timer):
		expiry_timer.queue_free()


func _cancel_invulnerability_token(token: int) -> void:
	var timer := _invulnerability_expiry_timers.get(token) as Timer
	_active_invulnerability_tokens.erase(token)
	_reward_invulnerability_tokens.erase(token)
	_reward_invulnerability_remaining_frames.erase(token)
	_non_reward_invulnerability_remaining_frames.erase(token)
	_invulnerability_expiry_timers.erase(token)
	if timer != null and is_instance_valid(timer):
		timer.stop()
		timer.queue_free()
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
	_queue_or_flush_frame_signal_event(&"died", [killer])
