extends Panel
class_name FoodBackpackPanel

const FOOD_TOOLTIP_SCRIPT := preload("res://HUDs/food_tooltip.gd")
const FOOD_CARD_VIEW_SCRIPT := preload("res://HUDs/food_card_view.gd")

@onready var grid_container = $ScrollContainer/GridContainer
@onready var btn_close = $BtnClose
var hud:HUD
var _tooltip: Control
var _modal_token: int = -1
var _owns_modal: bool = false
var _owns_tree_pause: bool = false
var _resolving: bool = false

func _ready():
	btn_close.pressed.connect(_on_close)
	hide()
	hud = get_tree().get_first_node_in_group("HUD")
	_tooltip = FOOD_TOOLTIP_SCRIPT.new()
	add_child(_tooltip)
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
		$BtnClose.button_down.connect(func(): mask.modulate = Color(0, 0, 0, 0.7)) # 按下更黑
		$BtnClose.button_up.connect(func(): mask.modulate = Color(0, 0, 0, 0.4))   # 松开恢复

# 打开背包并动态生成食物列表
func open_backpack(player: PlayerClass) -> void:
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
	if not _owns_modal and TurnManager.GameOn:
		_modal_token = TurnManager.begin_modal_resolution()
		_owns_modal = true
	if not _owns_tree_pause and not get_tree().paused:
		get_tree().paused = true
		_owns_tree_pause = true

# 纯代码动态生成单个食物 UI 项
func _create_food_item_ui(card: 食物牌, player: PlayerClass) -> void:
	var item_box = FOOD_CARD_VIEW_SCRIPT.new()
	item_box.setup(card, hud.default_font, "享用", _resolving or not card.can_use(player))
	item_box.action_requested.connect(func(selected: 食物牌): _on_food_used(selected, player))
	item_box.guide_requested.connect(_open_food_guide)
	_tooltip.bind(item_box.icon, card)
	grid_container.add_child(item_box)


func _open_food_guide(card: 食物牌, source: Control) -> void:
	if hud == null or card == null:
		return
	DiscoveryManager.record_food_face_presented(card)
	hud.open_game_guide(GuideOpenContext.new(
		GuideOpenContext.Source.CARD,
		&"food_system",
		DiscoveryManager.KIND_FOOD,
		card.food_id,
		source
	))

func _on_food_used(card: 食物牌, player: PlayerClass) -> void:
	if _resolving or not card.can_use(player):
		return
	_resolving = true
	open_backpack(player)
	var result: FoodResolutionResult = await FoodManager.consume_food(player, card)
	_resolving = false
	if result != null:
		hud._update_game_informs(result.message)
	if visible and is_instance_valid(player):
		open_backpack(player)

func _on_close():
	if _resolving:
		return
	hide()
	if _owns_modal:
		TurnManager.end_modal_resolution(false, true, _modal_token)
	if _owns_tree_pause:
		get_tree().paused = false
	_owns_modal = false
	_owns_tree_pause = false
	_modal_token = -1
