class_name LaunchOrdinaryCopyProjection
extends RefCounted

const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Affix := preload("res://scripts/enemies/launch/launch_elite_affix_runtime.gd")
const AffixDefinition := preload("res://scripts/enemies/launch/elite_affix_definition.gd")
const Rules := preload("res://scripts/enemies/launch/elite_affix_rules.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const CONTRACT_FIELDS := ["schema_version", "parent_definition_id", "origin_affixes"]
static var _ordinary_definitions: Dictionary = {}


static func create(parent_id: String, origin_affixes: Dictionary) -> Dictionary:
	if not Affix._valid_configuration(origin_affixes) or int(origin_affixes.native_revision) != 10 or not origin_affixes.ids.has("splitting") or not Rules.legal_for(parent_id, int(origin_affixes.floor_index), origin_affixes.ids):
		return _failure()
	if _ordinary_definitions.is_empty() and not _load_ordinary_definitions():
		return _failure()
	if not _ordinary_definitions.has(parent_id):
		return _failure()
	var definition: Dictionary = _ordinary_definitions[parent_id].duplicate(true)
	definition.actor_kind = "summon"
	definition.max_hp = float(definition.max_hp) * float(AffixDefinition.PARAMETERS.splitting.child_hp_fraction)
	definition["copy_contract"] = {"schema_version": 1, "parent_definition_id": parent_id, "origin_affixes": origin_affixes.duplicate(true)}
	return {"ok": true, "definition": definition}


static func _load_ordinary_definitions() -> bool:
	var sources: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/enemies.json"))
	if not sources is Array or sources.size() != 22:
		return false
	var definitions := {}
	for source: Dictionary in sources:
		var parser := Enemy.new()
		if not parser.configure(source).ok or definitions.has(source.id):
			return false
		definitions[source.id] = parser.runtime_projection()
	_ordinary_definitions = definitions
	return true


static func validate(definition: Dictionary) -> bool:
	var binding: Variant = definition.get("copy_contract")
	if not binding is Dictionary or not Contract.exact_fields(binding, CONTRACT_FIELDS) or typeof(binding.schema_version) != TYPE_INT or binding.schema_version != 1 or not binding.parent_definition_id is String or not binding.origin_affixes is Dictionary:
		return false
	var canonical := create(binding.parent_definition_id, binding.origin_affixes)
	return canonical.ok and JSON.stringify(canonical.definition, "", true, true) == JSON.stringify(definition, "", true, true)


static func _failure() -> Dictionary:
	return {"ok": false, "code": &"ORDINARY_COPY_PROJECTION_INVALID"}
