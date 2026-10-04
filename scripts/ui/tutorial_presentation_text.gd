class_name TutorialPresentationText
extends RefCounted


static func action_name(action: Dictionary) -> String:
	var key := "UI_TUTORIAL_ACTION_" + str(action.semantic_action_id).to_upper()
	var label := str(TranslationServer.translate(StringName(key)))
	if action.semantic_action_id == "time_slot_1":
		label += " (" + str(TranslationServer.translate(StringName("TIME_ABILITY_" + str(action.ability_id).to_upper() + "_NAME"))) + ")"
	return label


static func bindings_text(actions: Array) -> String:
	var lines: PackedStringArray = []
	for action: Dictionary in actions:
		for binding: Dictionary in action.bindings:
			var name_key := "INPUT_ACTION_" + str(binding.action_id).to_upper()
			var name := str(TranslationServer.translate(StringName(name_key)))
			if binding.action_id == "time_slot_1":
				name = action_name(action)
			var labels := " / ".join(PackedStringArray(binding.labels)) if not binding.labels.is_empty() else str(TranslationServer.translate(&"UI_TUTORIAL_UNBOUND"))
			lines.append(name + ": " + labels)
	return "\n".join(lines)


static func progress_text(requirements: Array, actions: Array) -> String:
	var lines: PackedStringArray = []
	for index: int in range(requirements.size()):
		var requirement: Dictionary = requirements[index]
		lines.append("%s: %d/%d" % [action_name(actions[index]), int(requirement.current), int(requirement.count)])
	return "\n".join(lines)
