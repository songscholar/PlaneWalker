class_name HubCosmeticsPanel
extends VBoxContainer

var _buttons: Array[Button] = []


func configure(rows: Array, operation_callback: Callable, activation_callback: Callable, epoch: int) -> bool:
	if not operation_callback.is_valid() or not activation_callback.is_valid() or rows.size() != 15:
		return false
	name = "CosmeticCollection"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = tr("UI_COSMETIC_COLLECTION")
	title.add_theme_font_size_override("font_size", 12)
	add_child(title)
	for row: Dictionary in rows:
		var line := HBoxContainer.new()
		line.name = "Appearance_" + str(row.id).replace(".", "_")
		line.custom_minimum_size = Vector2(0, 52)
		line.add_theme_constant_override("separation", 6)
		add_child(line)
		var atlas := AtlasTexture.new()
		atlas.atlas = load(str(row.atlas_path)) as Texture2D
		atlas.region = Rect2(0, 0, 48, 48)
		if atlas.atlas == null:
			return false
		var preview := TextureRect.new()
		preview.name = "RasterPreview"
		preview.texture = atlas
		preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		preview.custom_minimum_size = Vector2(48, 48)
		preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(preview)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		for field: String in ["name_key", "description_key"]:
			var label := Label.new()
			label.text = tr(str(row[field]))
			label.custom_minimum_size = Vector2(64, 0)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override("font_size", 11 if field == "name_key" else 10)
			text.add_child(label)
		var button := Button.new()
		button.name = "CosmeticAction_" + str(row.id).replace(".", "_")
		button.text = tr("UI_COSMETIC_EQUIPPED" if row.equipped else "UI_COSMETIC_EQUIP" if row.owned else "UI_COSMETIC_CLAIM")
		button.custom_minimum_size = Vector2(58, 26)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.disabled = not row.available
		button.tooltip_text = tr(str(row.reason_key)) if button.disabled else ""
		button.add_theme_font_size_override("font_size", 11)
		button.set_meta("action_id", "cosmetic:" + str(row.id))
		button.set_meta("available", row.available)
		button.pressed.connect(activation_callback.bind(button, operation_callback.bind(row.operation, {"cosmetic_id": row.id}), epoch))
		line.add_child(button)
		_buttons.append(button)
	return true


func action_buttons() -> Array[Button]:
	return _buttons.duplicate()
