extends VBoxContainer
class_name GuideMinigameGallery

## 只负责展示小游戏图鉴并把“重玩”意图向上交给宿主。
## 它不读取存档、不创建小游戏，也不接触对局状态，因此可安全复用于主菜单。

signal replay_requested(task_id: StringName)
signal avatar_selected(avatar_id: StringName)

const PAGE_SIZE: int = 6
const LOCKED_CARD_BACK: Texture2D = preload("res://arts/任务卡/任务卡（牌背）.png")

var _entries: Array[Dictionary] = []
var _page: int = 0
var _narrow_layout: bool = false
var _avatar_id: StringName = HeritageAvatarCatalog.DEFAULT_AVATAR_ID
var _avatars: Array[Dictionary] = []
var _avatar_buttons: Dictionary[StringName, Button] = {}
var _pixel_font: Font
var _pixel_aux: Font
var _last_physical_scale: float = 0.0


func _physical_scale() -> float:
	var value := (get_viewport().get_stretch_transform() * get_global_transform_with_canvas()).get_scale().abs()
	return maxf(0.1,minf(value.x,value.y))


func _px(value: float) -> float:
	return value / _physical_scale()


func _process(_delta: float) -> void:
	if not is_visible_in_tree(): return
	if _entries.is_empty() or is_equal_approx(_last_physical_scale,_physical_scale()): return
	var previous_focus := get_viewport().gui_get_focus_owner()
	var focus_name := String(previous_focus.name) if is_instance_valid(previous_focus) and is_ancestor_of(previous_focus) else ""
	_rebuild()
	if not focus_name.is_empty():
		var next := find_child(focus_name,true,false) as Control
		if next != null: next.grab_focus.call_deferred()


func configure(
		entries: Array[Dictionary],
		narrow_layout: bool = false,
		avatar_id: StringName = HeritageAvatarCatalog.DEFAULT_AVATAR_ID,
		avatars: Array[Dictionary] = []
) -> void:
	_entries.clear()
	for entry: Dictionary in entries:
		_entries.append(entry.duplicate())
	_narrow_layout = narrow_layout
	_avatar_id = HeritageAvatarCatalog.normalize(avatar_id)
	_avatars.clear()
	for avatar: Dictionary in avatars:
		_avatars.append(avatar.duplicate())
	_page = 0
	_rebuild()


func get_first_focusable() -> Control:
	return _find_focusable(self)


func _rebuild(focus_hint: StringName = &"") -> void:
	_last_physical_scale = _physical_scale()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", ceili(_px(18)))
	_add_avatar_selector()
	var grid := GridContainer.new()
	grid.name = "GalleryGrid"
	grid.columns = 1 if _narrow_layout else 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", ceili(_px(16)))
	grid.add_theme_constant_override("v_separation", ceili(_px(16)))
	add_child(grid)

	var page_count := maxi(ceili(float(_entries.size()) / PAGE_SIZE), 1)
	_page = clampi(_page, 0, page_count - 1)
	var start := _page * PAGE_SIZE
	var finish := mini(start + PAGE_SIZE, _entries.size())
	for index: int in range(start, finish):
		_add_entry_card(grid, _entries[index], index - start)
	if _entries.is_empty():
		var empty := _new_label("暂无小游戏", 30, FrontendStyle.BROWN_MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(empty)

	if page_count > 1:
		var footer := HBoxContainer.new()
		footer.name = "GalleryPager"
		footer.alignment = BoxContainer.ALIGNMENT_CENTER
		footer.add_theme_constant_override("separation", 16)
		add_child(footer)
		var previous := _new_button("上一页", Vector2(180, 62))
		previous.disabled = _page <= 0
		previous.pressed.connect(func() -> void:
			_page -= 1
			_rebuild(&"previous")
		)
		footer.add_child(previous)
		var progress := _new_label("%d / %d" % [_page + 1, page_count], 27, FrontendStyle.BROWN_MUTED)
		progress.custom_minimum_size = Vector2(110, 62)
		progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		footer.add_child(progress)
		var next := _new_button("下一页", Vector2(180, 62))
		next.disabled = _page >= page_count - 1
		next.pressed.connect(func() -> void:
			_page += 1
			_rebuild(&"next")
		)
		footer.add_child(next)
		# 键盘/手柄翻页时，旧按钮会随页面重建而释放。立即把焦点交给同侧
		# 按钮；鼠标路径随后仍会由 DigitalGameGuide 的延迟清焦点逻辑收走。
		if not focus_hint.is_empty():
			var focus_target := next if focus_hint == &"next" and not next.disabled else previous
			if focus_target.disabled:
				focus_target = next
			if not focus_target.disabled:
				focus_target.grab_focus()


func get_selected_avatar_id() -> StringName:
	return _avatar_id


func _add_avatar_selector() -> void:
	_avatar_buttons.clear()
	if _avatars.is_empty():
		return
	var title := _new_label("选择练习博主", 34, HeritageTelevisionStyle.V2_INK)
	add_child(title)
	var choices := GridContainer.new()
	choices.name = "PracticeAvatarSelector"
	choices.columns = 3 if _narrow_layout else 6
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("h_separation", 12)
	choices.add_theme_constant_override("v_separation", 12)
	add_child(choices)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for avatar: Dictionary in _avatars:
		var avatar_id := StringName(avatar.get("avatar_id", &""))
		if not HeritageAvatarCatalog.is_known(avatar_id):
			continue
		var button := _new_button(HeritageAvatarCatalog.display_name(avatar_id), Vector2(150, 192))
		button.name = "Avatar_%s" % avatar_id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", ceili(_px(20)))
		button.icon = _portrait_headshot(avatar.get("portrait") as Texture2D)
		button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", ceili(_px(88)))
		button.custom_minimum_size.y = _px(130)
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = avatar_id == _avatar_id
		button.accessibility_name = "选择%s练习" % HeritageAvatarCatalog.display_name(avatar_id)
		button.pressed.connect(_on_avatar_pressed.bind(avatar_id))
		_avatar_buttons[avatar_id] = button
		choices.add_child(button)


func _portrait_headshot(source: Texture2D) -> Texture2D:
	if source == null: return null
	# Retain the original full-resolution texture. Frame its head and shoulders
	# for selection instead of shrinking the whole body into a tiny button.
	var portrait := AtlasTexture.new()
	portrait.atlas = source
	var dimensions := source.get_size()
	portrait.region = Rect2(0, 0, dimensions.x, minf(dimensions.y, dimensions.x * 1.05))
	portrait.filter_clip = true
	return portrait


func _on_avatar_pressed(avatar_id: StringName) -> void:
	_avatar_id = avatar_id
	avatar_selected.emit(avatar_id)


func _add_entry_card(parent: GridContainer, entry: Dictionary, local_index: int) -> void:
	var unlocked := bool(entry.get("unlocked", false))
	var panel := PanelContainer.new()
	panel.name = "UnlockedTask%d" % local_index if unlocked else "LockedTask%d" % local_index
	panel.custom_minimum_size = Vector2(300, _px(300))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		HeritageTelevisionStyle.pixel_box("panel",_px(12),1.0 / _physical_scale())
	)
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", ceili(_px(8)))
	panel.add_child(content)
	if not unlocked:
		panel.accessibility_name = "未发现小游戏"
		panel.accessibility_description = "未发现"
		content.add_child(_new_thumbnail(LOCKED_CARD_BACK, _px(220)))
		var locked_title := _new_label("未发现", 30, FrontendStyle.BROWN_MUTED)
		locked_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(locked_title)
		return

	var texture := entry.get("thumbnail") as Texture2D
	if texture != null:
		content.add_child(_new_thumbnail(texture, _px(160)))
	else:
		var placeholder := _new_label("缩略图待替换", 34, FrontendStyle.ORANGE)
		placeholder.custom_minimum_size = Vector2(0, _px(160))
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		content.add_child(placeholder)
	var heritage_name := String(entry.get("heritage_name", "传承任务"))
	var goal := String(entry.get("goal", "")).strip_edges()
	var operation := String(entry.get("operation", "")).strip_edges()
	panel.accessibility_name = heritage_name
	panel.accessibility_description = "目标：%s；操作：%s" % [goal, operation]
	var card_title := heritage_name
	var title_label := _new_label(card_title, 31, FrontendStyle.BROWN_DARK)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(title_label)
	# Full goal and controls live on the preparation screen. Keeping them in
	# accessibility text avoids making six card fronts into tiny manuals.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	var task_id := StringName(entry.get("task_id", &""))
	var replay := _new_button("开始练习", Vector2(180, 62))
	replay.name = "ReplayButton%d" % local_index
	replay.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	replay.accessibility_name = "重玩%s" % heritage_name
	replay.accessibility_description = "在练习模式中重玩%s的传承任务" % heritage_name
	replay.pressed.connect(func() -> void: replay_requested.emit(task_id))
	content.add_child(replay)


func _new_thumbnail(texture: Texture2D, minimum_height: float) -> TextureRect:
	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(0, minimum_height)
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image


func _new_detail_label(text_value: String, color: Color) -> Label:
	var label := _new_label(text_value, 23, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 3
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _new_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	if _pixel_font == null: _pixel_font = HeritageTelevisionStyle.pixel_font()
	if _pixel_aux == null: _pixel_aux = HeritageTelevisionStyle.pixel_font(true)
	label.add_theme_font_override("font",_pixel_aux if font_size < 28 else _pixel_font)
	label.add_theme_font_size_override("font_size", ceili(_px(20 if font_size < 28 else 24)))
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.add_theme_color_override("font_color", color)
	return label


func _new_button(text_value: String, minimum_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(minimum_size.x,maxf(minimum_size.y,_px(48)))
	if _pixel_font == null: _pixel_font = HeritageTelevisionStyle.pixel_font()
	button.add_theme_font_override("font",_pixel_font)
	button.add_theme_font_size_override("font_size",ceili(_px(24)))
	HeritageTelevisionStyle.pixel_button(button,_px(8),1.0 / _physical_scale())
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _find_focusable(node: Node) -> Control:
	for child: Node in node.get_children():
		if child is Control:
			var control := child as Control
			if control is BaseButton:
				var button := control as BaseButton
				if button.is_visible_in_tree() and not button.disabled and button.focus_mode == Control.FOCUS_ALL:
					return button
			elif control.is_visible_in_tree() and control.focus_mode == Control.FOCUS_ALL:
				return control
		var nested := _find_focusable(child)
		if nested != null:
			return nested
	return null
