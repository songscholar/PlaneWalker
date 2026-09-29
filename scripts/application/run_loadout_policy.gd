class_name RunLoadoutPolicy
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunConfigScript := preload("res://scripts/application/run_config.gd")


func validate(config: Dictionary, registry: RefCounted):
	var normalized := RunConfigScript.normalized(config)
	var config_validation = RunConfigScript.validate(normalized)
	if not config_validation.ok:
		return CommandResultScript.failure(
			config_validation.code,
			0,
			config_validation.context
		)
	if registry == null or not registry.has_method("get_content"):
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE",
			0,
			{"field": "registry"}
		)

	var milestone := str(normalized["milestone"])
	var character_result := _resolve_definition(
		registry,
		str(normalized["character_id"]),
		"character",
		milestone,
		"character_id"
	)
	if not bool(character_result.get("ok", false)):
		return _content_failure(character_result)
	var weapon_result := _resolve_definition(
		registry,
		str(normalized["weapon_id"]),
		"weapon",
		milestone,
		"weapon_id"
	)
	if not bool(weapon_result.get("ok", false)):
		return _content_failure(weapon_result)

	var abilities: Array[Dictionary] = []
	for ability_id_value: Variant in normalized["enabled_time_skills"]:
		var ability_result := _resolve_definition(
			registry,
			str(ability_id_value),
			"time_ability",
			milestone,
			"enabled_time_skills"
		)
		if not bool(ability_result.get("ok", false)):
			return _content_failure(ability_result)
		abilities.append((ability_result["definition"] as Dictionary).duplicate(true))

	return CommandResultScript.success(
		0,
		{
			"loadout": {
				"character": (character_result["definition"] as Dictionary).duplicate(true),
				"weapon": (weapon_result["definition"] as Dictionary).duplicate(true),
				"time_abilities": abilities,
			},
		}
	)


func _resolve_definition(
	registry: RefCounted,
	content_id: String,
	expected_category: String,
	milestone: String,
	field: String
) -> Dictionary:
	var definition_value: Variant = registry.call("get_content", StringName(content_id))
	var definition: Dictionary = (
		(definition_value as Dictionary).duplicate(true)
		if definition_value is Dictionary
		else {}
	)
	var context := {
		"field": field,
		"content_id": content_id,
		"expected_category": expected_category,
		"milestone": milestone,
	}
	if definition.is_empty():
		context["reason"] = "unknown_id"
		return {"ok": false, "context": context}
	var actual_category := str(definition.get("category", ""))
	if actual_category != expected_category:
		context["reason"] = "category_mismatch"
		context["actual_category"] = actual_category
		return {"ok": false, "context": context}
	var availability_value: Variant = definition.get("availability", [])
	var availability: Array = availability_value if availability_value is Array else []
	if not availability.has(milestone):
		context["reason"] = "milestone_unavailable"
		context["availability"] = availability.duplicate()
		return {"ok": false, "context": context}
	return {"ok": true, "definition": definition, "context": {}}


func _content_failure(result: Dictionary):
	var context_value: Variant = result.get("context", {})
	var context := (
		(context_value as Dictionary).duplicate(true)
		if context_value is Dictionary
		else {}
	)
	return CommandResultScript.failure(&"CONTENT_NOT_AVAILABLE", 0, context)
