class_name MerchantViewState
extends RefCounted

const Rules := preload("res://scripts/ui/contracts/dungeon_view_state_rules.gd")
const Merchants := preload("res://scripts/dungeon/merchant_definition.gd")
const LaunchPoolCatalogScript := preload("res://scripts/content/launch_pool_catalog.gd")
const SCHEMA_VERSION := 1
const FIELDS := ["schema_version", "revision", "run_id", "merchant_id", "name_key", "description_key", "intro_key", "gold", "offers", "services"]
const OFFER_FIELDS := ["offer_id", "content_id", "category", "rarity", "name_key", "description_key", "price", "sold", "affordable", "available", "disabled_reason_key"]
const SERVICE_FIELDS := ["action_id", "target_id", "label_key", "cost_kind", "price", "available", "disabled_reason_key"]


static func validate(value: Variant):
	if not Rules.header(value, FIELDS):
		return Rules.reject(value, "root")
	var state := value as Dictionary
	if not Merchants.MERCHANT_IDS.has(state["merchant_id"]) or not Rules.integer(state["gold"]) or int(state["gold"]) < 0:
		return Rules.reject(value, "merchant")
	for field: String in ["name_key", "description_key", "intro_key"]:
		if not Rules.key(state[field]):
			return Rules.reject(value, field)
	if not state["offers"] is Array or not state["services"] is Array or state["offers"].size() > 32 or state["services"].size() > 128:
		return Rules.reject(value, "offers")
	var ids: Dictionary = {}
	for offer_value: Variant in state["offers"]:
		if not Rules.exact(offer_value, OFFER_FIELDS):
			return Rules.reject(value, "offers")
		var offer := offer_value as Dictionary
		if not Rules.identifier(offer["offer_id"]) or ids.has(offer["offer_id"]) or not known_content(offer["category"], offer["content_id"]) or not Merchants.RARITY_FIELDS.has(offer["rarity"]) or not Rules.key(offer["name_key"]) or not Rules.key(offer["description_key"]) or not Rules.integer(offer["price"]) or int(offer["price"]) < 0 or typeof(offer["sold"]) != TYPE_BOOL or typeof(offer["affordable"]) != TYPE_BOOL or not Rules.availability(offer):
			return Rules.reject(value, "offers.identity")
		if offer["affordable"] != (int(state["gold"]) >= int(offer["price"])) or offer["available"] != (not offer["sold"] and offer["affordable"]):
			return Rules.reject(value, "offers.affordable")
		ids[offer["offer_id"]] = true
	ids.clear()
	for service_value: Variant in state["services"]:
		if not Rules.exact(service_value, SERVICE_FIELDS):
			return Rules.reject(value, "services")
		var service := service_value as Dictionary
		var id := "%s:%s" % [service["action_id"], service["target_id"]]
		if not Merchants.SERVICES.has(service["action_id"]) or not Rules.identifier(service["target_id"]) or ids.has(id) or not Rules.key(service["label_key"]) or service["cost_kind"] not in ["gold", "health", "reward", "none"] or not Rules.integer(service["price"]) or int(service["price"]) < 0 or not Rules.availability(service):
			return Rules.reject(value, "services.identity")
		if service["cost_kind"] == "gold" and int(service["price"]) > int(state["gold"]) and service["available"]:
			return Rules.reject(value, "services.affordable")
		ids[id] = true
	return Rules.accept(state)


static func copy_of(value: Dictionary) -> Dictionary:
	return value.duplicate(true) if validate(value).ok else {}


static func known_content(category: Variant, content_id: Variant) -> bool:
	var catalogs := {"item": LaunchPoolCatalogScript.EXACT_ITEM_ROWS, "blessing": LaunchPoolCatalogScript.EXACT_BLESSING_ROWS, "curse": LaunchPoolCatalogScript.EXACT_CURSE_ROWS}
	if not catalogs.has(category) or not Rules.identifier(content_id):
		return false
	for row: String in catalogs[category]:
		if row.get_slice("|", 0) == content_id:
			return true
	return false
