class_name SummonDefinition
extends RefCounted

const Action := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_definition_contract.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const FIELDS: Array[String] = [
	"category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "references",
	"runtime_kind", "parent_definition_id", "max_hp", "hp_fraction", "damage", "damage_multiplier", "move_speed", "collision_radius_px",
	"lifetime_frames", "spawn_warning_frames", "attack_warning_frames", "final_explosion_warning_frames", "reward_eligible", "capabilities", "attack",
]
const CONTRACTS := {
  "mini_wraith": {
    "parent_definition_id": "ruins_wraith",
    "max_hp": 25,
    "hp_fraction": 0,
    "damage": 10,
    "damage_multiplier": 1,
    "move_speed": 80,
    "collision_radius_px": 7,
    "lifetime_frames": 480,
    "attack": {
      "kind": "melee",
      "range_px": 32,
      "active_frames": 6,
      "recovery_frames": 20,
      "cooldown_frames": 120
    }
  },
  "small_void_spore": {
    "parent_definition_id": "void_spore",
    "max_hp": 12,
    "hp_fraction": 0,
    "damage": 6,
    "damage_multiplier": 1,
    "move_speed": 42,
    "collision_radius_px": 6,
    "lifetime_frames": 480,
    "attack": {
      "kind": "melee",
      "range_px": 40,
      "active_frames": 6,
      "recovery_frames": 20,
      "cooldown_frames": 120
    }
  },
  "void_firefly": {
    "parent_definition_id": "forest_caller",
    "max_hp": 20,
    "hp_fraction": 0,
    "damage": 6,
    "damage_multiplier": 1,
    "move_speed": 96,
    "collision_radius_px": 6,
    "lifetime_frames": 900,
    "attack": {
      "kind": "projectile_volley",
      "range_px": 96,
      "active_frames": 6,
      "recovery_frames": 20,
      "cooldown_frames": 120
    }
  },
  "void_beetle": {
    "parent_definition_id": "stone_shell_strider",
    "max_hp": 80,
    "hp_fraction": 0,
    "damage": 18,
    "damage_multiplier": 1,
    "move_speed": 72,
    "collision_radius_px": 10,
    "lifetime_frames": 1200,
    "attack": {
      "kind": "charge",
      "range_px": 48,
      "active_frames": 6,
      "recovery_frames": 20,
      "cooldown_frames": 120
    }
  },
  "hunter_echo": {
    "parent_definition_id": "void_hunter",
    "max_hp": 45,
    "hp_fraction": 0,
    "damage": 7,
    "damage_multiplier": 1,
    "move_speed": 126,
    "collision_radius_px": 8,
    "lifetime_frames": 480,
    "attack": {
      "kind": "melee",
      "range_px": 24,
      "active_frames": 6,
      "recovery_frames": 20,
      "cooldown_frames": 120
    }
  },
  "ranger_echo": {
    "parent_definition_id": "phase_ranger",
    "max_hp": 42,
    "hp_fraction": 0,
    "damage": 11,
    "damage_multiplier": 1,
    "move_speed": 84,
    "collision_radius_px": 8,
    "lifetime_frames": 600,
    "attack": {
      "kind": "projectile_volley",
      "range_px": 144,
      "active_frames": 6,
      "recovery_frames": 20,
      "cooldown_frames": 120
    }
  },
  "timeline_echo": {
    "parent_definition_id": "time_sovereign",
    "max_hp": 200,
    "hp_fraction": 0,
    "damage": 15,
    "damage_multiplier": 1,
    "move_speed": 112,
    "collision_radius_px": 12,
    "lifetime_frames": 1200,
    "attack": {
      "kind": "melee",
      "range_px": 48,
      "active_frames": 6,
      "recovery_frames": 20,
      "cooldown_frames": 120
    }
  },
  "void_sapling": {
    "parent_definition_id": "forest_caller",
    "max_hp": 60,
    "hp_fraction": 0,
    "damage": 15,
    "damage_multiplier": 1,
    "move_speed": 58,
    "collision_radius_px": 9,
    "lifetime_frames": 900,
    "attack": {
      "kind": "melee",
      "range_px": 32,
      "active_frames": 6,
      "recovery_frames": 20,
      "cooldown_frames": 120
    }
  },
  "elite_mirror": {
    "parent_definition_id": "bound_ordinary",
    "max_hp": 1,
    "hp_fraction": 0.2,
    "damage": 0,
    "damage_multiplier": 0.5,
    "move_speed": 64,
    "collision_radius_px": 8,
    "lifetime_frames": 480,
    "attack": {
      "kind": "parent_first_damaging",
      "range_px": 0,
      "active_frames": 6,
      "recovery_frames": 20,
      "cooldown_frames": 120
    }
  }
}

var _snapshot: Dictionary = {}


func configure(source: Dictionary) -> Dictionary:
	_snapshot.clear()
	if not Action.exact_fields(source, FIELDS):
		return Contract.failure("summon", "exact_fields_required")
	var common := Contract.common(source, "summon_definition", Ids.SUMMON_IDS)
	if not common.ok:
		return common
	var result: Dictionary = common.definition
	var expected: Dictionary = CONTRACTS[result.id]
	if typeof(result.runtime_kind) != TYPE_STRING or result.runtime_kind != result.id:
		return Contract.failure("runtime_kind", "identity_mismatch")
	if typeof(result.parent_definition_id) != TYPE_STRING or result.parent_definition_id != expected.parent_definition_id:
		return Contract.failure("parent_definition_id", "identity_mismatch")
	if not source.compatibility is Dictionary or not Action.exact_fields(source.compatibility, ["floor_ids", "actor_kinds"]):
		return Contract.failure("compatibility", "exact_fields_required")
	if source.compatibility.floor_ids != Ids.FLOOR_IDS or source.compatibility.actor_kinds != ["summon"]:
		return Contract.failure("compatibility", "identity_mismatch")
	if typeof(source.reward_eligible) != TYPE_BOOL or source.reward_eligible or not source.capabilities is Array or not source.capabilities.is_empty():
		return Contract.failure("capabilities", "nonrecursive_no_reward_required")
	var numeric_rules: Dictionary = {
		"spawn_warning_frames": [30, 120, true], "attack_warning_frames": [23, 120, true], "final_explosion_warning_frames": [30, 120, true],
	}
	for field: String in ["max_hp", "hp_fraction", "damage", "damage_multiplier", "move_speed", "collision_radius_px", "lifetime_frames"]:
		numeric_rules[field] = [expected[field], expected[field], field == "lifetime_frames"]
	var numbers := Contract.numeric_fields(source, numeric_rules)
	if not numbers.ok:
		return numbers
	result.merge(numbers.value, true)
	if not source.attack is Dictionary or not Action.exact_fields(source.attack, ["kind", "range_px", "active_frames", "recovery_frames", "cooldown_frames"]):
		return Contract.failure("attack", "exact_fields_required")
	if typeof(source.attack.kind) != TYPE_STRING or source.attack.kind != expected.attack.kind:
		return Contract.failure("attack.kind", "identity_mismatch")
	var attack_rules: Dictionary = {}
	for field: String in ["range_px", "active_frames", "recovery_frames", "cooldown_frames"]:
		attack_rules[field] = [expected.attack[field], expected.attack[field], field != "range_px"]
	var attack := Contract.numeric_fields(source.attack, attack_rules)
	if not attack.ok:
		return attack
	result.attack = attack.value
	result.attack.kind = expected.attack.kind
	var expected_references: Array = [] if result.id == "elite_mirror" else [expected.parent_definition_id]
	if result.references != expected_references:
		return Contract.failure("references", "parent_reference_required")
	result.reward_eligible = false
	result.capabilities = []
	_snapshot = result.duplicate(true)
	return {"ok": true, "definition": snapshot(), "context": {}}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)
