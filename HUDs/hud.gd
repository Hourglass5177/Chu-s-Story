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

const MAP_ZOOM_MIN_FACTOR := 1.0
const MAP_ZOOM_MAX_FACTOR := 3.0
const MAP_ZOOM_STEP := 1.15
const MAP_DRAG_THRESHOLD := 8.0
const MAP_TOOLTIP_DELAY := 0.6

static func clamp_map_zoom_factor(value: float) -> float:
	return clampf(value, MAP_ZOOM_MIN_FACTOR, MAP_ZOOM_MAX_FACTOR)

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
const EVENT_OVERLAY_SCENE := preload("res://HUDs/event_overlay.tscn")
const MARKET_OVERLAY_SCENE := preload("res://HUDs/研究所弹窗.tscn")
const SCORE_OVERLAY_SCENE := preload("res://HUDs/计分详情弹窗.tscn")
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
	map_container.gui_input.connect(_on_map_container_gui_input)
	_setup_event_ui()
	_setup_market_ui()
	_setup_score_ui()
	_setup_map_tooltip()
	score_label.mouse_filter = Control.MOUSE_FILTER_STOP
	score_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	score_label.gui_input.connect(_on_score_label_gui_input)
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

func _setup_event_ui() -> void:
	event_overlay = EVENT_OVERLAY_SCENE.instantiate() as EventOverlay
	add_child(event_overlay)
	EventManager.retained_cards_changed.connect(_on_retained_cards_changed)
	EventManager.event_revealed.connect(_on_event_modal_opened)
	EventManager.event_finished.connect(_on_event_modal_closed)

func get_event_overlay() -> EventOverlay:
	return event_overlay

func _setup_market_ui() -> void:
	market_overlay = MARKET_OVERLAY_SCENE.instantiate() as 研究所弹窗
	add_child(market_overlay)

func _setup_score_ui() -> void:
	score_overlay = SCORE_OVERLAY_SCENE.instantiate() as ScoreDetailPanel
	add_child(score_overlay)

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
		_update_player_stats(TurnManager.players[TurnManager.now_player_index])
	_update_button_states(TurnManager.now_phase)
	call_deferred("_refresh_current_event_list")
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
	is_focus_mode = not is_focus_mode
	update_camera_view(0.4) # 0.4 秒的顺滑运镜动画

func update_camera_view(duration: float = 0.4):
	var target_zoom := global_zoom * map_zoom_factor
	var target_pos := _global_camera_position
	if is_focus_mode:
		if TurnManager.now_player_index >= 0 and TurnManager.now_player_index < TurnManager.players.size():
			var current_player = TurnManager.players[TurnManager.now_player_index]
			target_pos = current_player.position if is_instance_valid(current_player) else global_pos
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
	return section.get_tooltip_text()

func _process(delta: float):
	if timer and TurnManager.GameOn and timer.time_left > 0:
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
			TurnManager.players[TurnManager.now_player_index].roll_dice.connect(_roll_dice_information)
			await TurnManager.players[TurnManager.now_player_index].roll_dice
			TurnManager.players[TurnManager.now_player_index].roll_dice.disconnect(_roll_dice_information)
		TurnManager.TurnPhase.MOVING:
			phase_label.text = "【移动中】"
		TurnManager.TurnPhase.ACTION:
			phase_label.text = "【行动阶段】"
			# TODO: 这里需要根据玩家当前踩的格子类型，动态改变 btn_action 的文字（如“打工”、“抽取非遗”）
		TurnManager.TurnPhase.END:
			phase_label.text = "【结束阶段】"

func _roll_dice_information(result:int, player:PlayerClass) -> void:
	_update_game_informs("玩家 " + player.player_name + " 掷出了 " + str(result) + " 点！")

# --- UI 刷新状态函数 ---
func _update_player_stats(player: PlayerClass) -> void:
	money_label.text = str(player.current_money)
	energy_label.text = str(player.current_energy) + "/" + str(player.max_energy)
	score_label.text = "总分数：" + str(player.current_score) + "分"
	player.score_label.text = str(player.current_score)
	name_label.text = player.player_name
	立绘精二.texture = player.立绘精二
	$"玩家信息/职业背景/职业".text = PlayerClass.PlayerCharacter.find_key(player.player_types)
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
					btn_action.text = "已被收集完"
					btn_action.disabled = true
				# 判定二：精力不足或本回合已收集
				elif current_player.current_energy < 1 or current_player.feiyi_collected_this_turn:
					btn_action.disabled = true
				else: btn_action.disabled = false
					
			MapSection.SectionType.打工:
				btn_action.text = "打工"
				if EventManager.is_work_banned(current_player):
					btn_action.text = "暂时禁止打工"
					btn_action.disabled = true
				elif current_player.current_energy < 1:
					btn_action.disabled = true
				# 历史打过工，且现在并不在打工状态中，则终生禁止在此地再次打工
				elif current_section.grid_visit_history.get(current_player, 0) > 1 and not current_player.is_working:
					btn_action.disabled = true
				elif current_player.now_turn_worked:
					btn_action.disabled = true
				else: btn_action.disabled = false
					
			MapSection.SectionType.商店:
				btn_action.text = "打开商店"
				# 买过一次就禁止再买
				if current_section.grid_visit_history.get(current_player, 0) > 1:
					btn_action.disabled = true
				else: btn_action.disabled = false
					
			MapSection.SectionType.风景:
				btn_action.text = "行动"
				btn_action.disabled = true # 风景是自动的，手动按钮一直禁用
				if current_section.grid_visit_history.get(current_player, 0) <= 1:
					current_player.auto_trigger_scenery(current_section) 
			MapSection.SectionType.研究所:
				btn_action.text = "交易"
				btn_action.disabled = current_player.arrival_id <= 0 \
					or current_player.last_normal_arrival_position != current_player.now_pos \
					or not MarketManager.can_open_visit(current_player, current_player.arrival_id)
			_:
				btn_action.text = "探索"
				btn_action.disabled = true
	else: btn_action.text = "探索"

func _on_btn_action_pressed() -> void:
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

@onready var feiyi_list = $"积分区域/ScrollContainer/非遗列表容器"
@onready var detail_panel = $"非遗详情弹窗" 

# 刷新右侧非遗列表（回合开始、或者抽到新卡时调用）
func refresh_feiyi_list(player: PlayerClass):
	# 1. 清空旧列表
	for child in feiyi_list.get_children():
		child.queue_free()
		
	# 2. 按城市将手牌分组
	var city_groups: Dictionary[MapSection.REGION, Array] = {}
	for card in player.非遗牌手牌:
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
			await get_tree().process_frame
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
	var previous_section := feiyi_list.get_node_or_null("事件牌列表区")
	if previous_section != null:
		feiyi_list.remove_child(previous_section)
		previous_section.queue_free()
	if player.事件牌手牌.is_empty():
		return
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
	for card: 事件牌 in player.事件牌手牌:
		var thumbnail := EventThumbnailScene.instantiate() as 事件牌缩略图
		event_card_list.add_child(thumbnail)
		thumbnail.setup(card, player)
		thumbnail.request_open_detail.connect(_open_event_card_detail.bind(player))
		thumbnail.request_use_card.connect(_request_event_card_use.bind(player))

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
