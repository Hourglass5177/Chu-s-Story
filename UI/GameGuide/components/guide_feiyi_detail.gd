extends VBoxContainer
class_name GuideFeiyiDetail

signal media_preview_requested(texture: Texture2D, alt_text: String)

## Responsive guide rendering of the same content shown by the collected-feiyi
## popup.  The guide owns navigation and pause state; this node only presents
## the already formatted fields.


func setup(content: Dictionary, narrow_layout: bool) -> void:
	name = "FeiyiCollectedDetail"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 22)

	var heading := Label.new()
	heading.name = "FeiyiDetailHeading"
	heading.text = String(content.get("heading", ""))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 44 if narrow_layout else 50)
	heading.add_theme_color_override("font_color", FrontendStyle.BROWN_DARK)
	add_child(heading)

	var frame := PanelContainer.new()
	frame.name = "FeiyiDetailFrame"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override(
		"panel",
		FrontendStyle.make_box(
			Color("#F6E4BB"),
			Color(FrontendStyle.GOLD, 0.78),
			3,
			18,
			Vector4(26, 24, 26, 24)
		)
	)
	add_child(frame)

	var body: BoxContainer = VBoxContainer.new() if narrow_layout else HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 28 if narrow_layout else 34)
	frame.add_child(body)

	var texture := content.get("texture") as Texture2D
	if texture != null:
		body.add_child(_make_card(texture, String(content.get("name", "非遗牌")), narrow_layout))

	var fields := VBoxContainer.new()
	fields.name = "FeiyiDetailFields"
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 18)
	body.add_child(fields)

	_add_field(fields, "FeiyiName", String(content.get("name", "")), 38 if narrow_layout else 42, FrontendStyle.BROWN_DARK)
	_add_field(fields, "FeiyiCategory", String(content.get("category", "")), 32 if narrow_layout else 35, FrontendStyle.BROWN)
	_add_field(fields, "FeiyiScore", String(content.get("score", "")), 32 if narrow_layout else 35, FrontendStyle.ORANGE)
	fields.add_child(HSeparator.new())
	_add_field(fields, "FeiyiDescription", String(content.get("description", "")), 29 if narrow_layout else 32, FrontendStyle.BROWN)
	_add_field(fields, "FeiyiEffect", String(content.get("effect", "")), 29 if narrow_layout else 32, FrontendStyle.BROWN_DARK)


func _make_card(texture: Texture2D, alt_text: String, narrow_layout: bool) -> Control:
	var center := CenterContainer.new()
	center.name = "FeiyiCardCenter"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow_layout else Control.SIZE_SHRINK_CENTER
	center.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var holder := PanelContainer.new()
	holder.name = "FeiyiCardHolder"
	holder.custom_minimum_size = Vector2(460, 660) if narrow_layout else Vector2(480, 700)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.add_theme_stylebox_override(
		"panel",
		FrontendStyle.make_box(Color("#D7C4A1"), Color(FrontendStyle.GOLD, 0.68), 2, 13, Vector4(10, 10, 10, 10))
	)
	center.add_child(holder)

	var image := TextureRect.new()
	image.name = "FeiyiCollectedCardImage"
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.set_meta(&"guide_media_path", texture.resource_path)
	image.set_meta(&"guide_media_layout", "portrait")
	holder.add_child(image)

	var preview := Button.new()
	preview.name = "ManualMediaPreviewButton"
	preview.flat = true
	preview.focus_mode = Control.FOCUS_ALL
	preview.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	preview.accessibility_name = "查看大图"
	preview.accessibility_description = alt_text
	preview.add_theme_stylebox_override("normal", _preview_style(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	preview.add_theme_stylebox_override("hover", _preview_style(Color(FrontendStyle.GOLD, 0.08), Color(FrontendStyle.GOLD, 0.90), 3))
	preview.add_theme_stylebox_override("focus", _preview_style(Color(FrontendStyle.GOLD, 0.05), Color("#FFF1C7"), 5))
	preview.add_theme_stylebox_override("pressed", _preview_style(Color(FrontendStyle.ORANGE, 0.12), FrontendStyle.GOLD, 4))
	preview.pressed.connect(func() -> void: media_preview_requested.emit(texture, alt_text))
	holder.add_child(preview)
	return center


func _add_field(parent: Control, node_name: String, value: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.name = node_name
	label.text = value
	label.custom_minimum_size.x = 0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _preview_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(12)
	return style
