extends Panel
class_name 商店弹窗

@onready var food_container = $HBoxContainer
@onready var lbl_money = $余额
@onready var btn_close = $BtnClose
var hud:HUD
var current_player: PlayerClass
var shop_foods: Array[食物牌] = []

func _ready():
	btn_close.pressed.connect(_on_leave)
	hide()
	hud = get_tree().get_first_node_in_group("HUD")
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
	current_player = player
	show()
	hud.btn_action.disabled = true
	get_tree().paused = true
	lbl_money.text = "余额：" + str(player.current_money) + " 点"
	
	# 从裁判那里进货 3 张牌
	shop_foods = ResourceManager.draw_shop_foods(3)
	
	# 清理旧货架
	for child in food_container.get_children():
		child.queue_free()
		
	if shop_foods.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "商店已售空！"
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

func _create_commodity_ui(card: 食物牌) -> void:
	var item_box = VBoxContainer.new()
	item_box.add_theme_constant_override("separation", 10)
	item_box.set_meta("card_data", card)
	var icon = TextureRect.new()
	icon.texture = card.image_of_front
	icon.custom_minimum_size = Vector2(400, 500)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_box.add_child(icon)
	
	var info = Label.new()
	info.text = card.card_name + "\n￥" + str(card.cost)
	info.add_theme_font_override("font", hud.default_font)
	info.add_theme_font_size_override("font_size", 64)
	info.add_theme_color_override("font_color", Color.BLACK)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_box.add_child(info)
	
	var btn_buy = Button.new()
	btn_buy.text = "购买"
	btn_buy.add_theme_font_override("font", hud.default_font)
	btn_buy.add_theme_font_size_override("font_size", 64)
	# 买不起就置灰
	btn_buy.disabled = current_player.current_money < card.cost
	btn_buy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_buy.pressed.connect(func():
		_buy_food(card, item_box)
	)
	item_box.add_child(btn_buy)
	food_container.add_child(item_box)

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
					
	print(current_player.player_name, " 购买了 ", card.card_name)

func _on_leave() -> void:
	# 离开时，把没买完的牌塞回牌库底
	for leftover in shop_foods:
		ResourceManager.食物牌库.insert(0, leftover)
	shop_foods.clear()
	
	hide()
	get_tree().paused = false
	
