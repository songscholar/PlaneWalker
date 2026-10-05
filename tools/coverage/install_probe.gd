extends SceneTree


func _initialize() -> void:
	var configuration := ConfigFile.new()
	if configuration.load("res://project.godot") != OK:
		push_error("Runtime line coverage cannot read its isolated project configuration")
		quit(1)
		return
	if configuration.has_section_key("autoload", "PWLineCoverageProbe"):
		push_error("Runtime line coverage reserved autoload already exists")
		quit(1)
		return
	var existing: Dictionary = {}
	if configuration.has_section("autoload"):
		for key: String in configuration.get_section_keys("autoload"):
			existing[key] = configuration.get_value("autoload", key)
		configuration.erase_section("autoload")
	# Autoloads exit in reverse order; keep the counter alive through their cleanup.
	configuration.set_value("autoload", "PWLineCoverageProbe", "*res://tools/coverage/line_probe.gd")
	for key: String in existing:
		configuration.set_value("autoload", key, existing[key])
	if configuration.save("res://project.godot") != OK:
		push_error("Runtime line coverage cannot save its isolated project configuration")
		quit(1)
		return
	print("PASS: isolated runtime line probe installed")
	quit()
