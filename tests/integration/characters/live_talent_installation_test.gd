extends Node

const CharacterRuntimeProfileScript := preload(
	"res://scripts/player/characters/character_runtime_profile.gd"
)
const PlayerCharacterRuntimeScript := preload(
	"res://scripts/player/characters/player_character_runtime.gd"
)
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PROFILE_PATH := "res://data/content_packs/base/content/character_runtime_profiles.json"
const TALENT_PATH := "res://data/content_packs/base/content/talents.json"

var _suite
var _definitions: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_load_definitions()
	var profile = CharacterRuntimeProfileScript.from_definition(_profile("time_lord_launch_v1"))
	var runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(runtime.configure(self, profile, []), "live talent fixture configures without selected talents")

	var codex := (_definitions["codex_margin"] as Dictionary).duplicate(true)
	_suite.assert_true(runtime.has_method("install_talent"), "player character runtime exposes live talent installation")
	if not runtime.has_method("install_talent"):
		_suite.finish(get_tree())
		return
	_suite.assert_true(bool(runtime.call("install_talent", codex)), "compatible talent installs live")
	_suite.assert_equal(runtime.selected_talent_ids(), ["codex_margin"], "live installation updates canonical selection")
	_suite.assert_equal(
		int(runtime.presentation_snapshot().get("pair_window_frames", 0)),
		420,
		"live installation updates the active strategy modifier"
	)
	var installed := runtime.snapshot()
	_suite.assert_true(not bool(runtime.call("install_talent", codex)), "duplicate live talent is rejected")
	_suite.assert_equal(runtime.snapshot(), installed, "duplicate rejection is atomic")
	_suite.assert_true(
		not bool(runtime.call("install_talent", (_definitions["deep_debt"] as Dictionary).duplicate(true))),
		"cross-character live talent is rejected"
	)
	_suite.assert_equal(runtime.snapshot(), installed, "cross-character rejection preserves runtime exactly")

	var forged := codex.duplicate(true)
	forged["effects"] = {"talent_unknown_modifier": 999}
	_suite.assert_true(not bool(runtime.call("install_talent", forged)), "invalid effect plan is rejected")
	_suite.assert_equal(runtime.snapshot(), installed, "invalid effect rejection rolls back exactly")
	codex["effects"].clear()
	_suite.assert_equal(runtime.snapshot(), installed, "caller mutation cannot alter installed live talent")

	var restored = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(
			restored.configure(
				self,
				CharacterRuntimeProfileScript.from_definition(_profile("time_lord_launch_v1")),
				["codex_margin"],
				[(_definitions["codex_margin"] as Dictionary).duplicate(true)]
			),
		"restore target configures from the same content definition"
	)
	_suite.assert_true(restored.restore_snapshot(installed), "live talent snapshot restores")
	_suite.assert_equal(restored.snapshot(), installed, "live talent restore is byte-for-byte exact")
	restored.reset_runtime_state(&"room_transition")
	_suite.assert_equal(restored.selected_talent_ids(), ["codex_margin"], "reset preserves installed run talents")

	var player = PlayerScene.instantiate()
	add_child(player)
	await get_tree().process_frame
	_suite.assert_true(player.configure_run(&"talent-live-install"), "Player binds a Replay identity")
	_suite.assert_true(
		player.configure_loadout(player.loadout_runtime.snapshot()),
		"Player rebinds the loadout to the new run generation"
	)
	var player_before: Dictionary = player.character_talent_transaction_snapshot()
	_suite.assert_true(not player_before.is_empty(), "Player exposes an atomic talent transaction snapshot")
	var wanderer_definition := (
		_definitions["tal_eternity_reserve"] as Dictionary
	).duplicate(true)
	_suite.assert_true(
		player.loadout_runtime.install_character_talent(wanderer_definition),
		"Player loadout accepts the compatible definition in isolation"
	)
	_suite.assert_true(
		player.character_runtime.install_talent(wanderer_definition),
		"Player character runtime accepts the compatible definition in isolation"
	)
	_suite.assert_true(
		player.restore_character_talent_transaction_snapshot(player_before),
		"isolated component probes restore before the atomic Player path"
	)
	_suite.assert_true(
		player.install_character_talent(wanderer_definition),
		"Player atomically installs a compatible live talent"
	)
	_suite.assert_equal(
		player.loadout_runtime.character_talent_ids(),
		[&"tal_eternity_reserve"],
		"Player loadout identity advances with the live runtime"
	)
	_suite.assert_equal(
		player.character_runtime.selected_talent_ids(),
		["tal_eternity_reserve"],
		"Player character runtime advances with the loadout identity"
	)
	_suite.assert_equal(
		player.full_player_replay_identity().get("character_talent_ids", []),
		["tal_eternity_reserve"],
		"Replay identity seals the installed live talent"
	)
	var player_installed: Dictionary = player.character_talent_transaction_snapshot()
	_suite.assert_true(
		player.restore_character_talent_transaction_snapshot(player_before),
		"Player rolls the full talent transaction back atomically"
	)
	_suite.assert_equal(
		player.character_runtime.selected_talent_ids(),
		[],
		"rollback restores the pre-install runtime identity"
	)
	_suite.assert_true(
		player.restore_character_talent_transaction_snapshot(player_installed),
		"Player can restore the installed talent checkpoint"
	)
	_suite.assert_equal(
		player.character_talent_transaction_snapshot(),
		player_installed,
		"installed talent checkpoint restores byte-for-byte"
	)
	player.queue_free()
	await get_tree().process_frame
	_suite.finish(get_tree())


func _load_definitions() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TALENT_PATH))
	_suite.assert_true(parsed is Array, "talent catalog parses")
	if not parsed is Array:
		return
	for value: Variant in parsed:
		if value is Dictionary:
			_definitions[str((value as Dictionary).get("id", ""))] = (value as Dictionary).duplicate(true)


func _profile(profile_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not parsed is Array:
		return {}
	for value: Variant in parsed:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == profile_id:
			return (value as Dictionary).duplicate(true)
	return {}
