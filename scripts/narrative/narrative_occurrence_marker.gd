class_name NarrativeOccurrenceMarker
extends Sprite2D


func configure(heart: bool) -> void:
	var pixels := ["..RR..RR..", ".RRRRRRRR.", "RRRRRRRRRR", "RRRRRRRRRR", ".RRRRRRRR.", "..RRRRRR..", "...RRRR...", "....RR...."] if heart else ["..CCCCCC..", ".CCWWWWCC.", ".CWWGGWWC.", ".CWWWWWWC.", ".CWWGGWWC.", ".CWWWWWWC.", ".CCWWWWCC.", "..CCCCCC.."]
	var colors := {"R": Color("ff7184"), "C": Color("90e4ee"), "W": Color("f5f3e7"), "G": Color("53686c")}
	var bitmap := Image.create(10, 8, false, Image.FORMAT_RGBA8)
	bitmap.fill(Color.TRANSPARENT)
	for y: int in range(pixels.size()):
		for x: int in range(pixels[y].length()):
			var color_id: String = pixels[y].substr(x, 1)
			if colors.has(color_id):
				bitmap.set_pixel(x, y, colors[color_id])
	texture = ImageTexture.create_from_image(bitmap)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2(3, 3)
	z_index = 120
