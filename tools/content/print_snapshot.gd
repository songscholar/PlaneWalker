extends SceneTree

const Registry := preload("res://scripts/content/content_registry.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")


func _initialize() -> void:
	var registry := Registry.new()
	var report = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	if report.has_blocking_errors():
		printerr("Content snapshot refused: invalid Base pack")
		quit(1)
		return
	print(JSON.stringify(Content.snapshot(registry), "", true, true))
	quit()
