extends SceneTree


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		quit(2)
		return
	var output := arguments[0]
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(3)
		return
	var license_file := FileAccess.open(output.path_join("GODOT-LICENSE.txt"), FileAccess.WRITE)
	if license_file == null:
		quit(4)
		return
	license_file.store_string(Engine.get_license_text())
	license_file.close()
	var copyright_file := FileAccess.open(output.path_join("THIRD-PARTY-LICENSES.json"), FileAccess.WRITE)
	if copyright_file == null:
		quit(4)
		return
	copyright_file.store_string(JSON.stringify({
		"version": Engine.get_version_info(),
		"copyright": Engine.get_copyright_info(),
		"licenses": Engine.get_license_info(),
	}, "\t", true) + "\n")
	copyright_file.close()
	quit(0)
