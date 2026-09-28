class_name RunPhase
extends RefCounted

enum Value {
	BOOT,
	HUB,
	RUN_PREPARING,
	ROOM_ENTERING,
	COMBAT_ACTIVE,
	ROOM_RESOLVING,
	SELECTION_ACTIVE,
	ROOM_TRANSITION,
	BOSS_ACTIVE,
	VICTORY,
	DEFEAT,
}


static func is_terminal(phase: int) -> bool:
	return phase == Value.VICTORY or phase == Value.DEFEAT
