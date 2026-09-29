class_name AccessibilityRuntime
extends Node

const FONT_SIZE_KEYS: Array[StringName] = [
	&"font_size",
	&"normal_font_size",
	&"bold_font_size",
	&"italics_font_size",
	&"bold_italics_font_size",
	&"mono_font_size",
]
const FONT_META_PREFIX := "accessibility_base_font_"

var _settings: Dictionary = {}
var _roots: Array[WeakRef] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_settings()
	if not GameState.setting_changed.is_connected(_on_setting_changed):
		GameState.setting_changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	if GameState.setting_changed.is_connected(_on_setting_changed):
		GameState.setting_changed.disconnect(_on_setting_changed)


func apply_to_tree(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	_remember_root(root)
	_apply_node(root)


func settings_snapshot() -> Dictionary:
	if _settings.is_empty():
		_refresh_settings()
	return _settings.duplicate(true)


func damage_received_multiplier() -> float:
	return float(settings_snapshot().get("damage_received_multiplier", 1.0))


func enemy_telegraph_scale() -> float:
	return float(settings_snapshot().get("enemy_telegraph_scale", 1.0))


func _on_setting_changed(_setting_id: StringName, _value: Variant) -> void:
	_refresh_settings()
	_reapply_roots()


func _refresh_settings() -> void:
	_settings = GameState.normalized_settings().duplicate(true)
	_apply_audio_settings()


func _apply_audio_settings() -> void:
	_set_bus_volume(&"Master", float(_settings.get("master_volume", 0.85)))
	_set_bus_volume(&"Music", float(_settings.get("music_volume", 0.80)))
	_set_bus_volume(&"SFX", float(_settings.get("sfx_volume", 0.90)))
	_set_bus_volume(&"Dialogue", float(_settings.get("dialogue_volume", 0.90)))
	var master_index := AudioServer.get_bus_index(&"Master")
	if master_index >= 0:
		AudioServer.set_bus_mute(master_index, bool(_settings.get("master_muted", false)))


func _set_bus_volume(bus_name: StringName, linear_value: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	AudioServer.set_bus_volume_db(
		bus_index,
		linear_to_db(clampf(linear_value, 0.001, 1.0))
	)


func _remember_root(root: Node) -> void:
	var retained: Array[WeakRef] = []
	for weak_root: WeakRef in _roots:
		var existing: Variant = weak_root.get_ref()
		if existing == null or not is_instance_valid(existing):
			continue
		if existing == root:
			return
		retained.append(weak_root)
	retained.append(weakref(root))
	_roots = retained


func _reapply_roots() -> void:
	var retained: Array[WeakRef] = []
	for weak_root: WeakRef in _roots:
		var root: Variant = weak_root.get_ref()
		if root == null or not is_instance_valid(root):
			continue
		retained.append(weak_root)
		_apply_node(root as Node)
	_roots = retained


func _apply_node(node: Node) -> void:
	if node is Control:
		_apply_control_text_scale(node as Control)
	if node.has_method("apply_accessibility_settings"):
		node.call("apply_accessibility_settings", _settings.duplicate(true))
	elif node.has_method("set_danger_accessibility"):
		node.call("set_danger_accessibility", bool(_settings.get("high_contrast_danger", false)))
	if node.has_method("set_accessibility_options"):
		node.call(
			"set_accessibility_options",
			bool(_settings.get("high_contrast_danger", false)),
			float(_settings.get("enemy_telegraph_scale", 1.0))
		)
	for child: Node in node.get_children():
		_apply_node(child)


func _apply_control_text_scale(control: Control) -> void:
	var text_scale := float(_settings.get("text_scale", 1.0))
	for font_size_key: StringName in FONT_SIZE_KEYS:
		var meta_key := FONT_META_PREFIX + str(font_size_key)
		if not control.has_meta(meta_key):
			if font_size_key != &"font_size" and not control.has_theme_font_size_override(font_size_key):
				continue
			control.set_meta(meta_key, control.get_theme_font_size(font_size_key))
		var base_size := int(control.get_meta(meta_key, 0))
		if base_size <= 0:
			continue
		control.add_theme_font_size_override(font_size_key, maxi(1, roundi(base_size * text_scale)))
