extends RefCounted

const Catalog := preload("res://scripts/dungeon/launch_encounter_catalog.gd")
const Generator := preload("res://scripts/dungeon/floor_plan_generator.gd")


static func find_species(id: String, floor_index: int) -> Dictionary:
	var catalog := Catalog.new()
	if not catalog.configure_authored().ok:
		return {}
	var floors: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/floors.json"))
	var templates: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json"))
	for seed: int in range(1, 64):
		var generated: Dictionary = Generator.new().generate(seed, floors[floor_index], templates)
		if not generated.ok:
			continue
		for node: Dictionary in generated.plan.nodes:
			if node.room_type not in ["combat", "elite"]:
				continue
			var recipe: Dictionary = catalog.resolve_for_revision(str(floors[floor_index].encounter_profile_id), seed, str(node.id), str(node.room_type), str(node.template_id), 2)
			if not recipe.get("waves", []).is_empty() and recipe.waves[0].spawns.any(func(row: Dictionary): return row.enemy_id == id):
				return {"seed": seed, "node_id": node.id, "recipe_id": recipe.id}
	return {}
