class_name UiBossTrack
extends HBoxContainer

const Art := preload("res://scripts/ui/style/ui_artwork.gd")


func render_track(ids: Array, completed: int, current: int) -> void:
	name = "BossTrack"
	add_theme_constant_override("separation", 8)
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for index: int in range(ids.size()):
		var id := str(ids[index])
		var step := VBoxContainer.new()
		step.name = "BossStep_%d" % index
		step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step.add_theme_constant_override("separation", 2)
		add_child(step)
		var portrait := Art.image(Art.actor(id), 32, "BossPortrait")
		portrait.modulate = Color.WHITE if index <= current else Color("677d79")
		step.add_child(portrait)
		var caption := Label.new()
		caption.text = tr("BOSS_%s_NAME" % id.to_upper())
		caption.add_theme_font_size_override("font_size", 10)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.add_theme_color_override("font_color", Color("79baa1") if index < completed else Color("e5bd69") if index == current else Color("abb8ac"))
		step.add_child(caption)
		var progress := ProgressBar.new()
		progress.name = "BossStepProgress"
		progress.show_percentage = false
		progress.custom_minimum_size = Vector2(0, 3)
		progress.value = 100 if index < completed else 0
		step.add_child(progress)
