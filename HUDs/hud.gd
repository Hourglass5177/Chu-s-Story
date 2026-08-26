extends CanvasLayer
class_name HUD
@onready var turn_label = $"回合信息/TurnLabel" as Label
@onready var phase_label = $"回合信息/PhaseLabel" as Label
@onready var time_label = $"回合信息/TimeLabel" as Label

@onready var player_label = $"玩家信息/玩家信息" as Label
@onready var money_label = $"玩家信息/积分背景/MoneyLabel" as Label
@onready var energy_label = $"玩家信息/精力背景/EnergyLabel" as Label
@onready var name_label = $"玩家信息/姓名背景/NameLabel" as Label
@onready var 立绘精二 = $"玩家信息/立绘背景/立绘" as TextureRect

@onready var map_sec = $"地图"

@onready var btn_action = $"操作区域/BtnAction" as Button
@onready var btn_food = $"操作区域/BtnFood" as Button
@onready var btn_end_turn = $"操作区域/BtnEndTurn" as Button

@onready var score_label = $"积分区域/ScoreLabel" as Label

@onready var current_status = $"手牌信息/当前" as Label
@onready var information = $"手牌信息/游戏信息" as Label

@onready var backpack_panel = $食物背包弹窗 as Panel

@onready var timer = TurnManager.get_node("TurnTimer") as Timer
@export var default_font: FontFile = null

@onready var map_camera = $"地图/地图背景/SubViewportContainer/SubViewport/MapCamera"
@onready var btn_view_toggle = $"地图/BtnViewToggle" # 请换成你实际的按钮路径

var is_focus_mode: bool = false
var global_zoom: Vector2
var global_pos: Vector2
var map_zoom_factor := 1.0
var _global_camera_position := Vector2.ZERO
var _camera_tween: Tween = null
var _map_drag_candidate := false
var _map_dragging := false
var _map_drag_distance := 0.0
var _suppress_map_click_until_msec := 0
var _map_tooltip: PanelContainer = null
var _map_tooltip_label: Label = null
var _map_tooltip_timer: Timer = null
var _hovered_map_section: MapSection = null
var _active_event_map_request: EventChoiceRequest = null
var _event_map_selected_options: Array = []
var _event_map_restore_focus_mode: bool = false
var _event_map_source_name: String = ""
var _event_no_effect_pending: bool = false
var _active_profession_map_request: ProfessionSectionChoiceRequest = null
var _profession_map_restore_focus_mode: bool = false
var _profession_map_view_changed_by_user: bool = false
var _profession_map_focus_player: PlayerClass = null
var _profession_map_session_generation: int = -1
var _profession_map_turn_epoch: int = -1
var _profession_map_phase: TurnManager.TurnPhase = TurnManager.TurnPhase.BEGIN
var _camera_focus_player_override: PlayerClass = null
var _last_profession_block_turns: Dictionary = {}

const MAP_ZOOM_MIN_FACTOR := 1.0
const MAP_ZOOM_MAX_FACTOR := 3.0
const MAP_ZOOM_STEP := 1.15
const MAP_FOCUS_ENTRY_ZOOM_FACTOR := 2.0
const MAP_DRAG_THRESHOLD := 8.0
const MAP_TOOLTIP_DELAY := 0.6

static func clamp_map_zoom_factor(value: float) -> float:
	return clampf(value, MAP_ZOOM_MIN_FACTOR, MAP_ZOOM_MAX_FACTOR)

static func get_focus_entry_zoom_factor(_current_factor: float) -> float:
	# 追踪视角始终相对“默认全图”放大一倍，不按玩家当前缩放继续翻倍。
	return clamp_map_zoom_factor(MAP_FOCUS_ENTRY_ZOOM_FACTOR)

static func get_view_mode_hint_text(focus_mode: bool) -> String:
	return "【ALT】切换视角：%s\n【滚轮】视角缩放" % ("追踪" if focus_mode else "全局")

# 之前我们算好的留白参数，原封不动保留
const MAP_REAL_SIZE = Vector2(2560, 1600)
const margin_top = 250.0 - 250
const margin_bottom = 100.0 - 100
const margin_x = 50.0 - 50

# 对应各地区非遗牌背面与牌面边框的主色。
const REGION_TITLE_COLORS: Dictionary = {
	MapSection.REGION.鄂州: Color8(167, 18, 120),
	MapSection.REGION.恩施: Color8(131, 174, 190),
	MapSection.REGION.黄冈: Color8(248, 143, 95),
	MapSection.REGION.黄石: Color8(244, 209, 127),
	MapSection.REGION.荆门: Color8(51, 50, 128),
	MapSection.REGION.荆州: Color8(236, 98, 87),
	MapSection.REGION.潜江: Color8(128, 35, 124),
	MapSection.REGION.神农架: Color8(92, 146, 123),
	MapSection.REGION.十堰: Color8(169, 190, 133),
	MapSection.REGION.随州: Color8(203, 81, 78),
	MapSection.REGION.天门: Color8(158, 68, 68),
	MapSection.REGION.武汉: Color8(254, 177, 107),
	MapSection.REGION.仙桃: Color8(242, 0, 114),
	MapSection.REGION.咸宁: Color8(78, 45, 126),
	MapSection.REGION.襄阳: Color8(150, 68, 70),
	MapSection.REGION.孝感: Color8(94, 43, 120),
	MapSection.REGION.宜昌: Color8(73, 145, 125),
}

var map:MAP
var event_overlay: EventOverlay
var market_overlay: 研究所弹窗
var score_overlay: ScoreDetailPanel
var achievement_detail_overlay: AchievementDetailPanel
var achievement_toast: AchievementToast
var game_result_overlay: GameResultOverlay
var card_hand_animator: CardHandAnimator
var profession_detail_overlay: ProfessionDetailPanel
var profession_draw_overlay: ProfessionDrawPanel
var profession_skill_toast: ProfessionSkillToast
var event_presentation_director: EventPresentationDirector
var game_guide: DigitalGameGuide
var guide_button: Button
const EVENT_OVERLAY_SCENE := preload("res://HUDs/event_overlay.tscn")
const MARKET_OVERLAY_SCENE := preload("res://HUDs/研究所弹窗.tscn")
const SCORE_OVERLAY_SCENE := preload("res://HUDs/计分详情弹窗.tscn")
const ACHIEVEMENT_DETAIL_SCENE := preload("res://HUDs/成就详情弹窗.tscn")
const ACHIEVEMENT_TOAST_SCENE := preload("res://HUDs/成就获得提示.tscn")
const GAME_RESULT_OVERLAY_SCENE := preload("res://HUDs/GameResultOverlay/game_result_overlay.tscn")
const CARD_HAND_ANIMATOR_SCENE := preload("res://HUDs/card_hand_animator.tscn")
const PROFESSION_DETAIL_SCENE := preload("res://HUDs/职业详情弹窗.tscn")
const PROFESSION_DRAW_SCENE := preload("res://HUDs/职业抽牌弹窗.tscn")
const PROFESSION_SKILL_TOAST_SCENE := preload("res://HUDs/职业技能提示.tscn")
const EVENT_PRESENTATION_DIRECTOR_SCRIPT := preload("res://HUDs/event_presentation_director.gd")
const GAME_GUIDE_SCENE := preload("res://UI/GameGuide/digital_game_guide.tscn")
const FRONTEND_THEME := preload("res://UI/Frontend/frontend_theme.tres")
func _ready() -> void:
	map_container.resized.connect(_on_container_resized)
	_spawn_map_in_hud()
	map = get_tree().get_first_node_in_group("MAP")
	TurnManager.turn_start.connect(_on_turn_start)
	TurnManager.phase_changed.connect(_on_phase_changed)
	btn_end_turn.pressed.connect(_on_btn_end_turn_pressed)
	btn_action.pressed.connect(_on_btn_action_pressed)
	#_update_button_states(TurnManager.TurnPhase.BEGIN)
	$BtnClose.pressed.connect(_on_close_pressed)
	btn_food.pressed.connect(_on_btn_food_pressed)
	btn_view_toggle.pressed.connect(_on_view_toggle_pressed)
	_update_view_mode_hint()
	map_container.gui_input.connect(_on_map_container_gui_input)
	_setup_event_ui()
	_setup_event_presentation()
	_setup_market_ui()
	_setup_score_ui()
	_setup_achievement_ui()
	_setup_game_result_ui()
	_setup_card_hand_animation()
	_setup_profession_ui()
	_setup_map_tooltip()
	_setup_game_guide()
	phase_label.mouse_filter = Control.MOUSE_FILTER_STOP
	phase_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	phase_label.gui_input.connect(_on_phase_label_gui_input)
	score_label.mouse_filter = Control.MOUSE_FILTER_STOP
	score_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	score_label.gui_input.connect(_on_score_label_gui_input)
	var profession_panel := $"玩家信息/职业背景" as Control
	profession_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	profession_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	profession_panel.gui_input.connect(_on_profession_panel_gui_input)
	# 设置相机的绝对物理边界。
	map_camera.limit_left = -margin_x
	map_camera.limit_top = -margin_top
	map_camera.limit_right = MAP_REAL_SIZE.x + margin_x
	map_camera.limit_bottom = MAP_REAL_SIZE.y + margin_bottom
	if $BtnClose.texture_normal:
		var bitmap = BitMap.new()
		# 读取原图的透明通道数据
		bitmap.create_from_image_alpha($BtnClose.texture_normal.get_image())
		# 将其设为按钮的点击遮罩
		$BtnClose.texture_click_mask = bitmap
		var mask = $BtnClose/mask
		$BtnClose.mouse_entered.connect(func(): mask.show())
		$BtnClose.mouse_exited.connect(func(): mask.hide())
		$BtnClose.button_down.connect(func(): mask.modulate = Color(0, 0, 0, 0.7)) # 按下更黑
		$BtnClose.button_up.connect(func(): mask.modulate = Color(0, 0, 0, 0.4))   # 松开恢复


func _setup_game_guide() -> void:
	guide_button = Button.new()
	guide_button.name = "GuideButton"
	guide_button.text = "?"
	guide_button.tooltip_text = "游戏指南 · F1"
	guide_button.theme = FRONTEND_THEME
	guide_button.z_index = 50
	guide_button.focus_mode = Control.FOCUS_ALL
	guide_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	guide_button.position = Vector2(-320, 30)
	guide_button.size = Vector2(82, 82)
	guide_button.pressed.connect(func() -> void: open_game_guide())
	add_child(guide_button)
	game_guide = GAME_GUIDE_SCENE.instantiate() as DigitalGameGuide
	game_guide.name = "DigitalGameGuide"
	game_guide.set_shortcut_enabled(true)
	add_child(game_guide)


func get_game_guide() -> DigitalGameGuide:
	return game_guide


func open_game_guide(context: GuideOpenContext = null) -> bool:
	if game_guide == null:
		return false
	var open_context := context
	if open_context == null:
		if _hovered_map_section != null and is_instance_valid(_hovered_map_section):
			var section := _hovered_map_section
			var topic_id := &"map_movement" if section.type == MapSection.SectionType.一般 else &"functional_tiles"
			open_context = GuideOpenContext.new(
				GuideOpenContext.Source.MAP_SECTION,
				topic_id,
				&"map_section",
				StringName("%d,%d,%d" % [section.location_index.x, section.location_index.y, section.location_index.z]),
				guide_button
			)
		else:
			open_context = GuideOpenContext.new(
				GuideOpenContext.Source.HUD,
				&"turn_phases",
				&"phase",
				&"",
				guide_button
			)
	_cancel_map_pointer_state()
	return game_guide.open_guide(open_context)


func _cancel_map_pointer_state() -> void:
	_map_drag_candidate = false
	_map_dragging = false
	_map_drag_distance = 0.0
	_hovered_map_section = null
	if _map_tooltip_timer != null:
		_map_tooltip_timer.stop()
	if _map_tooltip != null:
		_map_tooltip.hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("guide_toggle") and game_guide != null and not game_guide.is_guide_open():
		open_game_guide()
		get_viewport().set_input_as_handled()


func _on_phase_label_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		open_game_guide(GuideOpenContext.new(
			GuideOpenContext.Source.PHASE,
			&"turn_phases",
			&"phase",
			&"",
			phase_label
		))
		get_viewport().set_input_as_handled()

func _setup_event_ui() -> void:
	event_overlay = EVENT_OVERLAY_SCENE.instantiate() as EventOverlay
	add_child(event_overlay)
	EventManager.retained_cards_changed.connect(_on_retained_cards_changed)
	EventManager.event_revealed.connect(_on_event_modal_opened)
	EventManager.event_finished.connect(_on_event_modal_closed)
	EventManager.choice_requested.connect(_on_event_choice_requested)
	EventManager.choice_resolved.connect(_on_event_choice_resolved)
	EventManager.interaction_finished.connect(_on_event_interaction_finished)
	if map != null and not map.event_section_selected.is_connected(_on_event_map_section_selected):
		map.event_section_selected.connect(_on_event_map_section_selected)

func get_event_overlay() -> EventOverlay:
	return event_overlay

func _setup_event_presentation() -> void:
	event_presentation_director = EVENT_PRESENTATION_DIRECTOR_SCRIPT.new() as EventPresentationDirector
	add_child(event_presentation_director)
	event_presentation_director.bind(self)

func capture_camera_state() -> Dictionary:
	return {
		"focus_mode": is_focus_mode,
		"map_zoom_factor": map_zoom_factor,
		"global_position": _global_camera_position,
		"camera_position": map_camera.position,
		"camera_zoom": map_camera.zoom,
	}

func focus_camera_for_event(player: PlayerClass, duration: float = 0.35) -> void:
	if player == null or not is_instance_valid(player):
		return
	var target_zoom := global_zoom * maxf(map_zoom_factor, MAP_FOCUS_ENTRY_ZOOM_FACTOR)
	var target_pos := _clamp_camera_position(player.position, target_zoom)
	_stop_camera_tween()
	if duration <= 0.0 or GameManager.is_headless_simulation():
		map_camera.zoom = target_zoom
		map_camera.position = target_pos
		return
	_camera_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_camera_tween.tween_property(map_camera, "zoom", target_zoom, duration)
	_camera_tween.tween_property(map_camera, "position", target_pos, duration)

func restore_camera_state(snapshot: Dictionary, duration: float = 0.4) -> void:
	if snapshot.is_empty():
		return
	_stop_camera_tween()
	is_focus_mode = bool(snapshot.get("focus_mode", false))
	map_zoom_factor = float(snapshot.get("map_zoom_factor", map_zoom_factor))
	_global_camera_position = snapshot.get("global_position", _global_camera_position)
	_update_view_mode_hint()
	var target_position: Vector2 = snapshot.get("camera_position", map_camera.position)
	var target_zoom: Vector2 = snapshot.get("camera_zoom", map_camera.zoom)
	if duration <= 0.0 or GameManager.is_headless_simulation():
		map_camera.position = target_position
		map_camera.zoom = target_zoom
		return
	_camera_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_camera_tween.tween_property(map_camera, "zoom", target_zoom, duration)
	_camera_tween.tween_property(map_camera, "position", target_position, duration)

func begin_event_presentation(card: 事件牌) -> void:
	if event_presentation_director != null and card != null:
		event_presentation_director.begin_sequence(card.event_id, card.card_name)

func finish_event_presentation(summary: String = "") -> void:
	if event_presentation_director != null:
		await event_presentation_director.finish_sequence(summary)

func cancel_event_presentation(reason: StringName = &"cancelled") -> void:
	if event_presentation_director != null:
		event_presentation_director.cancel_and_restore(reason)

func _setup_market_ui() -> void:
	market_overlay = MARKET_OVERLAY_SCENE.instantiate() as 研究所弹窗
	add_child(market_overlay)

func _setup_score_ui() -> void:
	score_overlay = SCORE_OVERLAY_SCENE.instantiate() as ScoreDetailPanel
	add_child(score_overlay)

func _setup_achievement_ui() -> void:
	achievement_detail_overlay = ACHIEVEMENT_DETAIL_SCENE.instantiate() as AchievementDetailPanel
	add_child(achievement_detail_overlay)
	achievement_toast = ACHIEVEMENT_TOAST_SCENE.instantiate() as AchievementToast
	add_child(achievement_toast)
	if not AchievementManager.achievement_claimed.is_connected(_on_achievement_claimed):
		AchievementManager.achievement_claimed.connect(_on_achievement_claimed)
	if not AchievementManager.achievement_destroyed.is_connected(_on_achievement_destroyed):
		AchievementManager.achievement_destroyed.connect(_on_achievement_destroyed)

func _setup_game_result_ui() -> void:
	game_result_overlay = GAME_RESULT_OVERLAY_SCENE.instantiate() as GameResultOverlay
	add_child(game_result_overlay)
	if not TurnManager.game_finished.is_connected(_on_game_finished):
		TurnManager.game_finished.connect(_on_game_finished)
	game_result_overlay.return_to_main_menu_requested.connect(_on_result_return_to_main_menu)
	game_result_overlay.quit_requested.connect(_on_result_quit_requested)

func _setup_card_hand_animation() -> void:
	card_hand_animator = CARD_HAND_ANIMATOR_SCENE.instantiate() as CardHandAnimator
	add_child(card_hand_animator)
	card_hand_animator.setup(self)
	card_hand_animator.animation_started.connect(_on_card_hand_animation_started)
	card_hand_animator.queue_finished.connect(_on_card_hand_queue_finished)
	if not ResourceManager.card_hand_visual_requested.is_connected(_on_card_hand_visual_requested):
		ResourceManager.card_hand_visual_requested.connect(_on_card_hand_visual_requested)

func _setup_profession_ui() -> void:
	profession_detail_overlay = PROFESSION_DETAIL_SCENE.instantiate() as ProfessionDetailPanel
	add_child(profession_detail_overlay)
	profession_draw_overlay = PROFESSION_DRAW_SCENE.instantiate() as ProfessionDrawPanel
	add_child(profession_draw_overlay)
	profession_skill_toast = PROFESSION_SKILL_TOAST_SCENE.instantiate() as ProfessionSkillToast
	add_child(profession_skill_toast)
	ProfessionManager.skill_triggered.connect(_on_profession_skill_triggered)
	ProfessionManager.skill_state_changed.connect(_on_profession_skill_state_changed)
	ProfessionManager.profession_changed.connect(_on_profession_changed)
	ProfessionManager.section_choice_requested.connect(_on_profession_section_choice_requested)
	ProfessionManager.section_choice_resolved.connect(_on_profession_section_choice_resolved)
	if map != null and not map.section_choice_selected.is_connected(_on_generic_map_section_selected):
		map.section_choice_selected.connect(_on_generic_map_section_selected)

func _on_profession_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if TurnManager.GameOn and TurnManager.now_player_index >= 0 and TurnManager.now_player_index < TurnManager.players.size():
			profession_detail_overlay.show_for_player(TurnManager.players[TurnManager.now_player_index])
			get_viewport().set_input_as_handled()

func _on_profession_skill_triggered(player: PlayerClass, profession_id: StringName, message: String) -> void:
	if profession_skill_toast != null:
		profession_skill_toast.enqueue(player, profession_id, message)
	_pulse_profession_label(player)
	if _can_display_player(player):
		_update_player_stats(player)

func _on_profession_skill_state_changed(player: PlayerClass) -> void:
	var previous: int = int(_last_profession_block_turns.get(player, 0))
	var current: int = ProfessionManager.get_blocked_turns(player)
	_last_profession_block_turns[player] = current
	if profession_skill_toast != null:
		var definition = ProfessionManager.get_definition(player)
		var profession_id: StringName = definition.profession_id if definition != null else &""
		if current > 0 and previous <= 0:
			profession_skill_toast.enqueue(player, profession_id, "职业技能被封锁")
		elif current == 0 and previous > 0:
			profession_skill_toast.enqueue(player, profession_id, "职业技能恢复")
	if _can_display_player(player):
		_update_player_stats(player)

func _on_profession_changed(first_player: PlayerClass, second_player: PlayerClass) -> void:
	if first_player != null:
		_update_player_stats(first_player)
	if second_player != null:
		_update_player_stats(second_player)

func _pulse_profession_label(player: PlayerClass) -> void:
	if not _can_display_player(player):
		return
	var label := $"玩家信息/职业背景/职业" as Label
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate", Color(1.0, 0.74, 0.28, 1.0), 0.12)
	tween.tween_property(label, "modulate", Color.WHITE, 0.24)

func _on_profession_section_choice_requested(request: ProfessionSectionChoiceRequest) -> void:
	if request == null or map == null or request.options.is_empty():
		return
	_active_profession_map_request = request
	map.begin_section_choice(&"profession", request.request_id, request.options)
	btn_action.text = "不移动"
	btn_action.disabled = not request.optional
	btn_food.disabled = true
	btn_end_turn.disabled = true
	_profession_map_restore_focus_mode = is_focus_mode
	_profession_map_view_changed_by_user = false
	_profession_map_focus_player = request.player
	_profession_map_session_generation = TurnManager.get_session_generation()
	_profession_map_turn_epoch = TurnManager.get_turn_epoch()
	_profession_map_phase = TurnManager.now_phase
	if is_focus_mode:
		_leave_focus_at_current_camera()
	btn_view_toggle.disabled = false
	current_status.text = "【%s】请选择移动终点" % request.source_name
	information.text = request.source_description

func _on_generic_map_section_selected(owner: StringName, request_id: int, section: MapSection) -> void:
	if owner != &"profession" or _active_profession_map_request == null:
		return
	if request_id == _active_profession_map_request.request_id:
		ProfessionManager.submit_section_choice(request_id, section)

func _on_profession_section_choice_resolved(request_id: int, _section: MapSection, _timed_out: bool) -> void:
	if _active_profession_map_request == null or request_id != _active_profession_map_request.request_id:
		return
	map.end_section_choice(&"profession", request_id)
	_active_profession_map_request = null
	# 此信号只表示“选项已经确定”，棋子的技能移动尚未完成。
	# ALT、按钮和追踪镜头统一在 complete_profession_section_choice() 中恢复，
	# 避免先追旧位置、再追新位置、随后又追下一玩家的连续 Tween 竞态。

func complete_profession_section_choice(
	player: PlayerClass,
	session_generation: int,
	turn_epoch: int,
	phase: TurnManager.TurnPhase
) -> void:
	if _profession_map_focus_player != player \
			or _profession_map_session_generation != session_generation \
			or _profession_map_turn_epoch != turn_epoch \
			or _profession_map_phase != phase:
		return
	var still_owns_view: bool = session_generation == TurnManager.get_session_generation() \
		and turn_epoch == TurnManager.get_turn_epoch() \
		and TurnManager.GameOn \
		and TurnManager.now_player_index >= 0 \
		and TurnManager.now_player_index < TurnManager.players.size() \
		and TurnManager.players[TurnManager.now_player_index] == player
	if still_owns_view:
		btn_view_toggle.disabled = false
		var desired_focus_mode: bool = is_focus_mode if _profession_map_view_changed_by_user else _profession_map_restore_focus_mode
		if desired_focus_mode:
			_set_focus_mode(true)
			update_camera_view_for_player(player, 0.25)
		elif is_focus_mode:
			_leave_focus_at_current_camera()
	_profession_map_restore_focus_mode = false
	_profession_map_view_changed_by_user = false
	_profession_map_focus_player = null
	_profession_map_session_generation = -1
	_profession_map_turn_epoch = -1
	_profession_map_phase = TurnManager.TurnPhase.BEGIN
	if still_owns_view:
		_update_button_states(TurnManager.now_phase)

func _on_card_hand_visual_requested(kind: int, player: PlayerClass, card: 卡牌基类, other_player: PlayerClass, reveal_detail: bool) -> void:
	if card_hand_animator == null or not TurnManager.GameOn or GameManager.is_headless_simulation():
		return
	card_hand_animator.enqueue(kind, player, card, other_player, reveal_detail)

func _on_card_hand_animation_started(_kind: int, _player: PlayerClass, card: 卡牌基类) -> void:
	if card is 成就牌:
		return
	btn_action.disabled = true
	btn_food.disabled = true
	btn_end_turn.disabled = true

func _on_card_hand_queue_finished() -> void:
	_update_button_states(TurnManager.now_phase)

func wait_for_card_hand_animations() -> void:
	while card_hand_animator != null and card_hand_animator.is_busy():
		await card_hand_animator.queue_finished

func get_player_card_anchor(player: PlayerClass) -> Vector2:
	if player == null or not is_instance_valid(player) or map_viewport == null or map_container == null:
		return map_container.get_global_rect().get_center() if map_container != null else Vector2(1280.0, 800.0)
	var viewport_position := map_viewport.get_canvas_transform() * player.global_position
	var viewport_size := Vector2(map_viewport.size)
	var display_scale := Vector2.ONE
	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		display_scale = map_container.size / viewport_size
	return map_container.get_global_rect().position + viewport_position * display_scale + Vector2(0.0, -72.0)

func get_hand_area_anchor(card: 卡牌基类) -> Vector2:
	if card is 食物牌:
		return btn_food.get_global_rect().get_center()
	return $"积分区域".get_global_rect().get_center()

func get_card_thumbnail_anchor(card: 卡牌基类) -> Vector2:
	var thumbnail := _find_card_thumbnail(feiyi_list, card)
	if thumbnail == null:
		thumbnail = _find_card_thumbnail(backpack_panel, card)
	return thumbnail.get_global_rect().get_center() if thumbnail != null else get_hand_area_anchor(card)

func set_card_thumbnail_hidden(card: 卡牌基类, hidden: bool) -> void:
	var thumbnail := _find_card_thumbnail(feiyi_list, card)
	if thumbnail != null:
		thumbnail.modulate.a = 0.0 if hidden else 1.0

func refresh_hand_after_animation(player: PlayerClass) -> void:
	if not _can_display_player(player):
		return
	refresh_feiyi_list(player)
	_update_player_stats(player)

func show_collected_feiyi_detail_and_wait(player: PlayerClass, card: 非遗牌) -> void:
	if not _can_display_player(player) or detail_panel == null:
		return
	detail_panel.show_detail(card, player)
	await detail_panel.detail_closed

func _find_card_thumbnail(root: Node, card: 卡牌基类) -> Control:
	if root == null or card == null:
		return null
	if root is 非遗牌缩略图 and (root as 非遗牌缩略图).card_data == card:
		return root as Control
	if root is 事件牌缩略图 and (root as 事件牌缩略图).card_data == card:
		return root as Control
	if root is Control and root.has_meta("card_data") and root.get_meta("card_data") == card:
		return root as Control
	for child: Node in root.get_children():
		var found := _find_card_thumbnail(child, card)
		if found != null:
			return found
	return null

func _on_game_finished(result: GameResult) -> void:
	if game_result_overlay != null:
		game_result_overlay.present(result)

func _on_result_return_to_main_menu() -> void:
	if game_result_overlay != null:
		game_result_overlay.reset_overlay(false)
	GameManager.return_to_main_menu()

func _on_result_quit_requested() -> void:
	if game_result_overlay != null:
		game_result_overlay.reset_overlay(false)
	get_tree().quit()

func _on_achievement_claimed(player: PlayerClass, card: 成就牌) -> void:
	if achievement_toast != null:
		achievement_toast.enqueue(card, player)
	if TurnManager.GameOn and TurnManager.now_player_index >= 0 and TurnManager.now_player_index < TurnManager.players.size():
		var current_player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
		if current_player == player:
			if card_hand_animator != null:
				card_hand_animator.enqueue(ResourceManager.CardHandVisualKind.获得, player, card, null, false, false)
			else:
				refresh_achievement_list(player)
		_update_player_stats(player)
	_update_game_informs("%s 达成【%s】，+%d分。" % [player.player_name, card.card_name, card.score_value])

func _on_achievement_destroyed(previous_owner: PlayerClass, card: 成就牌, _replacement: 成就牌) -> void:
	if previous_owner == null:
		return
	if TurnManager.GameOn and TurnManager.now_player_index >= 0 and TurnManager.now_player_index < TurnManager.players.size():
		var current_player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
		if current_player == previous_owner:
			refresh_achievement_list(previous_owner)
		_update_player_stats(previous_owner)
	_update_game_informs("%s 的【%s】已升级移除。" % [previous_owner.player_name, card.card_name])

func _on_score_label_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if TurnManager.GameOn and TurnManager.now_player_index >= 0 and TurnManager.now_player_index < TurnManager.players.size():
			score_overlay.open_for_player(TurnManager.players[TurnManager.now_player_index])
			get_viewport().set_input_as_handled()

func open_market_panel(player: PlayerClass) -> void:
	market_overlay.open_market(player)

func _on_retained_cards_changed(player: PlayerClass) -> void:
	if TurnManager.GameOn and TurnManager.now_player_index < TurnManager.players.size() and TurnManager.players[TurnManager.now_player_index] == player:
		refresh_event_list(player)

func _on_event_modal_opened(_player: PlayerClass, _card: 事件牌) -> void:
	btn_action.disabled = true
	btn_food.disabled = true
	btn_end_turn.disabled = true

func _on_event_modal_closed(_player: PlayerClass, _card: 事件牌, _summary: String) -> void:
	# 部分事件会直接改变玩家档案（例如“交换人生”的职业与立绘），
	# 不经过资源管理器的数值刷新链，因此在事件结算完成时统一刷新当前玩家信息。
	if TurnManager.GameOn and TurnManager.now_player_index >= 0 and TurnManager.now_player_index < TurnManager.players.size():
		var current_player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
		_update_player_stats(current_player)
		refresh_feiyi_list(current_player)
	_event_no_effect_pending = _summary.ends_with("无事发生！")
	if _event_no_effect_pending and _event_map_source_name.is_empty():
		if information != null:
			information.text += "\n无事发生！"
		_event_no_effect_pending = false
	_update_button_states(TurnManager.now_phase)

func _on_event_choice_requested(request: EventChoiceRequest) -> void:
	if request.presentation == EventChoiceRequest.Presentation.研究所:
		_event_map_source_name = request.source_name if not request.source_name.is_empty() else request.title
		current_status.text = "【%s】请选择非遗牌" % _event_map_source_name
		information.text = request.source_description if not request.source_description.is_empty() else request.prompt
		market_overlay.open_event_choice(request)
		return
	if request.kind not in [EventChoiceRequest.ChoiceKind.格子, EventChoiceRequest.ChoiceKind.玩家] or map == null:
		return
	var sections: Array[MapSection] = []
	if request.kind == EventChoiceRequest.ChoiceKind.格子:
		for option in request.options:
			if option is MapSection:
				sections.append(option as MapSection)
	else:
		for option in request.options:
			if not option is PlayerClass:
				continue
			var target_player := option as PlayerClass
			var target_section := map.grid_map.get(target_player.now_pos) as MapSection
			if target_section != null and not sections.has(target_section):
				sections.append(target_section)
	if sections.is_empty():
		return
	_active_event_map_request = request
	_event_map_selected_options.clear()
	_event_map_source_name = request.source_name if not request.source_name.is_empty() else request.title
	map.begin_event_section_choice(request.request_id, sections)
	btn_action.disabled = true
	btn_food.disabled = true
	btn_end_turn.disabled = true
	_event_map_restore_focus_mode = is_focus_mode
	if is_focus_mode:
		_leave_focus_at_current_camera()
	btn_view_toggle.disabled = true
	_update_event_map_choice_status()
	information.text = request.source_description if not request.source_description.is_empty() else request.prompt

func _on_event_map_section_selected(request_id: int, section: MapSection) -> void:
	if _active_event_map_request == null or request_id != _active_event_map_request.request_id:
		return
	var choice = section
	if _active_event_map_request.kind == EventChoiceRequest.ChoiceKind.玩家:
		choice = _get_player_option_at_section(_active_event_map_request, section)
	if choice == null:
		return
	if not _active_event_map_request.multiple:
		EventManager.submit_choice(request_id, choice)
		return
	if _event_map_selected_options.has(choice):
		_event_map_selected_options.erase(choice)
	else:
		_event_map_selected_options.append(choice)
	EventManager.submit_choice_preview(request_id, _event_map_selected_options)
	_update_event_map_choice_status()
	if _event_map_selected_options.size() >= _active_event_map_request.max_selections:
		EventManager.submit_choice(request_id, _event_map_selected_options.duplicate())

func _get_player_option_at_section(request: EventChoiceRequest, section: MapSection) -> PlayerClass:
	for option in request.options:
		if option is PlayerClass \
				and (option as PlayerClass).now_pos == section.location_index \
				and not _event_map_selected_options.has(option):
			return option as PlayerClass
	for option in request.options:
		if option is PlayerClass and (option as PlayerClass).now_pos == section.location_index:
			return option as PlayerClass
	return null


func _update_event_map_choice_status() -> void:
	if _active_event_map_request == null:
		return
	if _active_event_map_request.kind == EventChoiceRequest.ChoiceKind.玩家:
		if _active_event_map_request.multiple:
			current_status.text = "【%s】请选择玩家 %d/%d" % [
				_event_map_source_name,
				_event_map_selected_options.size(),
				_active_event_map_request.max_selections,
			]
		else:
			current_status.text = "【%s】请选择玩家" % _event_map_source_name
	else:
		current_status.text = "【%s】请选择移动终点" % _event_map_source_name

func _on_event_choice_resolved(request_id: int, _timed_out: bool) -> void:
	if market_overlay != null and market_overlay.is_event_choice_open(request_id):
		market_overlay.finish_event_choice(request_id)
		information.text = "【%s】结算中…" % _event_map_source_name
		return
	if _active_event_map_request == null or request_id != _active_event_map_request.request_id:
		return
	_finish_event_map_choice(request_id)
	information.text = "【%s】结算中…" % _event_map_source_name

func _on_event_interaction_finished(_player: PlayerClass) -> void:
	if market_overlay != null:
		market_overlay.finish_event_choice()
	if _active_event_map_request != null:
		_finish_event_map_choice(_active_event_map_request.request_id)
	if _event_map_source_name.is_empty():
		return
	if TurnManager.GameOn and TurnManager.now_player_index >= 0 and TurnManager.now_player_index < TurnManager.players.size():
		var current_player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
		_update_player_stats(current_player)
		_update_button_states(TurnManager.now_phase)
	information.text = "【%s】结算完成。" % _event_map_source_name
	if _event_no_effect_pending:
		information.text += "\n无事发生！"
	_event_no_effect_pending = false
	_event_map_source_name = ""

func _finish_event_map_choice(request_id: int) -> void:
	if map != null:
		map.end_event_section_choice(request_id)
	_active_event_map_request = null
	_event_map_selected_options.clear()
	btn_view_toggle.disabled = false
	if _event_map_restore_focus_mode:
		_set_focus_mode(true)
		update_camera_view(0.25)
	_event_map_restore_focus_mode = false
# 暴露给编辑器的变量，把你做好的 map.tscn 直接从底层文件系统拖到右侧面板的这个槽位里
@export var map_scene: PackedScene 

# 获取刚才建的那个 SubViewport 节点
@onready var map_viewport: SubViewport = $"地图/地图背景/SubViewportContainer/SubViewport"
@onready var map_container: SubViewportContainer = $"地图/地图背景/SubViewportContainer"
@onready var btn_close_game = $"BtnClose"

var map_instance:Node2D

func _spawn_map_in_hud():
	if map_scene:
		map_instance = map_scene.instantiate()
		map_viewport.add_child(map_instance)
		print("地图已成功嵌入 HUD 视口中！")
		_on_container_resized()
	else:
		push_error("HUD 没有配置地图场景！请在检查器中拖入 map.tscn")

func _on_container_resized():
	if not is_instance_valid(map_instance): return
	var ui_size = map_container.size
	
	# 计算全局视野的缩放比例
	var padded_size = MAP_REAL_SIZE + Vector2(margin_x * 2, margin_top + margin_bottom)
	var scale_factor = min(ui_size.x / padded_size.x, ui_size.y / padded_size.y)
	global_zoom = Vector2(scale_factor, scale_factor)
	
	# 计算带有留白的地图真实的几何中心点
	global_pos = Vector2(MAP_REAL_SIZE.x / 2.0, MAP_REAL_SIZE.y / 2.0 + (margin_bottom - margin_top) / 2.0)
	if _global_camera_position == Vector2.ZERO:
		_global_camera_position = global_pos
	
	map_instance.scale = Vector2(1.0, 1.0)
	map_instance.position = Vector2(0, 0)
	
	# 刷新当前镜头
	update_camera_view(0.0)

func _on_view_toggle_pressed():
	if _profession_map_focus_player != null:
		_profession_map_view_changed_by_user = true
	if is_focus_mode:
		_leave_focus_at_current_camera()
	else:
		_set_focus_mode(true)
		map_zoom_factor = get_focus_entry_zoom_factor(map_zoom_factor)
	update_camera_view(0.4) # 0.4 秒的顺滑运镜动画

func _leave_focus_at_current_camera() -> void:
	if not is_focus_mode:
		return
	# 手动切换和地图选点共用同一路径：只解除追踪，不跳回旧全局中心。
	# 先终止可能尚未完成的追踪 Tween，再以屏幕上的实时位置和缩放保存全局镜头状态。
	_stop_camera_tween()
	if is_instance_valid(map_camera) and global_zoom.x > 0.0 and global_zoom.y > 0.0:
		_global_camera_position = _clamp_camera_position(map_camera.position, map_camera.zoom)
	_set_focus_mode(false)

func _set_focus_mode(value: bool) -> void:
	is_focus_mode = value
	_update_view_mode_hint()

func _update_view_mode_hint() -> void:
	var hint_label := get_node_or_null("地图/缩放提示信息") as Label
	if hint_label != null:
		hint_label.text = get_view_mode_hint_text(is_focus_mode)

func update_camera_view(duration: float = 0.4):
	var target_zoom := global_zoom * map_zoom_factor
	var target_pos := _global_camera_position
	if is_focus_mode:
		var focus_player: PlayerClass = _camera_focus_player_override
		if focus_player == null and TurnManager.now_player_index >= 0 and TurnManager.now_player_index < TurnManager.players.size():
			focus_player = TurnManager.players[TurnManager.now_player_index]
		target_pos = focus_player.position if is_instance_valid(focus_player) else global_pos
	target_pos = _clamp_camera_position(target_pos, target_zoom)
	_stop_camera_tween()
	# 创建并行动画：同时平滑缩放(zoom)和移动(position)
	if duration > 0:
		_camera_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_camera_tween.tween_property(map_camera, "zoom", target_zoom, duration)
		_camera_tween.tween_property(map_camera, "position", target_pos, duration)
	else:
		map_camera.zoom = target_zoom
		map_camera.position = target_pos

func update_camera_view_for_player(player: PlayerClass, duration: float = 0.4) -> void:
	_camera_focus_player_override = player
	update_camera_view(duration)
	_camera_focus_player_override = null

func _stop_camera_tween() -> void:
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = null

func _on_map_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_apply_map_zoom(map_zoom_factor * MAP_ZOOM_STEP, event.position)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_apply_map_zoom(map_zoom_factor / MAP_ZOOM_STEP, event.position)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not is_focus_mode:
				_map_drag_candidate = true
				_map_dragging = false
				_map_drag_distance = 0.0
			elif not event.pressed:
				if _map_dragging:
					_suppress_map_click_until_msec = Time.get_ticks_msec() + 80
				_map_drag_candidate = false
				_map_dragging = false
	elif event is InputEventMouseMotion and _map_drag_candidate and not is_focus_mode:
		_map_drag_distance += event.relative.length()
		if _map_drag_distance >= MAP_DRAG_THRESHOLD:
			_map_dragging = true
		if _map_dragging:
			_hovered_map_section = null
			_map_tooltip_timer.stop()
			_map_tooltip.hide()
			_stop_camera_tween()
			var target: Vector2 = map_camera.position - event.relative / map_camera.zoom
			_global_camera_position = _clamp_camera_position(target, map_camera.zoom)
			map_camera.position = _global_camera_position
			get_viewport().set_input_as_handled()

func _apply_map_zoom(new_factor: float, mouse_position: Vector2) -> void:
	var clamped_factor := clamp_map_zoom_factor(new_factor)
	if is_equal_approx(clamped_factor, map_zoom_factor):
		return
	_stop_camera_tween()
	var old_zoom: Vector2 = map_camera.zoom
	var new_zoom := global_zoom * clamped_factor
	if is_focus_mode:
		map_zoom_factor = clamped_factor
		update_camera_view(0.12)
		return
	var viewport_center: Vector2 = map_container.size * 0.5
	var world_under_mouse: Vector2 = map_camera.position + (mouse_position - viewport_center) / old_zoom
	var target_position: Vector2 = world_under_mouse - (mouse_position - viewport_center) / new_zoom
	map_zoom_factor = clamped_factor
	_global_camera_position = _clamp_camera_position(target_position, new_zoom)
	map_camera.zoom = new_zoom
	map_camera.position = _global_camera_position

func _clamp_camera_position(target: Vector2, zoom_value: Vector2) -> Vector2:
	if zoom_value.x <= 0.0 or zoom_value.y <= 0.0:
		return global_pos
	var half_visible := Vector2(map_viewport.size) * 0.5 / zoom_value
	var min_position := Vector2(-margin_x, -margin_top) + half_visible
	var max_position := Vector2(MAP_REAL_SIZE.x + margin_x, MAP_REAL_SIZE.y + margin_bottom) - half_visible
	var result := target
	result.x = global_pos.x if min_position.x > max_position.x else clampf(target.x, min_position.x, max_position.x)
	result.y = global_pos.y if min_position.y > max_position.y else clampf(target.y, min_position.y, max_position.y)
	return result

func should_suppress_map_section_click() -> bool:
	return _map_dragging or Time.get_ticks_msec() <= _suppress_map_click_until_msec

func _setup_map_tooltip() -> void:
	_map_tooltip_timer = Timer.new()
	_map_tooltip_timer.one_shot = true
	_map_tooltip_timer.wait_time = MAP_TOOLTIP_DELAY
	_map_tooltip_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	_map_tooltip_timer.timeout.connect(_show_map_tooltip)
	add_child(_map_tooltip_timer)
	_map_tooltip = PanelContainer.new()
	_map_tooltip.name = "地图格信息"
	_map_tooltip.z_index = 30
	_map_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.96, 0.86, 0.68, 0.97)
	panel_style.border_color = Color(0.42, 0.22, 0.14, 1.0)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 18
	panel_style.content_margin_right = 18
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 12
	_map_tooltip.add_theme_stylebox_override("panel", panel_style)
	_map_tooltip_label = Label.new()
	_map_tooltip_label.add_theme_font_override("font", default_font)
	_map_tooltip_label.add_theme_font_size_override("font_size", 30)
	_map_tooltip_label.add_theme_color_override("font_color", Color(0.26, 0.14, 0.09))
	_map_tooltip.add_child(_map_tooltip_label)
	add_child(_map_tooltip)
	_map_tooltip.hide()

func request_map_section_tooltip(section: MapSection) -> void:
	_hovered_map_section = section
	_map_tooltip.hide()
	_map_tooltip_timer.start(MAP_TOOLTIP_DELAY)

func cancel_map_section_tooltip(section: MapSection) -> void:
	if _hovered_map_section != section:
		return
	_hovered_map_section = null
	_map_tooltip_timer.stop()
	_map_tooltip.hide()

func _show_map_tooltip() -> void:
	if not is_instance_valid(_hovered_map_section):
		return
	_map_tooltip_label.text = _get_map_section_tooltip_text(_hovered_map_section)
	_map_tooltip.show()
	_position_map_tooltip()

func _position_map_tooltip() -> void:
	if _map_tooltip == null or not _map_tooltip.visible:
		return
	var mouse_position := get_viewport().get_mouse_position()
	var target := mouse_position + Vector2(24, 28)
	var viewport_size := get_viewport().get_visible_rect().size
	_map_tooltip.reset_size()
	target.x = minf(target.x, viewport_size.x - _map_tooltip.size.x - 12)
	target.y = minf(target.y, viewport_size.y - _map_tooltip.size.y - 12)
	_map_tooltip.position = target

func _get_map_section_tooltip_text(section: MapSection) -> String:
	return "%s\nF1：相关规则" % section.get_tooltip_text()

func _process(delta: float):
	if _active_event_map_request != null:
		var choice_time_left := EventManager.get_choice_time_left(_active_event_map_request.request_id)
		time_label.visible = choice_time_left > 0.0
		time_label.text = " " + str(int(ceil(choice_time_left))) + " s"
	elif _active_profession_map_request != null:
		var choice_time_left := ProfessionManager.get_section_choice_time_left(_active_profession_map_request.request_id)
		time_label.visible = choice_time_left > 0.0
		time_label.text = " " + str(int(ceil(choice_time_left))) + " s"
	elif timer and TurnManager.GameOn and timer.time_left > 0:
		time_label.visible = true
		time_label.text = " " + str(int(ceil(timer.time_left))) + " s"
	else:
		time_label.visible = false
	_position_map_tooltip()
	
func _on_turn_start(player_idx: int) -> void:
	var current_player = TurnManager.players[player_idx]
	turn_label.text = "回合数：" + str(TurnManager.now_turn) + " 当前玩家：" + current_player.player_name
	_update_player_stats(current_player)
	refresh_feiyi_list(current_player)

func _on_phase_changed(new_phase: TurnManager.TurnPhase) -> void:
	_clear_dice_information_connection()
	# 每次阶段改变时，刷新 UI 上的数值和按钮可用性
	var current_player = TurnManager.players[TurnManager.now_player_index]
	_update_player_stats(current_player)
	_update_button_states(new_phase)
	refresh_event_list(current_player)
	
	match new_phase:
		TurnManager.TurnPhase.BEGIN:
			information.text = "等待中…"
			phase_label.text = "【准备阶段】"
		TurnManager.TurnPhase.ROLL_DICE:
			phase_label.text = "【掷骰子】"
			_dice_signal_player = TurnManager.players[TurnManager.now_player_index]
			_dice_signal_player.roll_dice.connect(_roll_dice_information, CONNECT_ONE_SHOT)
		TurnManager.TurnPhase.MOVING:
			phase_label.text = "【移动中】"
		TurnManager.TurnPhase.ACTION:
			phase_label.text = "【行动阶段】"
			# TODO: 这里需要根据玩家当前踩的格子类型，动态改变 btn_action 的文字（如“打工”、“抽取非遗”）
		TurnManager.TurnPhase.END:
			phase_label.text = "【结束阶段】"

func _roll_dice_information(result:int, player:PlayerClass) -> void:
	_dice_signal_player = null
	_update_game_informs("玩家 " + player.player_name + " 掷出了 " + str(result) + " 点！")

var _dice_signal_player: PlayerClass = null

func _clear_dice_information_connection() -> void:
	if _dice_signal_player != null and is_instance_valid(_dice_signal_player) \
			and _dice_signal_player.roll_dice.is_connected(_roll_dice_information):
		_dice_signal_player.roll_dice.disconnect(_roll_dice_information)
	_dice_signal_player = null

# --- UI 刷新状态函数 ---
func _update_player_stats(player: PlayerClass) -> void:
	if player == null:
		return
	# 地图上的棋子分数徽章属于玩家自身，不是共享 HUD；后台玩家也必须实时更新。
	if player.score_label != null and is_instance_valid(player.score_label):
		player.score_label.text = str(player.current_score)
	if not _can_display_player(player):
		return
	money_label.text = str(player.current_money)
	energy_label.text = str(player.current_energy) + "/" + str(player.max_energy)
	score_label.text = "总分数：%d / %d" % [player.current_score, TurnManager.target_score]
	name_label.text = player.player_name
	立绘精二.texture = player.立绘精二
	var profession_label := $"玩家信息/职业背景/职业" as Label
	profession_label.text = PlayerClass.PlayerCharacter.find_key(player.player_types)
	profession_label.add_theme_color_override(
		"font_color",
		Color("8c7568") if ProfessionManager.get_blocked_turns(player) > 0 else Color.BLACK
	)
	current_status.text = "当前位置：" + MapSection.REGION.find_key(map.grid_map[player.now_pos].region) + str(map.grid_map[player.now_pos].location_index) + " - " + MapSection.SectionType.find_key(map.grid_map[player.now_pos].type)
	if(TurnManager.now_phase == TurnManager.TurnPhase.MOVING):
		_update_game_informs("剩余可移动：" + str(player.maxMove) + " 步")

func _update_game_informs(information_to_display: String) -> void:
	information.text = information_to_display

func _update_button_states(phase: TurnManager.TurnPhase) -> void:
	# 核心解耦：UI 自己决定什么时候按钮该亮起
	btn_action.disabled = (phase != TurnManager.TurnPhase.ACTION)
	btn_end_turn.disabled = (not phase in [TurnManager.TurnPhase.ACTION, TurnManager.TurnPhase.MOVING])
	btn_food.disabled = (phase != TurnManager.TurnPhase.ACTION)
	if TurnManager.is_movement_locked():
		btn_action.disabled = true
		btn_end_turn.disabled = true
		btn_food.disabled = true
		return

	var current_player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
	var current_coord: Vector3i = current_player.now_pos
	
	if not map.grid_map.has(current_coord): return
	var current_section = map.grid_map[current_coord]
	
	if phase == TurnManager.TurnPhase.ACTION:
		match current_section.type: # 注意你定义的枚举变量名叫 type
			MapSection.SectionType.非遗:
				# 获取玩家当前脚下格子属于哪个市区（字符串）
				var region: MapSection.REGION = current_section.region
				
				btn_action.text = "收集非遗"
				
				# 判定一：如果该地区根本没有牌了
				if not ResourceManager.has_feiyi_in_region(region):
					btn_action.text = "集罄"
					btn_action.disabled = true
				# 判定二：精力不足或本回合已收集
				elif current_player.current_energy < 1 or current_player.feiyi_collected_this_turn:
					btn_action.disabled = true
				else: btn_action.disabled = false
					
			MapSection.SectionType.打工:
				btn_action.text = "打工"
				var work_energy_cost: int = ProfessionManager.get_work_energy_cost(current_player)
				if EventManager.is_work_banned(current_player):
					btn_action.text = "暂时禁止打工"
					btn_action.disabled = true
				elif current_player.current_energy < work_energy_cost:
					btn_action.disabled = true
				# 历史打过工，且现在并不在打工状态中，则终生禁止在此地再次打工
				elif current_section.grid_visit_history.get(current_player, 0) > 1 and not current_player.is_working:
					btn_action.disabled = true
				elif current_player.now_turn_worked:
					btn_action.disabled = true
				else: btn_action.disabled = false
					
			MapSection.SectionType.商店:
				btn_action.text = "打开商店"
				btn_action.disabled = not current_player.has_current_action_arrival_at(current_player.now_pos) \
					or current_player.last_opened_shop_arrival_id == current_player.arrival_id
					
			MapSection.SectionType.风景:
				btn_action.text = "行动"
				btn_action.disabled = true # 风景是自动的，手动按钮一直禁用
			MapSection.SectionType.研究所:
				btn_action.text = "交易"
				btn_action.disabled = not current_player.has_current_action_arrival_at(current_player.now_pos) \
					or not MarketManager.can_open_visit(current_player, current_player.arrival_id)
			_:
				btn_action.text = "探索"
				btn_action.disabled = true
	else: btn_action.text = "探索"

func _on_btn_action_pressed() -> void:
	if _active_profession_map_request != null and _active_profession_map_request.optional:
		ProfessionManager.submit_section_choice(_active_profession_map_request.request_id, null)
		return
	var current_player = TurnManager.players[TurnManager.now_player_index]
	current_player.execute_tile_action()

func _on_btn_end_turn_pressed() -> void:
	var current_player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
	if current_player.is_working:
		btn_end_turn.disabled = true
		btn_action.disabled = true
		btn_food.disabled = true
		await current_player.check_and_cancel_work()
		
	if TurnManager.now_phase == TurnManager.TurnPhase.MOVING:
		current_player.emit_next_phase(TurnManager.TurnPhase.ACTION)
	elif TurnManager.now_phase == TurnManager.TurnPhase.ACTION:
		current_player.emit_next_phase(TurnManager.TurnPhase.END)

func _on_btn_food_pressed() -> void:
	var current_player = TurnManager.players[TurnManager.now_player_index]
	if current_player.is_working:
		await current_player.check_and_cancel_work()
		
	backpack_panel.open_backpack(current_player)

func open_shop_panel(player:PlayerClass):
	$"商店弹窗".open_shop(player)

# 预加载你刚才做好的两个组件
const ThumbnailScene = preload("res://HUDs/非遗牌缩略图.tscn")
const DetailPanelScene = preload("res://HUDs/非遗详情弹窗.tscn")
const EventThumbnailScene = preload("res://HUDs/事件牌缩略图.tscn")
const AchievementThumbnailScene = preload("res://HUDs/成就牌缩略图.tscn")

@onready var feiyi_list = $"积分区域/ScrollContainer/非遗列表容器"
@onready var detail_panel = $"非遗详情弹窗" 

# 刷新右侧非遗列表（回合开始、或者抽到新卡时调用）
func refresh_feiyi_list(player: PlayerClass):
	if not _can_display_player(player):
		return
	# 1. 清空旧列表
	for child in feiyi_list.get_children():
		feiyi_list.remove_child(child)
		child.queue_free()
		
	# 2. 按城市将手牌分组
	var city_groups: Dictionary[MapSection.REGION, Array] = {}
	for card in player.非遗牌手牌:
		if card_hand_animator != null and card_hand_animator.should_hide_card(card):
			continue
		if not city_groups.has(card.region):
			city_groups[card.region] = []
		city_groups[card.region].append(card)
		
	var score_breakdown := ResourceManager.get_score_breakdown(player)
	var region_annotations: Dictionary = score_breakdown.get("region_annotations", {})
	# 3. 动态生成 UI
	for city_int in city_groups.keys():
		# 生成城市标题
		var city_name = MapSection.REGION.keys()[city_int]
		var city_label = Label.new()
		city_label.text = "== " + city_name + " =="
		city_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER # 文本居中
		var title_color: Color = REGION_TITLE_COLORS.get(city_int, Color.BLACK)
		city_label.add_theme_color_override("font_color", title_color)
		city_label.add_theme_color_override("font_outline_color", title_color.darkened(0.55))
		city_label.add_theme_constant_override("outline_size", 2)
		city_label.add_theme_font_size_override("font_size", 64)
		city_label.add_theme_font_override("font", default_font)
		feiyi_list.add_child(city_label)
		
		# 生成该城市下的卡牌网格 (2列)
		var grid = GridContainer.new()
		grid.columns = 2
		# 用代码强行设定网格间距
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		
		feiyi_list.add_child(grid)
		
		for card in city_groups[ResourceManager.STRING_TO_REGION[city_name]]:
			var thumbnail = ThumbnailScene.instantiate()
			grid.add_child(thumbnail)
			thumbnail.setup(card)
			
			# 连接缩略图发出的信号
			thumbnail.request_open_detail.connect(func(c): detail_panel.show_detail(c, player))
			thumbnail.request_use_card.connect(_execute_card_usage)

		if region_annotations.has(city_int):
			var score_hint := Label.new()
			score_hint.text = "\n".join(region_annotations[city_int])
			score_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			score_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			score_hint.add_theme_color_override("font_color", title_color.darkened(0.25))
			score_hint.add_theme_font_size_override("font_size", 30)
			score_hint.add_theme_font_override("font", default_font)
			feiyi_list.add_child(score_hint)
			
		# 生成城市间的分界线
		feiyi_list.add_child(HSeparator.new())
	refresh_event_list(player)

func refresh_event_list(player: PlayerClass) -> void:
	if not _can_display_player(player):
		return
	var previous_section := feiyi_list.get_node_or_null("事件牌列表区")
	if previous_section != null:
		feiyi_list.remove_child(previous_section)
		previous_section.queue_free()
	var previous_achievement_section := feiyi_list.get_node_or_null("成就牌列表区")
	if previous_achievement_section != null:
		feiyi_list.remove_child(previous_achievement_section)
		previous_achievement_section.queue_free()
	var visible_event_cards: Array[事件牌] = []
	for card: 事件牌 in player.事件牌手牌:
		if card_hand_animator == null or not card_hand_animator.should_hide_card(card):
			visible_event_cards.append(card)
	if not visible_event_cards.is_empty():
		var event_section := VBoxContainer.new()
		event_section.name = "事件牌列表区"
		event_section.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		feiyi_list.add_child(event_section)
		var title := Label.new()
		title.text = "事件牌"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_color_override("font_color", Color.BLACK)
		title.add_theme_font_size_override("font_size", 64)
		title.add_theme_font_override("font", default_font)
		event_section.add_child(title)
		var event_card_list := GridContainer.new()
		event_card_list.columns = 2
		event_card_list.add_theme_constant_override("h_separation", 10)
		event_card_list.add_theme_constant_override("v_separation", 10)
		event_section.add_child(event_card_list)
		for card: 事件牌 in visible_event_cards:
			var thumbnail := EventThumbnailScene.instantiate() as 事件牌缩略图
			event_card_list.add_child(thumbnail)
			thumbnail.setup(card, player)
			thumbnail.request_open_detail.connect(_open_event_card_detail.bind(player))
			thumbnail.request_use_card.connect(_request_event_card_use.bind(player))
	refresh_achievement_list(player)

func refresh_achievement_list(player: PlayerClass) -> void:
	if not _can_display_player(player):
		return
	var previous_section := feiyi_list.get_node_or_null("成就牌列表区")
	if previous_section != null:
		feiyi_list.remove_child(previous_section)
		previous_section.queue_free()
	var achievements: Array[成就牌] = AchievementManager.get_owned_achievements(player)
	var visible_achievements: Array[成就牌] = []
	for card: 成就牌 in achievements:
		if card_hand_animator == null or not card_hand_animator.should_hide_card(card):
			visible_achievements.append(card)
	if visible_achievements.is_empty():
		return
	var section := VBoxContainer.new()
	section.name = "成就牌列表区"
	section.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	feiyi_list.add_child(section)
	var separator := HSeparator.new()
	section.add_child(separator)
	var title := Label.new()
	title.name = "标题"
	title.text = "成就"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.55, 0.28, 0.11, 1))
	title.add_theme_color_override("font_outline_color", Color(0.31, 0.13, 0.05, 1))
	title.add_theme_constant_override("outline_size", 2)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_font_override("font", default_font)
	section.add_child(title)
	var grid := GridContainer.new()
	grid.name = "卡牌列表"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	section.add_child(grid)
	for card: 成就牌 in visible_achievements:
		var thumbnail := AchievementThumbnailScene.instantiate() as 成就牌缩略图
		grid.add_child(thumbnail)
		thumbnail.setup(card)
		thumbnail.request_open_detail.connect(_open_achievement_detail)

## 左右两侧是同一份“当前回合玩家”HUD，任何后台目标都不能直接覆盖它。
## GameOn=false 时保留场景预览和独立 UI 测试按指定玩家渲染的能力。
func _can_display_player(player: PlayerClass) -> bool:
	if player == null:
		return false
	if not TurnManager.GameOn:
		return true
	if TurnManager.now_player_index < 0 or TurnManager.now_player_index >= TurnManager.players.size():
		return false
	return TurnManager.players[TurnManager.now_player_index] == player

func _open_achievement_detail(card: 成就牌) -> void:
	if achievement_detail_overlay != null:
		achievement_detail_overlay.show_detail(card)

func _refresh_current_event_list() -> void:
	if TurnManager.GameOn and TurnManager.now_player_index >= 0 and TurnManager.now_player_index < TurnManager.players.size():
		refresh_event_list(TurnManager.players[TurnManager.now_player_index])

func _open_event_card_detail(card_data: 事件牌, player: PlayerClass) -> void:
	event_overlay.show_retained_card_detail(player, card_data)

func _request_event_card_use(card_data: 事件牌, player: PlayerClass) -> void:
	if not EventManager.can_play_retained_event_now(card_data, player):
		_update_game_informs(EventManager.get_retained_event_usage_hint(card_data, player))
		return
	EventManager.request_play_retained_event(player, card_data)

# 统一处理卡牌使用逻辑（途径1：右键菜单，途径2：弹窗点击）
func _execute_card_usage(card_data: 非遗牌) -> void:
	if not TurnManager.GameOn or TurnManager.now_player_index >= TurnManager.players.size():
		return
	var player: PlayerClass = TurnManager.players[TurnManager.now_player_index]
	print(player.player_name, " 主动使用了卡牌：", card_data.card_name)
	ResourceManager.use_feiyi(player, card_data)

# 途径3：被动/触发型卡牌的询问接口（留给 TurnManager 或 Player 脚本在特定时机调用）
func prompt_passive_card_use(card_data: 非遗牌, callable_if_yes: Callable):
	# 这里你可以唤起一个系统的 ConfirmationDialog 询问玩家
	print("询问：是否要发动被动技能【", card_data.card_name, "】？")
	# 如果玩家点是：callable_if_yes.call()

func _on_close_pressed():
	get_tree().paused = false
	print("退出游戏")
	get_tree().quit(0)
