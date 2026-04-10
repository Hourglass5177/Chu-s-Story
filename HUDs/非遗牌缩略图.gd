extends TextureButton
class_name 非遗牌缩略图

signal request_open_detail(card_data: 非遗牌)
signal request_use_card(card_data: 非遗牌)

var card_data: 非遗牌
@onready var mask = $Mask
func setup(data: 非遗牌):
	card_data = data
	# 设置牌面贴图
	texture_normal = card_data.image_of_front
	# 设置左上角分数
	$ScoreBadge/BaseScore.text = str(card_data.base_score)
	tooltip_text = card_data.card_name 
	
func _ready():
	# 连接内置的鼠标信号
	mouse_entered.connect(func(): mask.show())
	mouse_exited.connect(func(): mask.hide())
	button_down.connect(func(): mask.color = Color(0, 0, 0, 0.7)) # 按下时变得更黑
	button_up.connect(func(): mask.color = Color(0, 0, 0, 0.4))   # 松开恢复半透明黑
	
# 监听鼠标左右键点击
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# 左键：打开详情窗口
			request_open_detail.emit(card_data)
			
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# 右键：弹出使用菜单
			_show_context_menu(event.global_position)

func _show_context_menu(pos: Vector2):
	# 如果不是主动牌，或者当前不能用，就不弹菜单
	#if not card_data.can_use(TurnManager.players[TurnManager.now_player_index]):
		#return
		
	var popup = PopupMenu.new()
	popup.add_item("使用")
	popup.id_pressed.connect(func(id):
		if id == 0: request_use_card.emit(card_data)
	)
	add_child(popup)
	# 在鼠标点击的位置弹出菜单
	popup.popup(Rect2(pos.x, pos.y, popup.size.x, popup.size.y))
