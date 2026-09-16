class_name MainHUDLayout
extends Node

## The delivered HUD composition: portrait / map / collection, one bottom action row.
var hud: HUD
var _player_name: Label
var _phase_track: Button
var _phase_panels: Array[PanelContainer] = []
var _phase_names: Array[Label] = []
var _log_content: VBoxContainer
var _log_scroll: ScrollContainer
const PHASE_NAMES := ["准备", "掷骰", "移动", "行动", "结束"]

func _ready() -> void:
	hud = get_parent() as HUD
	hud.default_font = MainUI.FONT
	for key in ["玩家信息", "回合信息", "手牌信息", "操作区域", "积分区域"]:
		MainUI.apply(hud.get_node(key))
	for key in ["TextureRect", "玩家信息/玩家信息模块背景", "玩家信息/玩家信息背景2", "玩家信息/Left", "积分区域/Right", "积分区域/积分区域背景", "手牌信息/TextureRect", "玩家信息/玩家信息"]:
		var node := hud.get_node_or_null(key) as CanvasItem
		if node != null: node.hide()
	MainUI.surface(hud, "hud_background", "BoardBackdrop")
	for pair in [["玩家信息","hud_left"],["积分区域","hud_right"],["手牌信息","hud_bottom"],["回合信息","hud_top"]]:
		MainUI.surface(hud.get_node(pair[0]), pair[1])
	MainUI.surface(hud.get_node("手牌信息"), "hud_bottom_content", "LogFrame")
	hud.get_node("手牌信息").move_child(hud.get_node("手牌信息/LogFrame"), 1)
	for pair in [["姓名背景","hud_name"],["职业背景","hud_profession"],["积分背景","hud_resource"],["精力背景","hud_resource"],["立绘背景","hud_portrait_frame"]]:
		var field := hud.get_node("玩家信息/"+pair[0]) as TextureRect
		field.texture = MainUI.texture(pair[1])
		field.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		field.stretch_mode = TextureRect.STRETCH_SCALE
	for pair in [["积分背景","money"],["精力背景","energy"]]:
		var icon := MainUI.surface(hud.get_node("玩家信息/"+pair[0]), pair[1], "ResourceIcon")
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var map_background := hud.get_node("地图/地图背景") as TextureRect
	map_background.texture = MainUI.texture("hud_map_frame")
	map_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_background.stretch_mode = TextureRect.STRETCH_SCALE
	# The old map is drawn above the delivered placeholder; only its scroll frame remains visible.
	for pair in [["BtnGuide","guide"],["BtnPause","pause"],["BtnClose","close"]]:
		MainUI.icon(hud.get_node(pair[0]), pair[1])
	for control: Button in [hud.btn_action,hud.btn_food,hud.btn_end_turn]:
		for state in ["normal","hover","pressed","disabled"]:
			var style := MainUI.box("hud_action_disabled" if state == "disabled" else "hud_action", 16).duplicate() as StyleBoxTexture
			if state == "hover": style.modulate_color = Color(1.12,1.10,1.04)
			if state == "pressed": style.modulate_color = Color(0.85,0.80,0.72)
			control.add_theme_stylebox_override(state, style)
		MainUI.label(control, 44, true)
		control.custom_minimum_size = Vector2(0, 128)
		control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var title := Label.new()
	title.name = "CollectionTitle"
	title.text = "我的收藏"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MainUI.label(title, 44, true)
	hud.get_node("积分区域").add_child(title)
	MainUI.surface(hud.get_node("积分区域"), "hud_score", "ScoreFrame")
	hud.get_node("积分区域").move_child(hud.get_node("积分区域/ScoreFrame"), 1)
	MainUI.surface(hud.get_node("积分区域"), "hud_profession", "CollectionHeader")
	hud.get_node("积分区域").move_child(hud.get_node("积分区域/CollectionHeader"), 2)
	hud.get_node("玩家信息/立绘背景").clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
	title.add_theme_color_override("font_color", Color("fff1d3"))
	var score_button := Button.new()
	score_button.name = "ScoreButton"
	score_button.accessibility_name = "查看计分详情"
	score_button.tooltip_text = "查看计分详情"
	MainUI.button(score_button)
	for state in ["normal", "hover", "pressed", "disabled"]: score_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	score_button.pressed.connect(func():
		if TurnManager.GameOn and TurnManager.now_player_index >= 0 and TurnManager.now_player_index < TurnManager.players.size():
			hud.score_overlay.open_for_player(TurnManager.players[TurnManager.now_player_index]))
	hud.get_node("积分区域").add_child(score_button)
	_setup_turn_banner()
	_setup_information_panel()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _setup_information_panel() -> void:
	# Containers constrain long event descriptions to the illustrated writing area.
	# Keep the existing labels so manager updates and tutorial visibility still work.
	_log_content = VBoxContainer.new()
	_log_content.name = "InformationContent"
	_log_content.add_theme_constant_override("separation", 8)
	hud.get_node("手牌信息").add_child(_log_content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	_log_content.add_child(header)
	hud.current_status.reparent(header)
	hud.current_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.current_status.custom_minimum_size = Vector2.ZERO
	hud.current_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	hud.current_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hud.current_status.clip_text = true
	hud.current_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MainUI.label(hud.current_status, 34, true)
	var scroll_hint := Label.new()
	scroll_hint.text = "滚动查看"
	MainUI.label(scroll_hint, 26)
	scroll_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(scroll_hint)
	_log_scroll = ScrollContainer.new()
	_log_scroll.name = "MessageScroll"
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_scroll.follow_focus = true
	_log_scroll.focus_mode = Control.FOCUS_ALL
	_log_scroll.accessibility_name = "局内消息，可滚动阅读"
	_log_scroll.add_theme_stylebox_override("focus", MainUI.theme().get_stylebox("focus", "Button"))
	_log_content.add_child(_log_scroll)
	_log_scroll.get_v_scroll_bar().changed.connect(func():
		var bar := _log_scroll.get_v_scroll_bar()
		scroll_hint.visible = bar.max_value > bar.page)
	hud.information.reparent(_log_scroll)
	hud.information.custom_minimum_size = Vector2.ZERO
	hud.information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.information.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hud.information.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	hud.information.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MainUI.label(hud.information, 36)
	hud.information.add_theme_constant_override("line_spacing", 4)
	hud.information.minimum_size_changed.connect(_reset_message_scroll)
	hud.current_status.minimum_size_changed.connect(_update_status_tooltip)
	_update_status_tooltip()

func _reset_message_scroll() -> void:
	_log_scroll.set_deferred("scroll_vertical", 0)

func _update_status_tooltip() -> void:
	hud.current_status.tooltip_text = hud.current_status.text

func _setup_turn_banner() -> void:
	var banner := hud.get_node("回合信息")
	hud.phase_label.hide()
	_player_name = Label.new()
	_player_name.name = "ActivePlayerName"
	_player_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	MainUI.label(_player_name, 40, true)
	banner.add_child(_player_name)
	_phase_track = Button.new()
	_phase_track.name = "PhaseTrack"
	_phase_track.tooltip_text = "查看当前阶段规则"
	_phase_track.accessibility_name = "查看当前阶段规则"
	for state in ["normal", "hover", "pressed", "disabled"]:
		_phase_track.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_phase_track.add_theme_stylebox_override("focus", MainUI.theme().get_stylebox("focus", "Button"))
	_phase_track.pressed.connect(func(): hud.open_current_phase_guide(_phase_track))
	banner.add_child(_phase_track)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	_phase_track.add_child(row)
	MainUI.fill(row)
	for phase_name: String in PHASE_NAMES:
		var panel := PanelContainer.new()
		panel.custom_minimum_size.x = 170
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(panel)
		var label := Label.new()
		label.text = phase_name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		MainUI.label(label, 36)
		panel.add_child(label)
		_phase_panels.append(panel)
		_phase_names.append(label)
	TurnManager.turn_start.connect(_refresh_turn_player)
	TurnManager.phase_changed.connect(_refresh_phase)
	_refresh_turn_player(TurnManager.now_player_index)
	_refresh_phase(TurnManager.now_phase)

func _refresh_turn_player(index: int) -> void:
	if index < 0 or index >= TurnManager.players.size(): return
	_player_name.text = "P%d · %s" % [index + 1, TurnManager.players[index].player_name]
	_player_name.tooltip_text = "当前玩家：" + TurnManager.players[index].player_name

func _refresh_phase(phase: int) -> void:
	for index in range(_phase_panels.size()):
		var active := index == phase
		var style := StyleBoxFlat.new()
		style.bg_color = Color("b76823") if active else Color("efe1c6")
		style.border_color = Color("8d481b") if active else Color("ccb68e")
		style.set_border_width_all(2 if active else 1)
		style.set_corner_radius_all(8)
		_phase_panels[index].add_theme_stylebox_override("panel", style)
		_phase_names[index].text = ("▶ " if active else "") + PHASE_NAMES[index]
		_phase_names[index].add_theme_color_override("font_color", Color("fff7e6") if active else Color("6e604f"))
	_phase_track.accessibility_name = "当前阶段：%s。查看阶段规则" % PHASE_NAMES[clampi(phase, 0, 4)]

func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var unit := viewport_size / Vector2(2560,1600)
	_place("玩家信息", Rect2(30,236,410,1004), unit)
	_place("地图", Rect2(452,216,1628,1048), unit)
	_place("积分区域", Rect2(2094,236,436,1004), unit)
	_place("回合信息", Rect2(740,30,1060,172), unit)
	_place("手牌信息", Rect2(50,1286,2470,246), unit)
	_place("手牌信息/LogFrame", Rect2(24,24,1430,198), unit)
	_place("操作区域", Rect2(1536,1334,930,142), unit)
	_place("玩家信息/立绘背景", Rect2(28,30,354,458), unit)
	_place("玩家信息/姓名背景", Rect2(35,500,340,84), unit)
	_place("玩家信息/职业背景", Rect2(35,600,340,90), unit)
	_place("玩家信息/积分背景", Rect2(35,704,340,126), unit)
	_place("玩家信息/精力背景", Rect2(35,850,340,126), unit)
	MainUI.fill(hud.立绘精二, 18)
	hud.立绘精二.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	for key in ["玩家信息/姓名背景/NameLabel", "玩家信息/职业背景/职业"]:
		var text := hud.get_node(key) as Label
		MainUI.fill(text, 16)
		text.offset_top = 10
		text.offset_bottom = -10
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.clip_text = true
		text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		MainUI.label(text, 42, true)
	hud.get_node("玩家信息/职业背景/职业").add_theme_color_override("font_color", Color("fff1d3"))
	for pair in [[hud.money_label,"积分背景"],[hud.energy_label,"精力背景"]]:
		var text: Label = pair[0]
		MainUI.fill(text, 16)
		text.offset_left = 108
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		MainUI.pixel_label(text, 48)
		_place("玩家信息/"+pair[1]+"/ResourceIcon", Rect2(10,14,92,92), unit)
	MainUI.fill(hud.get_node("地图/地图背景"))
	MainUI.fill(hud.map_container)
	hud.map_container.offset_left = 90
	hud.map_container.offset_right = -90
	hud.map_container.offset_top = 80
	hud.map_container.offset_bottom = -80
	_place("地图/缩放提示信息", Rect2(-400,-170,600,102), unit)
	MainUI.label(hud.get_node("地图/缩放提示信息"), 36)
	_place("回合信息/TurnLabel", Rect2(64,22,230,60), unit)
	_place("回合信息/ActivePlayerName", Rect2(304,22,446,60), unit)
	_place("回合信息/TimeLabel", Rect2(768,22,228,60), unit)
	_place("回合信息/PhaseTrack", Rect2(64,94,932,58), unit)
	MainUI.pixel_label(hud.turn_label, 36)
	MainUI.pixel_label(hud.time_label, 36)
	hud.turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hud.time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place("手牌信息/InformationContent", Rect2(210,38,1190,166), unit)
	for index in range(3):
		var control: Button = [hud.btn_action,hud.btn_food,hud.btn_end_turn][index]
		MainUI.rect(control, Rect2(Vector2(index*310,0)*unit,Vector2(280,140)*unit))
	_place("积分区域/CollectionTitle", Rect2(38,12,360,66), unit)
	_place("积分区域/CollectionHeader", Rect2(18,0,400,104), unit)
	_place("积分区域/ScrollContainer", Rect2(38,130,360,662), unit)
	_place("积分区域/ScoreFrame", Rect2(30,820,376,122), unit)
	_place("积分区域/ScoreButton", Rect2(30,820,376,122), unit)
	_place("积分区域/ScoreLabel", Rect2(42,847,352,72), unit)
	MainUI.pixel_label(hud.score_label, 48)
	for i in range(3): _place(["BtnGuide","BtnPause","BtnClose"][i],Rect2(2110+i*142,128,96,96),unit)
	_layout_ai_control.call_deferred()
	hud.call_deferred("_on_container_resized")

func _layout_ai_control() -> void:
	var controller := get_tree().get_first_node_in_group("AI_SESSION")
	if controller == null: return
	var speed := controller.find_child("AISpeedButton", true, false) as Button
	if speed == null: return
	var hint_rect := (hud.get_node("地图/缩放提示信息") as Control).get_global_rect()
	var turn_center := (hud.get_node("回合信息") as Control).get_global_rect().get_center().x
	# Keep the mirrored hint position; reserve a separate row for the three utility icons.
	speed.position = Vector2(2.0 * turn_center - hint_rect.end.x, hint_rect.position.y)
	speed.size = Vector2(hint_rect.size.x, 72)
	speed.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	MainUI.label(speed, 36)

func _place(path: String, area: Rect2, unit: Vector2) -> void:
	MainUI.rect(hud.get_node(path),Rect2(area.position*unit,area.size*unit))
