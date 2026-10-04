class_name EnemyDefinition
extends RefCounted

const Action := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_definition_contract.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const FIELDS: Array[String] = [
	"category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "references",
	"floor_id", "runtime_kind", "max_hp", "defense", "move_speed", "threat_cost", "collision_radius_px", "mechanisms", "actions", "elite_actions",
]
const ACTION_IDS := {
  "shattered_sentinel": {
    "actions": [
      "shattered_sentinel.shield_sweep"
    ],
    "elite_actions": [
      "shattered_sentinel.boulder_slam"
    ]
  },
  "corrosive_moth": {
    "actions": [
      "corrosive_moth.corrosive_spit"
    ],
    "elite_actions": [
      "corrosive_moth.corrosive_barrage"
    ]
  },
  "stone_shell_strider": {
    "actions": [
      "stone_shell_strider.shell_charge",
      "stone_shell_strider.bite"
    ],
    "elite_actions": [
      "stone_shell_strider.shell_shock"
    ]
  },
  "ruins_wraith": {
    "actions": [
      "ruins_wraith.spirit_detonation"
    ],
    "elite_actions": [
      "ruins_wraith.spirit_split"
    ]
  },
  "rift_watcher": {
    "actions": [
      "rift_watcher.nourish",
      "rift_watcher.rift_pulse"
    ],
    "elite_actions": [
      "rift_watcher.rift_bind"
    ]
  },
  "void_hunter": {
    "actions": [
      "void_hunter.claw_pair",
      "void_hunter.backstab_dash"
    ],
    "elite_actions": [
      "void_hunter.hunter_echo"
    ]
  },
  "void_archer": {
    "actions": [
      "void_archer.void_arrow",
      "void_archer.arrow_fan"
    ],
    "elite_actions": [
      "void_archer.piercing_arrow"
    ]
  },
  "bramble_mage": {
    "actions": [
      "bramble_mage.bramble_growth",
      "bramble_mage.entangling_whip"
    ],
    "elite_actions": [
      "bramble_mage.bramble_cage"
    ]
  },
  "void_spore": {
    "actions": [
      "void_spore.spore_burst"
    ],
    "elite_actions": [
      "void_spore.spore_split"
    ]
  },
  "forest_caller": {
    "actions": [
      "forest_caller.void_call",
      "forest_caller.energy_bolt"
    ],
    "elite_actions": [
      "forest_caller.great_call"
    ]
  },
  "shadow_lurker": {
    "actions": [
      "shadow_lurker.shadow_ambush",
      "shadow_lurker.surface_claw"
    ],
    "elite_actions": [
      "shadow_lurker.shadow_trap"
    ]
  },
  "chrono_guard": {
    "actions": [
      "chrono_guard.chronal_slam",
      "chrono_guard.rift_slash"
    ],
    "elite_actions": [
      "chrono_guard.time_lock"
    ]
  },
  "rift_weaver": {
    "actions": [
      "rift_weaver.rift_make",
      "rift_weaver.distortion_bolt"
    ],
    "elite_actions": [
      "rift_weaver.rift_fusion"
    ]
  },
  "blink_striker": {
    "actions": [
      "blink_striker.blink_cut",
      "blink_striker.rift_cross"
    ],
    "elite_actions": [
      "blink_striker.triple_blink"
    ]
  },
  "rewind_priest": {
    "actions": [
      "rewind_priest.rewind_heal",
      "rewind_priest.slow_bolt"
    ],
    "elite_actions": [
      "rewind_priest.time_reverse"
    ]
  },
  "chrono_storm_elemental": {
    "actions": [
      "chrono_storm_elemental.time_storm",
      "chrono_storm_elemental.timeflow_push"
    ],
    "elite_actions": [
      "chrono_storm_elemental.time_stasis"
    ]
  },
  "eternal_hound": {
    "actions": [
      "eternal_hound.temporal_bite"
    ],
    "elite_actions": [
      "eternal_hound.time_hunt"
    ]
  },
  "forge_titan": {
    "actions": [
      "forge_titan.forge_fist",
      "forge_titan.ground_fissure",
      "forge_titan.flame_breath"
    ],
    "elite_actions": [
      "forge_titan.plane_collapse"
    ]
  },
  "void_web_weaver": {
    "actions": [
      "void_web_weaver.void_web",
      "void_web_weaver.thread_fan",
      "void_web_weaver.binding_thread"
    ],
    "elite_actions": [
      "void_web_weaver.web_cage"
    ]
  },
  "phase_ranger": {
    "actions": [
      "phase_ranger.phase_arrow",
      "phase_ranger.void_arrow_rain"
    ],
    "elite_actions": [
      "phase_ranger.phase_split"
    ]
  },
  "chaos_amalgam": {
    "actions": [
      "chaos_amalgam.rage_combo",
      "chaos_amalgam.flame_charge",
      "chaos_amalgam.frost_wave",
      "chaos_amalgam.ice_spikes",
      "chaos_amalgam.void_pull",
      "chaos_amalgam.void_pulse"
    ],
    "elite_actions": [
      "chaos_amalgam.chaos_outburst"
    ]
  },
  "plane_ripper": {
    "actions": [
      "plane_ripper.plane_rip",
      "plane_ripper.rift_strike"
    ],
    "elite_actions": [
      "plane_ripper.one_way_plane"
    ]
  }
}
const MECHANISM_RULES := {
	"shattered_sentinel": {"retreat_distance_px": [0, 32, false], "retreat_frames": [1, 60, true], "first_attack_stagger_frames": [1, 120, true]},
	"corrosive_moth": {"kite_min_px": [32, 128, false], "kite_max_px": [32, 128, false], "impact_pool_radius_px": [1, 24, false], "impact_pool_lifetime_frames": [1, 180, true], "impact_pool_damage": [0, 5, false], "impact_pool_tick_frames": [60, 120, true], "death_pool_warning_frames": [30, 120, true], "death_pool_damage": [0, 5, false], "death_pool_radius_px": [1, 24, false]},
	"stone_shell_strider": {"shell_frames": [1, 120, true], "shell_damage_multiplier": [0.3, 1, false], "open_frames": [1, 30, true], "open_damage_multiplier": [1, 1.3, false], "elite_shock_once_per_cycle": true},
	"ruins_wraith": {"internal_obstacle_passthrough": true, "windup_interrupt_damage": [1, 15, false], "stagger_frames": [30, 60, true], "consume_after_active": true, "elite_split_on_final_death": true},
	"rift_watcher": {"support_only": true, "recipient_heal_fraction_cap": [0, 0.4, false], "all_sources_recipient_heal_fraction_cap": [0, 0.8, false], "death_attack_multiplier": [0.8, 1, false], "death_debuff_frames": [1, 180, true]},
	"void_hunter": {"flank_speed_multiplier": [1, 1.2, false], "retreat_distance_px": [0, 32, false], "silhouette_always_visible": true},
	"void_archer": {"kite_min_px": [32, 160, false], "kite_max_px": [32, 160, false], "obstacle_aware_retreat": true},
	"bramble_mage": {"own_pool_immunity": true, "ally_pool_immunity": false, "pool_count_cap": [1, 3, true], "whip_slow_multiplier": [0.4, 1, false], "whip_slow_frames": [0, 48, true]},
	"void_spore": {"chain_depth_cap": [1, 5, true], "chain_warning_frames": [30, 120, true], "residual_radius_px": [1, 24, false], "residual_lifetime_frames": [1, 180, true], "residual_tick_damage": [0, 5, false], "residual_tick_frames": [60, 120, true], "residual_slow_multiplier": [0.8, 1, false], "elite_split_count": [2, 2, true]},
	"forest_caller": {"summon_warning_interruptible": true, "retire_summons_on_owner_death": true, "retreat_route_validated": true},
	"shadow_lurker": {"burrow_cap_frames": [1, 180, true], "ground_damage_multiplier": [0.5, 1, false], "landing_all_weapons_hittable": true, "visible_burrow_trail": true},
	"chrono_guard": {"revival_count_cap": [1, 1, true], "revival_recovery_frames": [90, 180, true], "revival_hp": [1, 54, false], "revival_flag_before_publication": true, "slash_corridor_lifetime_frames": [1, 360, true]},
	"rift_weaver": {"prediction_cap_frames": [0, 30, true], "zone_count_cap": [1, 3, true], "zone_shift_warning_frames": [30, 120, true], "shift_portal_opt_in": true, "elite_fusion_consumes_owned_zones": true},
	"blink_striker": {"transit_frames": [1, 8, true], "followup_warning_frames": [25, 120, true], "rift_transit_distance_multiplier": [0.5, 1, false], "stop_postpones_landing": true},
	"rewind_priest": {"history_frames": [1, 180, true], "base_heal_recipient_fraction": [0, 0.3, false], "recipient_heal_fraction_cap": [0, 0.4, false], "all_sources_recipient_heal_fraction_cap": [0, 0.8, false], "elite_attack_multiplier": [1, 1.25, false], "elite_attack_buff_frames": [1, 300, true], "no_resurrection": true},
	"chrono_storm_elemental": {"zone_count_cap": [1, 2, true], "pattern_radius_px": [1, 64, false], "fast_multiplier": [1, 1.25, false], "slow_multiplier": [0.6, 1, false], "swap_warning_frames": [30, 120, true], "swap_interval_frames": [90, 180, true], "death_warning_frames": [35, 120, true], "death_slow_multiplier": [0.7, 1, false], "death_slow_frames": [0, 180, true], "elite_enemy_only_action_freeze": true},
	"eternal_hound": {"dormancy_count_cap": [1, 1, true], "dormancy_frames": [300, 300, true], "dormancy_sigil_hp": [1, 12, false], "revival_hp": [1, 35, false], "elite_hit_heal_cap": [0, 20, false], "no_reward_until_final": true},
	"forge_titan": {"breath_hp_threshold": [0.5, 0.5, false], "overheat_hp_threshold": [0.3, 0.3, false], "overheat_frames": [1, 600, true], "overheat_attack_multiplier": [1, 1.25, false], "overheat_speed_multiplier": [1, 1.15, false], "explosion_warning_frames": [60, 120, true], "explosion_damage": [0, 40, false], "explosion_radius_px": [1, 48, false], "corpse_explosion_warning_frames": [60, 120, true], "pool_lifetime_frames": [1, 180, true]},
	"void_web_weaver": {"link_count_cap": [1, 3, true], "link_attack_multiplier": [1, 1.15, false], "link_speed_multiplier": [1, 1.1, false], "link_strongest_only": true, "link_collision_warning_frames": [35, 120, true], "elevation_grants_immunity": false},
	"phase_ranger": {"projectiles_always_visible": true, "shift_distance_cap_px": [0, 80, false], "shift_cooldown_frames": [180, 360, true], "shift_recovery_frames": [30, 60, true]},
	"chaos_amalgam": {"form_ids": ["red", "blue", "void"], "form_cycle_frames": [240, 240, true], "low_hp_form_cycle_frames": [150, 150, true], "low_hp_threshold": [0.5, 0.5, false], "switch_recovery_frames": [30, 60, true], "never_switch_committed_action": true, "elite_burn_damage": [0, 5, false], "elite_burn_tick_frames": [60, 120, true], "elite_burn_frames": [0, 180, true]},
	"plane_ripper": {"portal_pair_cap": [1, 1, true], "portal_transit_cooldown_frames": [12, 60, true], "portal_arrival_clearance_px": [48, 128, false], "death_collapse_warning_frames": [45, 120, true], "death_collapse_damage": [0, 20, false], "death_collapse_radius_px": [1, 32, false]},
}

var _snapshot: Dictionary = {}


func configure(source: Dictionary) -> Dictionary:
	_snapshot.clear()
	if not Action.exact_fields(source, FIELDS):
		return Contract.failure("enemy", "exact_fields_required")
	var common := Contract.common(source, "enemy_definition", Ids.enemy_ids())
	if not common.ok:
		return common
	var result: Dictionary = common.definition
	var floor_id: String = Ids.FLOOR_IDS[int(Ids.ENEMY_FLOORS[result.id]) - 1]
	if typeof(result.floor_id) != TYPE_STRING or result.floor_id != floor_id or typeof(result.runtime_kind) != TYPE_STRING or result.runtime_kind != result.id:
		return Contract.failure("floor_id", "identity_mismatch")
	if not source.compatibility is Dictionary or not Action.exact_fields(source.compatibility, ["floor_ids", "actor_kinds"]):
		return Contract.failure("compatibility", "exact_fields_required")
	if source.compatibility.floor_ids != [floor_id] or source.compatibility.actor_kinds != ["enemy", "elite"]:
		return Contract.failure("compatibility", "identity_mismatch")
	var numbers := Contract.numeric_fields(source, {"max_hp": [1, 1000, false], "defense": [0, 100, false], "move_speed": [0, 240, false], "threat_cost": [1, 5, true], "collision_radius_px": [1, 32, false]})
	if not numbers.ok:
		return numbers
	result.merge(numbers.value, true)
	var mechanism := Contract.mechanisms(source.mechanisms, MECHANISM_RULES[result.id])
	if not mechanism.ok:
		return mechanism
	result.mechanisms = mechanism.value
	if result.mechanisms.has("kite_min_px") and result.mechanisms.kite_min_px > result.mechanisms.kite_max_px:
		return Contract.failure("mechanisms.kite_min_px", "greater_than_max")
	var seen: Dictionary = {}
	var warning_floor := 30 if Ids.ENEMY_FLOORS[result.id] == 1 else 23
	var ordinary := Contract.actions(source.actions, "enemy", result.id + ".", warning_floor, seen)
	if not ordinary.ok:
		return ordinary
	var elite := Contract.actions(source.elite_actions, "elite", result.id + ".", warning_floor, seen)
	if not elite.ok:
		return elite
	if elite.value.size() != 1:
		return Contract.failure("elite_actions", "one_species_move_required")
	result.actions = ordinary.value
	result.elite_actions = elite.value
	for field: String in ["actions", "elite_actions"]:
		var action_ids: Array[String] = []
		for action: Dictionary in result[field]:
			action_ids.append(action.id)
		if action_ids != ACTION_IDS[result.id][field]:
			return Contract.failure(field, "canonical_species_actions_required")
	var expected_references: Array[String] = [floor_id]
	for action: Dictionary in result.actions + result.elite_actions:
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


func runtime_projection(actor_kind: String = "enemy") -> Dictionary:
	if _snapshot.is_empty() or actor_kind not in ["enemy", "elite"]:
		return {}
	var actions: Array = _snapshot.actions.duplicate(true)
	if actor_kind == "elite":
		actions.append_array(_snapshot.elite_actions.duplicate(true))
		for action: Dictionary in actions:
			for hit: Dictionary in action.hit_schedule:
				hit.damage *= 1.25
	return {
		"id": _snapshot.id, "actor_kind": actor_kind, "runtime_kind": _snapshot.runtime_kind,
		"max_hp": _snapshot.max_hp * (2.0 if actor_kind == "elite" else 1.0), "defense": _snapshot.defense,
		"move_speed": _snapshot.move_speed, "collision_radius_px": _snapshot.collision_radius_px,
		"actions": actions, "mechanisms": _snapshot.mechanisms.duplicate(true),
	}
