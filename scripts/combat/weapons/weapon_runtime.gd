class_name WeaponRuntime
extends RefCounted


func weapon_id() -> StringName:
	return &""


func configure(_owner: Node, _profile: Variant, _modifiers: Variant) -> bool:
	return false


func capabilities() -> PackedStringArray:
	return PackedStringArray()


func plan_intent(_intent: Dictionary, _context: Dictionary) -> Dictionary:
	return {"ok": false, "code": &"UNSUPPORTED_INTENT"}


func commit_action(_plan: Dictionary, _token: int) -> Dictionary:
	return {"ok": false, "code": &"UNSUPPORTED_ACTION"}


func on_phase_enter(_plan: Dictionary, _phase: StringName, _token: int) -> Array[Dictionary]:
	return []


func cancel_action(_token: int, _reason: StringName) -> void:
	pass


func finish_action(_token: int) -> void:
	pass


func apply_modifier(_effect_id: StringName, _value: Variant) -> bool:
	return false


func reset_runtime_state(_reason: StringName) -> void:
	pass


func snapshot() -> Dictionary:
	return {}


func restore_snapshot(_runtime_snapshot: Dictionary) -> bool:
	return false


func presentation_snapshot() -> Dictionary:
	return {}
