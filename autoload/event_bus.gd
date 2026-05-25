extends Node

signal damage_about_to_apply(damage_info: Variant, target: Node)
signal damage_applied(damage_info: Variant, target: Node, final_amount: float)
signal hit_confirmed(damage_info: Variant, target: Node, final_amount: float)
signal entity_died(entity: Node, killer: Variant)
signal room_started(room_id: StringName)
signal room_cleared(room_id: StringName)
signal reward_selected(reward_data: Dictionary)
signal curse_selected(curse_data: Dictionary)
signal curse_offer_resolved()
signal time_skill_started(skill_id: StringName)
signal time_skill_ended(skill_id: StringName)
signal player_dashed()
signal player_attacked(weapon_id: StringName)
signal enemy_spawned(enemy: Node)
signal run_started(run_data: Dictionary)
signal run_ended(result: Dictionary)

const DAMAGE_ABOUT_TO_APPLY := &"damage_about_to_apply"
const DAMAGE_APPLIED := &"damage_applied"
const HIT_CONFIRMED := &"hit_confirmed"
const ENTITY_DIED := &"entity_died"
const ROOM_STARTED := &"room_started"
const ROOM_CLEARED := &"room_cleared"
const REWARD_SELECTED := &"reward_selected"
const CURSE_SELECTED := &"curse_selected"
const CURSE_OFFER_RESOLVED := &"curse_offer_resolved"
const TIME_SKILL_STARTED := &"time_skill_started"
const TIME_SKILL_ENDED := &"time_skill_ended"
const PLAYER_DASHED := &"player_dashed"
const PLAYER_ATTACKED := &"player_attacked"
const ENEMY_SPAWNED := &"enemy_spawned"
const RUN_STARTED := &"run_started"
const RUN_ENDED := &"run_ended"

var _handlers: Dictionary = {}
var _deferred_events: Array = []


func subscribe(event_name: StringName, target: Object, method_name: StringName) -> void:
	var entry := {"target": target, "method": method_name}
	if not _handlers.has(event_name):
		_handlers[event_name] = []
	_handlers[event_name].append(entry)


func unsubscribe(event_name: StringName, target: Object, method_name: StringName) -> void:
	if not _handlers.has(event_name):
		return
	_handlers[event_name] = _handlers[event_name].filter(
		func(entry: Dictionary) -> bool:
			return entry["target"] != target or entry["method"] != method_name
	)


func publish(event_name: StringName, payload: Dictionary = {}) -> void:
	for entry: Dictionary in _handlers.get(event_name, []):
		var target: Object = entry["target"]
		if is_instance_valid(target):
			target.call(entry["method"], payload)


func publish_deferred(event_name: StringName, payload: Dictionary = {}) -> void:
	_deferred_events.append({"name": event_name, "payload": payload})


func _process(_delta: float) -> void:
	var events := _deferred_events
	_deferred_events = []
	for event: Dictionary in events:
		publish(event["name"], event["payload"])
