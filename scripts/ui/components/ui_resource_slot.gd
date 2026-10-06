class_name UiResourceSlot
extends Control

const Art := preload("res://scripts/ui/style/ui_artwork.gd")

var artwork: TextureRect
var counter: Label
var gauge: ProgressBar
var _ready_state := false
var _settings: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(56, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	artwork = Art.image(null, 24, "SlotArtwork")
	add_child(artwork)
	counter = Label.new()
	counter.name = "SlotCounter"
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	counter.add_theme_font_size_override("font_size", 11)
	counter.theme_type_variation = &"CounterLabel"
	counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(counter)
	gauge = ProgressBar.new()
	gauge.name = "SlotGauge"
	gauge.show_percentage = false
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gauge)
	resized.connect(_fit)
	counter.theme_changed.connect(_fit)
	_fit()


func set_artwork(texture: Texture2D) -> void:
	artwork.texture = texture


func render_slot(icon_id: StringName, current: float, maximum: float, ready: bool, status_text: String = "") -> void:
	if not icon_id.is_empty():
		var texture := Art.icon(&"time_abilities", icon_id)
		if texture == null:
			texture = Art.icon(&"weapons", icon_id)
		if texture == null:
			texture = Art.icon(&"items", icon_id)
		set_artwork(texture)
	_ready_state = ready
	counter.text = status_text
	counter.add_theme_color_override("font_color", Color("edf0dc") if ready else Color("e5bd69"))
	gauge.visible = maximum > 0
	gauge.max_value = maxf(1, maximum)
	gauge.value = clampf(current, 0, maximum)
	queue_redraw()
	_fit()


func apply_accessibility_settings(settings: Dictionary) -> void:
	_settings = settings.duplicate(true)
	queue_redraw()
	_fit()


func _fit() -> void:
	if not is_instance_valid(counter):
		return
	var enlarged := counter.get_theme_font_size("font_size") >= 16
	var extent := 16 if enlarged else 24
	artwork.custom_minimum_size = Vector2(extent, extent)
	artwork.position = Vector2(roundf((size.x - extent) / 2), 2)
	artwork.size = Vector2(extent, extent)
	counter.position = Vector2(2, extent + 2)
	counter.size = Vector2(maxf(0, size.x - 4), 44 - extent - 4)
	gauge.position = Vector2(4, 41)
	gauge.size = Vector2(maxf(0, size.x - 8), 2)
	queue_redraw()


func _draw() -> void:
	draw_style_box(get_theme_stylebox("panel", "PanelContainer"), Rect2(Vector2.ZERO, size))
	var accent := Color("79baa1") if _ready_state else Color("e5bd69")
	if bool(_settings.get("high_contrast_danger", false)) and not _ready_state:
		accent = Color("edf0dc")
	draw_rect(Rect2(Vector2(size.x - 7, 3), Vector2(4, 4)), accent)
