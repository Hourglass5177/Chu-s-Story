extends Panel
class_name 非遗详情弹窗

signal use_button_clicked(card_data: 非遗牌)

@onready var card_image = $TextureRect as TextureRect
@onready var lbl_name = $VBoxContainer/LblName as Label
@onready var lbl_score = $VBoxContainer/LblScore as Label
@onready var lbl_desc = $VBoxContainer/LblDesc as Label
@onready var lbl_cate = $VBoxContainer/LblCate as Label
@onready var lbl_effect = $VBoxContainer/LblEffect as Label
@onready var btn_use = $BtnUse as Button

var current_card: 非遗牌

func _ready():
	btn_use.pressed.connect(_on_use_pressed)
	$BtnClose.pressed.connect(_on_close_pressed)
	hide()
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

# 打开面板并填充数据
func show_detail(card_data: 非遗牌, player: PlayerClass):
	current_card = card_data
	card_image.texture = card_data.image_of_front
	lbl_name.text = "【名称】" + card_data.card_name
	lbl_score.text = "【分数】" + str(card_data.base_score) + " 分"
	lbl_desc.text = "【描述】" + card_data.description
	lbl_cate.text = "【类别】" + 非遗牌.CardCategory.find_key(card_data.category)
	lbl_effect.text = "【效果】" + card_data.effect_description
	
	
	# 判断“使用”按钮是否亮起
	btn_use.disabled = not card_data.can_use(player)
	
	show()
	get_tree().paused = true

func _on_use_pressed():
	use_button_clicked.emit(current_card)
	hide() # 用完关闭弹窗

func _on_close_pressed():
	hide()
	get_tree().paused = false

# 你还可以加一个“关闭”按钮的逻辑，或者点击遮罩区关闭，这里省略
