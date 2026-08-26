extends Panel
class_name 非遗详情弹窗

signal detail_closed

@onready var card_image = $TextureRect as TextureRect
@onready var lbl_name = $VBoxContainer/LblName as Label
@onready var lbl_score = $VBoxContainer/LblScore as Label
@onready var lbl_desc = $VBoxContainer/LblDesc as Label
@onready var lbl_cate = $VBoxContainer/LblCate as Label
@onready var lbl_effect = $VBoxContainer/LblEffect as Label
@onready var guide_button := $BtnGuide as Button

var current_card: 非遗牌 = null
var _hud: HUD = null
var _owns_pause: bool = false

func _ready() -> void:
	#btn_use.pressed.connect(_on_use_pressed)
	_hud = get_tree().get_first_node_in_group("HUD") as HUD
	guide_button.pressed.connect(_open_guide)
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
func show_detail(card_data: 非遗牌, _player: PlayerClass) -> void:
	if card_data == null:
		return
	current_card = card_data
	card_image.texture = card_data.image_of_front
	lbl_name.text = "【名称】" + card_data.card_name
	lbl_score.text = "【分数】" + str(card_data.base_score) + " 分"
	lbl_desc.text = "【描述】" + card_data.description
	lbl_cate.text = "【类别】" + 非遗牌.CardCategory.find_key(card_data.category)
	lbl_effect.text = "【效果】" + card_data.effect_description
	if not visible:
		_owns_pause = not get_tree().paused
		if _owns_pause:
			get_tree().paused = true
	show()


func _open_guide() -> void:
	if current_card == null:
		return
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group("HUD") as HUD
	if _hud == null:
		return
	_hud.open_game_guide(GuideOpenContext.new(
		GuideOpenContext.Source.CARD,
		&"feiyi_cards",
		DiscoveryManager.KIND_FEIYI,
		StringName(current_card.resource_path),
		guide_button
	))

func _on_close_pressed() -> void:
	close_detail()

func close_detail() -> void:
	if not visible:
		return
	hide()
	if _owns_pause:
		get_tree().paused = false
	_owns_pause = false
	detail_closed.emit()
