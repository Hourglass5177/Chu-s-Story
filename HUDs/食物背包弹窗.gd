extends Panel
class_name FoodBackpackPanel

@onready var grid_container = $ScrollContainer/GridContainer
@onready var btn_close = $BtnClose
var hud:HUD

func _ready():
	btn_close.pressed.connect(_on_close)
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
		$BtnClose.button_down.connect(func(): mask.modulate = Color(0, 0, 0, 0.7)) # 按下更黑
		$BtnClose.button_up.connect(func(): mask.modulate = Color(0, 0, 0, 0.4))   # 松开恢复

# 打开背包并动态生成食物列表
func open_backpack(player: PlayerClass):
	# 先清空旧的列表
	for child in grid_container.get_children():
		child.queue_free()
		
	if player.食物牌手牌.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "背包空空如也..."
		empty_lbl.add_theme_font_override("font", hud.default_font)
		empty_lbl.add_theme_font_size_override("font_size", 64)
		empty_lbl.add_theme_color_override("font_color", Color.BLACK)
		grid_container.add_child(empty_lbl)
	else:
		# 遍历生成拥有的食物
		for card in player.食物牌手牌:
			_create_food_item_ui(card, player)
			
	show()
	get_tree().paused = true

# 纯代码动态生成单个食物 UI 项
func _create_food_item_ui(card: 食物牌, player: PlayerClass):
	var item_box = VBoxContainer.new()
	
	# 食物图片
	var icon = TextureRect.new()
	icon.texture = card.image_of_front
	icon.custom_minimum_size = Vector2(400, 500)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_box.add_child(icon)
	
	# 食物名字与回复量
	var info_lbl = Label.new()
	info_lbl.text = card.card_name
	info_lbl.add_theme_font_override("font", hud.default_font)
	info_lbl.add_theme_font_size_override("font_size", 64)
	info_lbl.add_theme_color_override("font_color", Color.BLACK)
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_box.add_child(info_lbl)
	
	# 使用按钮
	var btn_use = Button.new()
	btn_use.text = "享用"
	btn_use.add_theme_font_override("font", hud.default_font)
	btn_use.add_theme_font_size_override("font_size", 64)
	btn_use.add_theme_color_override("color", Color.BLACK)
	btn_use.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# 判定能否吃
	btn_use.disabled = not card.can_use(player)
	
	btn_use.pressed.connect(func(): 
		_on_food_used(card, player)
	)
	item_box.add_child(btn_use)
	
	grid_container.add_child(item_box)

func _on_food_used(card: 食物牌, player: PlayerClass):
	if card.food_type == 食物牌.FoodType.市级:
		# 动态生成一个弹出菜单
		var popup = PopupMenu.new()
		popup.add_item("精力 +2", 0)
		popup.add_item("精力 +1, 积分 +100", 1)
		
		# 连接点击信号
		popup.id_pressed.connect(func(id):
			card.execute_effect(player, id)
			match id:
				0:
					hud._update_game_informs("吃下了【" + card.card_name + "】回复了 2 点精力！")
				1:
					hud._update_game_informs("吃下了【" + card.card_name + "】回复了1点精力，获得了100积分点！")
			player.食物牌手牌.erase(card)
			open_backpack(player) # 刷新背包
			popup.queue_free()    # 选完销毁菜单
		)
		
		add_child(popup)

		# 1. 实时获取鼠标在当前屏幕（视口）上的绝对坐标
		var mouse_pos = get_viewport().get_mouse_position()

		# 2. 加上一个小偏移量（向右下角偏 10 像素）
		# 极其重要：如果不加偏移，菜单的左上角会正好刷在鼠标尖端，极易导致玩家误触第一个选项！
		var offset = Vector2(10, 10) 

		# 3. 在鼠标右下方弹出菜单 (注意 Godot 4 推荐转成 Vector2i)
		popup.popup(Rect2i(mouse_pos + offset, Vector2i(200, 100)))
	else:
		card.execute_effect(player)
		player.食物牌手牌.erase(card)
	
	ResourceManager.食物牌库.insert(0, card)
	
	# 3. 刷新 HUD 信息和背包界面
	# 重新渲染当前拥有的食物
	open_backpack(player) 

func _on_close():
	hide()
	get_tree().paused = false
