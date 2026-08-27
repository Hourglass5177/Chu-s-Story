extends Control
class_name EventPresentationDirector

signal sequence_started(event_id: StringName)
signal step_started(kind: StringName, player: PlayerClass)
signal step_finished(kind: StringName, player: PlayerClass)
signal sequence_finished(event_id: StringName)

enum Tier { CONCISE, MAP_ACTION, SEQUENTIAL }

const STEP_SECONDS := 1.5
const COMPACT_PANEL_SIZE := Vector2(720.0, 176.0)
const CARD_PANEL_HEIGHT := 396.0
const PIXEL_FONT := preload("res://arts/像素字体.ttf")
const PRESENTATION_TIERS: Dictionary = {
	&"zuo_shou_yu_li": Tier.SEQUENTIAL, &"bai_ge_zheng_liu": Tier.SEQUENTIAL,
	&"pou_duo_yi_gua": Tier.SEQUENTIAL, &"gu_zhu_yi_zhi": Tier.CONCISE,
	&"ba_geng_xie_ye": Tier.CONCISE, &"yi_chuang_zeng_shou": Tier.CONCISE,
	&"wen_hua_xin_feng": Tier.SEQUENTIAL, &"jiao_huan_ren_sheng": Tier.CONCISE,
	&"mei_mei_yu_gong": Tier.SEQUENTIAL, &"yang_jing_xu_rui": Tier.CONCISE,
	&"miao_shou_hui_chun": Tier.CONCISE, &"cun_bu_nan_xing": Tier.CONCISE,
	&"jing_pi_li_jin": Tier.CONCISE, &"bi_men_xie_ke": Tier.CONCISE,
	&"juan_yi_xiu_zheng": Tier.CONCISE, &"you_mu_cheng_huai": Tier.MAP_ACTION,
	&"chen_jin_ti_yan": Tier.MAP_ACTION, &"yi_wai_zhi_xi": Tier.CONCISE,
	&"xin_huo_xiang_chuan": Tier.CONCISE, &"you_shi_tong_xiang": Tier.SEQUENTIAL,
	&"chuan_yi_hu_jian": Tier.CONCISE, &"yi_cang_hu_huan": Tier.CONCISE,
	&"tai_jiu_huan_xin": Tier.CONCISE, &"wen_hua_gong_xiang": Tier.CONCISE,
	&"tong_tai_jing_ji": Tier.SEQUENTIAL, &"yi_shi_hui_you": Tier.CONCISE,
	&"gu_di_chong_you": Tier.MAP_ACTION, &"dou_zhuan_xing_yi": Tier.MAP_ACTION,
	&"chang_xing_wu_zu": Tier.CONCISE, &"ri_xing_qian_li": Tier.MAP_ACTION,
	&"yi_jing_xun_zong": Tier.MAP_ACTION, &"tong_xing_feng_cai": Tier.MAP_ACTION,
	&"guo_bao_hu_hang": Tier.SEQUENTIAL, &"jin_chan_tuo_qiao": Tier.CONCISE,
	&"yi_hua_jie_mu": Tier.CONCISE, &"jin_ji_bi_xian": Tier.CONCISE,
	&"jian_wang_zhi_lai": Tier.CONCISE, &"fu_di_chou_xin": Tier.CONCISE,
	&"zhan_yi_gong_yan": Tier.CONCISE, &"shi_ji_tao_zhen": Tier.CONCISE,
}

var hud: HUD = null
var active_event_id: StringName = &""
var _camera_snapshot: Dictionary = {}
var _generation := 0
var _fast_forward_requested := false
var _panel: PanelContainer
var _title: Label
var _message: Label
var _card_row: HBoxContainer
var _left_card: TextureRect
var _right_card: TextureRect
var _left_caption: Label
var _right_caption: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 80
	_build_ui()

func bind(target_hud: HUD) -> void:
	hud = target_hud

func get_tier(event_id: StringName) -> Tier:
	return int(PRESENTATION_TIERS.get(event_id, Tier.CONCISE)) as Tier

func begin_sequence(event_id: StringName, title: String) -> void:
	cancel_and_restore(&"superseded")
	_generation += 1
	active_event_id = event_id
	_camera_snapshot = hud.capture_camera_state() if hud != null else {}
	_title.text = "【%s】" % title
	_message.text = "结算中…"
	_card_row.visible = false
	_panel.custom_minimum_size.y = COMPACT_PANEL_SIZE.y
	_panel.visible = true
	sequence_started.emit(event_id)

func focus_player(player: PlayerClass, message: String = "") -> void:
	if active_event_id.is_empty() or player == null:
		return
	if hud != null:
		hud.focus_camera_for_event(player, 0.35)
	if not message.is_empty():
		_message.text = message
	step_started.emit(&"focus", player)
	await _wait_step(STEP_SECONDS)
	step_finished.emit(&"focus", player)

func show_dice(player: PlayerClass, values: Array[int]) -> void:
	if active_event_id.is_empty():
		return
	var labels := PackedStringArray()
	for value: int in values:
		labels.append(str(value))
	_message.text = "%s 掷出  %s 点" % [player.player_name, " · ".join(labels)]
	step_started.emit(&"dice", player)
	await _wait_step(STEP_SECONDS)
	step_finished.emit(&"dice", player)

func show_resource_delta(player: PlayerClass, kind: StringName, actual_delta: int) -> void:
	if active_event_id.is_empty() or player == null:
		return
	var label := "精力" if kind == &"energy" else "积分点"
	var signed_value := "+%d" % actual_delta if actual_delta >= 0 else str(actual_delta)
	_message.text = "%s  %s%s" % [player.player_name, label, signed_value]
	step_started.emit(&"resource_delta", player)
	await _wait_step(STEP_SECONDS)
	step_finished.emit(&"resource_delta", player)

func show_status_applied(player: PlayerClass, status: String) -> void:
	if active_event_id.is_empty() or player == null:
		return
	_message.text = "%s  %s" % [player.player_name, status]
	step_started.emit(&"status", player)
	await _wait_step(STEP_SECONDS)
	step_finished.emit(&"status", player)

func show_card_duel(
	first: PlayerClass,
	first_card: 卡牌基类,
	second: PlayerClass,
	second_card: 卡牌基类,
	result_text: String
) -> void:
	if active_event_id.is_empty() or first == null or second == null:
		return
	_left_card.texture = first_card.image_of_front if first_card != null else null
	_right_card.texture = second_card.image_of_front if second_card != null else null
	_left_caption.text = "%s · %s" % [first.player_name, first_card.card_name if first_card != null else "无牌"]
	_right_caption.text = "%s · %s" % [second.player_name, second_card.card_name if second_card != null else "无牌"]
	_message.text = result_text
	_card_row.visible = true
	_panel.custom_minimum_size.y = CARD_PANEL_HEIGHT
	step_started.emit(&"card_duel", first)
	await _wait_step(STEP_SECONDS)
	_card_row.visible = false
	_panel.custom_minimum_size.y = COMPACT_PANEL_SIZE.y
	step_finished.emit(&"card_duel", first)

func note_map_action(player: PlayerClass, message: String) -> void:
	if active_event_id.is_empty():
		return
	if hud != null and player != null:
		hud.focus_camera_for_event(player, 0.35)
	_message.text = message

func finish_sequence(summary: String = "") -> void:
	if active_event_id.is_empty():
		return
	if not summary.is_empty():
		_message.text = summary
	if get_tier(active_event_id) == Tier.CONCISE:
		await _wait_step(0.55)
	var finished_id := active_event_id
	if hud != null and not _camera_snapshot.is_empty():
		hud.restore_camera_state(_camera_snapshot, 0.4)
		if not GameManager.is_headless_simulation():
			var restore_generation := _generation
			await get_tree().create_timer(0.42, true).timeout
			if restore_generation != _generation:
				return
	active_event_id = &""
	_camera_snapshot.clear()
	_panel.visible = false
	_card_row.visible = false
	_panel.custom_minimum_size.y = COMPACT_PANEL_SIZE.y
	sequence_finished.emit(finished_id)

func fast_forward_current_step() -> void:
	_fast_forward_requested = true

func cancel_and_restore(_reason: StringName = &"cancelled") -> void:
	if active_event_id.is_empty():
		return
	_generation += 1
	if hud != null and not _camera_snapshot.is_empty():
		hud.restore_camera_state(_camera_snapshot, 0.0)
	active_event_id = &""
	_camera_snapshot.clear()
	_panel.visible = false
	_card_row.visible = false
	_panel.custom_minimum_size.y = COMPACT_PANEL_SIZE.y
	_fast_forward_requested = false

func restore_camera_state() -> void:
	if hud != null and not _camera_snapshot.is_empty():
		hud.restore_camera_state(_camera_snapshot, 0.4)

func _wait_step(seconds: float) -> void:
	if GameManager.is_headless_simulation():
		return
	var generation := _generation
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	_fast_forward_requested = false
	while generation == _generation and Time.get_ticks_msec() < deadline and not _fast_forward_requested:
		await get_tree().process_frame
	_fast_forward_requested = false

func _on_panel_gui_input(event: InputEvent) -> void:
	if active_event_id.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		fast_forward_current_step()
		accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if not active_event_id.is_empty() and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		fast_forward_current_step()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "EventSettlementPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.position = Vector2(-COMPACT_PANEL_SIZE.x * 0.5, 184)
	_panel.size = COMPACT_PANEL_SIZE
	_panel.custom_minimum_size = COMPACT_PANEL_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_gui_input)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f4dfb5")
	style.border_color = Color("9f603b")
	style.set_border_width_all(4)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0.16, 0.08, 0.04, 0.28)
	style.shadow_size = 10
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var margin := MarginContainer.new()
	margin.name = "ContentMargin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.name = "SettlementContent"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 7)
	margin.add_child(box)
	_title = Label.new()
	_title.name = "EventSettlementTitle"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", PIXEL_FONT)
	_title.add_theme_font_size_override("font_size", 44)
	_title.add_theme_color_override("font_color", Color("4b281e"))
	box.add_child(_title)
	_message = Label.new()
	_message.name = "EventSettlementMessage"
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message.add_theme_font_override("font", PIXEL_FONT)
	_message.add_theme_font_size_override("font_size", 30)
	_message.add_theme_color_override("font_color", Color("2d1a14"))
	box.add_child(_message)
	_card_row = HBoxContainer.new()
	_card_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_row.add_theme_constant_override("separation", 32)
	box.add_child(_card_row)
	var left_column := VBoxContainer.new()
	var right_column := VBoxContainer.new()
	for column: VBoxContainer in [left_column, right_column]:
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.custom_minimum_size = Vector2(180, 190)
		_card_row.add_child(column)
	_left_card = TextureRect.new()
	_right_card = TextureRect.new()
	for card_view: TextureRect in [_left_card, _right_card]:
		card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_view.custom_minimum_size = Vector2(120, 160)
		card_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_left_caption = Label.new()
	_right_caption = Label.new()
	for caption: Label in [_left_caption, _right_caption]:
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		caption.add_theme_font_override("font", PIXEL_FONT)
		caption.add_theme_font_size_override("font_size", 20)
		caption.add_theme_color_override("font_color", Color("2d1a14"))
	left_column.add_child(_left_card)
	left_column.add_child(_left_caption)
	right_column.add_child(_right_card)
	right_column.add_child(_right_caption)
	_card_row.visible = false
	_panel.visible = false
