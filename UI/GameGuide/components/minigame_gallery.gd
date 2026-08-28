extends VBoxContainer
class_name GuideMinigameGallery

## 只负责展示小游戏图鉴并把“重玩”意图向上交给宿主。
## 它不读取存档、不创建小游戏，也不接触对局状态，因此可安全复用于主菜单。

signal replay_requested(task_id: StringName)

const PAGE_SIZE: int = 6
const LOCKED_CARD_BACK: Texture2D = preload("res://arts/任务卡/任务卡（牌背）.png")

var _entries: Array[Dictionary] = []
var _page: int = 0
var _narrow_layout: bool = false


func configure(entries: Array[Dictionary], narrow_layout: bool = false) -> void:
	_entries.clear()
	for entry: Dictionary in entries:
		_entries.append(entry.duplicate())
	_narrow_layout = narrow_layout
	_page = 0
	_rebuild()


func get_first_focusable() -> Control:
	return _find_focusable(self)


func _rebuild(focus_hint: StringName = &"") -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 18)
	var grid := GridContainer.new()
	grid.name = "GalleryGrid"
	grid.columns = 1 if _narrow_layout else 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
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


func _add_entry_card(parent: GridContainer, entry: Dictionary, local_index: int) -> void:
	var unlocked := bool(entry.get("unlocked", false))
	var panel := PanelContainer.new()
	panel.name = "UnlockedTask%d" % local_index if unlocked else "LockedTask%d" % local_index
	panel.custom_minimum_size = Vector2(300, 590)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		FrontendStyle.make_box(
			Color("#F6E4BB") if unlocked else Color("#D9C8A7"),
			FrontendStyle.GOLD if unlocked else FrontendStyle.DISABLED,
			3,
			16,
			Vector4(16, 16, 16, 16)
		)
	)
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	if not unlocked:
		panel.accessibility_name = "未发现小游戏"
		panel.accessibility_description = "未发现"
		content.add_child(_new_thumbnail(LOCKED_CARD_BACK, 490.0))
		var locked_title := _new_label("未发现", 30, FrontendStyle.BROWN_MUTED)
		locked_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(locked_title)
		return

	var texture := entry.get("thumbnail") as Texture2D
	if texture != null:
		content.add_child(_new_thumbnail(texture, 290.0))
	else:
		var placeholder := _new_label("缩略图待替换", 34, FrontendStyle.ORANGE)
		placeholder.custom_minimum_size = Vector2(0, 290)
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		content.add_child(placeholder)
	var heritage_name := String(entry.get("heritage_name", "传承任务"))
	var task_name := String(entry.get("task_name", ""))
	var goal := String(entry.get("goal", "")).strip_edges()
	var operation := String(entry.get("operation", "")).strip_edges()
	panel.accessibility_name = "%s · %s" % [heritage_name, task_name]
	panel.accessibility_description = "目标：%s；操作：%s" % [goal, operation]
	var title_label := _new_label(heritage_name, 31, FrontendStyle.BROWN_DARK)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(title_label)
	if not task_name.is_empty():
		var task_label := _new_label("传承任务 · %s" % task_name, 23, FrontendStyle.ORANGE)
		task_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(task_label)
	if not goal.is_empty():
		content.add_child(_new_detail_label("目标：%s" % goal, FrontendStyle.BROWN_DARK))
	if not operation.is_empty():
		content.add_child(_new_detail_label("操作：%s" % operation, FrontendStyle.BROWN_MUTED))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	var task_id := StringName(entry.get("task_id", &""))
	var replay := _new_button("重玩", Vector2(180, 62))
	replay.name = "ReplayButton%d" % local_index
	replay.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	replay.accessibility_name = "重玩%s" % task_name
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
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _new_button(text_value: String, minimum_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = minimum_size
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
