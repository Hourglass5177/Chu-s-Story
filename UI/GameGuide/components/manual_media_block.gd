extends VBoxContainer
class_name ManualMediaBlock

signal media_preview_requested(texture: Texture2D, alt_text: String)

## Responsive renderer for one or more guide media declarations.  The parent
## resolves static/dynamic providers; this component only owns layout.

const DEFAULT_PORTRAIT_WIDTH := 520.0
const MAX_PORTRAIT_WIDTH := 680.0
const DEFAULT_GALLERY_ITEM_WIDTH := 330.0
const ITEM_GAP := 18.0

var _records: Array[Dictionary] = []
var _narrow_layout: bool = false
var _groups: Array[Dictionary] = []


func setup(records: Array[Dictionary], narrow_layout: bool) -> void:
	_records = records.duplicate(true)
	_narrow_layout = narrow_layout
	add_theme_constant_override("separation", 18)
	resized.connect(_relayout)
	_build()
	call_deferred(&"_relayout")


func _build() -> void:
	for child: Node in get_children():
		child.queue_free()
	_groups.clear()
	for record: Dictionary in _records:
		var layout := _normalize_layout(String(record.get("layout", "full")))
		# Godot 4.6 warns when FIT_WIDTH_PROPORTIONAL TextureRects participate in
		# a multi-line FlowContainer. A centred GridContainer gives us the same
		# responsive columns without that engine limitation.
		var center := CenterContainer.new()
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(center)
		var grid := GridContainer.new()
		grid.columns = 1
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		grid.add_theme_constant_override("h_separation", int(ITEM_GAP))
		grid.add_theme_constant_override("v_separation", int(ITEM_GAP))
		center.add_child(grid)
		var group_data: Dictionary = {
			"grid": grid,
			"layout": layout,
			"target_width_ratio": clampf(float(record.get("target_width_ratio", 1.0)), 0.2, 1.0),
			"min_item_width": maxf(float(record.get("min_item_width", 0.0)), 0.0),
			"max_columns": maxi(int(record.get("max_columns", 0)), 0),
			"items": [],
		}
		for item: Dictionary in record.get("items", []):
			var texture := item.get("texture") as Texture2D
			if texture == null:
				continue
			var item_box := VBoxContainer.new()
			item_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			item_box.add_theme_constant_override("separation", 8)
			grid.add_child(item_box)
			var image_holder := PanelContainer.new()
			image_holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			item_box.add_child(image_holder)
			var image := TextureRect.new()
			image.name = "ManualSectionMedia"
			image.texture = texture
			# The holder owns the responsive dimensions. Ignoring the texture's
			# native minimum prevents a wide screenshot from forcing the centred
			# grid beyond the article bounds.
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if String(record.get("fit", "contain")) != "cover" else TextureRect.STRETCH_KEEP_ASPECT_COVERED
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			image.set_meta(&"guide_media_path", String(item.get("path", "")))
			image.set_meta(&"guide_media_layout", layout)
			image.set_meta(&"guide_media_kind", StringName(item.get("kind", "")))
			image.set_meta(&"guide_media_id", StringName(item.get("id", record.get("id", ""))))
			var alt := String(item.get("alt", record.get("alt", ""))).strip_edges()
			image_holder.add_child(image)
			image_holder.add_child(_make_preview_button(texture, alt if not alt.is_empty() else "规则配图"))
			var caption := String(item.get("caption", "")).strip_edges()
			if not caption.is_empty():
				var caption_label := Label.new()
				caption_label.text = caption
				caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				caption_label.add_theme_font_size_override("font_size", 27)
				caption_label.add_theme_color_override("font_color", FrontendStyle.BROWN_MUTED)
				item_box.add_child(caption_label)
			(group_data["items"] as Array).append({
				"box": item_box,
				"holder": image_holder,
				"image": image,
			})
		_groups.append(group_data)


func _make_preview_button(texture: Texture2D, alt_text: String) -> Button:
	var button := Button.new()
	button.name = "ManualMediaPreviewButton"
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(96, 54)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.accessibility_name = "查看大图"
	button.accessibility_description = alt_text
	button.add_theme_stylebox_override("normal", _preview_style(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	button.add_theme_stylebox_override("hover", _preview_style(Color(FrontendStyle.GOLD, 0.08), Color(FrontendStyle.GOLD, 0.9), 3))
	button.add_theme_stylebox_override("focus", _preview_style(Color(FrontendStyle.GOLD, 0.05), Color("#FFF1C7"), 5))
	button.add_theme_stylebox_override("pressed", _preview_style(Color(FrontendStyle.ORANGE, 0.12), Color(FrontendStyle.GOLD), 4))
	button.pressed.connect(func() -> void: media_preview_requested.emit(texture, alt_text))
	return button


func _preview_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(12)
	return style


func set_narrow_layout(narrow_layout: bool) -> void:
	if _narrow_layout == narrow_layout:
		return
	_narrow_layout = narrow_layout
	_relayout()


func _relayout() -> void:
	if not is_inside_tree():
		return
	var available := maxf(size.x, 360.0)
	for group: Dictionary in _groups:
		var layout := String(group.get("layout", "full"))
		var items: Array = group.get("items", []) as Array
		if items.is_empty():
			continue
		var grid := group.get("grid") as GridContainer
		var target_ratio := float(group.get("target_width_ratio", 1.0))
		var declared_min := float(group.get("min_item_width", 0.0))
		var max_columns := int(group.get("max_columns", 0))
		var item_width := available * target_ratio
		var columns := 1
		match layout:
			"portrait":
				var portrait_ratio := maxf(target_ratio, 0.55 if _narrow_layout else 0.38)
				item_width = clampf(available * portrait_ratio, maxf(declared_min, 420.0), minf(available, MAX_PORTRAIT_WIDTH))
			"pair":
				columns = 1 if _narrow_layout else mini(items.size(), 2)
				item_width = available if _narrow_layout else (available - ITEM_GAP) * 0.5
			"sequence":
				columns = 1 if _narrow_layout else mini(items.size(), 3)
				item_width = available if _narrow_layout else maxf(declared_min, (available - ITEM_GAP * minf(items.size() - 1, 2)) / minf(items.size(), 3))
			"gallery":
				var desired := maxf(declared_min, DEFAULT_GALLERY_ITEM_WIDTH)
				columns = 1 if _narrow_layout else maxi(1, floori((available + ITEM_GAP) / (desired + ITEM_GAP)))
				if max_columns > 0:
					columns = mini(columns, max_columns)
				item_width = (available - ITEM_GAP * (columns - 1)) / columns
			_:
				item_width = available * target_ratio
		if grid != null:
			grid.columns = maxi(columns, 1)
		item_width = clampf(item_width, minf(maxf(declared_min, 1.0), available), available)
		for item_data: Dictionary in items:
			var item_box := item_data.get("box") as Control
			var image_holder := item_data.get("holder") as Control
			var image := item_data.get("image") as TextureRect
			if item_box == null:
				continue
			item_box.custom_minimum_size.x = item_width
			item_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			if image_holder != null and image != null and image.texture != null:
				var texture_size := image.texture.get_size()
				var proportional_height := item_width
				if texture_size.x > 0.0:
					proportional_height = item_width * texture_size.y / texture_size.x
				# 主图应按原始比例真正铺满正文宽度。近方形实机截图如果沿用画廊卡片的
				# 820px 高度上限，会只在一个很宽的空槽中央显示一小块，既浪费空间也
				# 看不清界面信息；画廊/对照图仍保留原上限。
				var maximum_height := 1120.0 if layout == "full" else 820.0
				image_holder.custom_minimum_size.y = clampf(
					proportional_height,
					320.0 if _narrow_layout else 380.0,
					maximum_height
				)


func _normalize_layout(value: String) -> String:
	match value.to_lower():
		"wide":
			return "full"
		"split":
			return "pair"
		"stack":
			return "sequence"
		"grid":
			return "gallery"
		"full", "pair", "sequence", "gallery", "portrait":
			return value.to_lower()
		_:
			return "full"
