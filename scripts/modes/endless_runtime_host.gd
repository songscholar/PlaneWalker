extends "res://scripts/application/run_runtime_host.gd"

const EndlessDriver := preload("res://scripts/modes/endless_encounter_driver.gd")
const EndlessReplay := preload("res://scripts/replay/replay_recorder.gd")
var cycle_index := 0


func _configure_native_encounter_runner(runner: Node, facade: RefCounted) -> bool:
	var driver: Node = runner.get("_native_launch_driver")
	if driver == null:
		driver = EndlessDriver.new()
		driver.name = "NativeLaunchEncounterDriver"
		runner.add_child(driver)
		runner.set("_native_launch_driver", driver)
	if not driver is EndlessDriver:
		return false
	driver.cycle_index = cycle_index
	return super._configure_native_encounter_runner(runner, facade)


func install_carry(build_codec: String, player_codec: String) -> bool:
	if build_codec.is_empty() and player_codec.is_empty():
		return true
	var build := EndlessReplay.decode_replay_json(build_codec)
	var player := EndlessReplay.decode_replay_json(player_codec)
	if not build.ok or not player.ok or _facade == null or _player == null:
		return false
	var domain: RefCounted = _facade.native_run_state()
	var before_build: Dictionary = domain.reward_replay_build_snapshot()
	var before_player: Dictionary = _player.reward_effect_snapshot()
	if domain.restore_reward_replay_build_snapshot(build.replay) and _player.restore_reward_effect_snapshot(player.replay, false) and domain.observe_player_health(float(_player.health.current_hp), float(_player.health.max_hp)):
		return true
	domain.restore_reward_replay_build_snapshot(before_build)
	_player.restore_reward_effect_snapshot(before_player, false)
	return false
