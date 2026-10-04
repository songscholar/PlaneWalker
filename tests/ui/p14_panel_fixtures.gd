extends RefCounted


static func map_state() -> Dictionary:
	return {
		"schema_version": 1, "revision": 4, "run_id": "panel-run",
		"floor_id": "floor_ruins_of_remnant", "floor_index": 0,
		"floor_name_key": "FLOOR_RUINS_OF_REMNANT_NAME", "gold": 120,
		"current_node_id": "entry", "boss_distance": 6,
		"nodes": [
			{"id": "entry", "layer": 0, "room_type": "entry", "name_key": "ROOM_TYPE_ENTRY", "revealed": true, "visited": true, "cleared": true, "current": true},
			{"id": "left", "layer": 1, "room_type": "combat", "name_key": "ROOM_TYPE_COMBAT", "revealed": true, "visited": false, "cleared": false, "current": false},
			{"id": "right", "layer": 1, "room_type": "shop", "name_key": "ROOM_TYPE_SHOP", "revealed": true, "visited": false, "cleared": false, "current": false},
			{"id": "secret", "layer": 2, "room_type": "unknown", "name_key": "UI_ROOM_UNKNOWN", "revealed": false, "visited": false, "cleared": false, "current": false},
			{"id": "boss", "layer": 3, "room_type": "unknown", "name_key": "UI_ROOM_UNKNOWN", "revealed": false, "visited": false, "cleared": false, "current": false},
		],
		"edges": [
			{"id": "left-edge", "source_node_id": "entry", "destination_node_id": "left", "selected": false},
			{"id": "right-edge", "source_node_id": "entry", "destination_node_id": "right", "selected": false},
			{"id": "secret-edge", "source_node_id": "left", "destination_node_id": "secret", "selected": false},
			{"id": "right-secret-edge", "source_node_id": "right", "destination_node_id": "secret", "selected": false},
			{"id": "boss-edge", "source_node_id": "secret", "destination_node_id": "boss", "selected": false},
		],
		"routes": [
			{"edge_id": "left-edge", "node_id": "left", "choice_order": 0, "room_type": "combat", "name_key": "ROOM_TYPE_COMBAT", "available": true, "disabled_reason_key": ""},
			{"edge_id": "right-edge", "node_id": "right", "choice_order": 1, "room_type": "shop", "name_key": "ROOM_TYPE_SHOP", "available": false, "disabled_reason_key": "UI_ROUTE_UNAVAILABLE"},
		],
	}


static func merchant_state() -> Dictionary:
	return {
		"schema_version": 1, "revision": 4, "run_id": "panel-run",
		"merchant_id": "merchant_wayfarer", "name_key": "MERCHANT_WAYFARER_NAME",
		"description_key": "MERCHANT_WAYFARER_DESC", "intro_key": "MERCHANT_WAYFARER_INTRO", "gold": 120,
		"offers": [
			{"offer_id": "offer-a", "content_id": "frozen_burst", "category": "item", "rarity": "common", "name_key": "FROZEN_BURST_NAME", "description_key": "FROZEN_BURST_DESC", "price": 40, "sold": false, "affordable": true, "available": true, "disabled_reason_key": ""},
			{"offer_id": "offer-b", "content_id": "rewind_echo", "category": "item", "rarity": "rare", "name_key": "REWIND_ECHO_NAME", "description_key": "REWIND_ECHO_DESC", "price": 160, "sold": false, "affordable": false, "available": false, "disabled_reason_key": "UI_MERCHANT_INSUFFICIENT_GOLD"},
		],
		"services": [{"action_id": "heal", "target_id": "heal", "label_key": "UI_MERCHANT_HEAL", "cost_kind": "gold", "price": 20, "available": true, "disabled_reason_key": ""}],
	}


static func event_state() -> Dictionary:
	return {
		"schema_version": 1, "revision": 4, "run_id": "panel-run",
		"phase": "open", "event_id": "event_chronal_altar",
		"name_key": "EVENT_CHRONAL_ALTAR_NAME", "description_key": "EVENT_CHRONAL_ALTAR_DESC", "prompt_key": "EVENT_CHRONAL_ALTAR_PROMPT",
		"options": [
			{"id": "commit", "label_key": "EVENT_CHRONAL_ALTAR_OPTION_COMMIT", "eligible": true, "disabled_reason_key": "", "outcome_visibility": "hidden_until_commit", "visible_preview": []},
			{"id": "decline", "label_key": "UI_MERCHANT_HEAL", "eligible": false, "disabled_reason_key": "UI_REQUIREMENT_UNMET", "outcome_visibility": "preview_exact", "visible_preview": []},
		],
		"result_key": "", "pending_kind": "",
	}


static func reward_offer(revision: int) -> Dictionary:
	return {
		"schema_version": 1, "offer_id": "event-reward-offer", "category": "item", "title_key": "CHOICE_TITLE_ITEM", "revision": revision, "can_skip": false, "continuation_id": "event-reward-continuation",
		"options": [{"option_id": "choose-frozen-burst", "content_id": "frozen_burst", "name_key": "FROZEN_BURST_NAME", "description_key": "FROZEN_BURST_DESC", "archetype_key": "ARCHETYPE_TIME_STOP_BURST", "role_key": "ROLE_DAMAGE", "rarity": "common", "icon_id": "icon_frozen_burst", "effect_summary_keys": ["EFFECT_TIME_STOP_BURST"]}],
	}


static func room_state() -> Dictionary:
	return {
		"schema_version": 1, "revision": 4, "run_id": "panel-run",
		"room_type": "rest", "node_id": "rest-node", "name_key": "ROOM_TYPE_REST", "description_key": "UI_REST_PROMPT",
		"choices": [
			{"id": "heal", "label_key": "UI_MERCHANT_HEAL", "description_key": "UI_REST_PROMPT", "available": true, "disabled_reason_key": ""},
			{"id": "leave", "label_key": "UI_ROOM_LEAVE", "description_key": "UI_REST_PROMPT", "available": false, "disabled_reason_key": "UI_MERCHANT_INSUFFICIENT_GOLD"},
		],
	}


static func transition_state() -> Dictionary:
	return {
		"schema_version": 1, "revision": 4, "run_id": "panel-run",
		"completed_floor_id": "floor_ruins_of_remnant", "completed_floor_index": 0, "completed_name_key": "FLOOR_RUINS_OF_REMNANT_NAME",
		"next_floor_id": "floor_void_forest", "next_floor_index": 1, "next_name_key": "FLOOR_VOID_FOREST_NAME", "gold": 120, "available": true,
	}


static func for_kind(kind: String) -> Dictionary:
	match kind:
		"map", "route": return map_state()
		"merchant": return merchant_state()
		"event": return event_state()
		"room": return room_state()
		"transition": return transition_state()
	return {}
