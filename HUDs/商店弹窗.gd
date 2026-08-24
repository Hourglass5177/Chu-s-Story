extends Panel
class_name 商店弹窗

const FOOD_TOOLTIP_SCRIPT := preload("res://HUDs/food_tooltip.gd")
const FOOD_CARD_VIEW_SCRIPT := preload("res://HUDs/food_card_view.gd")

@onready var food_container = $HBoxContainer
@onready var lbl_money = $余额
@onready var btn_close = $BtnClose
@onready var btn_refresh: Button = $BtnRefresh
var hud:HUD
var current_player: PlayerClass
var shop_foods: Array[食物牌] = []
var _refresh_used_this_visit: bool = false
var _owns_modal: bool = false
var _owns_tree_pause: bool = false
var _turn_session_generation: int = -1
var _tooltip: Control

func _ready():
	btn_close.pressed.connect(_on_leave)
	btn_refresh.pressed.connect(_on_refresh_pressed)
	hide()
	hud = get_tree().get_first_node_in_group("HUD")
	_tooltip = FOOD_TOOLTIP_SCRIPT.new()
	add_child(_tooltip)
	if hud != null:
		_tooltip.set_display_font(hud.default_font)
	if $BtnClose.texture_normal:
		var bitmap = BitMap.new()
		# 读取原图的透明通道数据
		bitmap.create_from_image_alpha($BtnClose.texture_normal.get_image())
		# 将其设为按钮的点击遮罩
		$BtnClose.texture_click_mask = bitmap
		var mask = $BtnClose/mask
		$BtnClose.mouse_entered.connect(func(): mask.show())
		$BtnClose.mouse_exited.connect(func(): mask.hide())
		$BtnClose.button_down.connect(func(): mask.modulate = Color(0, 0, 0, 0.7)) 
		$BtnClose.button_up.connect(func(): mask.modulate = Color(0, 0, 0, 0.4))   

func open_shop(player: PlayerClass) -> void:
	if visible:
		return
	current_player = player
	_refresh_used_this_visit = false
	_turn_session_generation = TurnManager.get_session_generation()
	_owns_modal = TurnManager.GameOn
	if _owns_modal:
		TurnManager.begin_modal_resolution()
	_owns_tree_pause = not get_tree().paused
	show()
	if hud != null:
		hud.btn_action.disabled = true
	if _owns_tree_pause:
		get_tree().paused = true
	lbl_money.text = "余额：" + str(player.current_money) + " 点"
	
	# 从裁判那里进货 3 张牌
	shop_foods = ResourceManager.draw_shop_foods(3)
	_refresh_shelf()

func _refresh_shelf() -> void:
	# 清理旧货架
	for child in food_container.get_children():
		child.queue_free()
	_update_refresh_button()

	if shop_foods.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "商店已售空！"
		if hud != null:
			empty_lbl.add_theme_font_override("font", hud.default_font)
		empty_lbl.add_theme_font_size_override("font_size", 64)
		empty_lbl.add_theme_color_override("font_color", Color.BLACK)
		empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		food_container.add_child(empty_lbl)
		return
		
	# 渲染货架商品
	for card in shop_foods:
		_create_commodity_ui(card)

func _update_refresh_button() -> void:
	if btn_refresh == null:
		return
	var can_refresh := current_player != null \
		and ProfessionManager.is_skill_enabled(current_player, PlayerClass.PlayerCharacter.商业博主) \
		and not _refresh_used_this_visit \
		and not ResourceManager.食物牌库.is_empty()
	btn_refresh.visible = current_player != null \
		and ProfessionManager.is_skill_enabled(current_player, PlayerClass.PlayerCharacter.商业博主)
	btn_refresh.disabled = not can_refresh

func _on_refresh_pressed() -> void:
	if current_player == null or _refresh_used_this_visit:
		return
	if not ProfessionManager.is_skill_enabled(current_player, PlayerClass.PlayerCharacter.商业博主):
		return
	if ResourceManager.食物牌库.is_empty():
		return
	_refresh_used_this_visit = true
	var previous_foods: Array[食物牌] = shop_foods.duplicate()
	# 旧货先离开抽牌池；抽完一批新货后，再按原展示顺序放到牌库底。
	shop_foods = ResourceManager.draw_shop_foods(3)
	ResourceManager.return_shop_foods_to_bottom(previous_foods)
	_refresh_shelf()
	ProfessionManager.notify_skill_triggered(current_player, "刷新商店")
	if hud != null:
		hud._update_game_informs("商店已刷新。")

func _create_commodity_ui(card: 食物牌) -> void:
	var item_box = FOOD_CARD_VIEW_SCRIPT.new()
	var display_font: Font = hud.default_font if hud != null else get_theme_default_font()
	item_box.setup(card, display_font, "购买", current_player.current_money < card.cost, true)
	item_box.modulate.a = 0.0
	item_box.action_requested.connect(func(selected: 食物牌): _buy_food(selected, item_box))
	_tooltip.bind(item_box.icon, card)
	food_container.add_child(item_box)
	var reveal_tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	reveal_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	reveal_tween.tween_property(item_box, "modulate:a", 1.0, 0.18)

func _buy_food(card: 食物牌, ui_node: Control) -> void:
	if not shop_foods.has(card):
		return
	if not ResourceManager.buy_food(current_player, card):
		return
	
	# 从货架数组中移除
	shop_foods.erase(card)
	
	# 销毁对应的 UI
	ui_node.queue_free()
	
	# 刷新余额显示和剩余按钮的状态
	lbl_money.text = "余额：" + str(current_player.current_money) + " 点"
	for child in food_container.get_children():
		if child is VBoxContainer and not child.is_queued_for_deletion():
			# 取出我们在第一步藏进去的卡牌数据
			var linked_card = child.get_meta("card_data") as 食物牌
			# 安全地找出这个容器里的 Button 节点
			for sub_node in child.get_children():
				if sub_node is Button:
					# 重新判定钱够不够买这件商品
					sub_node.disabled = current_player.current_money < linked_card.cost
					break # 找到了按钮就跳出内层循环
	_update_refresh_button()
					
	print(current_player.player_name, " 购买了 ", card.card_name)

func _on_leave() -> void:
	# 离开时，把没买完的牌塞回牌库底
	ResourceManager.return_shop_foods_to_bottom(shop_foods)
	shop_foods.clear()
	_refresh_used_this_visit = false
	current_player = null
	
	hide()
	if _owns_modal and _turn_session_generation == TurnManager.get_session_generation():
		TurnManager.end_modal_resolution(false, true)
	if _owns_tree_pause:
		get_tree().paused = false
	_owns_modal = false
	_owns_tree_pause = false
	_turn_session_generation = -1
	
