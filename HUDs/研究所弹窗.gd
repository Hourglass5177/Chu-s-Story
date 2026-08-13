extends Panel
class_name 研究所弹窗

@onready var title_label: Label = $标题
@onready var balance_label: Label = $状态栏/余额
@onready var purchase_label: Label = $状态栏/购买次数
@onready var buy_tab: Button = $页签/购买
@onready var sell_tab: Button = $页签/出售
@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var card_grid: GridContainer = $ScrollContainer/CardGrid
@onready var close_button: TextureButton = $BtnClose

var hud: HUD = null
var current_player: PlayerClass = null
var current_arrival_id: int = -1
var _showing_buy: bool = true
var _modal_owned: bool = false

func _ready() -> void:
	buy_tab.pressed.connect(_show_buy_page)
	sell_tab.pressed.connect(_show_sell_page)
	close_button.pressed.connect(close_market)
	MarketManager.inventory_changed.connect(_on_inventory_changed)
	hide()

func open_market(player: PlayerClass) -> void:
	if player == null or visible:
		return
	hud = get_tree().get_first_node_in_group("HUD") as HUD
	current_player = player
	current_arrival_id = player.arrival_id
	_showing_buy = true
	show()
	TurnManager.begin_modal_resolution()
	_modal_owned = true
	if hud != null:
		hud.btn_action.disabled = true
		hud.btn_food.disabled = true
		hud.btn_end_turn.disabled = true
	_refresh()

func close_market() -> void:
	if not visible:
		return
	hide()
	if _modal_owned:
		TurnManager.end_modal_resolution(true)
		_modal_owned = false
	if hud != null:
		hud._update_button_states(TurnManager.now_phase)
	current_player = null
	current_arrival_id = -1

func _show_buy_page() -> void:
	_showing_buy = true
	_refresh()

func _show_sell_page() -> void:
	_showing_buy = false
	_refresh()

func _refresh() -> void:
	if current_player == null:
		return
	balance_label.text = "余额  %d" % current_player.current_money
	purchase_label.text = "本次可购  %d/3" % MarketManager.get_remaining_purchases(current_player, current_arrival_id)
	buy_tab.button_pressed = _showing_buy
	sell_tab.button_pressed = not _showing_buy
	for child: Node in card_grid.get_children():
		child.queue_free()
	var cards: Array[非遗牌] = MarketManager.get_inventory() if _showing_buy else MarketManager.get_tradable_cards(current_player)
	if cards.is_empty():
		var empty_label := Label.new()
		empty_label.text = "暂无藏品" if _showing_buy else "暂无可出售非遗牌"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.custom_minimum_size = Vector2(1100, 420)
		if hud != null:
			empty_label.add_theme_font_override("font", hud.default_font)
		empty_label.add_theme_font_size_override("font_size", 58)
		empty_label.add_theme_color_override("font_color", Color("5a3325"))
		card_grid.add_child(empty_label)
		return
	for card: 非遗牌 in cards:
		_create_card_item(card)

func _create_card_item(card: 非遗牌) -> void:
	var item := VBoxContainer.new()
	item.custom_minimum_size = Vector2(390, 510)
	item.add_theme_constant_override("separation", 8)
	var image_button := TextureButton.new()
	image_button.texture_normal = card.image_of_front
	image_button.custom_minimum_size = Vector2(310, 400)
	image_button.ignore_texture_size = true
	image_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	image_button.tooltip_text = card.card_name
	image_button.pressed.connect(_show_card_detail.bind(card))
	item.add_child(image_button)
	var price: int = MarketManager.get_buy_price(card) if _showing_buy else MarketManager.get_sell_price(card)
	var action_button := Button.new()
	action_button.text = ("购买  %d" if _showing_buy else "出售  %d") % price
	action_button.custom_minimum_size = Vector2(300, 62)
	action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if hud != null:
		action_button.add_theme_font_override("font", hud.default_font)
	action_button.add_theme_font_size_override("font_size", 42)
	_style_action_button(action_button)
	if _showing_buy:
		action_button.disabled = current_player.current_money < price or MarketManager.get_remaining_purchases(current_player, current_arrival_id) <= 0
		action_button.pressed.connect(_buy_card.bind(card))
	else:
		action_button.pressed.connect(_sell_card.bind(card))
	item.add_child(action_button)
	card_grid.add_child(item)

func _style_action_button(button: Button) -> void:
	button.add_theme_color_override("font_color", Color("5a3325"))
	button.add_theme_color_override("font_hover_color", Color("5a3325"))
	button.add_theme_color_override("font_pressed_color", Color("fff1cf"))
	button.add_theme_color_override("font_disabled_color", Color("8d816e"))
	button.add_theme_stylebox_override("normal", _button_style(Color("f2cf8c"), Color("7b3e27")))
	button.add_theme_stylebox_override("hover", _button_style(Color("f8dea8"), Color("7b3e27")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("b65d38"), Color("67301f")))
	button.add_theme_stylebox_override("disabled", _button_style(Color("d5c8aa"), Color("9d8c6b")))

func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	return style

func _show_card_detail(card: 非遗牌) -> void:
	if hud != null:
		hud.detail_panel.show_detail(card, current_player)

func _buy_card(card: 非遗牌) -> void:
	if not MarketManager.buy_card(current_player, card, current_arrival_id):
		if hud != null:
			hud._update_game_informs("无法购买这张非遗牌。")
		_refresh()
		return
	if hud != null:
		hud._update_game_informs("购得【%s】。" % card.card_name)
	_refresh()

func _sell_card(card: 非遗牌) -> void:
	if not MarketManager.sell_card(current_player, card):
		if hud != null:
			hud._update_game_informs("无法出售这张非遗牌。")
		_refresh()
		return
	if hud != null:
		hud._update_game_informs("售出【%s】。" % card.card_name)
	_refresh()

func _on_inventory_changed(_cards: Array[非遗牌]) -> void:
	if visible:
		_refresh()
