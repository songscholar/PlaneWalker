class_name CombatHudFacts
extends RefCounted

const TimeIds := preload("res://scripts/time_system/time_ability_ids.gd")


static func weapon(value: Dictionary) -> Dictionary:
	var status_id := str(value.status_id)
	var status := _tr("HUD_WEAPON_STATUS_" + status_id.to_upper())
	if str(value.weapon_id) == "staff":
		var element_keys := ["FIRE", "FIRE", "ICE", "LIGHTNING"]
		var element := _tr("HUD_WEAPON_STATUS_ELEMENT_" + str(element_keys[clampi(int(value.secondary_value), 0, 3)]))
		if status_id == "sequence_ready":
			status = "%s / %s / %.1fs" % [status, element, float(value.status_remaining) / 60.0]
		elif status_id in ["channeling", "acting"]:
			status = "%s / %s" % [status, element]
	elif status_id == "time_load":
		status = _tr("HUD_WEAPON_STATUS_TIME_LOAD_FMT") % (float(value.status_remaining) / 60.0)
	elif status_id == "perfect_reload":
		status = _tr("HUD_WEAPON_STATUS_PERFECT_RELOAD")
	elif str(value.secondary_id) == "time_load" and float(value.secondary_value) > 0:
		status = _tr("HUD_WEAPON_STATUS_TIME_LOAD_FMT") % (float(value.secondary_value) / 60.0)
	elif status_id == "ready":
		status = _tr("HUD_WEAPON_READY")
	return {
		"name": _tr("WEAPON_" + str(value.weapon_id).to_upper() + "_NAME"),
		"meter": _tr("HUD_WEAPON_METER_" + str(value.meter_kind).to_upper() + "_FMT") % [roundi(value.meter_current), roundi(value.meter_max)],
		"status": status,
	}


static func character(value: Dictionary) -> Dictionary:
	var status_id := str(value.status_id)
	var status := _tr("HUD_CHARACTER_STATUS_" + status_id.to_upper())
	if status_id == "primer":
		status = _tr("HUD_CHARACTER_STATUS_PRIMER_FMT") % [_tr(TimeIds.localization_key(str(value.secondary_value))), float(value.status_remaining) / 60.0]
	elif status_id == "echo_pending":
		status = _tr("HUD_CHARACTER_STATUS_ECHO_PENDING_FMT") % int(value.status_stacks)
	elif not status_id in ["guarding", "devouring", "armored", "ready"]:
		status = _tr("HUD_CHARACTER_STATUS_" + status_id.to_upper() + "_FMT") % (float(value.status_remaining) / 60.0)
	return {
		"name": _tr("CHARACTER_" + str(value.character_id).to_upper() + "_NAME"),
		"meter": _tr("HUD_CHARACTER_METER_" + str(value.meter_kind).to_upper() + "_FMT") % [roundi(value.meter_current), roundi(value.meter_max)],
		"status": status,
		"cooldown": _tr("HUD_CHARACTER_COOLDOWN_FMT") % (float(value.cooldown_current) / 60.0) if float(value.cooldown_current) > 0 else _tr("HUD_CHARACTER_COOLDOWN_READY"),
	}


static func _tr(key: String) -> String:
	return TranslationServer.translate(key)
