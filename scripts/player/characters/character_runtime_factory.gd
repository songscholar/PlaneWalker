class_name CharacterRuntimeFactory
extends RefCounted

const CharacterRuntimeScript := preload(
	"res://scripts/player/characters/character_runtime.gd"
)
const TimeGuardianCharacterRuntimeScript := preload(
	"res://scripts/player/characters/time_guardian_character_runtime.gd"
)
const WandererCharacterRuntimeScript := preload(
	"res://scripts/player/characters/wanderer_character_runtime.gd"
)
const SUPPORTED_RUNTIME_KINDS: Array[String] = [
	"wanderer_m1_compat",
	"wanderer",
	"time_guardian",
	"void_walker",
	"primordial_knight",
	"time_lord",
]


static func create(runtime_kind: Variant) -> Variant:
	if typeof(runtime_kind) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return null
	var normalized := str(runtime_kind).strip_edges()
	if not SUPPORTED_RUNTIME_KINDS.has(normalized):
		return null
	if normalized == "wanderer":
		return WandererCharacterRuntimeScript.new()
	if normalized == "time_guardian":
		return TimeGuardianCharacterRuntimeScript.new()
	return CharacterRuntimeScript.new(StringName(normalized))
