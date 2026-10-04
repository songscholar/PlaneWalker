extends RefCounted

const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")


static func catalog() -> RefCounted:
	var loaded := Factory.load_base()
	return loaded.context.catalog if loaded.ok else null


static func profile(catalog_value: RefCounted, complete_unlocks: bool = true) -> Dictionary:
	var state := Profile.new()
	if not state.configure(catalog_value):
		return {}
	var value := state.snapshot()
	value.chronos_shards = 1000
	value.existential_imprints = 20
	if complete_unlocks:
		value.unlocked_nodes = catalog_value.call("ids")
		value.unlocked_characters = ["primordial_knight", "time_guardian", "time_lord", "void_walker", "wanderer"]
		value.unlocked_weapons = ["bow", "gauntlets", "gun", "staff", "sword"]
	return value


static func forge_entries() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/forge_definitions.json"))
