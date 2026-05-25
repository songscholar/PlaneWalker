extends Node

var current_scene_path: String = ""


func change_scene(scene_path: String) -> Error:
	current_scene_path = scene_path
	return get_tree().change_scene_to_file(scene_path)


func reload_current_scene() -> Error:
	if current_scene_path.is_empty():
		return get_tree().reload_current_scene()
	return change_scene(current_scene_path)
