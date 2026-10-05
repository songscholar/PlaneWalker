class_name BossDefinition
extends RefCounted

const Action := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_definition_contract.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const FIELDS: Array[String] = [
	"category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "references",
	"floor_id", "runtime_kind", "max_hp", "defense", "move_speed", "collision_radius_px", "actions", "phases", "enrage", "arena", "mechanisms", "time_responses",
]
const RUNTIME_FIELDS: Array[String] = ["actor_kind", "id", "runtime_kind", "max_hp", "defense", "move_speed", "collision_radius_px", "actions", "phases", "enrage", "arena", "mechanisms", "time_responses"]
const PREFIXES: Array[String] = ["guardian_", "matriarch_", "traitor_", "forge_", "voidking_"]
const HP: Array[int] = [800, 1400, 2000, 2800, 3000]
const ENRAGE_FRAMES: Array[int] = [18000, 16200, 14400, 12600, 10800]
const RESPONSE_IDS: Array[String] = ["traitor.counter_stop", "traitor.counter_rewind", "traitor.counter_accelerate", "traitor.counter_rift"]
const ACTION_IDS := {
  "ruin_king": [
    "guardian_shield_sweep",
    "guardian_fist_slam",
    "guardian_rift_beam",
    "guardian_charge",
    "guardian_rift_pulse",
    "guardian_debris_barrage",
    "guardian_wall",
    "guardian_enrage_collapse"
  ],
  "forest_heart": [
    "matriarch_root_sweep",
    "matriarch_spore_release",
    "matriarch_root_pierce",
    "matriarch_void_seed",
    "matriarch_void_cage",
    "matriarch_call",
    "matriarch_drain_roots",
    "matriarch_enrage_dissolution"
  ],
  "time_sovereign": [
    "traitor_temporal_slash",
    "traitor_chrono_bolt",
    "traitor_blink",
    "traitor_self_rewind",
    "traitor_time_freeze",
    "traitor_rift_slash",
    "traitor_timeline_split",
    "traitor_enrage_collapse"
  ],
  "forge_colossus": [
    "forge_hammer_slam",
    "forge_furnace_spray",
    "forge_lava_toss",
    "forge_combo",
    "forge_furnace_devour",
    "forge_anvil_sweep",
    "forge_eruption",
    "forge_forged_thrust",
    "forge_sword_wave",
    "forge_forged_cyclone",
    "forge_enrage_ultimate"
  ],
  "void_throne": [
    "voidking_scepter_strike",
    "voidking_void_bolt",
    "voidking_plane_tear",
    "voidking_void_step",
    "voidking_void_grasp",
    "voidking_tentacle_lash",
    "voidking_vortex",
    "voidking_devour",
    "voidking_shard_projection",
    "voidking_dual_strike",
    "voidking_void_end",
    "voidking_existence_denial",
    "voidking_enrage_zero"
  ]
}
const PHASE_CONTRACTS := {
  "ruin_king": [
    {
      "id": "p1",
      "hp_threshold": 1,
      "move_speed": 70,
      "poise_threshold": 200,
      "action_ids": [
        "guardian_shield_sweep",
        "guardian_fist_slam",
        "guardian_rift_beam",
        "guardian_charge"
      ]
    },
    {
      "id": "p2",
      "hp_threshold": 0.6,
      "move_speed": 84,
      "poise_threshold": 200,
      "action_ids": [
        "guardian_shield_sweep",
        "guardian_fist_slam",
        "guardian_rift_beam",
        "guardian_charge",
        "guardian_rift_pulse",
        "guardian_debris_barrage",
        "guardian_wall"
      ]
    }
  ],
  "forest_heart": [
    {
      "id": "p1",
      "hp_threshold": 1,
      "move_speed": 0,
      "poise_threshold": 200,
      "action_ids": [
        "matriarch_root_sweep",
        "matriarch_spore_release",
        "matriarch_root_pierce",
        "matriarch_void_seed"
      ]
    },
    {
      "id": "p2",
      "hp_threshold": 0.6,
      "move_speed": 0,
      "poise_threshold": 200,
      "action_ids": [
        "matriarch_root_sweep",
        "matriarch_spore_release",
        "matriarch_root_pierce",
        "matriarch_void_seed",
        "matriarch_void_cage",
        "matriarch_call",
        "matriarch_drain_roots"
      ]
    }
  ],
  "time_sovereign": [
    {
      "id": "p1",
      "hp_threshold": 1,
      "move_speed": 112,
      "poise_threshold": 150,
      "action_ids": [
        "traitor_temporal_slash",
        "traitor_chrono_bolt",
        "traitor_blink",
        "traitor_self_rewind"
      ]
    },
    {
      "id": "p2",
      "hp_threshold": 0.6,
      "move_speed": 126,
      "poise_threshold": 200,
      "action_ids": [
        "traitor_temporal_slash",
        "traitor_chrono_bolt",
        "traitor_blink",
        "traitor_self_rewind",
        "traitor_time_freeze",
        "traitor_rift_slash",
        "traitor_timeline_split"
      ]
    }
  ],
  "forge_colossus": [
    {
      "id": "p1",
      "hp_threshold": 1,
      "move_speed": 84,
      "poise_threshold": 250,
      "action_ids": [
        "forge_hammer_slam",
        "forge_furnace_spray",
        "forge_lava_toss",
        "forge_combo"
      ]
    },
    {
      "id": "p2",
      "hp_threshold": 0.6,
      "move_speed": 0,
      "poise_threshold": 200,
      "action_ids": [
        "forge_furnace_devour",
        "forge_anvil_sweep",
        "forge_eruption"
      ]
    },
    {
      "id": "p3",
      "hp_threshold": 0.25,
      "move_speed": 140,
      "poise_threshold": 180,
      "action_ids": [
        "forge_forged_thrust",
        "forge_sword_wave",
        "forge_forged_cyclone"
      ]
    }
  ],
  "void_throne": [
    {
      "id": "p1",
      "hp_threshold": 1,
      "move_speed": 126,
      "poise_threshold": 180,
      "action_ids": [
        "voidking_scepter_strike",
        "voidking_void_bolt",
        "voidking_plane_tear",
        "voidking_void_step",
        "voidking_void_grasp"
      ]
    },
    {
      "id": "p2",
      "hp_threshold": 0.6,
      "move_speed": 0,
      "poise_threshold": 220,
      "action_ids": [
        "voidking_tentacle_lash",
        "voidking_vortex",
        "voidking_devour",
        "voidking_shard_projection"
      ]
    },
    {
      "id": "p3",
      "hp_threshold": 0.2,
      "move_speed": 154,
      "poise_threshold": 200,
      "action_ids": [
        "voidking_scepter_strike",
        "voidking_void_bolt",
        "voidking_plane_tear",
        "voidking_void_step",
        "voidking_void_grasp",
        "voidking_dual_strike",
        "voidking_void_end",
        "voidking_existence_denial"
      ]
    }
  ]
}
const ARENA_CONTRACTS := {
  "ruin_king": [
    {
      "id": "ruins_cover_pillar",
      "kind": "cover",
      "count": 4,
      "max_hp": 80,
      "radius_px": 14
    }
  ],
  "forest_heart": [
    {
      "id": "forest_root",
      "kind": "root",
      "count": 6,
      "max_hp": 100,
      "radius_px": 12
    },
    {
      "id": "forest_spore_sac",
      "kind": "spore_sac",
      "count": 4,
      "max_hp": 30,
      "radius_px": 10
    },
    {
      "id": "forest_healing_flower",
      "kind": "healing_flower",
      "count": 3,
      "max_hp": 1,
      "radius_px": 8
    }
  ],
  "time_sovereign": [
    {
      "id": "traitor_watch",
      "kind": "weakpoint_proxy",
      "count": 1,
      "max_hp": 80,
      "radius_px": 12
    }
  ],
  "forge_colossus": [
    {
      "id": "forge_anvil",
      "kind": "cover",
      "count": 4,
      "max_hp": 120,
      "radius_px": 14
    },
    {
      "id": "forge_vent",
      "kind": "vent",
      "count": 4,
      "max_hp": 1,
      "radius_px": 16
    },
    {
      "id": "forge_cooling_pool",
      "kind": "cooling_pool",
      "count": 4,
      "max_hp": 1,
      "radius_px": 24
    }
  ],
  "void_throne": [
    {
      "id": "void_cover_pillar",
      "kind": "cover",
      "count": 4,
      "max_hp": 120,
      "radius_px": 14
    },
    {
      "id": "void_plane_core",
      "kind": "arena_core",
      "count": 4,
      "max_hp": 100,
      "radius_px": 12
    }
  ]
}
const PHASE_DAMAGE_OVERRIDES := {
  "ruin_king": {
    "p2": {
      "guardian_shield_sweep": 22
    }
  },
  "forest_heart": {
    "p2": {
      "matriarch_root_sweep": 26
    }
  },
  "time_sovereign": {
    "p2": {
      "traitor_temporal_slash": 30
    }
  },
  "forge_colossus": {},
  "void_throne": {}
}
const MECHANISM_RULES := {
  "ruin_king": {
    "poise_recovery_extension_frames": [
      45,
      45,
      true
    ],
    "charge_collision_exposure_frames": [
      60,
      60,
      true
    ],
    "aftershock_delay_frames": [
      60,
      60,
      true
    ],
    "aftershock_warning_frames": [
      40,
      40,
      true
    ],
    "aftershock_damage": [
      12,
      12,
      true
    ],
    "aftershock_radius_px": [
      32,
      32,
      true
    ],
    "debris_count_cap": [
      4,
      4,
      true
    ],
    "debris_hp": [
      20,
      20,
      true
    ],
    "debris_lifetime_frames": [
      480,
      480,
      true
    ],
    "wall_collapse_warning_frames": [
      40,
      40,
      true
    ],
    "wall_collapse_damage": [
      8,
      8,
      true
    ],
    "wall_collapse_radius_px": [
      24,
      24,
      true
    ],
    "cover_breaks_only_declared_constructs": true,
    "core_always_reachable": true
  },
  "forest_heart": {
    "root_break_exposure_frames": [
      45,
      45,
      true
    ],
    "p2_root_retirement_count": [
      3,
      3,
      true
    ],
    "roots_never_resurrect": true,
    "flower_heal": [
      20,
      20,
      true
    ],
    "flowers_once_only": true,
    "trunk_always_hittable": true,
    "root_burn_damage": [
      6,
      6,
      true
    ],
    "root_burn_tick_frames": [
      60,
      60,
      true
    ],
    "root_burn_frames": [
      180,
      180,
      true
    ],
    "pierce_slow_multiplier": [
      0.4,
      0.4,
      false
    ],
    "pierce_slow_frames": [
      90,
      90,
      true
    ],
    "seed_pool_radius_px": [
      29,
      29,
      true
    ],
    "seed_pool_lifetime_frames": [
      480,
      480,
      true
    ],
    "seed_pool_tick_damage": [
      12,
      12,
      true
    ],
    "seed_pool_tick_frames": [
      60,
      60,
      true
    ],
    "cage_pulse_warning_frames": [
      30,
      30,
      true
    ],
    "cage_pulse_damage": [
      8,
      8,
      true
    ],
    "cage_collapse_warning_frames": [
      40,
      40,
      true
    ],
    "cage_collapse_damage": [
      15,
      15,
      true
    ],
    "drain_heal_per_cast_cap": [
      80,
      80,
      true
    ],
    "drain_heal_encounter_cap": [
      200,
      200,
      true
    ],
    "drain_heal_actual_loss_only": true,
    "retire_summons_on_owner_death": true,
    "core_always_reachable": true
  },
  "time_sovereign": {
    "history_frames": [
      180,
      180,
      true
    ],
    "rewind_heal_per_cast_cap": [
      150,
      150,
      true
    ],
    "rewind_heal_encounter_cap": [
      300,
      300,
      true
    ],
    "rewind_interrupt_damage": [
      80,
      80,
      true
    ],
    "rewind_never_restores_claims": true,
    "temporal_mark_multiplier": [
      1.15,
      1.15,
      false
    ],
    "temporal_mark_frames": [
      240,
      240,
      true
    ],
    "temporal_mark_count_cap": [
      1,
      1,
      true
    ],
    "bolt_pool_radius_px": [
      16,
      16,
      true
    ],
    "bolt_pool_lifetime_frames": [
      180,
      180,
      true
    ],
    "freeze_time_regen_floor": [
      0.5,
      0.5,
      false
    ],
    "response_shared_cooldown_p1_frames": [
      900,
      900,
      true
    ],
    "response_shared_cooldown_p2_frames": [
      600,
      600,
      true
    ],
    "response_once_per_ability_generation": true,
    "response_defers_until_recovery": true,
    "counter_stop_delay_frames": [
      72,
      72,
      true
    ],
    "counter_stop_cancel_damage": [
      40,
      40,
      true
    ],
    "counter_stop_exposure_frames": [
      60,
      60,
      true
    ],
    "counter_rewind_echo_exposure_frames": [
      30,
      30,
      true
    ],
    "counter_accelerate_shatter_hits": [
      6,
      6,
      true
    ],
    "counter_accelerate_exposure_frames": [
      90,
      90,
      true
    ],
    "counter_rift_delay_frames": [
      30,
      30,
      true
    ],
    "counter_rift_recovery_extension_frames": [
      45,
      45,
      true
    ],
    "echo_final_warning_frames": [
      35,
      35,
      true
    ],
    "echo_final_damage": [
      20,
      20,
      true
    ],
    "echo_final_radius_px": [
      32,
      32,
      true
    ],
    "enrage_energy_cost_cap": [
      10,
      10,
      true
    ],
    "player_time_inputs_retained": true,
    "core_always_reachable": true
  },
  "forge_colossus": {
    "transformation_heal": [
      0,
      0,
      true
    ],
    "phase_retires_owned_hazards": true,
    "concurrent_arm_cap": [
      2,
      2,
      true
    ],
    "eruption_min_spacing_px": [
      32,
      32,
      true
    ],
    "cooling_removes_owned_burn": true,
    "cooling_entry_cooldown_frames": [
      30,
      30,
      true
    ],
    "cooling_survives_enrage": true,
    "vents_coordinate_floor_rule": true,
    "slam_pool_radius_px": [
      32,
      32,
      true
    ],
    "slam_pool_lifetime_frames": [
      180,
      180,
      true
    ],
    "slam_pool_tick_damage": [
      8,
      8,
      true
    ],
    "slam_pool_tick_frames": [
      60,
      60,
      true
    ],
    "slam_burn_damage": [
      10,
      10,
      true
    ],
    "slam_burn_tick_frames": [
      60,
      60,
      true
    ],
    "slam_burn_frames": [
      180,
      180,
      true
    ],
    "spray_pool_lifetime_frames": [
      120,
      120,
      true
    ],
    "lava_pool_radius_px": [
      32,
      32,
      true
    ],
    "lava_pool_lifetime_frames": [
      300,
      300,
      true
    ],
    "lava_pool_tick_damage": [
      8,
      8,
      true
    ],
    "lava_pool_tick_frames": [
      60,
      60,
      true
    ],
    "devour_inner_radius_px": [
      16,
      16,
      true
    ],
    "devour_inner_damage": [
      40,
      40,
      true
    ],
    "devour_inner_once": true,
    "eruption_pool_lifetime_frames": [
      120,
      120,
      true
    ],
    "cyclone_move_speed": [
      48,
      48,
      true
    ],
    "cyclone_route_frozen": true,
    "enrage_pool_lifetime_frames": [
      300,
      300,
      true
    ],
    "ground_immunity": false,
    "core_always_reachable": true
  },
  "void_throne": {
    "outer_body_damage_multiplier": [
      0.6,
      0.6,
      false
    ],
    "core_exposure_damage_multiplier": [
      1.5,
      1.5,
      false
    ],
    "core_always_reachable": true,
    "p2_cover_becomes_nondamaging_debris": true,
    "core_break_body_damage": [
      100,
      100,
      true
    ],
    "core_break_exposure_frames": [
      60,
      60,
      true
    ],
    "core_round_exposure_frames": [
      120,
      120,
      true
    ],
    "core_regeneration_frames": [
      600,
      600,
      true
    ],
    "core_round_cap": [
      2,
      2,
      true
    ],
    "p3_player_heal_fraction": [
      0.3,
      0.3,
      false
    ],
    "p3_heal_once": true,
    "p3_heal_never_revives": true,
    "scepter_burn_damage": [
      2,
      2,
      true
    ],
    "scepter_burn_tick_frames": [
      30,
      30,
      true
    ],
    "scepter_burn_frames": [
      180,
      180,
      true
    ],
    "bolt_slow_multiplier": [
      0.65,
      0.65,
      false
    ],
    "bolt_slow_frames": [
      120,
      120,
      true
    ],
    "tear_final_warning_frames": [
      40,
      40,
      true
    ],
    "tear_final_damage": [
      25,
      25,
      true
    ],
    "tear_final_radius_px": [
      32,
      32,
      true
    ],
    "step_followup_warning_frames": [
      28,
      28,
      true
    ],
    "grasp_slow_multiplier": [
      0.4,
      0.4,
      false
    ],
    "grasp_slow_frames": [
      90,
      90,
      true
    ],
    "tentacle_exposure_frames": [
      30,
      30,
      true
    ],
    "vortex_inner_radius_px": [
      24,
      24,
      true
    ],
    "vortex_inner_damage": [
      40,
      40,
      true
    ],
    "vortex_inner_once": true,
    "devour_damage_output_multiplier": [
      0.85,
      0.85,
      false
    ],
    "devour_debuff_frames": [
      180,
      180,
      true
    ],
    "devour_preserves_item_ownership": true,
    "shard_pickup_count_cap": [
      4,
      4,
      true
    ],
    "shard_pickup_lifetime_frames": [
      180,
      180,
      true
    ],
    "shard_pickup_energy": [
      5,
      5,
      true
    ],
    "shard_pickups_once_only": true,
    "void_end_zone_lifetime_frames": [
      300,
      300,
      true
    ],
    "core_break_interrupts_denial": true,
    "core_break_interrupts_enrage": true,
    "player_time_inputs_retained": true
  }
}

var _snapshot: Dictionary = {}
var _difficulty: Dictionary = {}


func configure(source: Dictionary) -> Dictionary:
	_snapshot.clear()
	_difficulty.clear()
	if not Action.exact_fields(source, FIELDS):
		return Contract.failure("boss", "exact_fields_required")
	var common := Contract.common(source, "boss_definition", Ids.BOSS_IDS)
	if not common.ok:
		return common
	var result: Dictionary = common.definition
	var index := Ids.BOSS_IDS.find(result.id)
	var floor_id: String = Ids.FLOOR_IDS[index]
	if typeof(result.floor_id) != TYPE_STRING or result.floor_id != floor_id or typeof(result.runtime_kind) != TYPE_STRING or result.runtime_kind != result.id:
		return Contract.failure("floor_id", "identity_mismatch")
	if not source.compatibility is Dictionary or not Action.exact_fields(source.compatibility, ["floor_ids", "actor_kinds"]):
		return Contract.failure("compatibility", "exact_fields_required")
	if source.compatibility.floor_ids != [floor_id] or source.compatibility.actor_kinds != ["boss"]:
		return Contract.failure("compatibility", "identity_mismatch")
	var numbers := Contract.numeric_fields(source, {"max_hp": [HP[index], HP[index], false], "defense": [0, 100, false], "move_speed": [0, 240, false], "collision_radius_px": [1, 48, false]})
	if not numbers.ok:
		return numbers
	result.merge(numbers.value, true)
	var seen: Dictionary = {}
	var warning_floor := 40 if index == 0 else 25 if index == 4 else 30
	var primary := Contract.actions(source.actions, "boss", PREFIXES[index], warning_floor, seen)
	if not primary.ok:
		return primary
	var actual_ids: Array[String] = []
	for action: Dictionary in primary.value:
		actual_ids.append(action.id)
		var expected_weight := 2 if "enrage_" in action.id else 8 if action.handler_id == "projectile_volley" else 6 if action.handler_id in ["zone", "pull_zone"] else 4 if action.handler_id in ["summon", "wall", "blink", "self_rewind"] else 10
		if action.idle_frames != 20 or action.weight != expected_weight or action.max_consecutive != (2 if "_bolt" in action.id else 1):
			return Contract.failure("actions", "canonical_selection_budget_required")
	if actual_ids != ACTION_IDS[result.id]:
		return Contract.failure("actions", "canonical_primary_moves_required")
	result.actions = primary.value
	var phase_result := _phases(source.phases, result.id)
	if not phase_result.ok:
		return phase_result
	result.phases = phase_result.value
	if result.move_speed != result.phases[0].move_speed:
		return Contract.failure("move_speed", "first_phase_mismatch")
	var enrage := _enrage(source.enrage, index, actual_ids.back())
	if not enrage.ok:
		return enrage
	result.enrage = enrage.value
	var arena := _arena(source.arena, result.id)
	if not arena.ok:
		return arena
	result.arena = arena.value
	var mechanism := _mechanisms(source.mechanisms, result.id)
	if not mechanism.ok:
		return mechanism
	result.mechanisms = mechanism.value
	if not source.time_responses is Array:
		return Contract.failure("time_responses", "expected_array")
	result.time_responses = []
	if index == 2:
		var responses := Contract.actions(source.time_responses, "boss", "traitor.counter_", 45, seen)
		if not responses.ok:
			return responses
		var response_ids: Array[String] = []
		for response: Dictionary in responses.value:
			response_ids.append(response.id)
		if response_ids != RESPONSE_IDS:
			return Contract.failure("time_responses", "four_canonical_ability_responses_required")
		result.time_responses = responses.value
	elif not source.time_responses.is_empty():
		return Contract.failure("time_responses", "unsupported_boss")
	var expected_references: Array[String] = [floor_id]
	for action: Dictionary in result.actions + result.time_responses:
		if action.handler_id == "summon":
			var summon_id := str(action.parameters.definition_id)
			if not Ids.SUMMON_IDS.has(summon_id):
				return Contract.failure("actions.parameters.definition_id", "unsupported_summon")
			if not expected_references.has(summon_id):
				expected_references.append(summon_id)
	expected_references.sort()
	if result.references != expected_references:
		return Contract.failure("references", "authored_reference_mismatch")
	_snapshot = result.duplicate(true)
	return {"ok": true, "definition": snapshot(), "context": {}}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func runtime_projection() -> Dictionary:
	if _snapshot.is_empty():
		return {}
	var result := {"actor_kind": "boss"}
	for field: String in RUNTIME_FIELDS.slice(1):
		var value: Variant = _snapshot[field]
		result[field] = value.duplicate(true) if value is Array or value is Dictionary else value
	if not _difficulty.is_empty():
		result["difficulty"] = _difficulty.duplicate(true)
	return result


func configure_runtime_projection(source: Dictionary) -> Dictionary:
	_snapshot.clear()
	_difficulty.clear()
	if source.has("difficulty"):
		return _configure_difficulty(source)
	if not Action.exact_fields(source, RUNTIME_FIELDS) or source.actor_kind != "boss" or not Ids.BOSS_IDS.has(source.id) or not source.actions is Array:
		return Contract.failure("runtime_projection", "exact_boss_fields_required")
	var floor_id: String = Ids.FLOOR_IDS[Ids.BOSS_IDS.find(source.id)]
	var references: Array[String] = [floor_id]
	for row: Variant in source.actions:
		if not row is Dictionary or not row.get("parameters") is Dictionary:
			return Contract.failure("actions", "expected_dictionary")
		if row.get("handler_id") == "summon" and row.parameters.get("definition_id") is String and not references.has(row.parameters.definition_id):
			references.append(row.parameters.definition_id)
	references.sort()
	# Rebuild only the structural envelope to reuse all authored gameplay checks.
	var envelope := source.duplicate(true)
	envelope.erase("actor_kind")
	envelope.merge({"category": "boss_definition", "schema_version": 1, "name_key": "BOSS_RUNTIME_NAME", "description_key": "BOSS_RUNTIME_DESC", "availability": ["LAUNCH", "EXPANSION"], "tags": ["boss"], "compatibility": {"floor_ids": [floor_id], "actor_kinds": ["boss"]}, "references": references, "floor_id": floor_id})
	var result := configure(envelope)
	return {"ok": true, "definition": runtime_projection(), "context": {}} if result.ok else result


static func difficulty_projection(base: Dictionary, hp_multiplier: float, damage_multiplier: float) -> Dictionary:
	if base.has("difficulty") or not Action.number_in_range(hp_multiplier, 1.0, 3.0) or not Action.number_in_range(damage_multiplier, 1.0, 2.0):
		return Contract.failure("difficulty", "canonical_base_and_bounded_multipliers_required")
	var parser := BossDefinition.new()
	var validated := parser.configure_runtime_projection(base)
	if not validated.ok:
		return validated
	var canonical := parser.runtime_projection()
	var projected := _scaled_projection(canonical, hp_multiplier, damage_multiplier)
	projected["difficulty"] = {"schema_version": 1, "hp_multiplier": hp_multiplier, "damage_multiplier": damage_multiplier, "base": canonical}
	return {"ok": true, "definition": projected, "context": {}}


func _configure_difficulty(source: Dictionary) -> Dictionary:
	var fields := RUNTIME_FIELDS.duplicate()
	fields.append("difficulty")
	if not Action.exact_fields(source, fields) or not source.difficulty is Dictionary or not Action.exact_fields(source.difficulty, ["schema_version", "hp_multiplier", "damage_multiplier", "base"]) or not Action.integer_in_range(source.difficulty.schema_version, 1, 1) or not source.difficulty.base is Dictionary:
		return Contract.failure("difficulty", "exact_fields_required")
	var projected := difficulty_projection(source.difficulty.base, float(source.difficulty.get("hp_multiplier", -1)), float(source.difficulty.get("damage_multiplier", -1))) if Action.number_in_range(source.difficulty.hp_multiplier, 1.0, 3.0) and Action.number_in_range(source.difficulty.damage_multiplier, 1.0, 2.0) else Contract.failure("difficulty", "invalid_multiplier")
	if not projected.ok:
		return projected
	if JSON.parse_string(JSON.stringify(source)) != JSON.parse_string(JSON.stringify(projected.definition)):
		return Contract.failure("difficulty", "scaled_projection_mismatch")
	var canonical: Dictionary = projected.definition.difficulty.base
	var validated := configure_runtime_projection(canonical)
	if not validated.ok:
		return validated
	var scaled: Dictionary = projected.definition
	for field: String in RUNTIME_FIELDS.slice(1):
		_snapshot[field] = scaled[field].duplicate(true) if scaled[field] is Array or scaled[field] is Dictionary else scaled[field]
	_difficulty = scaled.difficulty.duplicate(true)
	return {"ok": true, "definition": runtime_projection(), "context": {}}


static func _scaled_projection(base: Dictionary, hp_multiplier: float, damage_multiplier: float) -> Dictionary:
	var result := base.duplicate(true)
	result.max_hp = float(result.max_hp) * hp_multiplier
	for action: Dictionary in result.actions + result.time_responses:
		for hit: Dictionary in action.hit_schedule:
			hit.damage = float(hit.damage) * damage_multiplier
	for phase: String in result.mechanisms.phase_damage_overrides:
		for action: String in result.mechanisms.phase_damage_overrides[phase]:
			result.mechanisms.phase_damage_overrides[phase][action] = float(result.mechanisms.phase_damage_overrides[phase][action]) * damage_multiplier
	# Only outgoing damage scales; weakpoint thresholds and self-damage stay authored.
	for field: String in ["aftershock_damage", "wall_collapse_damage", "seed_pool_tick_damage", "cage_pulse_damage", "cage_collapse_damage", "echo_final_damage", "slam_pool_tick_damage", "slam_burn_damage", "lava_pool_tick_damage", "devour_inner_damage", "scepter_burn_damage", "tear_final_damage", "vortex_inner_damage"]:
		if result.mechanisms.has(field):
			result.mechanisms[field] = float(result.mechanisms[field]) * damage_multiplier
	return result


func _phases(value: Variant, id: String) -> Dictionary:
	var expected: Array = PHASE_CONTRACTS[id]
	if not value is Array or value.size() != expected.size():
		return Contract.failure("phases", "canonical_phase_count_required")
	var result: Array[Dictionary] = []
	var previous := 2.0
	for index: int in range(expected.size()):
		var source: Variant = value[index]
		if not source is Dictionary or not Action.exact_fields(source, ["id", "hp_threshold", "move_speed", "poise_threshold", "action_ids"]):
			return Contract.failure("phases", "exact_fields_required")
		if typeof(source.id) != TYPE_STRING or source.id != expected[index].id:
			return Contract.failure("phases.id", "identity_mismatch")
		var numbers := Contract.numeric_fields(source, {"hp_threshold": [0.01, 1, false], "move_speed": [0, 240, false], "poise_threshold": [1, 300, false]})
		if not numbers.ok:
			return numbers
		if numbers.value.hp_threshold >= previous:
			return Contract.failure("phases.hp_threshold", "strictly_descending_required")
		previous = numbers.value.hp_threshold
		for field: String in numbers.value:
			if numbers.value[field] != expected[index][field]:
				return Contract.failure("phases." + field, "phase_contract_mismatch")
		var ids := Contract.string_list(source.action_ids, ACTION_IDS[id].slice(0, -1), 1, 13, "phases.action_ids")
		if not ids.ok:
			return ids
		var expected_ids: Array = expected[index].action_ids.duplicate()
		expected_ids.sort()
		if ids.value != expected_ids:
			return Contract.failure("phases.action_ids", "phase_contract_mismatch")
		var phase: Dictionary = numbers.value
		phase.id = source.id
		phase.action_ids = ids.value
		result.append(phase)
	return {"ok": true, "value": result}


func _enrage(value: Variant, index: int, action_id: String) -> Dictionary:
	if not value is Dictionary or not Action.exact_fields(value, ["threshold_frames", "damage_multiplier", "cooldown_multiplier", "action_id"]):
		return Contract.failure("enrage", "exact_fields_required")
	var numbers := Contract.numeric_fields(value, {"threshold_frames": [ENRAGE_FRAMES[index], ENRAGE_FRAMES[index], true], "damage_multiplier": [1.2, 1.2, false], "cooldown_multiplier": [0.85, 0.85, false]})
	if not numbers.ok:
		return numbers
	if typeof(value.action_id) != TYPE_STRING or value.action_id != action_id:
		return Contract.failure("enrage.action_id", "identity_mismatch")
	var result: Dictionary = numbers.value
	result.action_id = action_id
	return {"ok": true, "value": result}


func _arena(value: Variant, id: String) -> Dictionary:
	if not value is Dictionary or not Action.exact_fields(value, ["bounds", "safe_corridor_width_px", "constructs", "edge_erosion_step_px", "edge_erosion_max_steps"]):
		return Contract.failure("arena", "exact_fields_required")
	if not value.bounds is Dictionary or not Action.exact_fields(value.bounds, ["x", "y", "width", "height"]):
		return Contract.failure("arena.bounds", "exact_fields_required")
	var bounds := Contract.numeric_fields(value.bounds, {"x": [-10000, 10000, false], "y": [-10000, 10000, false], "width": [320, 1280, false], "height": [180, 720, false]})
	if not bounds.ok:
		return bounds
	var erosion := 2 if id == "forest_heart" else 0
	var numbers := Contract.numeric_fields(value, {"safe_corridor_width_px": [48, 128, false], "edge_erosion_step_px": [16 if erosion else 0, 16 if erosion else 0, false], "edge_erosion_max_steps": [erosion, erosion, true]})
	if not numbers.ok:
		return numbers
	var expected: Array = ARENA_CONTRACTS[id]
	if not value.constructs is Array or value.constructs.size() != expected.size():
		return Contract.failure("arena.constructs", "canonical_constructs_required")
	var constructs: Array[Dictionary] = []
	for index: int in range(expected.size()):
		var source: Variant = value.constructs[index]
		if not source is Dictionary or not Action.exact_fields(source, ["id", "kind", "count", "max_hp", "radius_px"]):
			return Contract.failure("arena.constructs", "exact_fields_required")
		for field: String in ["id", "kind"]:
			if typeof(source[field]) != TYPE_STRING or source[field] != expected[index][field]:
				return Contract.failure("arena.constructs." + field, "identity_mismatch")
		var normalized := Contract.numeric_fields(source, {"count": [expected[index].count, expected[index].count, true], "max_hp": [expected[index].max_hp, expected[index].max_hp, false], "radius_px": [1, 32, false]})
		if not normalized.ok:
			return normalized
		var construct: Dictionary = normalized.value
		construct.id = source.id
		construct.kind = source.kind
		constructs.append(construct)
	var result: Dictionary = numbers.value
	result.bounds = bounds.value
	result.constructs = constructs
	return {"ok": true, "value": result}


func _mechanisms(value: Variant, id: String) -> Dictionary:
	if not value is Dictionary:
		return Contract.failure("mechanisms", "expected_dictionary")
	var expected_fields: Array = MECHANISM_RULES[id].keys()
	expected_fields.append("phase_damage_overrides")
	if not Action.exact_fields(value, expected_fields):
		return Contract.failure("mechanisms", "exact_fields_required")
	var overrides: Variant = value.phase_damage_overrides
	var expected: Dictionary = PHASE_DAMAGE_OVERRIDES[id]
	if not overrides is Dictionary or not Action.exact_fields(overrides, expected.keys()):
		return Contract.failure("mechanisms.phase_damage_overrides", "exact_phases_required")
	var normalized_overrides: Dictionary = {}
	for phase_id: String in expected:
		if not overrides[phase_id] is Dictionary or not Action.exact_fields(overrides[phase_id], expected[phase_id].keys()):
			return Contract.failure("mechanisms.phase_damage_overrides", "exact_actions_required")
		normalized_overrides[phase_id] = {}
		for action_id: String in expected[phase_id]:
			var damage: Variant = overrides[phase_id][action_id]
			if not Action.number_in_range(damage, expected[phase_id][action_id], expected[phase_id][action_id]):
				return Contract.failure("mechanisms.phase_damage_overrides", "invalid_damage")
			normalized_overrides[phase_id][action_id] = float(damage)
	var scalar_source: Dictionary = value.duplicate(true)
	scalar_source.erase("phase_damage_overrides")
	var scalar := Contract.mechanisms(scalar_source, MECHANISM_RULES[id])
	if not scalar.ok:
		return scalar
	var result: Dictionary = scalar.value
	result.phase_damage_overrides = normalized_overrides
	return {"ok": true, "value": result}
