class_name HubPageLayout
extends RefCounted

const Art := preload("res://scripts/ui/style/ui_artwork.gd")


static func grid(node_name: String, columns: int = 2) -> GridContainer:
	var layout := GridContainer.new()
	layout.name = node_name
	layout.columns = columns
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("h_separation", 12)
	layout.add_theme_constant_override("v_separation", 8)
	return layout


static func section(parent: Control, title: String, texture: Texture2D = null, subtitle: String = "") -> VBoxContainer:
	var section_root := VBoxContainer.new()
	section_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_root.add_theme_constant_override("separation", 4)
	parent.add_child(section_root)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	section_root.add_child(heading)
	if texture != null:
		heading.add_child(Art.image(texture, 32))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	heading.add_child(text)
	text.add_child(label(title, 14))
	if not subtitle.is_empty():
		var secondary := label(subtitle, 11)
		secondary.add_theme_color_override("font_color", Color("abb8ac"))
		text.add_child(secondary)
	var rule := ColorRect.new()
	rule.color = Color("697771")
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section_root.add_child(rule)
	return section_root


static func label(text: String, font_size: int = 12) -> Label:
	var view := Label.new()
	view.text = text
	view.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_theme_font_size_override("font_size", font_size)
	return view


static func relocate_row(button: Button, destination: Control) -> void:
	var row := button.get_parent() as Control
	row.reparent(destination, false)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
