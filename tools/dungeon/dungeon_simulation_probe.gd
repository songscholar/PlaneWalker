extends Node

const RunnerScript := preload("res://tools/dungeon/dungeon_simulation_runner.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path := OS.get_environment("PLANEWALKER_DUNGEON_OUTPUT")
	if output_path.is_empty():
		push_error("Dungeon probe requires PLANEWALKER_DUNGEON_OUTPUT")
		get_tree().quit(2)
		return
	var runs: Array = []
	for seed_value: int in range(20261001, 20261031):
		var runner = RunnerScript.new()
		var player: Node = PlayerScene.instantiate()
		player.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(player)
		player.set_physics_process(false)
		player.get_node("TimeManager").set_process(false)
		player.get_node("RewindRecorder").set_process(false)
		var initialized: Dictionary = runner.initialize(runner.launch_config(seed_value), player)
		var player_configured: bool = bool(initialized.get("ok", false)) and player.configure_loadout(runner.player_config())
		if not player_configured:
			push_error("Dungeon probe cannot configure seed %d: initialization=%s player_configured=%s" % [seed_value, initialized, player_configured])
			get_tree().quit(3)
			return
		runs.append(await runner.run_five_floors())
		player.queue_free()
		await get_tree().process_frame
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Dungeon probe cannot write output")
		get_tree().quit(4)
		return
	file.store_string(JSON.stringify({"probe_version": "1.0.0", "runs": runs}, "  ", true, true) + "\n")
	file.close()
	get_tree().quit(0)
