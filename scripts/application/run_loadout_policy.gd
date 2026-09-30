class_name RunLoadoutPolicy
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunConfigScript := preload("res://scripts/application/run_config.gd")
const TIME_ABILITY_ORDER := {
	"stop": 0,
	"rewind": 1,
	"rift": 2,
	"accelerate": 3,
}


func validate(config: Dictionary, registry: RefCounted):
	var normalized := RunConfigScript.normalized(config)
	var config_validation = RunConfigScript.validate(normalized)
	if not config_validation.ok:
		return CommandResultScript.failure(
			config_validation.code,
			0,
			config_validation.context
		)
	var selected_time_skills: Array = normalized["enabled_time_skills"]
	var first_time_id := str(selected_time_skills[0])
	var second_time_id := str(selected_time_skills[1])
	if (
		TIME_ABILITY_ORDER.has(first_time_id)
		and TIME_ABILITY_ORDER.has(second_time_id)
		and int(TIME_ABILITY_ORDER[first_time_id]) >= int(TIME_ABILITY_ORDER[second_time_id])
	):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			0,
			{
				"field": "enabled_time_skills",
				"reason": "noncanonical_time_pair",
				"expected_order": ["stop", "rewind", "rift", "accelerate"],
			}
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
	if not registry.has_method("resolve_character_runtime_profile"):
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE",
			0,
			{"field": "character_profile", "reason": "registry_boundary"}
		)
	var character_profile_value: Variant = registry.call(
		"resolve_character_runtime_profile",
		StringName(str(normalized["character_id"])),
		StringName(milestone)
	)
	var character_profile: Dictionary = (
		(character_profile_value as Dictionary).duplicate(true)
		if character_profile_value is Dictionary
		else {}
	)
	if character_profile.is_empty():
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE",
			0,
			{
				"field": "character_profile",
				"reason": "missing_or_ambiguous",
				"character_id": str(normalized["character_id"]),
				"milestone": milestone,
			}
		)
	var weapon_result := _resolve_definition(
		registry,
		str(normalized["weapon_id"]),
		"weapon",
		milestone,
		"weapon_id"
	)
	if not bool(weapon_result.get("ok", false)):
		return _content_failure(weapon_result)
	if not registry.has_method("resolve_weapon_runtime_profile"):
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE",
			0,
			{"field": "weapon_profile", "reason": "registry_boundary"}
		)
	var profile_value: Variant = registry.call(
		"resolve_weapon_runtime_profile",
		StringName(str(normalized["weapon_id"])),
		StringName(milestone)
	)
	var weapon_profile: Dictionary = (
		(profile_value as Dictionary).duplicate(true)
		if profile_value is Dictionary
		else {}
	)
	if weapon_profile.is_empty():
		return CommandResultScript.failure(
			&"CONTENT_NOT_AVAILABLE",
			0,
			{
				"field": "weapon_profile",
				"reason": "missing_or_ambiguous",
				"weapon_id": str(normalized["weapon_id"]),
				"milestone": milestone,
			}
		)

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

	var compatibility_result := _validate_compatibility(
		[
			(character_result["definition"] as Dictionary),
			character_profile,
			(weapon_result["definition"] as Dictionary),
			weapon_profile,
		] + abilities,
		str(normalized["character_id"]),
		str(normalized["weapon_id"]),
		normalized["enabled_time_skills"]
	)
	if not bool(compatibility_result.get("ok", false)):
		return _content_failure(compatibility_result)

	return CommandResultScript.success(
		0,
		{
			"loadout": {
				"character": (character_result["definition"] as Dictionary).duplicate(true),
				"character_profile": character_profile.duplicate(true),
				"weapon": (weapon_result["definition"] as Dictionary).duplicate(true),
				"weapon_profile": weapon_profile.duplicate(true),
				"time_abilities": abilities,
			},
		}
	)


func _validate_compatibility(
	definitions: Array,
	character_id: String,
	weapon_id: String,
	time_ability_ids: Array
) -> Dictionary:
	for definition_value: Variant in definitions:
		if not definition_value is Dictionary:
			return {
				"ok": false,
				"context": {"field": "compatibility", "reason": "definition_type"},
			}
		var definition: Dictionary = definition_value
		var compatibility_value: Variant = definition.get("compatibility", {})
		if not compatibility_value is Dictionary:
			return {
				"ok": false,
				"context": {
					"field": "compatibility",
					"reason": "type",
					"content_id": str(definition.get("id", "")),
				},
			}
		var compatibility: Dictionary = compatibility_value
		for unsupported_field: String in ["archetype_ids", "modes"]:
			if compatibility.has(unsupported_field):
				return {
					"ok": false,
					"context": {
						"field": "compatibility.%s" % unsupported_field,
						"reason": "unsupported_constraint",
						"content_id": str(definition.get("id", "")),
					},
				}
		var scalar_checks := {
			"character_ids": character_id,
			"weapon_ids": weapon_id,
		}
		for field_value: Variant in scalar_checks.keys():
			var field := str(field_value)
			if not compatibility.has(field):
				continue
			var allowed_value: Variant = compatibility[field]
			if not allowed_value is Array or (allowed_value as Array).is_empty():
				return {
					"ok": false,
					"context": {
						"field": "compatibility.%s" % field,
						"reason": "empty_or_invalid",
						"content_id": str(definition.get("id", "")),
					},
				}
			if not (allowed_value as Array).has(str(scalar_checks[field_value])):
				return {
					"ok": false,
					"context": {
						"field": "compatibility.%s" % field,
						"reason": "unsupported_selection",
						"content_id": str(definition.get("id", "")),
						"selected_id": str(scalar_checks[field_value]),
					},
				}
		if compatibility.has("time_ability_ids"):
			var allowed_time_value: Variant = compatibility["time_ability_ids"]
			if not allowed_time_value is Array or (allowed_time_value as Array).is_empty():
				return {
					"ok": false,
					"context": {
						"field": "compatibility.time_ability_ids",
						"reason": "empty_or_invalid",
						"content_id": str(definition.get("id", "")),
					},
				}
			for ability_id_value: Variant in time_ability_ids:
				if not (allowed_time_value as Array).has(str(ability_id_value)):
					return {
						"ok": false,
						"context": {
							"field": "compatibility.time_ability_ids",
							"reason": "unsupported_selection",
							"content_id": str(definition.get("id", "")),
							"selected_id": str(ability_id_value),
						},
					}
	return {"ok": true, "context": {}}


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
