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

# 之前我们算好的留白参数，原封不动保留
const MAP_REAL_SIZE = Vector2(2560, 1600)
const margin_top = 250.0 - 250
const margin_bottom = 100.0 - 100
const margin_x = 50.0 - 50

var map:MAP
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
# 暴露给编辑器的变量，把你做好的 map.tscn 直接从底层文件系统拖到右侧面板的这个槽位里
@export var map_scene: PackedScene 

# 获取刚才建的那个 SubViewport 节点
@onready var map_viewport = $"地图/地图背景/SubViewportContainer/SubViewport"
@onready var map_container = $"地图/地图背景/SubViewportContainer"
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
	
	map_instance.scale = Vector2(1.0, 1.0)
	map_instance.position = Vector2(0, 0)
	
	# 刷新当前镜头
	update_camera_view(0.0)

func _on_view_toggle_pressed():
	is_focus_mode = not is_focus_mode
	update_camera_view(0.4) # 0.4 秒的顺滑运镜动画

func update_camera_view(duration: float = 0.4):
	var target_zoom: Vector2
	var target_pos: Vector2
	
	if is_focus_mode:
		# 聚焦时，镜头放大到全局的 2 倍（你可以根据美术素材精细度改为 1.5 或 2.5）
		target_zoom = global_zoom * 2.0
		
		# 自动寻找当前回合玩家的坐标
		var current_player = TurnManager.players[TurnManager.now_player_index]
		target_pos = current_player.position if is_instance_valid(current_player) else global_pos
	else:
		target_zoom = global_zoom
		target_pos = global_pos
		
	# 创建并行动画：同时平滑缩放(zoom)和移动(position)
	if duration > 0:
		var tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(map_camera, "zoom", target_zoom, duration)
		tween.tween_property(map_camera, "position", target_pos, duration)
	else:
		map_camera.zoom = target_zoom
		map_camera.position = target_pos

func _process(delta: float):
	if timer and TurnManager.GameOn and timer.time_left > 0:
		time_label.visible = true
		time_label.text = " " + str(int(ceil(timer.time_left))) + " s"
	else:
		time_label.visible = false
	
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
	score_label.text = "总分数: " + str(player.current_score)
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
				if current_player.current_energy < 1:
					btn_action.disabled = true
				# 历史打过工，且现在并不在打工状态中，则终生禁止在此地再次打工
				elif current_section.grid_visit_history[current_player] > 1 and not current_player.is_working:
					btn_action.disabled = true
				elif current_player.now_turn_worked:
					btn_action.disabled = true
				else: btn_action.disabled = false
					
			MapSection.SectionType.商店:
				btn_action.text = "打开商店"
				# 买过一次就禁止再买
				if current_section.grid_visit_history[current_player] > 1:
					btn_action.disabled = true
				else: btn_action.disabled = false
					
			MapSection.SectionType.风景:
				btn_action.text = "行动"
				btn_action.disabled = true # 风景是自动的，手动按钮一直禁用
				if current_section.grid_visit_history[current_player] <= 1:
					current_player.auto_trigger_scenery(current_section) 
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
		
	# 3. 动态生成 UI
	for city_int in city_groups.keys():
		# 生成城市标题
		var city_name = MapSection.REGION.keys()[city_int]
		var city_label = Label.new()
		city_label.text = "== " + city_name + " =="
		city_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER # 文本居中
		city_label.add_theme_color_override("font_color", Color.BLACK) # 字体设为纯黑
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
			
		# 生成城市间的分界线
		feiyi_list.add_child(HSeparator.new())

# 统一处理卡牌使用逻辑（途径1：右键菜单，途径2：弹窗点击）
func _execute_card_usage(card_data: 非遗牌):
	var player = TurnManager.players[TurnManager.now_player_index]
	print(player.player_name, " 主动使用了卡牌：", card_data.card_name)
	card_data.execute_effect(player)
	
	# 使用完后可能需要从手牌移除（视规则而定）
	# player.非遗牌手牌.erase(card_data)
	# refresh_feiyi_list(player)

# 途径3：被动/触发型卡牌的询问接口（留给 TurnManager 或 Player 脚本在特定时机调用）
func prompt_passive_card_use(card_data: 非遗牌, callable_if_yes: Callable):
	# 这里你可以唤起一个系统的 ConfirmationDialog 询问玩家
	print("询问：是否要发动被动技能【", card_data.card_name, "】？")
	# 如果玩家点是：callable_if_yes.call()

func _on_close_pressed():
	get_tree().paused = false
	print("退出游戏")
	get_tree().quit(0)
