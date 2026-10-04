class_name HubViewStateProjector
extends RefCounted

const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Forge := preload("res://scripts/progression/forge_runtime.gd")
const Builds := preload("res://scripts/progression/build_library.gd")
const Contract := preload("res://scripts/ui/contracts/hub_view_state.gd")
const ZERO_COST := {"chronos_shards": 0, "existential_imprints": 0}

var _catalog: RefCounted
var _loadouts: RefCounted
var _forge: RefCounted
var _builds: RefCounted
var _districts: Array = []
var _meta_names: Dictionary = {}
var _narrative: Array = []
var _items: Array = []
var _enchantments: Array = []


func configure(registry: RefCounted, catalog: RefCounted, loadouts: RefCounted) -> bool:
	var forge := Forge.new()
	var builds := Builds.new()
	var forge_entries: Array = registry.get_catalog_entries(&"forge_definition", &"LAUNCH")
	if not forge.configure(forge_entries, catalog).ok or not builds.configure(catalog):
		return false
	_catalog = catalog
	_loadouts = loadouts
	_forge = forge
	_builds = builds
	_districts = registry.get_catalog_entries(&"hub_district", &"LAUNCH")
	_narrative = registry.get_catalog_entries(&"narrative_definition", &"LAUNCH")
	_items = registry.get_catalog_entries(&"item", &"LAUNCH")
	_meta_names.clear()
	_enchantments.clear()
	for row: Dictionary in registry.get_catalog_entries(&"meta_node", &"LAUNCH"):
		_meta_names[row.node_id] = {"name_key": row.name_key, "description_key": row.description_key}
	for row: Dictionary in forge_entries:
		if row.definition_kind == "enchantment":
			_enchantments.append(row)
	return true


func project(service: RefCounted, selection: Dictionary, district_id: String, function_id: String, epoch: int, providers: Array) -> Dictionary:
	var profile: Dictionary = service.snapshot()
	var validator := Profile.new()
	if _catalog == null or not validator.configure(_catalog, profile):
		return {}
	var districts: Array = []
	var functions: Array = []
	var panel := ""
	var npc := ""
	for district: Dictionary in _districts:
		districts.append(_row({"id": district.id, "name_key": district.name_key, "current": district.id == district_id, "scene_path": district.scene_path}))
		if district.id == district_id:
			for entry: Dictionary in district.functions:
				functions.append(_row({"id": entry.id, "name_key": "HUB_FUNCTION_" + str(entry.id).to_upper(), "district_id": district.id, "npc_id": entry.npc_id, "panel_id": entry.panel_id}))
				if entry.id == function_id:
					panel = entry.panel_id
					npc = entry.npc_id
	var nodes: Array = []
	for id: String in _catalog.ids():
		var definition: Dictionary = _catalog.definition(StringName(id))
		var probe := Profile.new()
		probe.configure(_catalog, profile)
		var result: Dictionary = probe.prepare_command({"command_id": _probe_id(profile), "kind": "meta_unlock", "node_id": id}, profile.revision)
		var row := {"id": id, "name_key": _meta_names[id].name_key, "description_key": _meta_names[id].description_key, "branch": definition.branch, "owned": profile.unlocked_nodes.has(id), "prerequisites": definition.prerequisites.duplicate()}
		row.merge(_status(result, definition.cost))
		nodes.append(row)
	var builds: Array = []
	for build: Dictionary in profile.build_library:
		var row: Dictionary = build.duplicate(true)
		row.merge(_status(service.resolve_build(build.id)))
		row["remove"] = _status(_builds.prepare_command(profile, {"command_id": _probe_id(profile), "kind": "build_remove", "build_id": build.id}, profile.revision))
		builds.append(row)
	var build_save := _status(_builds.prepare_command(profile, {"command_id": _probe_id(profile), "kind": "build_save", "build": {"id": _build_probe_id(profile), "name": "Preview", "character_id": selection.character_id, "weapon_id": selection.weapon_id, "time_abilities": selection.enabled_time_skills.duplicate()}}, profile.revision))
	var characters := _owned_rows(_loadouts.characters(), profile.unlocked_characters)
	var weapons := _owned_rows(_loadouts.weapons(), profile.unlocked_weapons)
	var pairs: Array = []
	for entry: Dictionary in _loadouts.time_pairs():
		pairs.append(_row({"id": entry.id, "ability_ids": entry.ability_ids.duplicate(), "name_keys": entry.name_keys.duplicate()}))
	var forge_rows: Array = []
	for weapon: Dictionary in _loadouts.weapons():
		forge_rows.append(_weapon(profile, weapon))
	var dialogue := _dialogue(service, npc)
	var launch_available: bool = profile.active_launch_receipt.is_empty() and profile.unlocked_characters.has(selection.character_id) and profile.unlocked_weapons.has(selection.weapon_id)
	var resume_available: bool = not profile.active_launch_receipt.is_empty() and service.authenticated_native_checkpoint(int(profile.revision)).ok
	var value := {"schema_version": 1, "revision": int(profile.revision), "epoch": epoch, "run_id": str(profile.active_launch_receipt.get("run_id", "")), "district_id": district_id, "panel_id": panel, "function_id": function_id, "currencies": {"chronos_shards": int(profile.chronos_shards), "existential_imprints": int(profile.existential_imprints)}, "repair_stage": int(profile.repair_stage), "districts": districts, "functions": functions, "nodes": nodes, "forge": {"weapons": forge_rows}, "builds": builds, "loadout": {"selected": selection.duplicate(true), "characters": characters, "weapons": weapons, "time_pairs": pairs, "build_save": build_save}, "dialogue": dialogue, "collections": _collections(profile), "providers": providers.duplicate(true), "launch_available": launch_available, "launch_reason_key": "" if launch_available else "HUB_LAUNCH_ACTIVE"}
	value["resume_available"] = resume_available
	value["resume_reason_key"] = "" if resume_available else "HUB_LAUNCH_ACTIVE"
	return value.duplicate(true) if Contract.validate(value).ok else {}


func _weapon(profile: Dictionary, weapon: Dictionary) -> Dictionary:
	var definition: Dictionary = _forge.weapon_definition(weapon.id)
	var projection: Dictionary = _forge.weapon_projection(profile, weapon.id)
	var cost: Dictionary = definition.levels[int(projection.forge_level)].cost if projection.forge_level < definition.levels.size() else ZERO_COST
	var upgrade: Dictionary = _forge.prepare_command(profile, {"command_id": _probe_id(profile), "kind": "forge_upgrade", "weapon_id": weapon.id}, profile.revision)
	var temper: Array = []
	for currency: String in ["chronos_shards", "existential_imprints"]:
		var result: Dictionary = _forge.prepare_command(profile, {"command_id": _probe_id(profile), "kind": "void_temper", "weapon_id": weapon.id, "payment_currency": currency}, profile.revision)
		var row := {"currency": currency}
		row.merge(_status(result, definition.void_temper_costs[0 if currency == "chronos_shards" else 1]))
		temper.append(row)
	var enchantments: Array = []
	for enchantment: Dictionary in _enchantments:
		var selected: bool = projection.enchant_preferences.has(enchantment.enchantment_id)
		var preferences: Array = projection.enchant_preferences.duplicate()
		if selected:
			preferences.erase(enchantment.enchantment_id)
		else:
			preferences.append(enchantment.enchantment_id)
		var result: Dictionary = _forge.prepare_command(profile, {"command_id": _probe_id(profile), "kind": "enchant_preference", "weapon_id": weapon.id, "enchantment_ids": preferences}, profile.revision)
		var enchant_cost: Dictionary = ZERO_COST if selected or profile.completed_command_ids.has("forge-enchant-unlock:" + str(enchantment.enchantment_id)) else enchantment.unlock_cost
		var row := {"id": enchantment.enchantment_id, "name_key": enchantment.name_key, "selected": selected}
		row.merge(_status(result, enchant_cost))
		enchantments.append(row)
	return {"id": weapon.id, "name_key": weapon.name_key, "level": int(projection.forge_level), "attack_bonus": projection.attack_bonus, "enchant_preferences": projection.enchant_preferences.duplicate(), "void_tempered": projection.void_tempered, "upgrade": _status(upgrade, cost), "enchantments": enchantments, "temper_options": temper}


func _dialogue(service: RefCounted, npc_id: String) -> Dictionary:
	var value := {"npc_id": npc_id, "affinity": 0, "nodes": []}
	if npc_id.is_empty():
		return value
	var produced: Dictionary = service.narrative_dialogue_view(npc_id)
	if not produced.ok:
		return value
	value.affinity = int(produced.context.affinity)
	for node: Dictionary in produced.context.nodes:
		var available: bool = node.available and not node.consumed
		var code := "SOURCE_CONSUMED" if node.consumed else "PREREQUISITE_MISSING"
		var choices: Array = []
		for choice: Dictionary in node.choices:
			choices.append(_row({"id": choice.id, "text_key": choice.text_key}, available, "" if available else "HUB_" + code))
		value.nodes.append(_row({"id": node.node_id, "text_key": node.text_key, "consumed": node.consumed, "choices": choices}, available, "" if available else "HUB_" + code))
	return value


func _collections(profile: Dictionary) -> Dictionary:
	var value := {"archive": [], "gallery": [], "mirror": []}
	for row: Dictionary in _narrative:
		if row.definition_kind in ["artifact", "environment_record"]:
			var id: String = row.artifact_id if row.definition_kind == "artifact" else row.record_id
			var owned: bool = profile.narrative_state.artifacts.has(id) if row.definition_kind == "artifact" else profile.narrative_state.environment_records.has(id)
			value.archive.append(_row({"id": id, "name_key": row.name_key, "owned": owned}, owned, "" if owned else "HUB_NOT_DISCOVERED"))
		elif row.definition_kind == "ending":
			var owned: bool = profile.narrative_state.endings.has(row.ending_id)
			value.mirror.append(_row({"id": row.ending_id, "name_key": row.name_key, "owned": owned}, owned, "" if owned else "HUB_NOT_DISCOVERED"))
	for row: Dictionary in _items:
		var owned: bool = profile.discovered_items.has(row.id)
		value.gallery.append(_row({"id": row.id, "name_key": row.name_key, "owned": owned}, owned, "" if owned else "HUB_NOT_DISCOVERED"))
	return value


func _owned_rows(entries: Array, owned: Array) -> Array:
	var value: Array = []
	for row: Dictionary in entries:
		value.append(_row({"id": row.id, "name_key": row.name_key}, owned.has(row.id), "" if owned.has(row.id) else "HUB_LOADOUT_LOCKED"))
	return value


static func _row(fields: Dictionary, available: bool = true, reason: String = "") -> Dictionary:
	var row := fields.duplicate(true)
	row.merge({"available": available, "reason_key": reason, "cost": ZERO_COST.duplicate()})
	return row


static func _status(result: Dictionary, cost: Dictionary = ZERO_COST) -> Dictionary:
	return {"available": bool(result.ok), "reason_key": "" if result.ok else "HUB_" + str(result.code), "cost": {"chronos_shards": int(cost.chronos_shards), "existential_imprints": int(cost.existential_imprints)}}


static func _probe_id(profile: Dictionary) -> String:
	var sequence := 0
	var id := "hub-preview-0"
	while profile.completed_command_ids.has(id):
		sequence += 1
		id = "hub-preview-%d" % sequence
	return id


static func _build_probe_id(profile: Dictionary) -> String:
	var occupied: Array = []
	for row: Dictionary in profile.build_library:
		occupied.append(row.id)
	var sequence := 0
	var id := "hub-preview-0"
	while occupied.has(id):
		sequence += 1
		id = "hub-preview-%d" % sequence
	return id
