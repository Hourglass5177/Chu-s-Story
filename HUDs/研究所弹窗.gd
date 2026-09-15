extends Panel
class_name 研究所弹窗

@onready var title_label: Label = $标题
@onready var balance_label: Label = $状态栏/余额
@onready var purchase_label: Label = $状态栏/购买次数
@onready var buy_tab: Button = $页签/购买
@onready var sell_tab: Button = $页签/出售
@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var card_grid: GridContainer = $ScrollContainer/CardGrid
@onready var guide_button: Button = $BtnGuide
@onready var close_button: TextureButton = $BtnClose

var hud: HUD = null
var current_player: PlayerClass = null
var current_arrival_id: int = -1
var _showing_buy: bool = true
var _modal_lease: int = -1
var _modal_session_generation: int = -1
var _modal_turn_epoch: int = -1
var _event_request: EventChoiceRequest = null
var _event_cards: Array[非遗牌] = []
var _event_selected_cards: Array[非遗牌] = []
var _preview_image: TextureRect
var _preview_name: Label
var _preview_effect: Label
var _preview_card: 非遗牌

func _ready() -> void:
	_build_selected_preview()
	call_deferred("_install_board_ui")
	buy_tab.pressed.connect(_show_buy_page)
	sell_tab.pressed.connect(_show_sell_page)
	guide_button.pressed.connect(_open_guide)
	close_button.pressed.connect(close_market)
	MarketManager.inventory_changed.connect(_on_inventory_changed)
	EventManager.choice_resolved.connect(_on_event_choice_resolved)
	EventManager.interaction_finished.connect(_on_event_interaction_finished)
	set_process(false)
	hide()

func _build_selected_preview() -> void:
	var panel := PanelContainer.new()
	panel.name = "SelectedPreview"
	panel.add_theme_stylebox_override("panel", MainUI.box("detail_card_frame", 40))
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	_preview_name = Label.new()
	MainUI.label(_preview_name, 46, true)
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_preview_name)
	_preview_image = TextureRect.new()
	_preview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_image.custom_minimum_size = Vector2(0, 420)
	column.add_child(_preview_image)
	_preview_effect = Label.new()
	MainUI.label(_preview_effect, 36)
	_preview_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_effect.max_lines_visible = 3
	_preview_effect.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_preview_effect)
	var details := Button.new()
	details.text = "查看详情"
	MainUI.button(details, "secondary")
	details.custom_minimum_size = Vector2(390, 112)
	details.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	details.pressed.connect(func():
		if _preview_card != null and hud != null: hud.detail_panel.show_detail(_preview_card, current_player))
	column.add_child(details)

func _select_preview(card: 非遗牌) -> void:
	_preview_card = card
	_preview_image.texture = card.image_of_front if card != null else null
	_preview_name.text = card.card_name if card != null else "藏品预览"
	_preview_effect.text = card.description if card != null else "从右侧选择藏品，查看牌面与详情。"
	_preview_effect.tooltip_text = _preview_effect.text


func _open_guide() -> void:
	if hud == null or not is_instance_valid(hud):
		hud = get_tree().get_first_node_in_group("HUD") as HUD
	if hud == null:
		return
	hud.open_game_guide(GuideOpenContext.new(
		GuideOpenContext.Source.MARKET,
		&"market_economy",
		&"market",
		&"global_research_market",
		guide_button,
		&"market_prices"
	))

func _process(_delta: float) -> void:
	if _event_request == null:
		return
	var remaining := EventManager.get_choice_time_left(_event_request.request_id)
	purchase_label.text = "剩余 %02d 秒" % int(ceil(remaining))

func open_market(player: PlayerClass) -> void:
	if player == null or visible:
		return
	_reset_event_mode()
	hud = get_tree().get_first_node_in_group("HUD") as HUD
	current_player = player
	current_arrival_id = player.arrival_id
	_showing_buy = true
	title_label.text = "非遗研究所"
	balance_label.show()
	purchase_label.show()
	buy_tab.get_parent().show()
	close_button.show()
	close_button.disabled = false
	show()
	_modal_session_generation = TurnManager.get_session_generation()
	_modal_turn_epoch = TurnManager.get_turn_epoch()
	if TurnManager.GameOn:
		_modal_lease = TurnManager.acquire_modal(
			&"research_market",
			TurnManager.ModalResumePolicy.RESET_ACTION
		)
	if hud != null:
		hud.btn_action.disabled = true
		hud.btn_food.disabled = true
		hud.btn_end_turn.disabled = true
	_refresh()

func open_event_choice(request: EventChoiceRequest) -> bool:
	if request == null or visible or request.presentation != EventChoiceRequest.Presentation.研究所:
		return false
	var cards: Array[非遗牌] = []
	for option in request.options:
		if option is 非遗牌:
			cards.append(option as 非遗牌)
	if cards.is_empty():
		return false
	hud = get_tree().get_first_node_in_group("HUD") as HUD
	current_player = request.requester
	current_arrival_id = -1
	_showing_buy = true
	_event_request = request
	_event_cards.assign(cards)
	_event_selected_cards.clear()
	_modal_lease = -1
	_modal_session_generation = -1
	_modal_turn_epoch = -1
	title_label.text = request.source_name if not request.source_name.is_empty() else "非遗研究所"
	balance_label.text = request.prompt
	balance_label.show()
	purchase_label.text = "剩余 %02d 秒" % int(ceil(request.timeout_seconds))
	purchase_label.show()
	buy_tab.get_parent().hide()
	close_button.visible = request.optional
	close_button.disabled = not request.optional
	set_process(true)
	show()
	if hud != null:
		hud.btn_action.disabled = true
		hud.btn_food.disabled = true
		hud.btn_end_turn.disabled = true
	_refresh()
	return true

func close_market() -> void:
	if not visible:
		return
	if _event_request != null:
		if _event_request.multiple:
			EventManager.submit_choice(_event_request.request_id, _event_selected_cards.duplicate())
		elif _event_request.optional:
			EventManager.submit_choice(_event_request.request_id, null)
		return
	hide()
	var same_context: bool = _release_market_modal()
	if same_context and hud != null and is_instance_valid(hud):
		hud._update_button_states(TurnManager.now_phase)
	current_player = null
	current_arrival_id = -1


func _release_market_modal() -> bool:
	var same_context: bool = (
		_modal_session_generation == TurnManager.get_session_generation()
		and _modal_turn_epoch == TurnManager.get_turn_epoch()
	)
	if _modal_lease >= 0 and same_context:
		TurnManager.release_modal(_modal_lease)
	_modal_lease = -1
	_modal_session_generation = -1
	_modal_turn_epoch = -1
	return same_context

func _show_buy_page() -> void:
	if _event_request != null:
		return
	_showing_buy = true
	_refresh()

func _show_sell_page() -> void:
	if _event_request != null:
		return
	_showing_buy = false
	_refresh()

func _refresh() -> void:
	if current_player == null:
		return
	if _event_request == null:
		balance_label.text = "余额  %d" % current_player.current_money
		purchase_label.text = "本次可购  %d/3" % MarketManager.get_remaining_purchases(current_player, current_arrival_id)
		buy_tab.button_pressed = _showing_buy
		sell_tab.button_pressed = not _showing_buy
	for child: Node in card_grid.get_children():
		child.queue_free()
	var cards: Array[非遗牌] = []
	if _event_request != null:
		cards.assign(_event_cards)
	else:
		cards = MarketManager.get_inventory() if _showing_buy else MarketManager.get_tradable_cards(current_player)
	_select_preview(_preview_card if cards.has(_preview_card) else (cards[0] if not cards.is_empty() else null))
	if cards.is_empty():
		var empty_label := Label.new()
		empty_label.text = "暂无藏品" if _event_request != null or _showing_buy else "暂无可出售非遗牌"
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
	if _event_request != null and _event_request.multiple:
		var confirm_button := Button.new()
		confirm_button.text = "确认（%d/%d）" % [_event_selected_cards.size(), _event_request.max_selections]
		confirm_button.custom_minimum_size = Vector2(300, 70)
		if hud != null:
			confirm_button.add_theme_font_override("font", hud.default_font)
			confirm_button.add_theme_font_size_override("font_size", 42)
		_style_action_button(confirm_button)
		confirm_button.pressed.connect(_confirm_event_multi_choice)
		card_grid.add_child(confirm_button)

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
	image_button.pressed.connect(_select_preview.bind(card))
	item.add_child(image_button)
	var name_label := Label.new()
	name_label.text = card.card_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MainUI.label(name_label, 38)
	item.add_child(name_label)
	var action_button := Button.new()
	action_button.custom_minimum_size = Vector2(300, 62)
	action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if hud != null:
		action_button.add_theme_font_override("font", hud.default_font)
	action_button.add_theme_font_size_override("font_size", 42)
	_style_action_button(action_button)
	if _event_request != null:
		if _event_request.multiple:
			action_button.text = "已选" if _event_selected_cards.has(card) else "选择"
			action_button.button_pressed = _event_selected_cards.has(card)
			action_button.pressed.connect(_toggle_event_card.bind(card))
		else:
			action_button.text = "选择"
			action_button.pressed.connect(_select_event_card.bind(card))
	elif _showing_buy:
		var price := MarketManager.get_buy_price(card, current_player)
		action_button.text = "购买  %d" % price
		action_button.disabled = current_player.current_money < price or MarketManager.get_remaining_purchases(current_player, current_arrival_id) <= 0
		action_button.pressed.connect(_buy_card.bind(card))
	else:
		var price := MarketManager.get_sell_price(card)
		action_button.text = "出售  %d" % price
		action_button.pressed.connect(_sell_card.bind(card))
	item.add_child(action_button)
	card_grid.add_child(item)

func _style_action_button(button: Button) -> void:
	MainUI.button(button)

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

func _select_event_card(card: 非遗牌) -> void:
	if _event_request == null or not _event_cards.has(card):
		return
	EventManager.submit_choice(_event_request.request_id, card)

func _toggle_event_card(card: 非遗牌) -> void:
	if _event_request == null or not _event_request.multiple or not _event_cards.has(card):
		return
	if _event_selected_cards.has(card):
		_event_selected_cards.erase(card)
	elif _event_selected_cards.size() < _event_request.max_selections:
		_event_selected_cards.append(card)
	EventManager.submit_choice_preview(_event_request.request_id, _event_selected_cards)
	_refresh()

func _confirm_event_multi_choice() -> void:
	if _event_request == null or not _event_request.multiple:
		return
	EventManager.submit_choice(_event_request.request_id, _event_selected_cards.duplicate())

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

func is_event_choice_open(request_id: int = -1) -> bool:
	if _event_request == null or not visible:
		return false
	return request_id < 0 or _event_request.request_id == request_id

func finish_event_choice(request_id: int = -1) -> void:
	if _event_request == null:
		return
	if request_id >= 0 and _event_request.request_id != request_id:
		return
	if hud != null and hud.detail_panel != null and hud.detail_panel.visible:
		hud.detail_panel.close_detail()
	hide()
	current_player = null
	current_arrival_id = -1
	_reset_event_mode()

func _on_event_choice_resolved(request_id: int, _timed_out: bool) -> void:
	finish_event_choice(request_id)

func _on_event_interaction_finished(_player: PlayerClass) -> void:
	finish_event_choice()

func _reset_event_mode() -> void:
	_event_request = null
	_event_cards.clear()
	_event_selected_cards.clear()
	set_process(false)
	if title_label != null:
		title_label.text = "非遗研究所"
	if purchase_label != null:
		purchase_label.show()
	if buy_tab != null and buy_tab.get_parent() != null:
		buy_tab.get_parent().show()
	if close_button != null:
		close_button.show()
		close_button.disabled = false

func _install_board_ui() -> void:
	BoardPanelLayout.install(self, "market", close_market)
