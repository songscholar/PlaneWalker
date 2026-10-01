class_name InputActionContract
extends RefCounted

const LEGACY_PROFILE_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_down",
	&"move_left",
	&"move_right",
	&"attack",
	&"heavy_attack",
	&"ranged_attack",
	&"dash",
	&"time_stop",
	&"time_rewind",
	&"time_rift",
	&"time_accelerate",
	&"interact",
	&"pause",
]
const REQUIRED_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_down",
	&"move_left",
	&"move_right",
	&"attack",
	&"heavy_attack",
	&"ranged_attack",
	&"dash",
	&"interact",
	&"pause",
]
const SEMANTIC_ACTIONS: Array[StringName] = [
	&"weapon_primary",
	&"weapon_secondary",
	&"weapon_utility",
	&"weapon_skill",
	&"weapon_ultimate",
	&"time_slot_1",
	&"time_slot_2",
	&"character_skill",
	&"active_item",
	&"dash",
	&"interact",
	&"pause",
]


static func required_actions() -> Array[StringName]:
	return REQUIRED_ACTIONS.duplicate()


static func legacy_profile_actions() -> Array[StringName]:
	return LEGACY_PROFILE_ACTIONS.duplicate()


static func semantic_actions() -> Array[StringName]:
	return SEMANTIC_ACTIONS.duplicate()


static func missing_required_bindings() -> Array[Dictionary]:
	return _missing_bindings(REQUIRED_ACTIONS)


static func missing_semantic_bindings() -> Array[Dictionary]:
	return _missing_bindings(SEMANTIC_ACTIONS)


static func _missing_bindings(actions: Array[StringName]) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for action: StringName in actions:
		if not InputMap.has_action(action):
			missing.append({"action": str(action), "family": "action"})
			continue
		var families := binding_families(action)
		for family: String in ["keyboard_mouse", "controller"]:
			if not bool(families[family]):
				missing.append({"action": str(action), "family": family})
	return missing


static func binding_families(action: StringName) -> Dictionary:
	var families := {
		"keyboard_mouse": false,
		"controller": false,
	}
	if not InputMap.has_action(action):
		return families
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
			families["keyboard_mouse"] = true
		elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
			families["controller"] = true
	return families


static func controller_binding_ids(action: StringName) -> Array[String]:
	var binding_ids: Array[String] = []
	if not InputMap.has_action(action):
		return binding_ids
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			var button := event as InputEventJoypadButton
			binding_ids.append("button:%d" % button.button_index)
		elif event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			var direction := -1 if motion.axis_value < 0.0 else 1
			binding_ids.append("axis:%d:%d" % [motion.axis, direction])
	return binding_ids
